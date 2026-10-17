'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {chooseRelease} = require('./monthly-release.cjs');
const pick = (date, upstream = null, releases = []) => chooseRelease({now: new Date(date), upstream, releases});
test('calendar fallback starts on the 24th in Vienna and catches up on later days', () => {
  assert.equal(pick('2026-10-23T21:59:00Z'), null);
  assert.equal(pick('2026-10-23T22:00:00Z').trigger, 'calendar-fallback');
  assert.equal(pick('2026-10-31T12:00:00Z').version, '2026.10.0');
  assert.equal(pick('2026-12-23T22:59:00Z'), null);
  assert.equal(pick('2026-12-23T23:00:00Z').version, '2026.12.0');
});
test('a current-month upstream stable release prepares early, older releases wait', () => {
  assert.equal(pick('2026-10-17T12:00:00Z', {tag_name:'v2026.10.0',sha:'source'}).trigger, 'upstream-release');
  assert.equal(pick('2026-10-17T12:00:00Z', {tag_name:'v2026.9.0'}), null);
  assert.equal(pick('2026-10-17T12:00:00Z', {tag_name:'v2026.10.0',prerelease:true}), null);
});
test('drafts, published releases and patches prevent duplicate monthly preparation', () => {
  for (const release of [{tag_name:'v2026.10.0',draft:true}, {tag_name:'v2026.10.0'}, {tag_name:'v2026.10.1'}]) {
    assert.equal(pick('2026-10-26T12:00:00Z', {tag_name:'v2026.10.1'}, [release]), null);
  }
  assert.equal(pick('2026-11-24T12:00:00Z',null,[{tag_name:'v2026.10.0'}]).version,'2026.11.0');
});
