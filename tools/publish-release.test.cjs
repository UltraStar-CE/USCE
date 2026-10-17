'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const {execFileSync} = require('node:child_process');
const {planRelease, publishDraft} = require('./publish-release.cjs');
async function fixture(run) {
  const previous = process.cwd();
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'usce-release-'));
  try {
    process.chdir(temp);
    fs.writeFileSync('VERSION', '2026.10.0\n');
    fs.writeFileSync('release-plan.json', JSON.stringify({ready:true,version:'2026.10.0',trigger:'calendar-fallback',upstream:null}));
    execFileSync('git',['init','--quiet']);
    execFileSync('git',['add','VERSION','release-plan.json']);
    execFileSync('git',['-c','user.name=USCE Tests','-c','user.email=tests@example.invalid','commit','--quiet','-m','Improve playback #123']);
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
    const github = {rest:{repos},paginate:async method=> method===repos.listReleases?state.releases:state.assets};
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
  fs.writeFileSync('release-plan.json',JSON.stringify({ready:true,version:'2026.10.0'}));
  await planRelease(x);assert.equal(x.state.outputs.version,'2026.10.0');
  x.state.outputs={};x.state.releases.push({tag_name:'v2026.10.0',draft:false});
  await planRelease(x);assert.deepEqual(x.state.outputs,{});
}));
