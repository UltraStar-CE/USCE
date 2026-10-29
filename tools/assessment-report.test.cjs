'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {issueReport, forkReport, upstreamReport} = require('./assessment-report.cjs');
const {validateResult} = require('./usce-automation.cjs');
test('reports expose source changes without closing referenced issues', () => {
  const issue = {number: 3, source: 'org/repo#3', title: 'Fix #4', state: 'closed', comments: 2, description: 'Crashes on exit'};
  const report = issueReport({batch: [issue]}, {issues: [{...issue, state: 'open', comments: 1, assessment: {decision: 'investigate', reason: 'needs reproduction'}}]});
  assert.match(report, /state, comments/);
  assert.match(report, /Crashes on exit/);
  assert.match(report, /needs reproduction/);
  assert.match(report, /&#70;ix #4/);
  validateResult(JSON.stringify({summary: report, validation: 'Not run', files: []}), 'issue');
});
test('fork excerpts stay below GitHub body limits and disclose omitted commits', () => {
  const commits = Array.from({length: 12}, () => ({sha: 'a'.repeat(40), title: 'x'.repeat(500), author: 'author'}));
  const report = forkReport({batch: Array.from({length: 20}, () => ({repository: 'a/repo', branch: 'feature', ahead: 20, behind: 4, compareUrl: 'https://github.com/a/repo/compare/a...b', commits}))});
  assert.ok(report.length < 65536);
  assert.match(report, /Only 6 commit titles/);
  assert.match(report, /Do not infer a speedup/);
});
test('upstream report includes commit subjects, file scope and incomplete coverage', () => {
  const report = upstreamReport({url: 'comparison', total: 1, commits: [{sha: 'a'.repeat(40), subject: 'Audio change'}], files: [{path: 'src/base/Audio.pas', status: 'modified'}], filesTruncated: true});
  assert.match(report, /Audio change/);
  assert.match(report, /src\/base\/Audio.pas/);
  assert.match(report, /comparison limit reached/);
});


test('closing-keyword escaping preserves exact comparison URL destinations', () => {
  const url = 'https://github.com/fix/usdx-resolve/compare/a...b';
  const commits = [{sha: 'a'.repeat(40), title: 'Fix #42', author: 'author'}];
  const fork = forkReport({batch: [{repository: 'fix/usdx-resolve', branch: 'fix',
    ahead: 1, behind: 0, compareUrl: url, commits}]});
  const upstream = upstreamReport({url, total: 1, commits, files: []});
  for (const report of [fork, upstream]) {
    assert.ok(report.includes(url));
    assert.match(report, /&#70;ix #42/);
    assert.ok(!report.includes('https://github.com/&#'));
  }
});
