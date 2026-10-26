import assert from 'node:assert/strict';
import test from 'node:test';
import {PartySession} from '../../game/webs/party-session.mjs';
function fixture() {
  let clock=0, state='song_select';
  const players=new Map([['a',{playerId:'a',name:'A',slot:1,connected:true}],['b',{playerId:'b',name:'B',slot:2,connected:true}]]);
  const library=[{songId:1,title:'One',visible:true},{songId:2,title:'Two',visible:true},{songId:3,title:'Locked',visible:false}];
  const sent=[],commands=[];
  const party=new PartySession({players:()=>players,library:()=>library,playlist:()=>[library[1]],
    gameState:()=>state,send:m=>sent.push(m),command:m=>commands.push(m),now:()=>clock});
  const like=(playerId,songs)=>party.handle({type:'party.likeShown',playerId,songs:songs.map(songId=>({songId}))});
  const start=(args={})=>party.handle({type:'control.command',playerId:'a',commandId:1,command:'party.startMatchmaking',args});
  return {party,players,sent,commands,like,start,advance:ms=>{clock+=ms;party.tick();},setState:s=>state=s};
}
test('party waits for matching votes and asks USCE to run a continuous queue',()=>{
  const f=fixture(); f.start(); f.like('a',[1,2,3]); f.advance(1100);
  assert.equal(f.commands.length,0);
  f.like('b',[1,2,3]); f.advance(0); f.advance(1000);
  assert.equal(f.commands.length,1);
  assert.equal(f.commands[0].command,'continuous.start');
  assert.deepEqual(f.commands[0].args.songIds,[1,2]);
  assert.ok(!f.commands.some(m=>['song.start','song.select','menu.select'].includes(m.command)));
  assert.equal(f.party.gameActive,false,'do not pretend the game accepted a start');
  f.party.observe({type:'ack',commandId:f.commands[0].commandId,accepted:true});
  f.party.observe({type:'song.started',songId:1,songSeq:10}); f.advance(0);
  assert.equal(f.commands.at(-1).command,'continuous.queue');
  assert.deepEqual(f.commands.at(-1).args.songIds,[2]);
});
test('unlikes, offline phones and game rejection cannot leave a phantom playing party',()=>{
  const f=fixture(); f.start(); f.like('a',[1]); f.like('b',[1]);
  f.party.handle({type:'party.unlikeShown',playerId:'b',songs:[{songId:1}]}); f.advance(2000);
  assert.equal(f.commands.length,0);
  f.like('b',[1]); f.players.get('b').connected=false; f.party.rosterChanged(); f.advance(2000);
  assert.equal(f.commands.length,0);
  f.players.get('b').connected=true; f.party.rosterChanged(); f.advance(0); f.advance(1000);
  f.party.observe({type:'ack',commandId:f.commands[0].commandId,accepted:false,reason:'unavailable'}); f.advance(0);
  assert.equal(f.party.enabled,false); assert.equal(f.party.gameActive,false);
  assert.match(f.party.notice,/rejected/);
});

test('party starts immediately and passes screen timing to the game instead of running a relay countdown',()=>{
  const f=fixture(); f.like('a',[1]); f.like('b',[1]);
  f.start({playerSetupSeconds:10,resultSeconds:5,highScoreSeconds:-1,songDisplay:1,singingDisplay:2});
  f.advance(0);
  assert.equal(f.commands.length,1);
  assert.deepEqual(f.commands[0].args,{songIds:[1],playerSetupSeconds:10,resultSeconds:5,highScoreSeconds:-1,songDisplay:1,singingDisplay:2});
  f.advance(10000);
  assert.equal(f.commands.length,1,'a pending game acknowledgement must not start duplicate sessions');
});
test('scores use the singers present at song start and duplicate endings do not double count',()=>{
  const f=fixture(); f.start(); f.like('a',[1]); f.like('b',[1]); f.advance(0); f.advance(1000);
  f.party.observe({type:'ack',commandId:f.commands[0].commandId,accepted:true});
  f.party.observe({type:'song.started',songId:1,songSeq:10});
  f.players.get('a').slot=2; f.players.get('b').slot=1;
  const ending={type:'song.ended',songSeq:10,players:[{slot:1,scoreTotal:6000},{slot:2,scoreTotal:4000}]};
  f.party.observe(ending); f.party.observe(ending);
  assert.equal(f.party.leaderboard.get('a').score,6000);
  assert.equal(f.party.leaderboard.get('a').songs,1);
  f.party.observe({type:'continuous.state',active:false,reason:'manual'}); f.advance(0);
  assert.equal(f.party.enabled,false);
});
