'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const themePin = {repository:'UltraStar-CE/Themes',sha:'a'.repeat(40)};
const {planRelease, publishDraft, releaseBaseline} = require('./publish-release.cjs');
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
    execFileSync('git',['-c','user.name=USCE Tests','-c','user.email=tests@example.invalid','commit','--quiet','-m','Improve playback #123']);
    execFileSync('git', ['tag', 'v2026.9.0']);
    execFileSync('git', ['-c','user.name=USCE Tests','-c','user.email=tests@example.invalid','commit','--quiet','--allow-empty','-m','Improve playback #123']);
    const sha = execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim();
    fs.mkdirSync('release-output');
    for (const name of ['USCE-windows-installer-2026.10.0.exe','USCE-windows-portable-2026.10.0.zip','USCE-linux-2026.10.0.AppImage','USCE-mac-ARM-2026.10.0.dmg','USCE-mac-x86-2026.10.0.dmg','SHA256SUMS','VERSION']) fs.writeFileSync('release-output/'+name, name);
    const state = {releases:[],assets:[],uploads:0,outputs:{}};
    const repos = {
      getCommit: async () => {const e=Error('missing tag');e.status=404;throw e;},
      listReleases(){}, listReleaseAssets(){},
      createRelease: async data => { const release={...data,id:1,html_url:'draft-url'};state.releases.push(release);return {data:release}; },
      uploadReleaseAsset: async data => {state.uploads++;state.assets.push({name:data.name,digest:'sha256:'+crypto.createHash('sha256').update(data.data).digest('hex')});},
    };
    const github = {rest:{repos},paginate:async method=> method===repos.listReleases?[...state.releases,{tag_name:'v2026.9.0',draft:false,prerelease:false}]:state.assets};
    const context={repo:{owner:'UltraStar-CE',repo:'USCE'},sha};
    const core={notice(){},setOutput:(k,v)=>state.outputs[k]=v};
    await run({github,context,core,state,repos});
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
  const notes = '## Enhancements\n\n* New theme.\n\n![Theme screenshot](https://example.org/theme.png)';
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
  assert(body.includes('Changes compared with **USCE 2026.9.0**'));
  assert(body.includes('https://github.com/UltraStar-CE/USCE/commit/' + x.context.sha));
  assert(!body.includes('#123'));
}));
