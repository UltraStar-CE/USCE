'use strict';
const fs = require('node:fs');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const versionPattern = /^[0-9]{4}\.(?:[1-9]|1[0-2])\.[0-9]+$/;
async function planRelease({github, context, core}) {
  const plan = JSON.parse(fs.readFileSync('release-plan.json', 'utf8'));
  if (plan.ready !== true) { core.notice('A reviewed release preparation PR is needed first.'); return; }
  if (!versionPattern.test(plan.version) || fs.readFileSync('VERSION', 'utf8').trim() !== plan.version) throw Error('Release plan and VERSION must match');
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
  try {
    const tagged = await github.rest.repos.getCommit({...context.repo, ref: 'refs/tags/' + tag});
    if (tagged.data.sha !== context.sha) throw Error('Existing release tag points to another revision');
  } catch (e) { if (e.status !== 404) throw e; }
  const releases = await github.paginate(github.rest.repos.listReleases, {...context.repo, per_page: 100});
  let release = releases.find(r => r.tag_name === tag);
  if (release && (!release.draft || release.target_commitish !== context.sha || !release.body?.includes(marker))) throw Error('Refusing to replace an existing release');
  if (!release) {
    let notes = '';
    const previous = releases.find(r => !r.draft && !r.prerelease && /^v[0-9]{4}\./.test(r.tag_name));
    try {
      notes = execFileSync('git', ['log', '--first-parent', '--format=- %s', previous ? previous.tag_name + '..' + context.sha : context.sha, ...(previous ? [] : ['-20'])], {encoding: 'utf8'});
    } catch (_) { notes = 'Review the included changes against the previous release.'; }
    // Keep imported commit subjects from creating PR cross-reference notifications.
    notes = notes.replace(/#/g, ' PR ').replace(/https?:\/\/github\.com\/[^\s)]+/g, '[source reference omitted]');
    const plan = JSON.parse(fs.readFileSync('release-plan.json', 'utf8'));
    release = (await github.rest.repos.createRelease({...context.repo, tag_name: tag, target_commitish: context.sha,
      name: 'USCE ' + version, draft: true, prerelease: false,
      body: marker + '\nSource revision: `' + context.sha + '`.\n\nUpstream reference: ' + (plan.upstream?.tag || 'none recorded') +
        '. Preparation: ' + plan.trigger + '.\n\n## Changes to review\n\n' + notes +
        '\n## Testing\n\n- [ ] Windows installer and portable package\n- [ ] Linux AppImage\n- [ ] Intel macOS DMG\n- [ ] ARM macOS DMG\n- [ ] Songs, microphone input, scoring, settings reuse and themes\n\n## Known limitations\n\nRecord the results and limitations before publication. These draft packages are not yet a published release.'})).data;
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
module.exports = {planRelease, publishDraft};
