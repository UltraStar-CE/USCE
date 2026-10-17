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

test('generated closing keywords cannot reach a candidate PR body', () => {
  for (const summary of ['Fixes #12', 'CLOSES owner/repo#4', 'Resolved https://github.com/o/r/issues/8', 'Fixes [#1](https://github.com/o/r/issues/1)']) {
    assert.throws(() => validateResult(JSON.stringify({summary, validation: 'Not run', files: []}), 'issue'), /closing keyword/);
  }
  assert.throws(() => validateResult(JSON.stringify({summary: 'Prevent crash', validation: 'fixes #12', files: []}), 'upstream'), /closing keyword/);
  assert.equal(validateResult(JSON.stringify({summary: 'Prevent crash', validation: 'Not run', files: []}), 'issue').files.length, 0);
});

test('PR review rejects missing and oversized patches instead of truncating', async () => {
  for (const patch of [undefined, '', 'x'.repeat(20001)]) {
    const github = {paginate: async () => [{filename: 'src/base/Test.pas', changes: 1, patch}], rest: {
      git: {getRef: async () => ({data: {object: {sha: 'base'}}}),
        getCommit: async () => ({data: {sha: 'base', tree: {sha: 'tree'}}})},
      pulls: {get: async () => ({data: {state: 'open', head: {sha: 'head'}}})},
    }};
    const context = {repo: {owner: 'o', repo: 'r'}, eventName: 'pull_request_target',
      payload: {repository: {default_branch: 'master'}, pull_request: {number: 1}}};
    await assert.rejects(prepare({github, context, core: {}}), /patch is missing or oversized/);
  }
});

