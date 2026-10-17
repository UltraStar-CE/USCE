'use strict';
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const scope = require('./ci-build-paths.json');
const root = path.resolve(__dirname, '..');
for (const [file, kind, count] of [['main.yml', 'build', 2], ['usce-automation-check.yml', 'automation', 1]]) {
  const text = fs.readFileSync(path.join(root, '.github/workflows', file), 'utf8');
  const blocks = [...text.matchAll(new RegExp(`# ci-${kind}-paths:start\\n([\\s\\S]*?)\\s*# ci-${kind}-paths:end`, 'g'))];
  assert.equal(blocks.length, count, `${file}: missing path filters`);
  for (const block of blocks) {
    const patterns = block[1].split('\n').map(line => line.trim()).filter(Boolean)
      .map(line => JSON.parse(line.replace(/^-\s*/, '')));
    assert.deepEqual(patterns, scope[kind], `${file}: path filters differ from the merge gate`);
  }
}
const workflow = name => fs.readFileSync(path.join(root, '.github/workflows', name), 'utf8');
assert(!workflow('main.yml').includes('workflow_dispatch:'), 'Normal builds must not expose manual-only jobs');
assert(!workflow('main.yml').includes('schedule:'), 'Unchanged code must not receive daily rebuilds');
assert(!workflow('usce-agents.yml').includes('pull_request_target:'), 'Optional API jobs must not run on PRs');
assert(!workflow('candidate-validation.yml').includes('pull_request:'), 'Candidate validation is manual only');
assert(workflow('candidate-validation.yml').includes('use-caches: false'), 'Candidates must not use shared caches');
assert(workflow('platform-builds.yml').includes("process.env.USE_CACHES !== 'false'"), 'Candidate cache isolation guard missing');
assert(workflow('platform-builds.yml').includes("context.ref !== 'refs/tags/ci-validation-v4'"), 'Protected candidate tag guard missing');
for (const [file, job] of [['upstream-tracking.yml', 'track'], ['usce-agents.yml', 'publish']]) {
  assert(workflow(file).includes('  ' + job + ':\n    concurrency:\n      group: usce-pr-publication\n      cancel-in-progress: false\n      queue: max'), `${file}: bot publishers must share the publication lock`);
}
const {isUpstreamProposal} = require('./usce-pr-policy.cjs');
const policyCopy = isUpstreamProposal.toString().split('\n').map(line => '            ' + line).join('\n');
assert(workflow('pr-cap.yml').includes(policyCopy), 'PR cap must use the tested upstream exemption');
console.log('Workflow filters, required validation and candidate isolation agree.');
