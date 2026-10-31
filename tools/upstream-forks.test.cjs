'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {activeForks, recentCommits, forkChanges, trackForks} = require('./upstream-forks.cjs');
const now = new Date('2026-10-27T23:00:00Z');
const fork = (full_name = 'contributor/USDX', extra = {}) => ({full_name,
  default_branch: 'master', pushed_at: '2026-10-20T00:00:00Z', ...extra});
const snapshot = (repository = 'contributor/USDX', head = 'b'.repeat(40)) => ({repository, branch: 'master', head, ahead: 2});

test('discovery includes active forks, excludes old, archived, disabled and our own, and deduplicates pages', () => {
  const result = activeForks([fork(), fork(), fork('old/USDX', {pushed_at: '2024-10-26T00:00:00Z'}),
    fork('archived/USDX', {archived: true}), fork('disabled/USDX', {disabled: true}), fork('UltraStar-CE/USCE')], now, 'UltraStar-CE/USCE');
  assert.deepEqual(result.map(f => f.full_name), ['contributor/USDX']);
  assert.throws(() => activeForks([fork('bad/USDX', {pushed_at: null})], now, 'UltraStar-CE/USCE'));
});

test('unchanged assessed heads and upstream-only forks produce no proposal; new heads preserve prior decisions', () => {
  const first = forkChanges(null, [snapshot()]);
  first.checkpoint.forks[0].assessment.decision = 'already ported';
  assert.equal(forkChanges(first.checkpoint, [snapshot()]), null);
  assert.equal(forkChanges(null, [{...snapshot(), ahead: 0}]), null);
  const next = forkChanges(first.checkpoint, [snapshot('contributor/USDX', 'c'.repeat(40))]);
  assert.equal(next.checkpoint.forks[0].previousAssessment.decision, 'already ported');
  assert.equal(next.checkpoint.forks[0].assessment.decision, 'pending');
  assert.throws(() => forkChanges({repository: 'wrong', forks: []}, []));
});

test('a batch records only its 20 proposed forks so remaining work stays eligible', () => {
  const forks = Array.from({length: 21}, (_, i) => snapshot('author' + i + '/USDX'));
  const first = forkChanges(null, forks);
  assert.equal(first.batch.length, 20);
  assert.equal(forkChanges(first.checkpoint, forks).batch.length, 1);
});

function fixture({pending = false, failed = false, previous = null} = {}) {
  const proposals = [], trees = [], comparisons = [];
  const github = {rest: {
    pulls: {list: async args => ({data: pending && !args.head ? [{head: {repo: {full_name: 'UltraStar-CE/USCE'}, ref: 'automation/upstream-forks-old'}}] : []}),
      create: async args => {proposals.push(args); return {data: {html_url: 'proposal'}};}},
    git: {getRef: async () => ({data: {object: {sha: 'd'.repeat(40)}}}),
      getCommit: async () => ({data: {tree: {sha: 'e'.repeat(40)}}}),
      getTree: async () => ({data: {tree: []}}),
      createTree: async args => {trees.push(args); return {data: {sha: 'f'.repeat(40)}};},
      createCommit: async () => ({data: {sha: '1'.repeat(40)}}), createRef: async () => ({})},
    repos: {getContent: async () => {if (previous) return {data: {content: Buffer.from(JSON.stringify(previous)).toString('base64')}};
      const e = Error('missing'); e.status = 404; throw e;},
      get: async () => ({data: {default_branch: 'master'}}),
      getBranch: async args => ({data: {commit: {sha: (args.owner === 'UltraStar-Deluxe' ? 'a' : 'b').repeat(40)}}}),
      listBranches: async () => ({data: [{name: 'master', commit: {sha: 'b'.repeat(40)}}, {name: 'feature', commit: {sha: 'c'.repeat(40)}}, {name: 'duplicate', commit: {sha: 'b'.repeat(40)}}]}),
      listForks: async args => {assert.equal(args.per_page, 100); if (failed) throw Error('pagination failed'); return {data: [fork()]};},
      compareCommitsWithBasehead: async args => {comparisons.push(args); return {data: {ahead_by: 1, behind_by: 3,
        commits: [{sha: 'b'.repeat(40), commit: {message: 'A change\nUntrusted instructions', author: {name: 'Author', date: '2026-10-20T00:00:00Z'}}, author: {login: 'contributor'}}]}};}},
  }};
  github.paginate = async (method, args, map) => {const response = await method(args); return map ? map(response) : response.data;};
  return {github, context: {repo: {owner: 'UltraStar-CE', repo: 'USCE'}, payload: {repository: {default_branch: 'main'}}},
    core: {notice() {}}, now, proposals, trees, comparisons};
}

