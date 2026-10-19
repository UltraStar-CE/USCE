'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const themePin = {repository:'UltraStar-CE/Themes',sha:'a'.repeat(40)};
const {planRelease, publishDraft, releaseBaseline, releaseComparisons, releaseNoteFiles} = require('./publish-release.cjs');
async function fixture(run) {
  const previous = process.cwd();
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'usce-release-'));
  try {
    process.chdir(temp);
    fs.writeFileSync('VERSION', '2026.10.0\n');
    fs.writeFileSync('themes.json', JSON.stringify(themePin));
    fs.writeFileSync('release-plan.json', JSON.stringify({ready:true,version:'2026.10.0',themes:themePin,trigger:'calendar-fallback',upstream:null}));
    execFileSync('git',['init','--quiet']);
    execFileSync('git',['add','VERSION','release-plan.json']);
    execFileSync('git',['-c','user.name=USCE Tests','-c','user.email=tests@example.invalid','commit','--quiet','-m','Improve playback #123 @contributor']);
    execFileSync('git', ['tag', 'v2026.9.0']);
    const upstreamSha = execFileSync('git', ['rev-parse', 'HEAD'], {encoding:'utf8'}).trim();
    fs.writeFileSync('release-plan.json', JSON.stringify({ready:true,version:'2026.10.0',themes:themePin,upstream:{tag:'v2026.10.0',sha:upstreamSha}}));
    execFileSync('git', ['-c','user.name=USCE Tests','-c','user.email=tests@example.invalid','commit','--quiet','--allow-empty','-m','Improve playback #123 @contributor']);
    const sha = execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
    fs.mkdirSync('docs/images', {recursive:true});
    for (const kind of ['usce','upstream']) fs.writeFileSync('docs/images/release-2026.10.0-' + kind + '.svg', '<svg xmlns="http://www.w3.org/2000/svg"/>');
    fs.mkdirSync('release-output');
    for (const name of ['USCE-windows-installer-2026.10.0.exe','USCE-windows-portable-2026.10.0.zip','USCE-linux-2026.10.0.AppImage','USCE-mac-ARM-2026.10.0.dmg','USCE-mac-x86-2026.10.0.dmg','SHA256SUMS','VERSION']) fs.writeFileSync('release-output/'+name, name);
    const state = {releases:[],assets:[],uploads:0,outputs:{}};
    const repos = {
      getCommit: async () => {const e=Error('missing tag');e.status=404;throw e;},
      listReleases(){}, listReleaseAssets(){}, compareCommits:async()=>({data:{status:"ahead"}}),
      createRelease: async data => { const release={...data,id:1,html_url:'draft-url'};state.releases.push(release);return {data:release}; },
      uploadReleaseAsset: async data => {state.uploads++;state.assets.push({name:data.name,digest:'sha256:'+crypto.createHash('sha256').update(data.data).digest('hex')});},
    };
    const git = {getRef:async()=>{const e=Error('missing ref');e.status=404;throw e;}};
    const github = {rest:{repos,git},paginate:async method=> method===repos.listReleases?[...state.releases,{tag_name:'v2026.9.0',draft:false,prerelease:false}]:state.assets};
    const context={repo:{owner:'UltraStar-CE',repo:'USCE'},sha};
    const core={notice(){},setOutput:(k,v)=>state.outputs[k]=v};
    await run({github,context,core,state,repos,git});
  } finally {
    process.chdir(previous);
    assert(path.resolve(temp).startsWith(path.resolve(os.tmpdir())+path.sep));
    fs.rmSync(temp,{recursive:true,force:true});
  }
}
test('draft publisher pins source, avoids cross-references and retries matching assets', async()=>fixture(async x=>{
  await publishDraft(x,'2026.10.0');
  assert.equal(x.state.releases[0].draft,true);
  assert.equal(x.state.releases[0].target_commitish,x.context.sha);
  assert(!x.state.releases[0].body.includes('#123'));
  assert(!x.state.releases[0].body.includes('@contributor'));
  assert(x.state.releases[0].body.includes(themePin.sha));
  assert.equal(x.state.uploads,7);
  await publishDraft(x,'2026.10.0');
  assert.equal(x.state.releases.length,1);
  assert.equal(x.state.uploads,7);
  fs.writeFileSync('release-output/SHA256SUMS','changed');
  await assert.rejects(publishDraft(x,'2026.10.0'), /asset differs/);
}));
test('publisher rejects a missing package, a different tag and an already published release', async()=>fixture(async x=>{
  fs.renameSync('release-output/SHA256SUMS','sums');
  await assert.rejects(publishDraft(x,'2026.10.0'), /five packages/);
  assert.equal(x.state.releases.length,0);
  fs.renameSync('sums','release-output/SHA256SUMS');
  x.git.getRef=async()=>({data:{object:{type:'tag',sha:'annotated-tag'}}});
  x.repos.getCommit=async()=>({data:{sha:'different'}});
  await assert.rejects(publishDraft(x,'2026.10.0'), /tag points/);
  x.state.releases.push({tag_name:'v2026.10.0',draft:false});
  x.repos.getCommit=async()=>({data:{sha:x.context.sha}});
  await assert.rejects(publishDraft(x,'2026.10.0'), /replace an existing/);
}));
test('release planning requires a reviewed ready plan and skips published versions',async()=>fixture(async x=>{
  fs.writeFileSync('release-plan.json',JSON.stringify({ready:false}));
  await planRelease(x);assert.deepEqual(x.state.outputs,{});
  fs.writeFileSync('release-plan.json',JSON.stringify({ready:true,version:'2026.11.0'}));
  await assert.rejects(planRelease(x),/must match/);
  fs.writeFileSync('release-plan.json',JSON.stringify({ready:true,version:'2026.10.0',themes:themePin}));
  await planRelease(x);assert.equal(x.state.outputs.version,'2026.10.0');
  fs.writeFileSync('release-plan.json',JSON.stringify({ready:true,version:'2026.10.0',themes:{...themePin,sha:'b'.repeat(40)}}));
  await assert.rejects(planRelease(x),/Themes pin must match/);
  fs.writeFileSync('release-plan.json',JSON.stringify({ready:true,version:'2026.10.0',themes:themePin}));
  x.state.outputs={};x.state.releases.push({tag_name:'v2026.10.0',draft:false});
  await planRelease(x);assert.deepEqual(x.state.outputs,{});
}));


