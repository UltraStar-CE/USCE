'use strict';

// This module runs only from the trusted default branch, never a PR checkout.
const TRACKS = [
  {id: 'usdx', repo: 'UltraStar-Deluxe/USDX', ref: 'master', baseline: '05a3cb37c63361695b16e777f5b5678ebd873198'},
  {id: 'mxe', repo: 'UltraStar-Deluxe/mxe', ref: 'ultrastardx', baseline: '355c55d2723e344c47cf353f9d47699a2ce1150a'},
  {id: 'themes', repo: 'UltraStar-Deluxe/Themes', ref: 'main', baseline: 'f21d921f43e6cd430435a2cb5423f2bf5243f6c9'},
];
const SHA = /^[a-f0-9]{40}$/;
const bounded = (x, max = 24000) => String(x || '').slice(0, max);
const repoParts = repo => { const [owner, name] = repo.split('/'); return {owner, repo: name}; };

function validateFiles(files) {
  if (!Array.isArray(files) || files.length > 8) throw Error('At most eight candidate files are allowed');
  let bytes = 0;
  const seen = new Set();
  for (const f of files) {
    if (!f || typeof f.path !== 'string' || typeof f.content !== 'string') throw Error('Invalid candidate file');
    // No workflows, credentials, executable build scripts, vendored code, or arbitrary paths.
    if (!/^(src\/(?:base|screens|classes|menu)\/[A-Za-z0-9_/-]+\.pas|doc\/[A-Za-z0-9_/-]+\.md|test\/[A-Za-z0-9_/-]+\.pas)$/.test(f.path)
        || f.path.includes('..') || f.path.includes('//') || seen.has(f.path)) throw Error('Disallowed candidate path: ' + f.path);
    if (f.content.includes('\0')) throw Error('Binary content is not permitted');
    seen.add(f.path);
    bytes += Buffer.byteLength(f.content);
  }
  if (bytes > 250000) throw Error('Candidate exceeds 250 KB');
  return files;
}

async function baseInfo(github, context) {
  const repo = context.repo;
  const branch = context.payload.repository.default_branch;
  const ref = await github.rest.git.getRef({...repo, ref: 'heads/' + branch});
  const commit = await github.rest.git.getCommit({...repo, commit_sha: ref.data.object.sha});
  return {branch, sha: commit.data.sha, tree: commit.data.tree.sha};
}

async function openDraft(github, context, base, branch, files, title, body) {
  const repo = context.repo;
  const existing = await github.rest.pulls.list({...repo, state: 'all', head: repo.owner + ':' + branch, per_page: 100});
  if (existing.data.length) return existing.data[0];
  const now = await github.rest.git.getRef({...repo, ref: 'heads/' + base.branch});
  if (now.data.object.sha !== base.sha) throw Error('Default branch changed; rerun against its new head');
  // Refuse replacement of symlinks, submodules, directories, or executable files.
  for (const f of files) {
    const parts = f.path.split('/');
    let treeSha = base.tree;
    for (let i = 0; i < parts.length; ++i) {
      const tree = await github.rest.git.getTree({...repo, tree_sha: treeSha});
      const entry = tree.data.tree.find(e => e.path === parts[i]);
      if (!entry) break;
      if (i < parts.length - 1) {
        if (entry.type !== 'tree') throw Error('Non-directory ancestor: ' + f.path);
        treeSha = entry.sha;
      } else if (entry.mode !== '100644' || entry.type !== 'blob') {
        throw Error('Only ordinary text files may be replaced: ' + f.path);
      }
    }
  }
  const tree = await github.rest.git.createTree({...repo, base_tree: base.tree,
    tree: files.map(f => ({path: f.path, mode: '100644', type: 'blob', content: f.content}))});
  const commit = await github.rest.git.createCommit({...repo, message: title, tree: tree.data.sha, parents: [base.sha]});
  try {
    await github.rest.git.createRef({...repo, ref: 'refs/heads/' + branch, sha: commit.data.sha});
  } catch (e) {
    // A failed PR creation can be retried; never overwrite a branch changed by a person.
    if (e.status !== 422) throw e;
    const ref = await github.rest.git.getRef({...repo, ref: 'heads/' + branch});
    const prior = await github.rest.git.getCommit({...repo, commit_sha: ref.data.object.sha});
    if (prior.data.tree.sha !== tree.data.sha) throw Error('Candidate branch already exists with different content');
  }
  return (await github.rest.pulls.create({...repo, base: base.branch, head: branch, title, body, draft: true})).data;
}

async function checkpoint(github, context, base, track) {
  const path = 'doc/upstream/' + track.id + '-checkpoint.json';
  try {
    const r = await github.rest.repos.getContent({...context.repo, path, ref: base.sha});
    const value = JSON.parse(Buffer.from(r.data.content, 'base64').toString());
    if (!SHA.test(value.sha)) throw Error('Invalid checkpoint');
    return value.sha;
  } catch (e) {
    if (e.status === 404) return track.baseline;
    throw e;
  }
}