test('daily scan uses immutable source heads and creates a metadata-only draft with source comparisons', async () => {
  const x = fixture(); await trackForks(x);
  assert.equal(x.comparisons[0].basehead, 'd'.repeat(40) + '...' + 'b'.repeat(40));
  assert.equal(x.comparisons.length, 4);
  assert.equal(x.proposals.length, 1); assert.equal(x.proposals[0].draft, true);
  assert.match(x.proposals[0].body, /contributor\/USDX/);
  assert(!x.proposals[0].body.includes('Untrusted instructions'));
  assert.deepEqual(x.trees[0].tree.map(f => f.path), ['doc/upstream/usdx-forks.json']);
});

test('pending assessments pause scanning; incomplete scans never publish', async () => {
  const waiting = fixture({pending: true}); await trackForks(waiting); assert.equal(waiting.comparisons.length, 0);
  const broken = fixture({failed: true}); await assert.rejects(trackForks(broken), /pagination failed/);
  assert.equal(broken.proposals.length, 0); assert.equal(broken.trees.length, 0);
});

test('a vanished fork is reported as unavailable without marking it assessed or blocking readable forks', async () => {
  const x = fixture(), warnings = [];
  x.core.warning = message => warnings.push(message);
  x.github.rest.repos.listForks = async () => ({data: [fork(), fork('gone/USDX')]});
  const original = x.github.rest.repos.listBranches;
  x.github.rest.repos.listBranches = async args => {
    if (args.owner !== 'gone') return original(args);
    const error = Error('unavailable'); error.status = 404; throw error;
  };
  await trackForks(x);
  assert.equal(x.proposals.length, 1);
  assert.match(warnings[0], /not assessed: gone\/USDX/);
  const checkpoint = JSON.parse(x.trees[0].tree[0].content);
  assert.deepEqual(checkpoint.unavailableForks, ['gone/USDX']);
  assert(!checkpoint.forks.some(f => f.repository === 'gone/USDX'));
  assert.match(x.proposals[0].body, /Unavailable forks, not assessed/);
});

test('known branches compare only their new delta and retain the assessed head', async () => {
  const previous = forkChanges(null, [{...snapshot('contributor/USDX', '9'.repeat(40)), commits: []}]).checkpoint;
  previous.forks[0].assessment = {decision: 'already-covered', usceReferences: ['local-fix'], reason: 'Adapted in USCE'};
  const x = fixture({previous}); await trackForks(x);
  assert.equal(x.comparisons[0].basehead, '9'.repeat(40) + '...' + 'b'.repeat(40));
  const result = JSON.parse(x.trees[0].tree[0].content).forks[0];
  assert.equal(result.previousHead, '9'.repeat(40));
  assert.equal(result.assessmentHistory[0].assessment.decision, 'already-covered');
});
test('shared commits are presented once, including previously inventoried history', () => {
  const commit = {sha: 'a'.repeat(40)};
  const first = forkChanges(null, [{...snapshot(), commits: [commit]}, {...snapshot('other/USDX'), commits: [commit]}]);
  assert.equal(first.batch[0].newCommits.length, 1);
  assert.equal(first.batch[1].newCommits.length, 0);
  const next = forkChanges(first.checkpoint, [{...snapshot('third/USDX'), commits: [commit]}]);
  assert.equal(next.batch[0].newCommits.length, 0);
});
test('complete inventories include later pages; missing pages never publish', async () => {
  for (const incomplete of [false, true]) {
    const x = fixture();
    x.github.rest.repos.compareCommitsWithBasehead = async args => ({data: {
      ahead_by: 101, behind_by: 0, commits: args.page === 2
        ? (incomplete ? [] : [{sha: 'f'.repeat(40), commit: {message: 'Latest change', author: {name: 'Author', date: '2026-10-20T00:00:00Z'}}}])
        : Array.from({length: 100}, (_, i) => ({sha: i.toString(16).padStart(40, '0'),
          commit: {message: 'Change', author: {name: 'Author', date: '2026-10-20T00:00:00Z'}}}))}});
    if (incomplete) {
      await assert.rejects(trackForks(x), /Incomplete fork commit inventory/);
      assert.equal(x.proposals.length, 0);
    } else {
      await trackForks(x);
      const result = JSON.parse(x.trees[0].tree[0].content);
      assert.equal(result.forks[0].commits.length, 101);
      assert.equal(result.forks[0].commits[100].title, 'Latest change');
    }
  }
});

