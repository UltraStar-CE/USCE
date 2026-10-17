'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {policy, requestBody, parseRequest, planReview} = require('./codex-review-queue.cjs');
const now = Date.parse('2026-10-17T12:00:00Z');
const pr = (number, authorId = 123) => ({repo: 'UltraStar-CE/USCE', number, authorId,
  head: number.toString(16).padStart(40, '0'), state: 'open', draft: false,
  checksPassed: true, reviewed: false, created_at: '2026-10-16T00:00:00Z'});
const request = (p, age = 1000) => ({user: {id: policy.ownerId}, body: requestBody(p),
  created_at: new Date(now - age).toISOString()});
const plan = (prs, requests = [], extra = {}) => planReview({prs, requests, now, reviewInFlight: false, ...extra});

test('two requests consume an author budget across repositories, without blocking other authors', () => {
  const otherRepo = {...pr(2), repo: 'UltraStar-CE/Themes'};
  assert.equal(plan([pr(3), pr(4, 456)], [request(pr(1)), request(otherRepo)]).number, 4);
});
test('rolling windows expire at exactly 24 hours', () => {
  assert.equal(plan([pr(3)], [request(pr(1)), request(pr(2), policy.windowMs - 1)]), null);
  assert.equal(plan([pr(3)], [request(pr(1)), request(pr(2), policy.windowMs)]).number, 3);
});
test('the owner has no author budget but completed commits are still deduplicated', () => {
  const history = Array.from({length: 20}, (_, n) => request(pr(n + 1, policy.ownerId)));
  assert.equal(plan([pr(21, policy.ownerId)], history).number, 21);
  assert.equal(plan([pr(1, policy.ownerId)], history), null);
});
test('only ready, open, passing and not already reviewed heads can be requested', () => {
  for (const patch of [{draft: true}, {state: 'closed'}, {checksPassed: false},
    {reviewed: true}, {head: 'bad'}, {repo: 'other/repo'}, {authorId: undefined}]) {
    assert.equal(plan([{...pr(1), ...patch}]), null);
  }
});
test('in-flight work pauses dispatch and missing state fails closed', () => {
  assert.equal(plan([pr(1)], [], {reviewInFlight: true}), null);
  assert.throws(() => plan([pr(1)], [], {reviewInFlight: undefined}), /Complete queue metadata/);
});
test('only owner-authored valid ledger comments consume the budget', () => {
  const forged = {...request(pr(1)), user: {id: 456}};
  assert.equal(parseRequest(forged), null);
  assert.equal(plan([pr(3)], [forged, request(pr(2))]).number, 3);
  assert.equal(parseRequest({...request(pr(1)), body: '@codex review'}), null);
});
test('an older request prevents a duplicate head even after the budget window expires', () => {
  assert.equal(plan([pr(1)], [request(pr(1), 2 * policy.windowMs)]), null);
  assert.equal(plan([{...pr(1), head: 'f'.repeat(40)}], [request(pr(1), 2 * policy.windowMs)]).number, 1);
});
test('clock skew stops dispatch rather than spending outside the ledger', () => {
  assert.throws(() => plan([pr(2)], [request(pr(1), -1)]), /ahead of the clock/);
});
