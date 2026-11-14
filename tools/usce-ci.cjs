'use strict';

const {execFileSync} = require('node:child_process');
const scope = require('./ci-build-paths.json');

function matches(path, pattern) {
  let expression = '^';
  for (let i = 0; i < pattern.length; i++) {
    if (pattern[i] === '*' && pattern[i + 1] === '*') {
      i++;
      if (pattern[i + 1] === '/') { expression += '(?:.*/)?'; i++; }
      else expression += '.*';
    } else if (pattern[i] === '*') expression += '[^/]*';
    else expression += pattern[i].replace(/[\\^$+?.()|{}\[\]]/g, '\\$&');
  }
  return new RegExp(expression + '$').test(path);
}

function selected(path, patterns) {
  let included = false;
  for (const pattern of patterns) {
    const excluded = pattern.startsWith('!');
    if (matches(path, excluded ? pattern.slice(1) : pattern)) included = !excluded;
  }
  return included;
}

function requiredWorkflows(files) {
  const workflows = [];
  if (files.some(path => selected(path, scope.build))) workflows.push('main.yml');
  if (files.some(path => selected(path, scope.automation))) workflows.push('usce-automation-check.yml');
  return workflows;
}

function workflowJob(jobs, name) {
  const matches = jobs.filter(job => job.name === name || job.name.endsWith(' / ' + name));
  return matches.length === 1 ? matches[0] : undefined;
}

function macBuildPassed(jobs, arch) {
  const built = job => job?.conclusion === 'success' && job.steps?.some(step =>
    step.name === 'Record successful build' && step.conclusion === 'success') &&
    job.steps.every(step => ['success', 'skipped'].includes(step.conclusion));
  const primary = workflowJob(jobs, `Build for MacOS (${arch})`);
  if (built(primary)) return true;
  const failed = ['failure', 'cancelled', 'startup_failure', 'timed_out'];
  const setup = primary?.steps?.find(step => step.name === 'Set up job');
  const startupFailed = setup ? failed.includes(setup.conclusion) && primary.steps.every(step =>
    ['Set up job', 'Complete job'].includes(step.name) || step.conclusion === 'skipped') :
    primary?.steps?.length === 0 && failed.includes(primary.conclusion);
  return startupFailed && workflowJob(jobs, 'Check macOS build results')?.conclusion === 'success' &&
    Boolean(built(workflowJob(jobs, `Retry MacOS (${arch})`)));
}

function recoveredMacBuild(jobs) {
  if (!['Resolve build source', 'Build for Windows', 'Build for Linux',
    'Build Ubuntu 22.04 package (amd64)', 'Check macOS build results']
    .every(name => workflowJob(jobs, name)?.conclusion === 'success')) return false;
  const arches = ['ARM', 'x86'];
  const recovered = arches.filter(arch => workflowJob(jobs, `Retry MacOS (${arch})`)?.conclusion === 'success');
  return recovered.length > 0 && arches.every(arch => macBuildPassed(jobs, arch)) &&
    jobs.every(job => ['success', 'skipped'].includes(job.conclusion) ||
      recovered.some(arch => job === workflowJob(jobs, `Build for MacOS (${arch})`)));
}

async function waitForBuilds({github, context, core, files, now = Date.now,
  sleep = ms => new Promise(resolve => setTimeout(resolve, ms)),
  timeoutMs = 55 * 60 * 1000, pollMs = 20000}) {
  const head = context.payload.pull_request.head.sha;
  if (!/^[a-f0-9]{40}$/.test(head)) throw Error('Invalid PR head SHA');
  const required = requiredWorkflows(files);
  if (!required.length) {
    core.info('Whitespace passed. No code or build-system changes; platform builds are not required.');
    return;
  }
  const started = now();
  const previous = new Map();
  while (now() - started < timeoutMs) {
    let complete = true;
    for (const workflow of required) {
      const response = await github.rest.actions.listWorkflowRuns({...context.repo,
        workflow_id: workflow, event: 'pull_request', head_sha: head, per_page: 100});
      const run = response.data.workflow_runs
        .filter(run => run.head_sha === head && run.event === 'pull_request')
        .sort((a, b) => b.id - a.id)[0];
      const state = run ? `${run.status}/${run.conclusion || ''}` : 'not started';
      if (previous.get(workflow) !== state) {
        core.info(`${workflow}: ${state}`);
        previous.set(workflow, state);
      }
      if (!run && files.length > 3000 && now() - started >= 60000) {
        throw Error(`GitHub did not start required ${workflow} for this PR with over 3,000 changed files. ` +
          'Its path filter can omit files beyond that limit. Split the change into smaller PRs; validation has not passed.');
      }
      if (!run || run.status !== 'completed') { complete = false; continue; }
      if (run.conclusion !== 'success') {
        let details = '';
        try {
          const jobs = await github.paginate(github.rest.actions.listJobsForWorkflowRun,
            {...context.repo, run_id: run.id, per_page: 100, filter: 'latest'});
          if (workflow === 'main.yml' && ['failure', 'cancelled'].includes(run.conclusion) && recoveredMacBuild(jobs)) {
            core.info('Both macOS builds passed after a runner startup retry.');
            continue;
          }
          details = jobs.filter(job => job.conclusion && job.conclusion !== 'success' &&
              job.conclusion !== 'skipped').map(job => {
            const failedSteps = (job.steps || []).filter(step => step.conclusion === 'failure');
            const location = failedSteps.length ? ' at ' + failedSteps.map(step => step.name).join(', ')
              : job.conclusion === 'cancelled' && !(job.steps || []).length
                ? ' before any steps ran; check job annotations for runner allocation errors' : '';
            return `${job.name}: ${job.conclusion}${location}`;
          }).join('; ');
        } catch (error) {
          core.info(`Could not read failed-job details: ${error.message}`);
        }
        throw Error(`Required ${workflow} finished with ${run.conclusion}: ${run.html_url || run.id}` +
          (details ? `\nUnsuccessful jobs: ${details}` : ''));
      }
    }
    if (complete) { core.info('Whitespace and every required build workflow passed.'); return; }
    await sleep(pollMs);
  }
  throw Error('Required build workflows did not finish for this exact PR revision. No merge approval is reported.');
}

function pullRequestFiles(base, head, cwd) {
  if (!/^[a-f0-9]{40}$/.test(base)) throw Error('Invalid PR base SHA');
  if (!/^[a-f0-9]{40}$/.test(head)) throw Error('Invalid PR head SHA');
  const options = {encoding: 'utf8', cwd};
  // Compare the event's immutable PR commits, never the checkout's synthetic
  // merge, which can already contain later changes from the target branch.
  const ancestor = execFileSync('git', ['merge-base', base, head], options).trim();
  // Include both paths when code is renamed to a documentation-only path.
  return execFileSync('git', ['diff', '--name-only', '-z', '--no-renames', ancestor, head, '--'],
    options).split('\0').filter(Boolean);
}

async function validatePullRequest({github, context, core}) {
  const base = context.payload.pull_request.base.sha;
  const head = context.payload.pull_request.head.sha;
  const files = pullRequestFiles(base, head);
  return waitForBuilds({github, context, core, files});
}

module.exports = {matches, selected, requiredWorkflows, waitForBuilds, validatePullRequest, pullRequestFiles,
  workflowJob, macBuildPassed, recoveredMacBuild};