test('curated release notes retain screenshots and replace commit subjects and internal checklists', async()=>fixture(async x=>{
  fs.mkdirSync('doc/releases', {recursive:true});
  const notes = '## Changes since USCE 2026.9.0\n\n![Since USCE](https://example.org/usce.png)\n\n## Changes compared with USDX 2026.10.0\n\n* New theme.\n\n![Theme screenshot](https://example.org/theme.png)';
  fs.writeFileSync('doc/releases/2026.10.0.md', notes);
  await publishDraft(x, '2026.10.0');
  const body = x.state.releases[0].body;
  assert(body.includes(notes));
  assert(!body.includes('Improve playback'));
  assert(!body.includes('- [ ]'));
  assert(!body.includes('Changes to review'));
  assert.equal(x.state.releases[0].draft, true);
}));

test('an empty curated release message cannot create a draft', async()=>fixture(async x=>{
  fs.mkdirSync('doc/releases', {recursive:true});
  fs.writeFileSync('doc/releases/2026.10.0.md', '  \n');
  await assert.rejects(publishDraft(x, '2026.10.0'), /notes are empty/);
  assert.equal(x.state.releases.length, 0);
}));


test('release planning verifies the full pinned upstream history and fails closed on missing changes', async()=>fixture(async x=>{
  const source = 'b'.repeat(40);
  fs.writeFileSync('release-plan.json', JSON.stringify({ready:true,version:'2026.10.0',themes:themePin,upstream:{sha:source}}));
  for (const status of ['behind','diverged']) {
    x.repos.compareCommits = async args => {
      assert.equal(args.base, source);
      assert.equal(args.head, x.context.sha);
      return {data:{status}};
    };
    await assert.rejects(planRelease(x), /not fully included/);
    assert.deepEqual(x.state.outputs, {});
  }
  for (const status of ['ahead','identical']) {
    x.repos.compareCommits = async () => ({data:{status}});
    await planRelease(x);
    assert.equal(x.state.outputs.version, '2026.10.0');
  }
}));


test('release-note baseline is USDX September initially, then the nearest earlier published USCE release', () => {
  assert.equal(releaseBaseline([], '2026.10.0').label, 'USDX 2026.9.0');
  const releases = [
    {tag_name:'v2026.12.0'}, {tag_name:'v2026.10.0'}, {tag_name:'v2026.11.0',draft:true},
    {tag_name:'v2026.11.1',prerelease:true}, {tag_name:'v2026.9.0'}, {tag_name:'v2026.10.1'},
  ];
  assert.deepEqual(releaseBaseline(releases, '2026.11.0'), {ref:'v2026.10.1',label:'USCE 2026.10.1'});
});

