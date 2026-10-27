'use strict';
const crypto = require('node:crypto');
const {TRACKS, openDraft} = require('./usce-automation.cjs');
const {createdSince} = require('../doc/upstream/issues-watch.json');
const digest = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const limit = 20;

function issueSnapshot(issue, repository) {
  if (!Number.isSafeInteger(issue.number) || issue.number < 1 || !Number.isFinite(Date.parse(issue.created_at)) ||
      !['open', 'closed'].includes(issue.state) || !Number.isFinite(Date.parse(issue.updated_at)) ||
      typeof issue.title !== 'string' || !Array.isArray(issue.labels) ||
      !Number.isSafeInteger(issue.comments) || issue.comments < 0) throw Error('Incomplete upstream issue metadata');
  const snapshot = {number: issue.number, source: repository + '#' + issue.number,
    title: issue.title, author: issue.user?.login || null, state: issue.state,
    stateReason: issue.state_reason || null, createdAt: issue.created_at, updatedAt: issue.updated_at,
    labels: issue.labels.map(label => typeof label === 'string' ? label : label.name).sort(),
    comments: issue.comments, description: (issue.body || '').slice(0, 2000)};
  // Hash the full description so edits beyond the displayed excerpt are detected.
  return {...snapshot, fingerprint: digest({...snapshot, description: issue.body || ''})};
}

function issueChanges({track, previous, issues, now}) {
  const observedAt = now.toISOString();
  if (!Number.isFinite(Date.parse(createdSince)) || Date.parse(createdSince) > now.getTime()) throw Error('Invalid issue watch start');
  if (previous && (previous.repository !== track.repo || previous.createdSince !== createdSince || !Array.isArray(previous.issues) ||
      !Number.isFinite(Date.parse(previous.checkedAt)) || Date.parse(previous.checkedAt) > now.getTime())) {
    throw Error('Invalid upstream issue checkpoint');
  }
  const records = new Map();
  for (const issue of previous?.issues || []) {
    if (!Number.isSafeInteger(issue.number) || issue.number < 1 || records.has(issue.number) ||
        !/^[a-f0-9]{64}$/.test(issue.fingerprint) || !Number.isFinite(Date.parse(issue.createdAt)) ||
        Date.parse(issue.createdAt) < Date.parse(createdSince)) throw Error('Invalid upstream issue record');
    records.set(issue.number, issue);
  }
  const snapshots = new Map();
  for (const issue of issues.filter(issue => !issue.pull_request)) {
    if (!Number.isFinite(Date.parse(issue.created_at))) throw Error('Missing issue creation time');
    if (Date.parse(issue.created_at) < Date.parse(createdSince)) continue;
    const snapshot = issueSnapshot(issue, track.repo);
    const prior = snapshots.get(issue.number);
    if (!prior || Date.parse(prior.updatedAt) <= Date.parse(snapshot.updatedAt)) snapshots.set(issue.number, snapshot);
  }
  const changed = [...snapshots.values()].filter(issue => records.get(issue.number)?.fingerprint !== issue.fingerprint)
    .sort((a, b) => Date.parse(b.updatedAt) - Date.parse(a.updatedAt) || a.number - b.number);
  if (!changed.length) return null;
  const batch = changed.slice(0, limit);
  for (const issue of batch) {
    const prior = records.get(issue.number);
    records.set(issue.number, {...issue, assessment: {decision: 'pending', usceReferences: [], reason: ''},
      ...(prior?.assessment ? {previousAssessment: prior.assessment} : {})});
  }
  return {batch, remaining: changed.length - batch.length,
    checkpoint: {repository: track.repo, createdSince,
      // Do not skip unprocessed closed reports when a large update spans batches.
      checkedAt: changed.length > limit ? previous?.checkedAt || createdSince : observedAt,
      issues: [...records.values()].sort((a, b) => a.number - b.number)}};
}

async function trackIssues({github, context, core, now = new Date()}) {
  const branch = context.payload.repository.default_branch;
  const sha = (await github.rest.git.getRef({...context.repo, ref: 'heads/' + branch})).data.object.sha;
  const commit = (await github.rest.git.getCommit({...context.repo, commit_sha: sha})).data;
  const base = {branch, sha, tree: commit.tree.sha};
  const open = await github.paginate(github.rest.pulls.list, {...context.repo, state: 'open', per_page: 100});
  for (const track of TRACKS) {
    const prefix = 'automation/upstream-issues-' + track.id + '-';
    if (open.some(pr => pr.head?.repo?.full_name === context.repo.owner + '/' + context.repo.repo && pr.head.ref.startsWith(prefix))) continue;
    const path = 'doc/upstream/' + track.id + '-issues.json';
    let previous = null;
    try {
      const content = (await github.rest.repos.getContent({...context.repo, path, ref: sha})).data;
      previous = JSON.parse(Buffer.from(content.content, 'base64').toString('utf8'));
    } catch (error) { if (error.status !== 404) throw error; }
    // Validate the checkpoint before using its timestamp to filter API results.
    issueChanges({track, previous, issues: [], now});
    const [owner, repo] = track.repo.split('/');
    const [active, recent] = await Promise.all([
      github.paginate(github.rest.issues.listForRepo, {owner, repo, state: 'open', since: createdSince, per_page: 100}),
      github.paginate(github.rest.issues.listForRepo, {owner, repo, state: 'closed',
        since: previous?.checkedAt || createdSince, per_page: 100}),
    ]);
    const changes = issueChanges({track, previous, issues: [...active, ...recent], now});
    if (!changes) continue;
    const identity = digest(changes.batch.map(issue => [issue.number, issue.fingerprint])).slice(0, 12);
    const pr = await openDraft(github, context, base, prefix + identity,
      [{path, content: JSON.stringify(changes.checkpoint, null, 2) + '\n'}],
      'Assess upstream ' + track.id + ' issue updates',
      'Upstream reports for assessment:\n\n' + changes.batch.map(issue => '- ' + issue.source).join('\n') +
      '\n\nThe assessment file contains source titles, description excerpts, labels, comment counts and prior decisions. ' +
      'Assess applicability to current USCE, reproduction steps, workarounds and existing local reports. ' +
      'Record a decision, links to related USCE issues or PRs, and the reason before merging. ' +
      'An upstream report is not a verified USCE bug. This proposal does not change the game or post upstream.' +
      (changes.remaining ? '\n\nAdditional changed reports remain for the next assessment.' : ''));
    core.notice('Upstream issue assessment: ' + pr.html_url);
  }
}
module.exports = {issueSnapshot, issueChanges, trackIssues};
