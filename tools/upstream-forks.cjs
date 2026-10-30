'use strict';
const crypto = require('node:crypto');
const {forkReport} = require('./assessment-report.cjs');
const {openDraft} = require('./usce-automation.cjs');
const source = {owner: 'UltraStar-Deluxe', repo: 'USDX'};
const prefix = 'automation/upstream-forks-';
const path = 'doc/upstream/usdx-forks.json';
const shaPattern = /^[a-f0-9]{40}$/;
const recordKey = fork => fork.repository + '#' + fork.branch;

function activeForks(forks, now, ownRepository) {
  const cutoff = new Date(now); cutoff.setUTCFullYear(cutoff.getUTCFullYear() - 2);
  if (!Number.isFinite(cutoff.getTime())) throw Error('Invalid fork scan time');
  const seen = new Set();
  return forks.filter(fork => {
    if (!fork.full_name || !fork.default_branch || !Number.isFinite(Date.parse(fork.pushed_at)))
      throw Error('Incomplete fork metadata');
    if (seen.has(fork.full_name)) return false;
    seen.add(fork.full_name);
    return !fork.archived && !fork.disabled && fork.full_name !== ownRepository &&
      Date.parse(fork.pushed_at) >= cutoff.getTime();
  }).sort((a, b) => Date.parse(b.pushed_at) - Date.parse(a.pushed_at) || a.full_name.localeCompare(b.full_name));
}

function forkChanges(previous, snapshots) {
  if (previous && (previous.repository !== 'UltraStar-Deluxe/USDX' || !Array.isArray(previous.forks)))
    throw Error('Invalid fork assessment checkpoint');
  const records = new Map();
  for (const fork of previous?.forks || []) {
    if (!fork.repository || !fork.branch || !shaPattern.test(fork.head) || records.has(recordKey(fork)))
      throw Error('Invalid fork assessment record');
    records.set(recordKey(fork), fork);
  }
  const batch = snapshots.filter(fork => {
    if (!fork.repository || !fork.branch || !shaPattern.test(fork.head) || !Number.isSafeInteger(fork.ahead) || fork.ahead < 0)
      throw Error('Invalid fork comparison');
    return fork.ahead > 0 && ![...records.values()].some(old => old.repository === fork.repository && old.head === fork.head);
  }).slice(0, 20);
  if (!batch.length) return null;
  const seen = new Set((previous?.forks || []).flatMap(f => [...(f.commits || []), ...(f.assessmentHistory || []).flatMap(h => h.commits || [])].map(c => c.sha)));
  for (const fork of batch) {
    fork.newCommits = (fork.commits || []).filter(c => !seen.has(c.sha));
    for (const c of fork.commits || []) seen.add(c.sha);
  }
  for (const fork of batch) records.set(recordKey(fork), {...fork,
    assessment: {decision: 'pending', usceReferences: [], reason: ''},
    ...(records.get(recordKey(fork))?.assessment ? {previousHead: records.get(recordKey(fork)).head,
      previousAssessment: records.get(recordKey(fork)).assessment,
      assessmentHistory: [...(records.get(recordKey(fork)).assessmentHistory || []),
        {head: records.get(recordKey(fork)).head, commits: records.get(recordKey(fork)).commits || [],
          assessment: records.get(recordKey(fork)).assessment}]} : {})});
  return {batch, checkpoint: {repository: 'UltraStar-Deluxe/USDX', forks: [...records.values()]}};
}

