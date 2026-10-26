'use strict';
const {openDraft} = require('./usce-automation.cjs');
const {releaseNoteFiles, releaseBaseline} = require('./publish-release.cjs');
const {validateThemePin} = require('./themes-pin.cjs');
const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const VERSION = /^([0-9]{4})\.([1-9]|1[0-2])\.([0-9]+)$/;
function chooseRelease({now, upstream, releases, previousPlan = null}) {
  const parts = new Intl.DateTimeFormat('en-CA', {timeZone: 'Europe/Vienna', year: 'numeric', month: 'numeric', day: 'numeric'}).formatToParts(now);
  const date = Object.fromEntries(parts.map(p => [p.type, p.value]));
  let version = `${date.year}.${Number(date.month)}.0`;
  const month = version.slice(0, version.lastIndexOf('.'));
  const monthReleases = releases.filter(r => !r.prerelease && new RegExp('^v' + month.replace('.', '\\.') + '\\.[0-9]+$').test(r.tag_name));
  const source = upstream && !upstream.draft && !upstream.prerelease && VERSION.exec(upstream.tag_name.replace(/^v/, ''));
  const marker = upstream ? '<!-- usce-upstream-release:' + upstream.tag_name + ' -->' : '';
  const followed = source && (previousPlan?.upstream?.tag === upstream.tag_name ||
    releases.some(r => !r.prerelease && r.body?.includes(marker)));
  const followup = source && !followed && (Number(source[3]) > 0 ||
    (monthReleases.length > 0 && upstream.tag_name.startsWith('v' + month + '.')));
  if (monthReleases.length && !followup) return null;
  // Finish publication of an existing draft before allocating another version.
  if (followup && releases.some(r => r.draft && !r.prerelease && VERSION.test(r.tag_name.replace(/^v/, '')))) return null;
  if (followup && monthReleases.length) {
    version = month + '.' + (Math.max(...monthReleases.map(r => Number(r.tag_name.split('.').at(-1)))) + 1);
  }
  const currentUpstream = source && (upstream.tag_name.startsWith('v' + month + '.') || followup);
  let releaseAfter = null;
  if (currentUpstream) {
    const publishedAt = Date.parse(upstream.published_at);
    if (!Number.isFinite(publishedAt)) throw Error('Missing or invalid USDX publication time');
    releaseAfter = new Date(publishedAt + 24 * 60 * 60 * 1000).toISOString();
    if (now.getTime() < Date.parse(releaseAfter)) return null;
  }
  if (!currentUpstream && Number(date.day) < 24) return null;
  return {version, ready: true, trigger: followup ? (Number(source[3]) > 0 ? 'upstream-bugfix' : 'upstream-followup') : currentUpstream ? 'upstream-release' : 'calendar-fallback',
    date: `${date.year}-${String(date.month).padStart(2, '0')}-${String(date.day).padStart(2, '0')}`,
    upstream: upstream ? {tag: upstream.tag_name, sha: upstream.sha} : null,
    ...(releaseAfter ? {releaseAfter} : {})};
}
async function chooseComparisonRelease({version, initial, upstream, resolveTag, followup = false}) {
  if (followup) return upstream;
  const tag = initial && version === '2026.10.0' ? 'v2026.9.0' : 'v' + version;
  if (upstream?.tag === tag) return upstream;
  try { return {tag, sha: await resolveTag(tag)}; }
  catch (e) {
    if (e.status !== 404) throw e;
    if (!upstream) throw Error('No USDX release is available for comparison');
    return upstream;
  }
}
async function prepareMonthly({github, context, core, now = new Date()}) {
  let upstream = null;
  try {
    upstream = (await github.rest.repos.getLatestRelease({owner: 'UltraStar-Deluxe', repo: 'USDX'})).data;
  } catch (e) { if (e.status !== 404) throw e; }
  if (upstream) {
    if (!/^v[0-9]{4}\.(?:[1-9]|1[0-2])\.[0-9]+$/.test(upstream.tag_name)) throw Error('Unexpected upstream release tag');
    upstream.sha = (await github.rest.repos.getCommit({owner: 'UltraStar-Deluxe', repo: 'USDX', ref: upstream.tag_name})).data.sha;
    if (!/^[a-f0-9]{40}$/.test(upstream.sha)) throw Error('Unexpected upstream release revision');
  }
  const releases = await github.paginate(github.rest.repos.listReleases, {...context.repo, per_page: 100});
  const previousPlan = fs.existsSync('release-plan.json') ? JSON.parse(fs.readFileSync('release-plan.json', 'utf8')) : null;
  const plan = chooseRelease({now, upstream, releases, previousPlan});
  if (!plan) { core.notice('No monthly release preparation is due.'); return; }
  plan.comparisons = {upstream: await chooseComparisonRelease({version: plan.version, followup: ['upstream-bugfix', 'upstream-followup'].includes(plan.trigger),
    initial: !releaseBaseline(releases, plan.version).label.startsWith('USCE '), upstream: plan.upstream,
    resolveTag: async ref => {
      const release = (await github.rest.repos.getReleaseByTag({owner:'UltraStar-Deluxe',repo:'USDX',tag:ref})).data;
      if (release.draft || release.prerelease) {
        const error = Error('The corresponding USDX release is not published as stable');
        error.status = 404;
        throw error;
      }
      return (await github.rest.repos.getCommit({owner:'UltraStar-Deluxe',repo:'USDX',ref})).data.sha;
    }})};
  if (!/^[a-f0-9]{40}$/.test(plan.comparisons.upstream.sha)) throw Error('Unexpected USDX comparison revision');
  const themes = (await github.rest.repos.getCommit({owner: 'UltraStar-CE', repo: 'Themes', ref: 'main'})).data;
  plan.themes = validateThemePin({repository: 'UltraStar-CE/Themes', sha: themes.sha});
  const branch = context.payload.repository.default_branch;
  const sha = (await github.rest.git.getRef({...context.repo, ref: 'heads/' + branch})).data.object.sha;
  const commit = (await github.rest.git.getCommit({...context.repo, commit_sha: sha})).data;
  if (!/^[a-f0-9]{40}$/.test(sha)) throw Error('Unexpected USCE release revision');
  try { execFileSync('git', ['cat-file', '-e', sha + '^{commit}'], {stdio: 'ignore'}); }
  catch { execFileSync('git', ['fetch', '--no-tags', 'origin', sha], {stdio: 'inherit'}); }
  for (const revision of new Set([plan.upstream?.sha, plan.comparisons.upstream.sha].filter(Boolean))) {
    try { execFileSync('git', ['cat-file', '-e', revision + '^{commit}'], {stdio: 'ignore'}); }
    catch { execFileSync('git', ['fetch', '--no-tags', 'https://github.com/UltraStar-Deluxe/USDX.git', revision], {stdio: 'inherit'}); }
  }
  const notes = releaseNoteFiles({releases, version: plan.version, upstream: plan.comparisons.upstream, sha,
    repositoryUrl: 'https://github.com/' + context.repo.owner + '/' + context.repo.repo});
  const notesPath = 'doc/releases/' + plan.version + '.md';
  const noteContent = fs.existsSync(notesPath) ? fs.readFileSync(notesPath, 'utf8') : notes.notes;
  const noteFiles = [{path: notesPath, content: noteContent},
    ...notes.images.filter(image => noteContent.includes(image.path) && !fs.existsSync(image.path))];
  const pr = await openDraft(github, context, {branch, sha, tree: commit.tree.sha},
    'automation/release-' + (plan.version.endsWith('.0') ? plan.version.split('.').slice(0, 2) : plan.version.split('.')).join('-'),
    [{path: 'VERSION', content: plan.version + '\n'}, {path: 'release-plan.json', content: JSON.stringify(plan, null, 2) + '\n'},
      {path: 'themes.json', content: JSON.stringify(plan.themes, null, 2) + '\n'},
      ...noteFiles],
    'Prepare USCE ' + plan.version,
    `Proposed USCE release: ${plan.version}. Trigger: ${plan.trigger}.\n\n` +
    `Release notes separately compare the previous USCE release and USDX ${plan.comparisons.upstream.tag}, each with a comparison graphic. Entries link to USCE PRs or commits.\n\n` +
    `Upstream reference: ${plan.upstream?.tag || 'no stable upstream release available'}. The release candidate requires the full upstream release history and a comparison against its release notes.\n\n` +
    `Themes revision: ${plan.themes.sha}. Every platform package includes all themes and their assets from this snapshot.\n\n` +
    'Merging prepares draft packages from the exact merged revision. Release review covers upstream changes, USCE additions, compatibility, release notes and required CI. Packages remain drafts until installation, launch, song and microphone testing are complete and a maintainer publishes the release.');
  core.notice('Release preparation: ' + pr.html_url);
}
module.exports = {chooseRelease, prepareMonthly, chooseComparisonRelease};
