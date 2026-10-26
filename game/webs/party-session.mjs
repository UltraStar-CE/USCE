// Votes choose upcoming songs. USCE owns playback, results, timing and advancement.
export class PartySession {
  constructor({players, library, playlist, gameState, send, command, now = Date.now}) {
    Object.assign(this,{players,library,playlist,gameState,send,command,now});
    this.likes=new Map(); this.played=new Set(); this.leaderboard=new Map();
    this.enabled=false; this.gameActive=false; this.dirty=true;
    this.minPlayers=2; this.endless=false; this.playback={}; this.source='all';
    this.deadline=0; this.owner=null; this.sequence=1000000000; this.pending=new Map();
    this.queue=[]; this.matches=[]; this.notice=''; this.currentMatch=null;
  }
  eligible() { return [...this.players().values()].filter(p=>p.connected!==false&&Number(p.slot)>0); }
  rosterChanged() { this.dirty=true; }
  handle(message) {
    if (['party.like','party.unlike','party.likeShown','party.unlikeShown'].includes(message.type)) {
      const known=new Set(this.library().map(s=>Number(s.songId)));
      const ids=this.likes.get(message.playerId)||new Set();
      this.likes.set(message.playerId,ids);
      const songs=Array.isArray(message.songs)?message.songs.slice(0,500):[message];
      const liked=message.type==='party.like'||message.type==='party.likeShown';
      for(const song of songs) {
        const id=Number(song.songId);
        if(Number.isInteger(id)&&known.has(id)) { if(liked) ids.add(id); else ids.delete(id); }
      }
      this.dirty=true; return true;
    }
    if(message.type!=='control.command'||!String(message.command).startsWith('party.')) return false;
    const ack=(accepted,reason=null)=>this.send({type:'ack',playerId:message.playerId,commandId:message.commandId,accepted,reason});
    const args=message.args||{};
    switch(message.command) {
      case 'party.configure': case 'party.startMatchmaking':
        this.minPlayers=Math.max(1,Math.min(12,Math.round(Number(args.minPlayers)||2)));
        this.playback={};
        for (const [key,max] of [['playerSetupSeconds',120],['resultSeconds',120],['highScoreSeconds',120],['songDisplay',3],['singingDisplay',4]]) {
          const value=Number(args[key]);
          if(args[key] != null && Number.isInteger(value) && value >= (key.endsWith('Seconds')?-1:0) && value <= max) this.playback[key]=value;
        }
        this.endless=Boolean(args.endless); this.source=args.source==='playlist'?'playlist':'all';
        if(message.command==='party.startMatchmaking') {
          this.owner=message; this.enabled=true; this.notice='';
          if(!this.gameActive) this.played.clear();
        }
        this.dirty=true; ack(true); return true;
      case 'party.stop':
        this.enabled=false; this.deadline=0;
        if(this.gameActive) this.issue('continuous.stop',{},'stop');
        this.dirty=true; ack(true); return true;
      case 'party.skip':
        if(!this.gameActive) { ack(false,'party_not_playing'); return true; }
        this.command({...message,command:'continuous.skip'}); return true;
      case 'party.resetLeaderboard': this.leaderboard.clear(); this.dirty=true; ack(true); return true;
      default: ack(false,'party_command_unavailable'); return true;
    }
  }
  issue(command,args,kind) {
    const commandId=++this.sequence;
    this.pending.set(commandId,kind);
    this.command({type:'control.command',playerId:this.owner?.playerId,role:'controller',
      commandId,command,args});
    return commandId;
  }
  observe(message) {
    if(message.type==='game.state') this.dirty=true;
    if(message.type==='ack'&&this.pending.has(message.commandId)) {
      const kind=this.pending.get(message.commandId); this.pending.delete(message.commandId);
      if(kind==='start') this.gameActive=Boolean(message.accepted);
      if(!message.accepted) { this.notice=`Game rejected ${kind}: ${message.reason||'unavailable'}`; this.enabled=false; }
      this.dirty=true;
    }
    if(message.type==='continuous.state'&&!message.active) {
      this.gameActive=false; this.currentMatch=null; this.dirty=true;
      if(message.reason==='manual') this.enabled=false;
    }
    if(message.type==='song.started'&&this.gameActive) {
      const id=Number(message.songId); this.played.add(id);
      this.currentMatch=this.library().find(s=>Number(s.songId)===id)||{songId:id,title:message.title,artist:message.artist};
      this.participants=new Map(this.eligible().map(p=>[Number(p.slot),{...p}]));
      this.dirty=true;
    }
    if(message.type==='song.ended'&&this.gameActive) {
      if(this.lastScoredSeq===message.songSeq) return;
      this.lastScoredSeq=message.songSeq;
      for(const result of message.players||[]) {
        const player=this.participants?.get(Number(result.slot));
        if(!player) continue;
        const total=this.leaderboard.get(player.playerId)||{playerId:player.playerId,name:player.name,score:0,songs:0};
        total.score+=Number(result.scoreTotal)||0; ++total.songs;
        this.leaderboard.set(player.playerId,total);
      }
      this.dirty=true;
    }
  }
  refresh() {
    const participants=this.eligible();
    const allowed=this.source==='playlist'?new Set(this.playlist().map(s=>Number(s.songId))):null;
    const library=this.library().filter(s=>s.visible!==false&&!s.category&&(!allowed||allowed.has(Number(s.songId))));
    this.matches=library.map(song=>({...song,likedBy:participants.filter(p=>this.likes.get(p.playerId)?.has(Number(song.songId))) }))
      .filter(song=>song.likedBy.length>=this.minPlayers)
      .sort((a,b)=>b.likedBy.length-a.likedBy.length||Number(a.songId)-Number(b.songId));
    this.queue=this.matches.filter(s=>!this.played.has(Number(s.songId)));
    if(this.enabled&&this.endless&&!this.queue.length&&participants.length>=this.minPlayers) {
      let remaining=library.filter(s=>!this.played.has(Number(s.songId)));
      if(!remaining.length) { this.played.clear(); remaining=library; }
      if(remaining.length) this.queue=[{...remaining[Math.floor(Math.random()*remaining.length)],random:true}];
    }
    const ids=this.queue.map(s=>Number(s.songId));
    const fingerprint=ids.join(',');
    if(this.enabled&&this.gameActive&&fingerprint!==this.queueFingerprint) this.issue('continuous.queue',{songIds:ids},'queue');
    this.queueFingerprint=fingerprint;
    this.dirty=false;
    this.publish();
  }
  tick() {
    if(this.dirty) this.refresh();
    if(this.enabled&&!this.gameActive&&this.queue.length&&
      ![...this.pending.values()].includes('start')&&this.gameState()==='song_select') {
      this.deadline=0;
      this.issue('continuous.start',{songIds:this.queue.map(s=>Number(s.songId)),...this.playback},'start');
    }
  }
  publish() {
    const songs=new Map(this.library().map(s=>[Number(s.songId),s]));
    const voted=new Map();
    for(const p of this.players().values()) for(const id of this.likes.get(p.playerId)||[]) {
      if(!songs.has(id)) continue;
      if(!voted.has(id)) voted.set(id,{...songs.get(id),likedBy:[]});
      voted.get(id).likedBy.push({playerId:p.playerId,name:p.name});
    }
    const compact=s=>({songId:s.songId,title:s.title,artist:s.artist,random:s.random,
      likedBy:(s.likedBy||[]).map(p=>({playerId:p.playerId,name:p.name})),likedByCount:s.likedBy?.length||0,
      neededLikes:Math.max(0,this.minPlayers-(s.likedBy?.length||0)),matched:(s.likedBy?.length||0)>=this.minPlayers});
    this.send({type:'party.state',available:true,enabled:this.enabled,minPlayers:this.minPlayers,
      endless:this.endless,playerSetupSeconds:null,resultSeconds:null,highScoreSeconds:null,songDisplay:null,singingDisplay:null,...this.playback,source:this.source,
      phase:this.gameActive?({player_setup:'calling_players',results:'scoring',high_scores:'highscores'}[this.gameState()]||'singing'):this.enabled?'collecting_votes':'off',
      notice:this.notice||(!this.gameActive&&this.enabled&&this.gameState()!=='song_select'?'Open song selection in the game to start the party.':''),
      currentMatch:this.currentMatch?compact(this.currentMatch):null,
      queue:this.queue.slice(0,30).map(compact),matches:this.matches.slice(0,30).map(compact),matchesTotal:this.matches.length,
      likedSongs:[...voted.values()].slice(0,30).map(compact),likedSongsTotal:voted.size,
      leaderboard:[...this.leaderboard.values()].sort((a,b)=>b.score-a.score).map(entry=>({...entry,points:entry.score,rounds:entry.songs}))});
    for(const [playerId,ids] of this.likes) if(this.players().has(playerId)&&this.players().get(playerId).connected!==false)
      this.send({type:'party.state',targetPlayerId:playerId,likedSongIdsByPlayer:{[playerId]:[...ids]}});
  }
}