async function upstreamDelta(github, track, from) {
  const repo = repoParts(track.repo);
  const tip = await github.rest.repos.getCommit({...repo, ref: track.ref});
  const to = tip.data.sha;
  if (to === from) return null;
  const comparison = await github.rest.repos.compareCommits({...repo, base: from, head: to, per_page: 100, page: 1});
  if (comparison.data.status !== 'ahead') throw Error('Upstream history diverged for ' + track.repo + '; manual assessment required');
  const commits = await github.paginate(github.rest.repos.compareCommits, {...repo, base: from, head: to, per_page: 100}, r => r.data.commits);
  return {track, from, to, url: 'https://github.com/' + track.repo + '/compare/' + from + '...' + to,
    total: comparison.data.total_commits,
    commits: commits.map(c => ({sha: c.sha, url: c.html_url, subject: bounded(c.commit.message.split('\n')[0], 300)})),
    files: (comparison.data.files || []).map(f => ({path: f.filename, status: f.status, patch: bounded(f.patch, 16000)})),
    filesTruncated: (comparison.data.files || []).length >= 300};
}

async function trackUpstream({github, context, core}) {
  const base = await baseInfo(github, context);
  for (const track of TRACKS) {
    const from = await checkpoint(github, context, base, track);
    const delta = await upstreamDelta(github, track, from);
    if (!delta) continue;
    const name = 'automation/upstream-' + track.id + '-' + delta.to.slice(0, 12);
    const content = {repository: track.repo, branch: track.ref, from, sha: delta.to,
      meaning: 'Assessed upstream tip, not a claim that changes have been incorporated',
      comparison: delta.url, commits: delta.commits};
    const pr = await openDraft(github, context, base, name,
      [{path: 'doc/upstream/' + track.id + '-checkpoint.json', content: JSON.stringify(content, null, 2) + '\n'}],
      'Assess upstream ' + track.id + ' changes through ' + delta.to.slice(0, 12),
      'Upstream changes: ' + delta.url + '\n\nThis PR records an assessment checkpoint only. Before merging, link reviewed adaptation PRs in the appropriate USCE, MXE, or Themes repository for every commit, or record an explicit deferral with a reason. Do not treat this checkpoint as code integration. Preserve source authorship and license notices.\n\n' +
      'For USDX code adaptation, run the USCE agent workflow with kind=upstream and the source commit SHA. Complex changes and MXE/Themes changes need maintainer-led adaptation PRs.\n\nNo automatic merge. Human approvals and required CI apply.');
    core.notice('Upstream assessment: ' + pr.html_url);
  }
}

async function prepare({github, context, core}) {
  const base = await baseInfo(github, context);
  let task;
  if (context.eventName === 'pull_request_target') {
    const number = context.payload.pull_request.number;
    const r = await github.rest.pulls.get({...context.repo, pull_number: number});
    if (r.data.state !== 'open') return;
    const files = await github.paginate(github.rest.pulls.listFiles, {...context.repo, pull_number: number, per_page: 100});
    if (files.length > 80 || files.some(f => f.changes > 1500)) throw Error('PR too large for this automated review; request human review');
    task = {kind: 'review', number, head: r.data.head.sha, base,
      input: {title: bounded(r.data.title, 300), body: bounded(r.data.body), files: files.map(f => ({path: f.filename, patch: bounded(f.patch, 20000)}))}};
  } else {
    // Issue labeling and dispatch require an actual write collaborator. A label name alone is not authorization.
    const permission = await github.rest.repos.getCollaboratorPermissionLevel({...context.repo, username: context.actor});
    if (!['write', 'maintain', 'admin'].includes(permission.data.permission)) throw Error('A write collaborator must authorize candidate generation');
    const kind = context.eventName === 'issues' ? 'issue' : context.eventName === 'schedule' ? 'upstream' : context.payload.inputs?.kind;
    if (kind === 'issue') {
      const number = Number(context.payload.issue?.number || context.payload.inputs?.number);
      if (!Number.isSafeInteger(number) || number < 1) throw Error('Invalid issue number');
      const r = await github.rest.issues.get({...context.repo, issue_number: number});
      if (r.data.pull_request || r.data.state !== 'open' || !r.data.labels.some(l => l.name === 'agent:fix')) throw Error('Open issue must carry the maintainer-applied agent:fix label');
      task = {kind, number, base, input: {title: bounded(r.data.title, 300), body: bounded(r.data.body), reporter: r.data.user.login}};
    } else if (kind === 'upstream') {
      let sha = context.payload.inputs?.source_sha;
      if (context.eventName === 'schedule') {
        const track = TRACKS[0];
        const from = await checkpoint(github, context, base, track);
        const delta = await upstreamDelta(github, track, from);
        if (!delta) return;
        // Process one source commit per daily run, with a persistent branch per
        // source SHA. Closed candidates count as handled until a human retries.
        for (const commit of delta.commits) {
          const head = context.repo.owner + ':automation/candidate-upstream-' + commit.sha.slice(0, 12);
          const prior = await github.rest.pulls.list({...context.repo, head, state: 'all', per_page: 100});
          if (!prior.data.length) { sha = commit.sha; break; }
        }
        if (!sha) return;
      }
      if (!SHA.test(sha || '')) throw Error('Supply a full source commit SHA');
      const source = await github.rest.repos.getCommit({...repoParts(TRACKS[0].repo), ref: sha});
      if ((source.data.files || []).length > 30) throw Error('Upstream change is too large for candidate automation');
      task = {kind, number: 0, base, input: {source: source.data.html_url, sha,
        author: source.data.commit.author,
        message: bounded(source.data.commit.message), files: source.data.files.map(f => ({path: f.filename, status: f.status, patch: bounded(f.patch, 20000)}))}};
    } else throw Error('Unsupported task');
  }
  if (JSON.stringify(task).length > 150000) throw Error('Input exceeds the automated review limit');
  core.setOutput('task', JSON.stringify(task));
  core.setOutput('kind', task.kind);
  core.setOutput('base', base.sha);
}

