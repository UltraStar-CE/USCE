'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {requiredWorkflows, waitForBuilds} = require('./usce-ci.cjs');
const sha = 'a'.repeat(40);
const context = {repo: {owner: 'UltraStar-CE', repo: 'USCE'}, payload: {pull_request: {head: {sha}}}};
const run = (conclusion, id = 1, head_sha = sha) => ({id, head_sha, event: 'pull_request', status: 'completed', conclusion});
function fixture(files, responses) {
  let time = 0;
  const calls = [];
  return {calls, args: {files, context, core: {info() {}}, now: () => time,
    timeoutMs: 50, pollMs: 10, sleep: async ms => { time += ms; },
    github: {rest: {actions: {listWorkflowRuns: async args => {
      calls.push(args);
      return {data: {workflow_runs: responses(args.workflow_id, calls.length)}};
    }}}}}};
}

test('README, policy, translation and banner changes need no build workflow', async () => {
  const f = fixture(['README.md', 'GOVERNANCE.md', 'branding/logo.png', 'languages/English.ini'], () => { throw Error('Unexpected build API call'); });
  assert.deepEqual(requiredWorkflows(f.args.files), []);
  await waitForBuilds(f.args);
  assert.equal(f.calls.length, 0);
});
test('code, build files, resources and deleted code require platform validation', () => {
  for (const file of ['src/base/UMain.pas', 'new-code.pas', 'configure.ac', 'Makefile.in',
    'dists/linux/Makefile', 'CMakeLists.txt', 'sub/CMakeLists.txt', 'LICENSE', 'icons/usce.ico', 'game/plugins/test.usdx']) {
    assert(requiredWorkflows([file]).includes('main.yml'), file);
  }
  assert.deepEqual(requiredWorkflows(['src/deleted.pas', 'doc/renamed.md']), ['main.yml']);
  assert.deepEqual(requiredWorkflows(['src/README.md', 'dists/linux/readme.txt']), []);
});
test('workflow and tooling changes also require automation tests', () => {
  assert.deepEqual(requiredWorkflows(['.github/workflows/main.yml']), ['main.yml', 'usce-automation-check.yml']);
  assert.deepEqual(requiredWorkflows(['tools/usce-ci.cjs']), ['main.yml', 'usce-automation-check.yml']);
});
test('failed, cancelled and skipped build workflows cannot satisfy the gate', async () => {
  for (const result of ['failure', 'cancelled', 'skipped', 'timed_out', 'neutral']) {
    const f = fixture(['src/a.pas'], () => [run(result)]);
    await assert.rejects(waitForBuilds(f.args), /Required main.yml finished/);
  }
});
test('a green workflow from a different revision or an older failed-attempt replacement is insufficient', async () => {
  const wrong = fixture(['src/a.pas'], () => [run('success', 10, 'b'.repeat(40))]);
  await assert.rejects(waitForBuilds(wrong.args), /did not finish/);
  const latest = fixture(['src/a.pas'], () => [run('success', 1), run('failure', 2)]);
  await assert.rejects(waitForBuilds(latest.args), /finished with failure/);
});
test('missing build runs fail closed and queued runs can finish successfully', async () => {
  const absent = fixture(['src/a.pas'], () => []);
  await assert.rejects(waitForBuilds(absent.args), /did not finish/);
  const pending = fixture(['src/a.pas'], (_, call) => call === 1
    ? [{...run(null), status: 'queued'}] : [run('success')]);
  await waitForBuilds(pending.args);
  assert.equal(pending.calls.length, 2);
  assert(pending.calls.every(call => call.head_sha === sha));
});
test('successful platform builds do not hide failed automation checks', async () => {
  const f = fixture(['tools/usce-ci.cjs'], workflow => [run(workflow === 'main.yml' ? 'success' : 'failure')]);
  await assert.rejects(waitForBuilds(f.args), /Required usce-automation-check.yml finished/);
});