test('aggregate UTF-8 upstream context becomes a persistent manual task', async () => {
  const outputs = {};
  const github = {rest: {git: {
    getRef: async () => ({data: {object: {sha: 'base'}}}),
    getCommit: async () => ({data: {sha: 'base', tree: {sha: 'tree'}}}),
  }, repos: {
    getCollaboratorPermissionLevel: async () => ({data: {permission: 'write'}}),
    compareCommits: async () => ({data: {status: 'ahead'}}),
    getCommit: async () => ({data: {html_url: 'source', commit: {message: 'change'},
      files: [{filename: 'src/base/Test.pas', patch: '\u20ac'.repeat(20000)}]}}),
  }}};
  const context = {repo: {owner: 'o', repo: 'r'}, actor: 'writer', eventName: 'workflow_dispatch',
    payload: {repository: {default_branch: 'master'}, inputs: {kind: 'upstream', source_sha: 'a'.repeat(40)}}};
  await prepare({github, context, core: {setOutput: (k,v) => outputs[k] = v}});
  assert.equal(outputs.kind, 'manual');
  assert.ok(Buffer.byteLength(outputs.task) < 60000);
  assert.match(JSON.parse(outputs.task).input.reason, /Combined source context/);
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

test('incomplete and oversized upstream patches require manual assessment without an agent task', async () => {
  for (const files of [[{filename: 'src/base/USong.pas'}], [{filename: 'src/base/USong.pas', patch: 'x'.repeat(20001)}]]) {
    const outputs = {};
    const github = {rest: {git: {
      getRef: async () => ({data: {object: {sha: 'base'}}}),
      getCommit: async () => ({data: {sha: 'base', tree: {sha: 'tree'}}}),
    }, repos: {
      getCollaboratorPermissionLevel: async () => ({data: {permission: 'write'}}),
      compareCommits: async () => ({data: {status: 'ahead'}}),
      getCommit: async () => ({data: {html_url: 'https://github.com/upstream/commit/test', files}}),
    }}};
    const context = {repo: {owner: 'o', repo: 'r'}, actor: 'writer', eventName: 'workflow_dispatch',
      payload: {repository: {default_branch: 'master'}, inputs: {kind: 'upstream', source_sha: 'a'.repeat(40)}}};
    await prepare({github, context, core: {setOutput: (k, v) => outputs[k] = v}});
    assert.equal(outputs.kind, 'manual');
    assert.equal(JSON.parse(outputs.task).input.files, undefined);
  }
});

test('an upstream no-candidate result persists a draft manual-assessment PR', async () => {
  const writes = [];
  const github = {rest: {pulls: {
    list: async () => ({data: []}),
    create: async x => { writes.push(x); return {data: {html_url: 'https://github.com/o/r/pull/7'}}; },
  }, git: {
    getRef: async () => ({data: {object: {sha: 'base'}}}),
    getTree: async () => ({data: {tree: []}}),
    createTree: async x => { writes.push(x); return {data: {sha: 'newtree'}}; },
    createCommit: async () => ({data: {sha: 'commit'}}),
    createRef: async () => ({}),
  }}};
  const task = {kind: 'upstream', base: {branch: 'master', sha: 'base', tree: 'tree'},
    input: {sha: 'a'.repeat(40), source: 'https://github.com/upstream/commit/a'}};
  await publish({github, context: {repo: {owner: 'o', repo: 'r'}}, core: {notice: () => {}}},
    JSON.stringify(task), JSON.stringify({summary: 'Needs build-script changes', validation: 'Not run', files: []}));
  assert.equal(writes[0].tree.length, 1);
  assert.match(writes[0].tree[0].path, /^doc\/upstream\/manual\//);
  assert.equal(writes[1].draft, true);
  assert.match(writes[1].head, /^automation\/upstream-manual-/);
});

test('the scheduled queue stops at an existing manual assessment instead of spending again', async () => {
  let outputs = 0;
  const github = {paginate: async () => [{sha: 'b'.repeat(40), html_url: 'source', commit: {message: 'change'}}], rest: {
    git: {
      getRef: async () => ({data: {object: {sha: 'base'}}}),
      getCommit: async () => ({data: {sha: 'base', tree: {sha: 'tree'}}}),
    }, repos: {
      getCollaboratorPermissionLevel: async () => ({data: {permission: 'write'}}),
      getContent: async () => { const e = Error('missing'); e.status = 404; throw e; },
      getCommit: async () => ({data: {sha: 'b'.repeat(40)}}),
      compareCommits: async () => ({data: {status: 'ahead', total_commits: 1, files: []}}),
    }, pulls: {list: async x => ({data: x.head.includes('upstream-manual-') ? [{html_url: 'manual PR'}] : []})},
  }};
  const context = {repo: {owner: 'o', repo: 'r'}, actor: 'writer', eventName: 'schedule',
    payload: {repository: {default_branch: 'master'}}};
  await prepare({github, context, core: {notice: () => {}, setOutput: () => outputs++}});
  assert.equal(outputs, 0);
});


test('upstream candidate proposals name the source author and retain the credit policy', async () => {
  let proposal;
  const github = {rest: {pulls: {
    list: async () => ({data: []}),
    create: async x => { proposal = x; return {data: {html_url: 'proposal'}}; },
  }, git: {
    getRef: async () => ({data: {object: {sha: 'base'}}}),
    getTree: async () => ({data: {tree: []}}),
    createTree: async () => ({data: {sha: 'tree'}}),
    createCommit: async () => ({data: {sha: 'commit'}}),
    createRef: async () => ({}),
  }}};
  const task = {kind: 'upstream', base: {branch: 'main', sha: 'base', tree: 'tree'},
    input: {sha: 'a'.repeat(40), source: 'https://github.com/upstream/commit/a', author: {name: 'Source Author'}}};
  await publish({github, context: {repo: {owner: 'o', repo: 'USCE'}}, core: {notice: () => {}}},
    JSON.stringify(task), JSON.stringify({summary: 'Adapt song loading', validation: 'Not run', files: [{path: 'doc/a.md', content: 'change'}]}));
  assert.match(proposal.body, /Upstream author: Source Author/);
  assert.match(proposal.body, /retain original authorship and credit in adaptation commits/);
  task.input.author.name = 'Fixes #123';
  proposal = undefined;
  await assert.rejects(publish({github, context: {repo: {owner: 'o', repo: 'USCE'}}, core: {notice: () => {}}},
    JSON.stringify(task), JSON.stringify({summary: 'Adapt song loading', validation: 'Not run', files: [{path: 'doc/a.md', content: 'change'}]})), /closing keyword/);
  assert.equal(proposal, undefined);
});


test('publication does not count or close unrelated PRs', async () => {
  const github = {rest: {pulls: {
    list: async x => { assert.ok(x.head, 'upstream publication must not request a slot'); return {data: []}; },
    create: async x => ({data: {state: 'open', ...x}}),
  }, git: {
    getRef: async () => ({data: {object: {sha: 'base'}}}),
    createTree: async () => ({data: {sha: 'tree'}}),
    createCommit: async () => ({data: {sha: 'commit'}}),
    createRef: async () => ({}),
  }}};
  const pr = await openDraft(github, {repo: {owner: 'UltraStar-CE', repo: 'USCE'}},
    {branch: 'main', sha: 'base', tree: 'tree'}, 'automation/upstream-usdx-aaaaaaaaaaaa', [], 'Assess upstream', 'Upstream changes');
  assert.equal(pr.state, 'open');
});

test('unmerged upstream commits cannot enter the adaptation path', async () => {
  for (const status of ['behind', 'diverged']) {
    const github = {rest: {git: {
      getRef: async () => ({data: {object: {sha: 'base'}}}),
      getCommit: async () => ({data: {sha: 'base', tree: {sha: 'tree'}}}),
    }, repos: {
      getCollaboratorPermissionLevel: async () => ({data: {permission: 'write'}}),
      compareCommits: async () => ({data: {status}}),
    }}};
    const context = {repo: {owner: 'UltraStar-CE', repo: 'USCE'}, actor: 'writer', eventName: 'workflow_dispatch',
      payload: {repository: {default_branch: 'main'}, inputs: {kind: 'upstream', source_sha: 'a'.repeat(40)}}};
    await assert.rejects(prepare({github, context, core: {}}), /must already be merged/);
  }
});


test('retry preserves the existing proposal without counting other PRs', async () => {
  const prior = {number: 17, state: 'open', user: {login: 'github-actions[bot]'}};
  const github = {rest: {pulls: {list: async x => ({data: x.head ? [prior] : x.repo === 'USCE'
    ? [prior, ...Array.from({length: 4}, (_, i) => ({number: i + 1, user: {login: 'github-actions[bot]'}}))] : []})}}};
  assert.equal(await openDraft(github, {repo: {owner: 'UltraStar-CE', repo: 'USCE'}}, {}, 'automation/test', [], '', ''), prior);
});
