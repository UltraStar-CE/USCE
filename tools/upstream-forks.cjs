'use strict';
const crypto = require('node:crypto');
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
  for (const fork of batch) records.set(recordKey(fork), {...fork,
    assessment: {decision: 'pending', usceReferences: [], reason: ''},
    ...(records.get(recordKey(fork))?.assessment ? {previousAssessment: records.get(recordKey(fork)).assessment} : {})});
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
  for (const fork of forks) {
    const [owner, repo] = fork.full_name.split('/');
    const branches = await github.paginate(github.rest.repos.listBranches, {owner, repo, per_page: 100});
    const seenHeads = new Set();
    for (const branch of branches.sort((a, b) => Number(b.name === fork.default_branch) - Number(a.name === fork.default_branch))) {
      const head = branch.commit?.sha;
      if (!shaPattern.test(head)) throw Error('Missing fork head: ' + fork.full_name);
      if (seenHeads.has(head) || previous?.forks.some(record => record.repository === fork.full_name && record.head === head)) continue;
      seenHeads.add(head);
      const comparison = (await github.rest.repos.compareCommitsWithBasehead({...source,
        basehead: upstreamHead + '...' + head, per_page: 100})).data;
      if (!Number.isSafeInteger(comparison.ahead_by) || !Number.isSafeInteger(comparison.behind_by) ||
          !Array.isArray(comparison.commits)) throw Error('Incomplete fork comparison: ' + fork.full_name);
      snapshots.push({repository: fork.full_name, branch: branch.name, head, upstreamHead,
        ahead: comparison.ahead_by, behind: comparison.behind_by,
        compareUrl: 'https://github.com/' + fork.full_name + '/compare/' + upstreamHead + '...' + head,
        // A bounded excerpt for discovery; the compare link contains the full change set.
        commits: comparison.commits.slice(0, 12).map(c => ({sha: c.sha,
          title: c.commit.message.split('\n')[0], author: c.author?.login || c.commit.author.name}))});
    }
  }
  const changes = forkChanges(previous, snapshots);
  if (!changes) return;
  const identity = crypto.createHash('sha256').update(JSON.stringify(changes.batch.map(f => [f.repository, f.branch, f.head])))
    .digest('hex').slice(0, 12);
  const pr = await openDraft(github, context, {branch, sha, tree: commit.tree.sha}, prefix + identity,
    [{path, content: JSON.stringify(changes.checkpoint, null, 2) + '\n'}],
    'Assess active USDX fork changes',
    'New fork work for assessment:\n\n' + changes.batch.map(f =>
      '- [' + f.repository + '](' + f.compareUrl + '): ' + f.ahead + ' commits ahead of USDX').join('\n') +
    '\n\nThese comparisons identify commits outside upstream history, not necessarily features missing from USCE. ' +
    'The assessment records applicability, existing ports and related USCE issues or PRs. ' +
    'This proposal contains metadata only and does not import code or post to other repositories.', {reopenClosed: true});
  core.notice('Fork assessment: ' + pr.html_url);
}
module.exports = {activeForks, forkChanges, trackForks};