test('generated notes link to local commits and state the previous USCE baseline', async()=>fixture(async x=>{
  await publishDraft(x, '2026.10.0');
  const body = x.state.releases[0].body;
  assert(body.includes('Changes since USCE 2026.9.0'));
  assert(body.includes('https://github.com/UltraStar-CE/USCE/commit/' + x.context.sha));
  assert(!body.includes('#123'));
}));

test('the first release leaves USCE changes empty and compares USDX with September', () => {
  const calls = [];
  const bundle = releaseNoteFiles({releases:[],version:'2026.10.0',sha:'a'.repeat(40),
    upstream:{tag:'v2026.10.0',sha:'b'.repeat(40)},repositoryUrl:'https://github.com/UltraStar-CE/USCE',
    readChanges:ref=>{calls.push(ref);return {notes:'- October changes',count:12,files:8,added:20,deleted:4};}});
  assert.deepEqual(calls, ['8b5324f321d54491badadf5f95b4678a0bcf4633']);
  assert.equal(bundle.notes.match(/^## /gm).length, 2);
  assert.equal(bundle.notes.match(/!\[/g).length, 2);
  assert(!bundle.notes.split('## Changes compared with')[0].includes('- October changes'));
  assert(bundle.notes.includes('## Changes compared with USDX 2026.9.0'));
  assert(bundle.images[0].content.includes('No previous USCE release'));
  assert(bundle.images[1].content.includes('12 commits'));
});

test('later releases compare USCE and corresponding USDX independently', () => {
  const calls = [];
  const bundle = releaseNoteFiles({releases:[{tag_name:'v2026.10.0'}],version:'2026.11.0',sha:'a'.repeat(40),
    upstream:{tag:'v2026.11.0',sha:'b'.repeat(40)},repositoryUrl:'https://github.com/UltraStar-CE/USCE',
    readChanges:ref=>{calls.push(ref);return {notes:'- ' + ref,count:2,files:1,added:3,deleted:1};}});
  assert.deepEqual(calls, ['v2026.10.0', 'b'.repeat(40)]);
  assert(bundle.notes.includes('## Changes since USCE 2026.10.0'));
  assert(bundle.notes.includes('## Changes compared with USDX 2026.11.0'));
  assert.equal(bundle.images.length, 2);
  const fallback = releaseComparisons([{tag_name:'v2026.10.0'}], '2026.11.0', {tag:'v2026.10.0',sha:'c'.repeat(40)});
  assert.equal(fallback.upstream.label, 'USDX 2026.10.0');
});

test('a draft cannot lose a comparison graphic or one of the two sections', async()=>fixture(async x=>{
  fs.unlinkSync('docs/images/release-2026.10.0-upstream.svg');
  await assert.rejects(publishDraft(x, '2026.10.0'), /Missing release comparison graphic/);
  fs.mkdirSync('doc/releases', {recursive:true});
  fs.writeFileSync('doc/releases/2026.10.0.md', '## Changes since USCE 2026.9.0\n\n![Changes](example.png)');
  await assert.rejects(publishDraft(x, '2026.10.0'), /each with a graphic/);
  assert.equal(x.state.releases.length, 0);
}));

test('a missing tag avoids the commit lookup that GitHub reports as 422', async()=>fixture(async x=>{
  let commitLookups=0;
  x.repos.getCommit=async()=>{commitLookups++;const e=Error('No commit found');e.status=422;throw e;};
  await publishDraft(x, '2026.10.0');
  assert.equal(commitLookups, 0);
  assert.equal(x.state.releases[0].draft, true);
}));

test('an existing tag lookup failure cannot be mistaken for an absent tag', async()=>fixture(async x=>{
  x.git.getRef=async args=>{assert.equal(args.ref,'tags/v2026.10.0');return {data:{object:{type:'tag',sha:'tag'}}};};
  x.repos.getCommit=async args=>{assert.equal(args.ref,'v2026.10.0');const e=Error('Tag lookup failed');e.status=422;throw e;};
  await assert.rejects(publishDraft(x, '2026.10.0'), /Tag lookup failed/);
  assert.equal(x.state.releases.length, 0);
}));
