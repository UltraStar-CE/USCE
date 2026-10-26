const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const test = require('node:test');
const source = readFileSync(path.join(__dirname,'../../game/webs/usdx-bridge.mjs'),'utf8');
test('large catalogs cannot cause preview-clock state to be dropped or mutate the source catalog', () => {
  const context = vm.createContext({Buffer,path,maxSongStateLibrarySongs:200,maxLowPriorityMessageBytes:65536,
    previewStreaming:false,rememberSongCover(){},rememberSongPreview(){},
    publicSongKey:(artist,title)=>`${artist}-${title}`,contentTypeForImage:()=>'',
    audioFormatForPath:()=>'',contentTypeForAudio:()=>''});
  vm.runInContext(source.slice(source.indexOf('function sanitizeSongStateForServer('),source.indexOf('async function waitForCatalogTransferBuffer(')),context);
  const library = Array.from({length:28402},(_,songId)=>({songId,title:'x'.repeat(600),audioPath:'/private/input.wav'}));
  const state = {type:'song.select.state',previewPositionSec:7.5,selectedSongId:3,library};
  const sanitized = context.sanitizeSongStateForServer(state);
  assert.ok(Buffer.byteLength(JSON.stringify(sanitized)) < 65536);
  assert.equal(sanitized.previewPositionSec,7.5);
  assert.equal(sanitized.selectedSongId,3);
  assert.equal(sanitized.libraryTotal,28402);
  assert.equal(sanitized.library,undefined);
  assert.equal(library[0].audioPath,'/private/input.wav');
});