function validateResult(text, kind) {
  if (!text || Buffer.byteLength(text) > 300000) throw Error('Missing or oversized agent response');
  const result = JSON.parse(text);
  if (typeof result.summary !== 'string' || result.summary.length > 12000 || typeof result.validation !== 'string'
      || result.validation.length > 12000) throw Error('Invalid summary or validation');
  validateFiles(result.files);
  if (kind === 'review' && result.files.length) throw Error('Review may not propose file writes');
  return result;
}

async function publish({github, context, core}, taskText, resultText) {
  const task = JSON.parse(taskText);
  const result = validateResult(resultText, task.kind);
  const validation = '\n\nValidation reported by the agent (not independently verified):\n' + result.validation;
  if (task.kind === 'review') {
    const r = await github.rest.pulls.get({...context.repo, pull_number: task.number});
    if (r.data.state !== 'open' || r.data.head.sha !== task.head) throw Error('PR changed; discard stale review');
    await github.rest.pulls.createReview({...context.repo, pull_number: task.number, commit_id: task.head,
      event: 'COMMENT', body: 'Automated advisory review for ' + task.head + '\n\n' + result.summary + validation +
        '\n\nThis is not a human approval.'});
    return;
  }
  if (!result.files.length) {
    core.warning('Agent could not produce an in-scope candidate: ' + result.summary);
    return;
  }
  if (task.kind === 'issue') {
    const r = await github.rest.issues.get({...context.repo, issue_number: task.number});
    if (r.data.state !== 'open' || !r.data.labels.some(l => l.name === 'agent:fix')) throw Error('Issue authorization was withdrawn');
  }
  const identity = task.kind === 'issue' ? 'issue-' + task.number : 'upstream-' + task.input.sha.slice(0, 12);
  const branch = 'automation/candidate-' + identity + (task.kind === 'issue' ? '-' + task.base.sha.slice(0, 8) : '');
  const body = 'AI-generated candidate. Human review and required CI are needed.\n\n' + result.summary + validation +
    (task.kind === 'issue' ? '\n\nRelated issue #' + task.number + '. Reporter confirmation is pending. Do not use closing keywords. A maintainer must provide a tested build or testing instructions.' :
      '\n\nAdapted from ' + task.input.source + '. Preserve original authorship and credit in the final commit. Record omitted hunks and compatibility adjustments before merge.') +
    '\n\nThe agent did not execute the candidate. A human must verify tests and provenance. No automatic merge.';
  const pr = await openDraft(github, context, task.base, branch, result.files, 'Candidate for ' + identity, body);
  core.notice('Candidate PR: ' + pr.html_url);
  if (task.kind === 'issue') {
    const marker = '<!-- usce-candidate:' + pr.number + ' -->';
    const comments = await github.paginate(github.rest.issues.listComments, {...context.repo, issue_number: task.number, per_page: 100});
    if (!comments.some(c => c.body?.includes(marker) && c.user.type === 'Bot')) {
      await github.rest.issues.createComment({...context.repo, issue_number: task.number,
        body: marker + '\nA candidate fix is available in ' + pr.html_url + '. It still needs maintainer review and a test build. Once a maintainer provides that build or testing instructions, please let us know whether it resolves the issue, still fails, or you cannot test it. No response will be treated as confirmation; this issue stays open for a human decision.'});
    }
  }
}

module.exports = {TRACKS, validateFiles, validateResult, openDraft, upstreamDelta, prepare, publish, trackUpstream};