test('large PRs receive an actionable error when GitHub truncates the workflow path filter', async () => {
  const files = Array.from({length: 3001}, (_, i) => `doc/${i}.md`).concat('src/a.pas');
  const f = fixture(files, () => []);
  f.args.timeoutMs = 120000;
  f.args.pollMs = 20000;
  await assert.rejects(waitForBuilds(f.args), /Split the change into smaller PRs/);
  assert.equal(f.calls.length, 4);
  const complete = fixture(files, () => [run('success')]);
  await waitForBuilds(complete.args);
});

test('candidate publisher requires every platform and whitespace on the resolved revision', async () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const vm = require('node:vm');
  const text = fs.readFileSync(path.join(__dirname, '../.github/workflows/candidate-validation.yml'), 'utf8');
  const body = text.slice(text.lastIndexOf('          script: |') + '          script: |'.length)
    .split('\n').map(line => line.replace(/^            /, '')).join('\n');
  const names = ['Build for Windows', 'Build for Linux', 'Build for MacOS (macos-15)', 'Build for MacOS (macos-15-intel)'];
  async function publish(results, lint = 'success', platform = 'success') {
    const statuses = [];
    const github = {paginate: async () => results, rest: {actions: {listJobsForWorkflowRun() {}},
      repos: {createCommitStatus: async value => { statuses.push(value); }}}};
    await vm.runInNewContext(`(async () => {${body}\n})()`, {github,
      context: {...context, serverUrl: 'https://github.com', runId: 123},
      process: {env: {TARGET_SHA: sha, LINT_RESULT: lint, PLATFORM_RESULT: platform}}});
    assert(statuses.every(value => value.sha === sha));
    return statuses.find(value => value.context === 'Check trailing whitespace').state;
  }
  const jobs = names.map(name => ({name: 'Candidate platforms / ' + name, conclusion: 'success'}));
  assert.equal(await publish(jobs), 'success');
  assert.equal(await publish(jobs.slice(1)), 'failure');
  assert.equal(await publish([...jobs, jobs[0]]), 'failure');
  assert.equal(await publish(jobs, 'failure'), 'failure');
  assert.equal(await publish(jobs, 'success', 'cancelled'), 'failure');
  for (const result of ['failure', 'cancelled', 'skipped', null]) {
    assert.equal(await publish(jobs.map((job, i) => i === 0 ? {...job, conclusion: result} : job)), 'failure');
  }
});

test('failure diagnostics identify runner cancellations and actual failed steps', async () => {
  const f = fixture(['src/a.pas'], () => [run('failure', 42)]);
  f.args.github.rest.actions.listJobsForWorkflowRun = () => {};
  f.args.github.paginate = async (_, args) => {
    assert.equal(args.run_id, 42);
    assert.equal(args.filter, 'latest');
    return [{name: 'Build for MacOS (macos-15)', conclusion: 'cancelled', steps: []},
      {name: 'Build for Linux', conclusion: 'failure', steps: [{name: 'Compile', conclusion: 'failure'}]},
      {name: 'Build for Windows', conclusion: 'success', steps: []}];
  };
  await assert.rejects(waitForBuilds(f.args), error => {
    assert.match(error.message, /MacOS.*cancelled before any steps ran/);
    assert.match(error.message, /Linux: failure at Compile/);
    assert.doesNotMatch(error.message, /Windows: success/);
    return true;
  });
});

test('unavailable failure details cannot make a failed build pass', async () => {
  const f = fixture(['src/a.pas'], () => [run('failure')]);
  f.args.github.paginate = async () => { throw Error('API unavailable'); };
  await assert.rejects(waitForBuilds(f.args), /Required main.yml finished with failure/);
});

test('ARM macOS uses an explicit supported image and remains required for candidates', () => {
  const fs = require('node:fs');
  const path = require('node:path');
  const workflow = fs.readFileSync(path.join(__dirname, '../.github/workflows/platform-builds.yml'), 'utf8');
  assert.match(workflow, /os: \[macos-15, macos-15-intel\]/);
  assert.match(workflow, /fail-fast: false/);
  const candidate = fs.readFileSync(path.join(__dirname, '../.github/workflows/candidate-validation.yml'), 'utf8');
  assert(candidate.includes("'Build for MacOS (macos-15)'"));
});
