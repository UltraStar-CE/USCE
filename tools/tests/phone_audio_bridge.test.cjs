const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const test = require('node:test');
const source = readFileSync(path.join(__dirname,'../../game/webs/usdx-bridge.mjs'),'utf8');

test('an assignment without a preceding join preserves name, difficulty and avatar through Mic 2 changes', async () => {
  const messages = [];
  const context = vm.createContext({players: new Map(), playerAssignmentFingerprints: new Map(),
    party: {handle: () => false, rosterChanged() {}}, nativePcmEnabled: true,
    phoneMicDelayToRawMs: Number, phoneMicDelayToEffectiveMs: Number,
    room: {roomId: 'test'}, p2pEnabled: false, log() {},
    sendToIpc: message => messages.push(message), scheduleGameState() {}, gameStateAfterPlayerChange: () => 'lobby'});
  vm.runInContext(source.slice(source.indexOf('function playerAssignmentFingerprint('),
    source.indexOf('function sendGameStateMessage(')), context);
  vm.runInContext(source.slice(source.indexOf('async function handleMessage('),
    source.indexOf('function connect(')), context);
  await context.handleMessage({type:'player.assigned',playerId:'phone',slot:0,role:'controller',
    name:'Daniel',difficulty:2,avatarId:'avatar',avatarFile:'phone.jpg'});
  await context.handleMessage({type:'player.assigned',playerId:'phone',slot:2,role:'controller'});
  assert.equal(messages.at(-1).name,'Daniel');
  assert.equal(messages.at(-1).slot,2);
  assert.equal(messages.at(-1).difficulty,2);
  assert.equal(messages.at(-1).avatarFile,'phone.jpg');
  await context.handleMessage({type:'player.assigned',playerId:'phone',slot:2,role:'controller',name:'New name',difficulty:0});
  assert.equal(messages.at(-1).name,'New name');
  assert.equal(messages.at(-1).difficulty,0);
  const count = messages.length;
  await context.handleMessage({type:'player.assigned',playerId:'phone',slot:2,role:'controller',name:'New name',difficulty:0});
  assert.equal(messages.length,count,'identical assignments still avoid feedback loops');
});
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
