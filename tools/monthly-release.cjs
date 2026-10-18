'use strict';
const {openDraft} = require('./usce-automation.cjs');
const {releaseBaseline} = require('./publish-release.cjs');
const {validateThemePin} = require('./themes-pin.cjs');
const VERSION = /^([0-9]{4})\.([1-9]|1[0-2])\.([0-9]+)$/;
function chooseRelease({now, upstream, releases}) {
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone: 'Europe/Vienna', year: 'numeric', month: 'numeric', day: 'numeric'}).formatToParts(now);
  const date = Object.fromEntries(parts.map(p => [p.type, p.value]));
  const version = `${date.year}.${Number(date.month)}.0`;
  const month = version.slice(0, version.lastIndexOf('.'));
  if (releases.some(r => !r.prerelease && new RegExp('^v' + month.replace('.', '\\.') + '\\.[0-9]+$').test(r.tag_name))) return null;
  const currentUpstream = upstream && !upstream.draft && !upstream.prerelease && VERSION.test(upstream.tag_name.replace(/^v/, ''))
    && upstream.tag_name.startsWith('v' + month + '.');
  if (!currentUpstream && Number(date.day) < 24) return null;
  return {version, ready: true, trigger: currentUpstream ? 'upstream-release' : 'calendar-fallback',
    date: `${date.year}-${String(date.month).padStart(2, '0')}-${String(date.day).padStart(2, '0')}`,
    upstream: upstream ? {tag: upstream.tag_name, sha: upstream.sha} : null};
}
async function prepareMonthly({github, context, core, now = new Date()}) {
  let upstream = null;
  try {
    upstream = (await github.rest.repos.getLatestRelease({owner: 'UltraStar-Deluxe', repo: 'USDX'})).data;
  } catch (e) { if (e.status !== 404) throw e; }
  if (upstream) {
    if (!/^v[0-9]{4}\.(?:[1-9]|1[0-2])\.[0-9]+$/.test(upstream.tag_name)) throw Error('Unexpected upstream release tag');
    upstream.sha = (await github.rest.repos.getCommit({owner: 'UltraStar-Deluxe', repo: 'USDX', ref: upstream.tag_name})).data.sha;
  }
  const releases = await github.paginate(github.rest.repos.listReleases, {...context.repo, per_page: 100});
  const plan = chooseRelease({now, upstream, releases});
  if (!plan) { core.notice('No monthly release preparation is due.'); return; }
  const baseline = releaseBaseline(releases, plan.version);
  const themes = (await github.rest.repos.getCommit({owner: 'UltraStar-CE', repo: 'Themes', ref: 'main'})).data;
  plan.themes = validateThemePin({repository: 'UltraStar-CE/Themes', sha: themes.sha});
  const branch = context.payload.repository.default_branch;
  const sha = (await github.rest.git.getRef({...context.repo, ref: 'heads/' + branch})).data.object.sha;
  const commit = (await github.rest.git.getCommit({...context.repo, commit_sha: sha})).data;
  const pr = await openDraft(github, context, {branch, sha, tree: commit.tree.sha},
    'automation/release-' + plan.version.split('.').slice(0, 2).join('-'),
    [{path: 'VERSION', content: plan.version + '\n'}, {path: 'release-plan.json', content: JSON.stringify(plan, null, 2) + '\n'},
      {path: 'themes.json', content: JSON.stringify(plan.themes, null, 2) + '\n'}],
    'Prepare USCE ' + plan.version,
    `Proposed monthly release: ${plan.version}. Trigger: ${plan.trigger}.\n\n` +
    `Release notes compare changes with ${baseline.label}. Entries link to USCE PRs or commits.\n\n` +
    `Upstream reference: ${plan.upstream?.tag || 'no stable upstream release available'}. The release candidate requires the full upstream release history and a comparison against its release notes.\n\n` +
    `Themes revision: ${plan.themes.sha}. Every platform package includes all themes and their assets from this snapshot.\n\n` +
    'Review the included upstream changes and USCE additions, compatibility, release notes and required CI. Merging prepares draft packages from the exact merged revision. Installation, launch, songs and microphone testing are required before a human publishes the release.');
  core.notice('Release preparation: ' + pr.html_url);
}
module.exports = {chooseRelease, prepareMonthly};