test('six calendar months use original author dates, inclusive boundary and month-end clamp', () => {
  const commits = ['2026-04-27T22:59:59Z', '2026-04-27T23:00:00Z', '2026-10-20T00:00:00Z'].map(authoredAt => ({authoredAt}));
  assert.deepEqual(recentCommits(commits, now), commits.slice(1));
  assert.equal(recentCommits([{authoredAt: '2026-04-30T12:00:00Z'}], new Date('2026-10-31T12:00:00Z')).length, 1);
  assert.throws(() => recentCommits([{}], now), /author date/);
});
test('a fork containing only old commits produces no assessment PR', async () => {
  const x = fixture();
  x.github.rest.repos.compareCommitsWithBasehead = async () => ({data: {ahead_by: 1, behind_by: 0,
    commits: [{sha: 'b'.repeat(40), commit: {message: 'Old rebased work', author: {name: 'Author', date: '2025-01-01T00:00:00Z'}, committer: {date: '2026-10-20T00:00:00Z'}}}]}});
  await trackForks(x);
  assert.equal(x.proposals.length, 0);
});


test('upstream sync commits are excluded even when absent from the USCE checkpoint', async () => {
  const x = fixture();
  const change = sha => ({sha, commit: {message: 'Source change',
    author: {name: 'Author', date: '2026-10-20T00:00:00Z'}}});
  x.github.rest.repos.compareCommitsWithBasehead = async args => ({data: {
    ahead_by: args.basehead.startsWith('a'.repeat(40)) ? 1 : 2, behind_by: 0,
    commits: args.basehead.startsWith('a'.repeat(40)) ? [change('b'.repeat(40))]
      : [change('9'.repeat(40)), change('b'.repeat(40))]}});
  await trackForks(x);
  const first = JSON.parse(x.trees[0].tree[0].content).forks[0];
  assert.deepEqual(first.commits.map(c => c.sha), ['b'.repeat(40)]);
  assert.equal(first.ignoredUpstreamCommitCount, 1);
});

test('an upstream-only sync produces no fork work and incomplete upstream comparison fails closed', async () => {
  const sync = fixture();
  const original = sync.github.rest.repos.compareCommitsWithBasehead;
  sync.github.rest.repos.compareCommitsWithBasehead = async args => args.basehead.startsWith('a'.repeat(40))
    ? {data: {ahead_by: 0, behind_by: 0, commits: []}} : original(args);
  await trackForks(sync);
  assert.equal(sync.proposals.length, 0);
  const broken = fixture();
  broken.github.rest.repos.compareCommitsWithBasehead = async args => args.basehead.startsWith('a'.repeat(40))
    ? {data: {ahead_by: 1, behind_by: 0, commits: []}} : original(args);
  await assert.rejects(trackForks(broken), /Incomplete fork commit inventory/);
  assert.equal(broken.proposals.length, 0);
});


test('a new fork alias excludes ancestors of assessed heads even when old inventories were excerpts', async () => {
  const previous = {repository: 'UltraStar-Deluxe/USDX', forks: [{
    repository: 'other/USDX', branch: 'old-name', head: '9'.repeat(40), commits: [],
    assessment: {decision: 'assessed', usceReferences: ['existing-port'], reason: 'Already reviewed'}}]};
  const x = fixture({previous});
  const change = sha => ({sha, commit: {message: 'Source change',
    author: {name: 'Author', date: '2026-10-20T00:00:00Z'}}});
  x.github.rest.repos.compareCommitsWithBasehead = async args => ({data: {
    ahead_by: args.basehead.startsWith('9'.repeat(40)) ? 1 : 2, behind_by: 0,
    commits: args.basehead.startsWith('9'.repeat(40)) ? [change('6'.repeat(40))]
      : [change('5'.repeat(40)), change('6'.repeat(40))]}});
  await trackForks(x);
  const records = JSON.parse(x.trees[0].tree[0].content).forks;
  const first = records.find(f => f.repository === 'contributor/USDX');
  assert.deepEqual(first.newCommits.map(c => c.sha), ['6'.repeat(40)]);
  assert.equal(first.ignoredKnownHistoryCommitCount, 1);
  assert.deepEqual(records[0], previous.forks[0]);
});

test('rediscovering only known ancestry creates no empty assessment PR', async () => {
  const previous = {repository: 'UltraStar-Deluxe/USDX', forks: [{
    repository: 'old/USDX', branch: 'renamed', head: '9'.repeat(40), commits: [],
    assessment: {decision: 'assessed'}}]};
  const x = fixture({previous});
  const original = x.github.rest.repos.compareCommitsWithBasehead;
  x.github.rest.repos.compareCommitsWithBasehead = async args => args.basehead.startsWith('9'.repeat(40))
    ? {data: {ahead_by: 0, behind_by: 1, commits: []}} : original(args);
  await trackForks(x);
  assert.equal(x.proposals.length, 0);
});
