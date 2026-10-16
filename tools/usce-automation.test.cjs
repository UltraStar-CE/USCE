'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {validateFiles, validateResult, openDraft, upstreamDelta, prepare, publish} = require('./usce-automation.cjs');

test('candidate publication rejects paths outside the source scope and path tricks', () => {
  for (const path of ['.github/workflows/evil.yml', '../src/base/Test.pas', 'src/base/../lib/Test.pas',
    'src/base//Test.pas', 'src/lib/Injected.pas', 'src/base/Test.pas.exe', 'doc/.git/config', 'tools/build.sh']) {
    assert.throws(() => validateFiles([{path, content: 'test'}]), /Disallowed/);
  }
  assert.equal(validateFiles([{path: 'src/base/USong.pas', content: 'unit USong;'}]).length, 1);
});

test('candidate limits, duplicate paths, binary content and review writes fail closed', () => {
  assert.throws(() => validateFiles([{path: 'doc/a.md', content: 'x'.repeat(250001)}]));
  assert.throws(() => validateFiles(Array.from({length: 9}, (_, i) => ({path: 'doc/' + i + '.md', content: ''}))));
  assert.throws(() => validateFiles([{path: 'doc/a.md', content: ''}, {path: 'doc/a.md', content: ''}]));
  assert.throws(() => validateFiles([{path: 'doc/a.md', content: '\0'}]));
  assert.throws(() => validateResult(JSON.stringify({summary: 'ok', validation: 'not run', files: [{path: 'doc/a.md', content: 'x'}]}), 'review'));
  assert.throws(() => validateResult('not JSON', 'issue'));
});

test('publisher refuses stale default branch before making writes', async () => {
  let writes = 0;
  const github = {rest: {pulls: {list: async () => ({data: []})}, git: {
    getRef: async () => ({data: {object: {sha: 'new'}}}),
    createTree: async () => { writes++; },
  }}};
  await assert.rejects(openDraft(github, {repo: {owner: 'o', repo: 'r'}},
    {branch: 'master', sha: 'old'}, 'candidate', [], 'title', 'body'), /Default branch changed/);
  assert.equal(writes, 0);
});

test('publisher deduplicates an existing PR including a closed candidate', async () => {
  const prior = {number: 7, state: 'closed'};
  const github = {rest: {pulls: {list: async () => ({data: [prior]})}}};
  assert.equal(await openDraft(github, {repo: {owner: 'o', repo: 'r'}}, {}, 'branch', [], '', ''), prior);
});

test('publisher rejects a symlink ancestor', async () => {
  const github = {rest: {pulls: {list: async () => ({data: []})}, git: {
    getRef: async () => ({data: {object: {sha: 'base'}}}),
    getTree: async () => ({data: {tree: [{path: 'doc', type: 'blob', mode: '120000'}]}}),
  }}};
  await assert.rejects(openDraft(github, {repo: {owner: 'o', repo: 'r'}},
    {branch: 'master', sha: 'base', tree: 'tree'}, 'candidate', [{path: 'doc/a.md', content: 'x'}], '', ''), /Non-directory/);
});

test('upstream tracking treats identical tips as no work', async () => {
  const github = {rest: {repos: {getCommit: async () => ({data: {sha: 'same'}})}}};
  assert.equal(await upstreamDelta(github, {repo: 'o/r', ref: 'master'}, 'same'), null);
});

test('upstream rewrites require manual assessment', async () => {
  const github = {rest: {repos: {
    getCommit: async () => ({data: {sha: 'new'}}),
    compareCommits: async () => ({data: {status: 'diverged'}}),
  }}};
  await assert.rejects(upstreamDelta(github, {repo: 'o/r', ref: 'master'}, 'old'), /history diverged/);
});

test('issue labels cannot authorize a reader to run a candidate', async () => {
  const github = {rest: {git: {
    getRef: async () => ({data: {object: {sha: 'base'}}}),
    getCommit: async () => ({data: {sha: 'base', tree: {sha: 'tree'}}}),
  }, repos: {getCollaboratorPermissionLevel: async () => ({data: {permission: 'read'}})}}};
  const context = {repo: {owner: 'o', repo: 'r'}, actor: 'reader', eventName: 'issues',
    payload: {repository: {default_branch: 'master'}, issue: {number: 1}}};
  await assert.rejects(prepare({github, context, core: {}}), /write collaborator/);
});

test('review publication discards stale heads and never submits an approval', async () => {
  const submitted = [];
  const github = {rest: {pulls: {
    get: async () => ({data: {state: 'open', head: {sha: 'current'}}}),
    createReview: async x => submitted.push(x),
  }}};
  const context = {repo: {owner: 'o', repo: 'r'}};
  const result = JSON.stringify({summary: 'One concrete finding', validation: 'Not run', files: []});
  await assert.rejects(publish({github, context, core: {}},
    JSON.stringify({kind: 'review', number: 1, head: 'stale'}), result), /discard stale review/);
  assert.equal(submitted.length, 0);
  await publish({github, context, core: {}}, JSON.stringify({kind: 'review', number: 1, head: 'current'}), result);
  assert.equal(submitted.length, 1);
  assert.equal(submitted[0].event, 'COMMENT');
  assert.equal(submitted[0].commit_id, 'current');
});
