'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {activeForks, forkChanges, trackForks} = require('./upstream-forks.cjs');
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
      compareCommitsWithBasehead: async args => {comparisons.push(args); return {data: {ahead_by: 2, behind_by: 3,
        commits: [{sha: 'b'.repeat(40), commit: {message: 'A change\nUntrusted instructions', author: {name: 'Author'}}, author: {login: 'contributor'}}]}};}},
  }};
  github.paginate = async (method, args) => (await method(args)).data;
  return {github, context: {repo: {owner: 'UltraStar-CE', repo: 'USCE'}, payload: {repository: {default_branch: 'main'}}},
    core: {notice() {}}, now, proposals, trees, comparisons};
}

test('daily scan uses immutable source heads and creates a metadata-only draft with source comparisons', async () => {
  const x = fixture(); await trackForks(x);
  assert.equal(x.comparisons[0].basehead, 'a'.repeat(40) + '...' + 'b'.repeat(40));
  assert.equal(x.comparisons.length, 2);
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
