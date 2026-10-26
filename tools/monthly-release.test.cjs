'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {chooseRelease, chooseComparisonRelease} = require('./monthly-release.cjs');
const pick = (date, upstream = null, releases = []) => chooseRelease({now: new Date(date), upstream, releases});
test('calendar fallback starts on the 24th in Vienna and catches up on later days', () => {
  assert.equal(pick('2026-10-23T21:59:00Z'), null);
  assert.equal(pick('2026-10-23T22:00:00Z').trigger, 'calendar-fallback');
  assert.equal(pick('2026-10-31T12:00:00Z').version, '2026.10.0');
  assert.equal(pick('2026-12-23T22:59:00Z'), null);
  assert.equal(pick('2026-12-23T23:00:00Z').version, '2026.12.0');
});
test('a current-month upstream stable release waits 24 hours, older releases wait', () => {
  const upstream = {tag_name:'v2026.10.0',sha:'source',published_at:'2026-10-17T07:32:01Z'};
  assert.equal(pick('2026-10-18T07:32:00Z', upstream), null);
  const plan = pick('2026-10-18T07:32:01Z', upstream);
  assert.equal(plan.trigger, 'upstream-release');
  assert.equal(plan.releaseAfter, '2026-10-18T07:32:01.000Z');
  assert.equal(pick('2026-10-17T12:00:00Z', {tag_name:'v2026.9.0'}), null);
  assert.equal(pick('2026-10-17T12:00:00Z', {tag_name:'v2026.10.0',prerelease:true}), null);
});

test('the calendar fallback does not bypass a freshly published USDX release', () => {
  const upstream = {tag_name:'v2026.10.0',published_at:'2026-10-24T12:00:00Z'};
  assert.equal(pick('2026-10-24T13:00:00Z', upstream), null);
  assert.equal(pick('2026-10-25T12:00:00Z', upstream).trigger, 'upstream-release');
  assert.throws(() => pick('2026-10-24T13:00:00Z', {...upstream,published_at:null}), /publication time/);
  assert.throws(() => pick('2026-10-24T13:00:00Z', {...upstream,published_at:'invalid'}), /publication time/);
});
test('drafts, published releases and patches prevent duplicate monthly preparation', () => {
  for (const release of [{tag_name:'v2026.10.0',draft:true}, {tag_name:'v2026.10.0'}, {tag_name:'v2026.10.1'}]) {
    assert.equal(pick('2026-10-26T12:00:00Z', {tag_name:'v2026.10.1'}, [release]), null);
  }
  assert.equal(pick('2026-11-24T12:00:00Z',null,[{tag_name:'v2026.10.0'}]).version,'2026.11.0');
});

test('comparison uses the corresponding monthly tag even after a newer patch release', async () => {
  const calls = [];
  const result = await chooseComparisonRelease({version:'2026.11.0',initial:false,
    upstream:{tag:'v2026.11.1',sha:'patch'},resolveTag:async tag=>{calls.push(tag);return 'monthly';}});
  assert.deepEqual(calls, ['v2026.11.0']);
  assert.deepEqual(result, {tag:'v2026.11.0',sha:'monthly'});
  const initial = await chooseComparisonRelease({version:'2026.10.0',initial:true,
    upstream:{tag:'v2026.10.0',sha:'october'},resolveTag:async tag=>{assert.equal(tag,'v2026.9.0');return 'september';}});
  assert.equal(initial.tag, 'v2026.9.0');
});

test('calendar fallback names the available USDX baseline and does not hide API failures', async () => {
  const upstream = {tag:'v2026.10.0',sha:'october'};
  const args = {version:'2026.11.0',initial:false,upstream,
    resolveTag:async()=>{const e=Error('missing monthly release');e.status=404;throw e;}};
  assert.deepEqual(await chooseComparisonRelease(args), upstream);
  await assert.rejects(chooseComparisonRelease({...args,resolveTag:async()=>{const e=Error('unavailable');e.status=503;throw e;}}), /unavailable/);
});
