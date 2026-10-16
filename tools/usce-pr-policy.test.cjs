'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const {isUpstreamProposal} = require('./usce-pr-policy.cjs');
const proposal = (repo, ref) => ({user: {login: 'github-actions[bot]'},
  base: {repo: {full_name: repo}}, head: {repo: {full_name: repo}, ref}});

test('trusted upstream assessments and adaptations are exempt across all three repositories', () => {
  for (const repo of ['UltraStar-CE/USCE', 'UltraStar-CE/mxe', 'UltraStar-CE/Themes']) {
    for (const prefix of ['upstream-usdx-', 'upstream-mxe-', 'upstream-themes-', 'candidate-upstream-', 'upstream-manual-']) {
      assert.equal(isUpstreamProposal(proposal(repo, 'automation/' + prefix + 'a'.repeat(12))), true);
    }
  }
});

test('ordinary authors, issue proposals and fork branches do not acquire the upstream exemption', () => {
  const pr = proposal('UltraStar-CE/USCE', 'automation/upstream-usdx-' + 'a'.repeat(12));
  assert.equal(isUpstreamProposal({...pr, user: {login: 'contributor'}}), false);
  assert.equal(isUpstreamProposal({...pr, head: {...pr.head, repo: {full_name: 'other/USCE'}}}), false);
  assert.equal(isUpstreamProposal(proposal('UltraStar-CE/USCE', 'automation/candidate-issue-1-aaaaaaaa')), false);
  assert.equal(isUpstreamProposal(proposal('other/USCE', pr.head.ref)), false);
  assert.equal(isUpstreamProposal({}), false);
});
