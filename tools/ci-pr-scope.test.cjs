'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const {pullRequestFiles, requiredWorkflows} = require('./usce-ci.cjs');

test('PR scope ignores newer target changes and the checked-out test merge', () => {
  const cwd = fs.mkdtempSync(path.join(os.tmpdir(), 'usce-pr-scope-'));
  const git = (...args) => execFileSync('git', args, {cwd, encoding: 'utf8'}).trim();
  const write = (file, text) => {
    fs.mkdirSync(path.dirname(path.join(cwd, file)), {recursive: true});
    fs.writeFileSync(path.join(cwd, file), text);
  };
  const commit = message => { git('add', '.'); git('commit', '-m', message); return git('rev-parse', 'HEAD'); };
  try {
    git('init');
    git('config', 'user.name', 'Scope test');
    git('config', 'user.email', 'scope@example.invalid');
    write('src/editor.pas', 'old\n');
    const base = commit('base');
    git('checkout', '-b', 'proposal');
    write('src/editor.pas', 'new\n');
    const head = commit('editor change');
    git('checkout', '-b', 'target', base);
    write('tools/later.cjs', 'later target change\n');
    const newerBase = commit('target tooling');
    git('merge', '--no-ff', 'proposal', '-m', 'test merge');
    assert.deepEqual(pullRequestFiles(base, head, cwd), ['src/editor.pas']);
    assert.deepEqual(pullRequestFiles(newerBase, head, cwd), ['src/editor.pas']);
    assert.deepEqual(requiredWorkflows(pullRequestFiles(base, head, cwd)), ['main.yml']);
    git('checkout', 'proposal');
    git('mv', 'src/editor.pas', 'editor.md');
    const renamed = commit('rename code to documentation');
    assert.deepEqual(pullRequestFiles(newerBase, renamed, cwd), ['editor.md', 'src/editor.pas']);
    assert.deepEqual(requiredWorkflows(pullRequestFiles(newerBase, renamed, cwd)), ['main.yml']);
    assert.throws(() => pullRequestFiles('invalid', head, cwd), /Invalid PR base/);
    assert.throws(() => pullRequestFiles(base, 'HEAD', cwd), /Invalid PR head/);
  } finally {
    fs.rmSync(cwd, {recursive: true, force: true});
  }
});
