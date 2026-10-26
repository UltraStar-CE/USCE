'use strict';
const fs = require('node:fs');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const {readThemePin, validateThemePin} = require('./themes-pin.cjs');
const versionPattern = /^[0-9]{4}\.(?:[1-9]|1[0-2])\.[0-9]+$/;
function releaseBaseline(releases, version) {
  const parts = value => value.replace(/^v/, '').split('.').map(Number);
  const compare = (a, b) => { const x = parts(a), y = parts(b); return x[0] - y[0] || x[1] - y[1] || x[2] - y[2]; };
  const previous = releases.filter(r => !r.draft && !r.prerelease && versionPattern.test(r.tag_name.replace(/^v/, ''))
    && compare(r.tag_name, version) < 0).sort((a, b) => compare(b.tag_name, a.tag_name))[0];
  return previous ? {ref: previous.tag_name, label: 'USCE ' + previous.tag_name.replace(/^v/, '')}
    : {ref: '8b5324f321d54491badadf5f95b4678a0bcf4633', label: 'USDX 2026.9.0'};
}
function releaseComparisons(releases, version, upstream) {
  const baseline = releaseBaseline(releases, version);
  const previous = baseline.label.startsWith('USCE ') ? baseline : null;
  if (!previous && version === '2026.10.0') {
    return {previous, upstream: {ref: '8b5324f321d54491badadf5f95b4678a0bcf4633', label: 'USDX 2026.9.0'}};
  }
  if (!upstream || !/^v[0-9]{4}\.(?:[1-9]|1[0-2])\.[0-9]+$/.test(upstream.tag) ||
      !/^[a-f0-9]{40}$/.test(upstream.sha)) throw Error('A pinned USDX release is required for release-note comparisons');
  return {previous, upstream: {ref: upstream.sha, label: 'USDX ' + upstream.tag.slice(1)}};
}
function gitChanges(ref, sha, repositoryUrl) {
  const range = ref + '..' + sha;
  const commits = execFileSync('git', ['log', '--first-parent', '--format=%H%x09%s', range], {encoding: 'utf8'});
  const notes = commits.trim().split('\n').filter(Boolean).map(line => {
    const [hash, ...subject] = line.split('\t');
    const title = subject.join('\t').replace(/https?:\/\/github\.com\/[^\s)]+/g, '[source reference omitted]')
      .replace(/#/g, ' PR ').replace(/@([A-Za-z0-9_-]+)/g, '$1').replace(/[\[\]]/g, '');
    return '- ' + title + ' ([`' + hash.slice(0, 7) + '`](' + repositoryUrl + '/commit/' + hash + '))';
  }).join('\n');
  const count = Number(execFileSync('git', ['rev-list', '--count', range], {encoding: 'utf8'}).trim());
  const stats = execFileSync('git', ['diff', '--numstat', ref, sha, '--'], {encoding: 'utf8'}).trim();
  let added = 0, deleted = 0, files = 0;
  for (const line of stats.split('\n').filter(Boolean)) {
    const fields = line.split('\t'); files++;
    if (/^[0-9]+$/.test(fields[0])) added += Number(fields[0]);
    if (/^[0-9]+$/.test(fields[1])) deleted += Number(fields[1]);
  }
  return {notes, count, files, added, deleted};
}
function comparisonGraphic(version, baseline, changes) {
  const escape = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
  const detail = baseline ? `${changes.count} commits · ${changes.files} files · text lines +${changes.added} / −${changes.deleted}` : 'No previous USCE release';
  return '<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="260" viewBox="0 0 1200 260">' +
    '<rect width="1200" height="260" rx="16" fill="#101d2b"/>' +
    '<g font-family="DejaVu Sans, sans-serif" fill="#e8f2fa">' +
    '<text x="40" y="65" font-size="26">' + escape(baseline?.label || 'First USCE release') + '</text>' +
    '<path d="M42 105H1150m-18-10 18 10-18 10" fill="none" stroke="#57dafa" stroke-width="3"/>' +
    '<text x="40" y="165" font-size="38">USCE ' + escape(version) + '</text>' +
    '<text x="40" y="218" font-size="23" fill="#bad3e9">' + escape(detail) + '</text></g></svg>\n';
}
function releaseNoteFiles({releases, version, upstream, sha, repositoryUrl, readChanges = gitChanges}) {
  if (!versionPattern.test(version) || !/^[a-f0-9]{40}$/.test(sha)) throw Error('Invalid release-note revision');
  const comparisons = releaseComparisons(releases, version, upstream);
  const images = [];
  const section = (kind, baseline, heading) => {
    const changes = baseline ? readChanges(baseline.ref, sha, repositoryUrl) : null;
    const path = 'docs/images/release-' + version + '-' + kind + '.svg';
    images.push({path, content: comparisonGraphic(version, baseline, changes)});
    return '## ' + heading + '\n\n![' + heading + '](' + repositoryUrl.replace('github.com/', 'raw.githubusercontent.com/') +
      '/main/' + path + ')\n\n' + (changes?.notes || '') + '\n';
  };
  const notes = section('usce', comparisons.previous, comparisons.previous ? 'Changes since ' + comparisons.previous.label : 'Changes since the previous USCE release') +
    '\n' + section('upstream', comparisons.upstream, 'Changes compared with ' + comparisons.upstream.label);
  return {notes, images};
}
async function planRelease({github, context, core}) {
  const plan = JSON.parse(fs.readFileSync('release-plan.json', 'utf8'));
  if (plan.ready !== true) { core.notice('A reviewed release preparation PR is needed first.'); return; }
  if (!versionPattern.test(plan.version) || fs.readFileSync('VERSION', 'utf8').trim() !== plan.version) throw Error('Release plan and VERSION must match');
  if (JSON.stringify(validateThemePin(plan.themes)) !== JSON.stringify(readThemePin())) throw Error('Release plan and Themes pin must match');
  if (plan.upstream) {
    if (!/^[a-f0-9]{40}$/.test(plan.upstream.sha)) throw Error('Invalid upstream release SHA');
    const comparison = await github.rest.repos.compareCommits({...context.repo, base: plan.upstream.sha, head: context.sha});
    if (!['ahead', 'identical'].includes(comparison.data.status)) throw Error('The upstream release is not fully included in this revision');
  }
  const releases = await github.paginate(github.rest.repos.listReleases, {...context.repo, per_page: 100});
  const existing = releases.find(r => r.tag_name === 'v' + plan.version);
  if (existing && !existing.draft) { core.notice('This version is already published.'); return; }
  if (existing && existing.target_commitish !== context.sha) throw Error('The existing draft belongs to another revision; retry its original workflow run');
  core.setOutput('version', plan.version);
}
async function publishDraft({github, context, core}, version) {
  if (!versionPattern.test(version)) throw Error('Invalid release version');
  const paths = fs.readdirSync('release-output').sort();
  const expected = ['USCE-windows-installer-' + version + '.exe', 'USCE-windows-portable-' + version + '.zip',
    'USCE-linux-' + version + '.AppImage', 'USCE-mac-ARM-' + version + '.dmg', 'USCE-mac-x86-' + version + '.dmg', 'SHA256SUMS', 'VERSION'].sort();
  if (JSON.stringify(paths) !== JSON.stringify(expected)) throw Error('Expected five packages, VERSION and SHA256SUMS');
  const marker = '<!-- usce-source:' + context.sha + ' -->';
  const tag = 'v' + version;
  let tagExists = false;
  try {
    await github.rest.git.getRef({...context.repo, ref: 'tags/' + tag});
    tagExists = true;
  } catch (e) { if (e.status !== 404) throw e; }
  if (tagExists) {
    const tagged = await github.rest.repos.getCommit({...context.repo, ref: tag});
    if (tagged.data.sha !== context.sha) throw Error('Existing release tag points to another revision');
  }
  const releases = await github.paginate(github.rest.repos.listReleases, {...context.repo, per_page: 100});
  let release = releases.find(r => r.tag_name === tag);
  if (release && (!release.draft || release.target_commitish !== context.sha || !release.body?.includes(marker))) throw Error('Refusing to replace an existing release');
  if (!release) {
    const repositoryUrl = 'https://github.com/' + context.repo.owner + '/' + context.repo.repo;
    const notesPath = 'doc/releases/' + version + '.md';
    const curated = fs.existsSync(notesPath) ? fs.readFileSync(notesPath, 'utf8').trim() : '';
    if (fs.existsSync(notesPath) && !curated) throw Error('Release notes are empty');
    const plan = JSON.parse(fs.readFileSync('release-plan.json', 'utf8'));
    if (plan.upstream && !/^v[0-9]{4}\.(?:[1-9]|1[0-2])\.[0-9]+$/.test(plan.upstream.tag)) throw Error('Invalid upstream release tag');
    const upstreamMarker = plan.upstream ? '<!-- usce-upstream-release:' + plan.upstream.tag + ' -->\n' : '';
    let notes = curated;
    if (!notes) {
      const generated = releaseNoteFiles({releases, version, upstream: plan.comparisons?.upstream || plan.upstream,
        sha: context.sha, repositoryUrl});
      for (const image of generated.images) {
        if (!fs.existsSync(image.path)) throw Error('Missing release comparison graphic: ' + image.path);
      }
      notes = generated.notes;
    }
    const sections = notes.split(/^## /m).slice(1);
    if (sections.length !== 2 || !/^Changes since /.test(sections[0]) ||
        !/^Changes compared with USDX /.test(sections[1]) || sections.some(section => !/!\[[^\]]*\]\([^)]+\)/.test(section))) {
      throw Error('Release notes require USCE and USDX comparison sections, each with a graphic');
    }
    const themes = readThemePin();
    release = (await github.rest.repos.createRelease({...context.repo, tag_name: tag, target_commitish: context.sha,
      name: 'USCE ' + version, draft: true, prerelease: false,
      body: marker + '\n' + upstreamMarker + '\n' + notes +
        '\n\n<details>\n<summary>Build information</summary>\n\nSource revision: `' + context.sha +
        '`.\nThemes revision: `' + themes.sha + '`.\n\n</details>\n'})).data;
  }
  const assets = await github.paginate(github.rest.repos.listReleaseAssets, {...context.repo, release_id: release.id, per_page: 100});
  if (assets.some(a => !expected.includes(a.name))) throw Error('Unexpected assets on existing draft');
  for (const name of paths) {
    const data = fs.readFileSync('release-output/' + name);
    const digest = 'sha256:' + crypto.createHash('sha256').update(data).digest('hex');
    const prior = assets.find(a => a.name === name);
    if (prior) {
      if (prior.digest !== digest) throw Error('An existing draft asset differs: ' + name);
      continue;
    }
    await github.rest.repos.uploadReleaseAsset({...context.repo, release_id: release.id, name, data, headers: {'content-type': 'application/octet-stream', 'content-length': data.length}});
  }
  core.notice('Draft release ready for human testing: ' + release.html_url);
}
module.exports = {planRelease, publishDraft, releaseBaseline, releaseComparisons, releaseNoteFiles, comparisonGraphic};