async function trackForks({github, context, core, now = new Date()}) {
  const ownRepository = context.repo.owner + '/' + context.repo.repo;
  const open = await github.paginate(github.rest.pulls.list, {...context.repo, state: 'open', per_page: 100});
  if (open.some(pr => pr.head?.repo?.full_name === ownRepository && pr.head.ref.startsWith(prefix))) return;
  const branch = context.payload.repository.default_branch;
  const sha = (await github.rest.git.getRef({...context.repo, ref: 'heads/' + branch})).data.object.sha;
  const commit = (await github.rest.git.getCommit({...context.repo, commit_sha: sha})).data;
  let previous = null;
  try {
    const file = (await github.rest.repos.getContent({...context.repo, path, ref: sha})).data;
    previous = JSON.parse(Buffer.from(file.content, 'base64').toString('utf8'));
  } catch (error) { if (error.status !== 404) throw error; }
  forkChanges(previous, []);
  const upstream = (await github.rest.repos.get(source)).data;
  const upstreamHead = (await github.rest.repos.getBranch({...source, branch: upstream.default_branch})).data.commit.sha;
  if (!shaPattern.test(upstreamHead)) throw Error('Missing upstream head');
  const forks = activeForks(await github.paginate(github.rest.repos.listForks,
    {...source, sort: 'newest', per_page: 100}), now, ownRepository);
  const snapshots = [];
  const unavailableForks = [];
  for (const fork of forks) {
    const [owner, repo] = fork.full_name.split('/');
    let branches;
    try {
      branches = await github.paginate(github.rest.repos.listBranches, {owner, repo, per_page: 100});
    } catch (error) {
      if (error.status !== 404) throw error;
      unavailableForks.push(fork.full_name);
      core.warning('Fork unavailable; not assessed: ' + fork.full_name);
      continue;
    }
    const seenHeads = new Set();
    for (const branch of branches.sort((a, b) => Number(b.name === fork.default_branch) - Number(a.name === fork.default_branch))) {
      const head = branch.commit?.sha;
      if (!shaPattern.test(head)) throw Error('Missing fork head: ' + fork.full_name);
      if (seenHeads.has(head) || previous?.forks.some(record => record.repository === fork.full_name && record.head === head)) continue;
      seenHeads.add(head);
      const prior = previous?.forks.find(record => recordKey(record) === fork.full_name + '#' + branch.name);
      // Compare known branches with their checkpoint, not their entire USDX history.
      // For first discovery, exclude exact commits already in USCE's main history.
      const base = prior?.head || sha;
      const args = {...context.repo, basehead: base + '...' + head, per_page: 100};
      const comparison = (await github.rest.repos.compareCommitsWithBasehead(args)).data;
      if (!Number.isSafeInteger(comparison.ahead_by) || !Number.isSafeInteger(comparison.behind_by) ||
          !Array.isArray(comparison.commits)) throw Error('Incomplete fork comparison: ' + fork.full_name);
      const commits = [...comparison.commits];
      for (let page = 2; commits.length < comparison.ahead_by; page++) {
        const next = (await github.rest.repos.compareCommitsWithBasehead({...args, page})).data.commits;
        if (!Array.isArray(next) || !next.length) throw Error('Incomplete fork commit inventory: ' + fork.full_name);
        commits.push(...next);
      }
      if (new Set(commits.map(c => c.sha)).size !== commits.length) throw Error('Duplicate fork commit inventory');
      if (commits.length !== comparison.ahead_by) throw Error('Incomplete fork commit inventory: ' + fork.full_name);
      snapshots.push({repository: fork.full_name, branch: branch.name, head, upstreamHead,
        comparisonBase: base, comparisonKind: prior ? 'since-checkpoint' : 'outside-usce',
        ahead: comparison.ahead_by, behind: comparison.behind_by,
        compareUrl: 'https://github.com/' + ownRepository + '/compare/' + base + '...' + head,
        commits: commits.map(c => ({sha: c.sha,
          title: c.commit.message.split('\n')[0], author: c.author?.login || c.commit.author.name}))});
    }
  }
  const changes = forkChanges(previous, snapshots);
  if (!changes) return;
  changes.checkpoint.unavailableForks = unavailableForks;
  const identity = crypto.createHash('sha256').update(JSON.stringify(changes.batch.map(f => [f.repository, f.branch, f.head])))
    .digest('hex').slice(0, 12);
  const pr = await openDraft(github, context, {branch, sha, tree: commit.tree.sha}, prefix + identity,
    [{path, content: JSON.stringify(changes.checkpoint, null, 2) + '\n'}],
    'Assess active USDX fork changes',
    forkReport(changes) +
    (unavailableForks.length ? '\n\nUnavailable forks, not assessed: ' + unavailableForks.join(', ') : ''), {reopenClosed: true});
  core.notice('Fork assessment: ' + pr.html_url);
}
module.exports = {activeForks, forkChanges, trackForks};
