{ Relay/game message adaptation. Owned by the game I/O thread. No file access,
  gameplay calls or Node process. The game remains authoritative for its screen. }
unit URemoteRelayProtocol;

{$IFDEF FPC}{$MODE Delphi}{$H+}{$ENDIF}

interface

uses Classes, SysUtils, fpjson, URemoteSongSnapshot, URemoteMediaSources, URemoteMediaTransfer;

type
  TRelayProtocolEvent = procedure(Message: TJSONObject) of object;
  TRelayProtocolSend = function(Message: TJSONObject): boolean of object;
  TRelayClock = function: int64;
  TRemoteRelayProtocol = class
  private
    FPlayers, FCache: TJSONObject;
    FCurrentRound: TJSONObject;
    FResults: TJSONArray;
    FContinuousSeq: int64;
    FSongs: TRemoteSongSnapshot;
    FMediaSources: TRemoteMediaSources;
    FTransfers: TStringList;
    FRoomId: string;
    FOnGame: TRelayProtocolEvent;
    FOnSend: TRelayProtocolSend;
    FClock: TRelayClock;
    FReady: boolean;
    procedure MediaRequest(Message: TJSONObject);
    procedure CancelMedia(const Id: string);
    function NowUs: int64;
    function Send(Message: TJSONObject): boolean;
    procedure Deliver(Message: TJSONObject);
    procedure Cache(Message: TJSONObject);
    procedure Replay;
    procedure UpdateResults;
    function AddRoundParticipant(Player: TJSONObject): boolean;
    procedure RecordRound(Message: TJSONObject);
    procedure PlayerUpdate(Message: TJSONObject; Notify: boolean = true);
    function CopyPublic(Message: TJSONObject): TJSONObject;
  public
    constructor Create;
    destructor Destroy; override;
    procedure TickMedia;
    procedure FromRelay(Message: TJSONObject);
    function FromGame(Message: TJSONObject): boolean;
    property MediaSources: TRemoteMediaSources read FMediaSources;
    property Songs: TRemoteSongSnapshot read FSongs;
    property OnGame: TRelayProtocolEvent read FOnGame write FOnGame;
    property OnSend: TRelayProtocolSend read FOnSend write FOnSend;
    property Clock: TRelayClock read FClock write FClock;
  end;

implementation

function CloneObject(Message: TJSONObject): TJSONObject;
begin
  Result := TJSONObject(Message.Clone);
end;

procedure RemoveField(Message: TJSONObject; const Name: string);
var Index: integer;
begin
  Index := Message.IndexOfName(Name);
  if Index >= 0 then Message.Delete(Index);
end;

procedure StripLocalPaths(Data: TJSONData);
var I: integer;
    Obj: TJSONObject;
    Name: string;
begin
  if Data.JSONType = jtObject then
  begin
    Obj := TJSONObject(Data);
    for I := Obj.Count - 1 downto 0 do
    begin
      Name := Obj.Names[I];
      if (Name = 'audioPath') or (Name = 'coverPath') or (Name = 'txtPath') or
        (Name = 'filePath') or (Name = 'hostToken') then Obj.Delete(I)
      else StripLocalPaths(Obj.Items[I]);
    end;
  end
  else if Data.JSONType = jtArray then
    for I := 0 to Data.Count - 1 do StripLocalPaths(Data.Items[I]);
end;

constructor TRemoteRelayProtocol.Create;
begin
  inherited;
  FSongs := TRemoteSongSnapshot.Create;
  FMediaSources := TRemoteMediaSources.Create;
  FTransfers := TStringList.Create;
  FPlayers := TJSONObject.Create;
  FCache := TJSONObject.Create;
  FResults := TJSONArray.Create;
  UpdateResults;
  FCache.Add('continuous.state', TJSONObject.Create(['type', 'continuous.state',
    'active', false, 'reason', 'initial', 'sessionSeq', 0]));
end;

destructor TRemoteRelayProtocol.Destroy;
begin
  while FTransfers.Count > 0 do CancelMedia(FTransfers[0]);
  FTransfers.Free;
  FMediaSources.Free;
  FSongs.Free;
  FPlayers.Free;
  FCache.Free;
  FCurrentRound.Free;
  FResults.Free;
  inherited;
end;

function TRemoteRelayProtocol.NowUs: int64;
begin
  if Assigned(FClock) then Result := FClock()
  else Result := int64(GetTickCount64) * 1000;
end;

function TRemoteRelayProtocol.Send(Message: TJSONObject): boolean;
begin
  Result := false;
  Message.Integers['protocol'] := 1;
  if FReady and Assigned(FOnSend) then Result := FOnSend(Message);
end;

procedure TRemoteRelayProtocol.Deliver(Message: TJSONObject);
begin
  if Assigned(FOnGame) then FOnGame(Message);
end;

procedure TRemoteRelayProtocol.Cache(Message: TJSONObject);
var Kind: string; Previous: TJSONData; Merged: TJSONObject; I: integer;
begin
  Kind := Message.Get('type', '');
  Previous := FCache.Find(Kind);
  if (Kind = 'song.select.state') and (Previous <> nil) and
    (Previous.JSONType = jtObject) then
  begin
    Merged := CloneObject(TJSONObject(Previous));
    for I := 0 to Message.Count - 1 do
    begin
      RemoveField(Merged, Message.Names[I]);
      Merged.Add(Message.Names[I], Message.Items[I].Clone);
    end;
  end
  else Merged := CloneObject(Message);
  RemoveField(FCache, Kind);
  FCache.Add(Kind, Merged);
end;

function TRemoteRelayProtocol.CopyPublic(Message: TJSONObject): TJSONObject;
var Players: TJSONArray;
    I: integer;
begin
  Result := CloneObject(Message);
  StripLocalPaths(Result);
  if Result.Get('type', '') = 'game.state' then
  begin
    // Relay roster updates never replace the game's screen or song sequence.
    RemoveField(Result, 'players');
    Players := TJSONArray.Create;
    for I := 0 to FPlayers.Count - 1 do Players.Add(FPlayers.Items[I].Clone);
    Result.Add('players', Players);
  end;
end;

procedure TRemoteRelayProtocol.Replay;
const Order: array[0..11] of string = ('input.state', 'game.state', 'continuous.state', 'api.state', 'song.results', 'screen.info',
  'playlist.state', 'song.select.state', 'song.clock', 'song.lyrics', 'score.snapshot', 'score.sheet');
var I: integer;
    Data: TJSONData;
    Message: TJSONObject;
begin
  for I := Low(Order) to High(Order) do
  begin
    Data := FCache.Find(Order[I]);
    if (Data = nil) or (Data.JSONType <> jtObject) then Continue;
    Message := CopyPublic(TJSONObject(Data));
    try Send(Message); finally Message.Free; end;
  end;
end;

procedure TRemoteRelayProtocol.UpdateResults;
var Snapshot: TJSONObject;
begin
  Snapshot := TJSONObject.Create(['type', 'song.results']);
  try
    Snapshot.Add('rounds', FResults.Clone);
    if Assigned(FCurrentRound) then Snapshot.Add('currentRound', FCurrentRound.Clone);
    Cache(Snapshot);
  finally Snapshot.Free; end;
end;

function TRemoteRelayProtocol.AddRoundParticipant(Player: TJSONObject): boolean;
var Participants: TJSONArray; I, Slot: integer;
begin
  Result := false;
  Slot := Player.Get('slot', 0);
  if (FCurrentRound = nil) or (Slot <= 0) or not Player.Get('connected', true) then Exit;
  Participants := FCurrentRound.Arrays['participants'];
  for I := 0 to Participants.Count - 1 do
    if Participants.Objects[I].Get('slot', 0) = Slot then Exit;
  Participants.Add(TJSONObject.Create(['playerId', Player.Get('playerId', ''),
    'name', Player.Get('name', ''), 'slot', Slot]));
  Result := true;
end;

procedure TRemoteRelayProtocol.RecordRound(Message: TJSONObject);
var Kind: string; Active, Players: TJSONData;
    I, Seq: integer; Player, Round: TJSONObject;
    Changed: boolean;
begin
  Kind := Message.Get('type', '');
  if Kind = 'song.started' then
  begin
    FreeAndNil(FCurrentRound);
    Active := FCache.Find('continuous.state');
    if (Active <> nil) and TJSONObject(Active).Get('active', false) then
    begin
      FCurrentRound := TJSONObject.Create(['songSeq', Message.Get('songSeq', -1),
        'sessionSeq', FContinuousSeq, 'songId', Message.Get('songId', -1),
        'catalogKey', FSongs.IdentityForSong(Message.Get('songId', -1))]);
      FCurrentRound.Add('participants', TJSONArray.Create);
      for I := 0 to FPlayers.Count - 1 do
      begin
        Player := TJSONObject(FPlayers.Items[I]);
        AddRoundParticipant(Player);
      end;
    end;
    UpdateResults;
  end
  else if (Kind = 'game.state') and Assigned(FCurrentRound) and
    (Message.Get('state', '') = 'singing') and
    (FCurrentRound.Get('songSeq', -1) = Message.Get('songSeq', -2)) then
  begin
    // Roster admission comes from the game thread; retain existing slot identities.
    Players := Message.Find('players');
    Changed := false;
    if (Players <> nil) and (Players.JSONType = jtArray) then
      for I := 0 to Players.Count - 1 do
        if Players.Items[I].JSONType = jtObject then
          if AddRoundParticipant(TJSONObject(Players.Items[I])) then Changed := true;
    if Changed then UpdateResults;
  end
  else if (Kind = 'song.ended') and Assigned(FCurrentRound) and
    (FCurrentRound.Get('songSeq', -1) = Message.Get('songSeq', -2)) then
  begin
    Seq := Message.Get('songSeq', -1);
    for I := 0 to FResults.Count - 1 do
      if FResults.Objects[I].Get('songSeq', -2) = Seq then Exit;
    Round := CloneObject(FCurrentRound);
    if Message.Find('players') <> nil then Round.Add('players', Message.Find('players').Clone);
    FResults.Add(Round);
    // Enough for brief reconnects without growing a session-long network log.
    while FResults.Count > 32 do FResults.Delete(0);
    FreeAndNil(FCurrentRound);
    UpdateResults;
  end;
end;

procedure TRemoteRelayProtocol.PlayerUpdate(Message: TJSONObject; Notify: boolean);
var Id: string;
    Profile, Existing: TJSONObject;
    Value: TJSONData;
    I: integer;
begin
  Id := Message.Get('playerId', '');
  if Id = '' then Exit;
  Value := FPlayers.Find(Id);
  if (Value <> nil) and (Value.JSONType = jtObject) then Existing := TJSONObject(Value)
  else Existing := nil;
  if Existing = nil then
  begin
    if FPlayers.Count >= 256 then Exit;
    Profile := TJSONObject.Create(['playerId', Id, 'slot', 0, 'connected', true]);
    FPlayers.Add(Id, Profile);
  end
  else Profile := Existing;
  if (Message.Get('type', '') = 'player.joined') or
    (Message.Get('type', '') = 'player.assigned') then Profile.Booleans['connected'] := true;
  for I := 0 to Message.Count - 1 do
    if (Message.Names[I] <> 'type') and (Message.Names[I] <> 'hostToken') then
    begin
      RemoveField(Profile, Message.Names[I]);
      Profile.Add(Message.Names[I], Message.Items[I].Clone);
    end;
  Profile.Strings['type'] := 'player.assigned';
  if Notify then Deliver(Profile);
end;

procedure TRemoteRelayProtocol.CancelMedia(const Id: string);
var I: integer;
begin
 I := FTransfers.IndexOf(Id);
 if I < 0 then Exit;
 FTransfers.Objects[I].Free; FTransfers.Delete(I);
end;
procedure TRemoteRelayProtocol.MediaRequest(Message: TJSONObject);
var Id, Path, Mime, Ext: string; First, Last: int64; Value: TJSONData;
    Transfer: TRemoteMediaTransfer; Error: TJSONObject;
begin
 Id := Message.Get('requestId', '');
 if (Id = '') or (Length(Id) > 200) then Exit;
 CancelMedia(Id);
 try
  if FTransfers.Count >= 4 then raise Exception.Create('too_many_active_previews');
  Path := FMediaSources.Resolve(Message.Get('songId', -1), Message.Get('purpose', 'song-preview'));
  if Path = '' then raise Exception.Create('media_unavailable');
  Ext := LowerCase(ExtractFileExt(Path));
  Mime := 'application/octet-stream';
  if Ext = '.wav' then Mime := 'audio/wav'
  else if Ext = '.mp3' then Mime := 'audio/mpeg'
  else if Ext = '.ogg' then Mime := 'audio/ogg'
  else if Ext = '.flac' then Mime := 'audio/flac'
  else if Ext = '.m4a' then Mime := 'audio/mp4'
  else if Ext = '.png' then Mime := 'image/png'
  else if (Ext = '.jpg') or (Ext = '.jpeg') then Mime := 'image/jpeg';
  First := 0; Last := -1;
  Value := Message.Find('rangeStart');
  if (Value <> nil) and (Value.JSONType = jtNumber) then First := Value.AsInt64;
  Value := Message.Find('rangeEnd');
  if (Value <> nil) and (Value.JSONType = jtNumber) then Last := Value.AsInt64;
  Transfer := TRemoteMediaTransfer.Create(Id, Path, Mime, First, Last);
  FTransfers.AddObject(Id, Transfer);
 except
  // Do not expose local filenames from filesystem exception messages.
  Error := TJSONObject.Create(['type', 'song.preview.error', 'requestId', Id, 'reason', 'media_unavailable']);
  try Send(Error); finally Error.Free; end;
 end;
end;
procedure TRemoteRelayProtocol.TickMedia;
var Transfer: TRemoteMediaTransfer; Id: string; Error: TJSONObject;
begin
 if not FReady or (FTransfers.Count = 0) then Exit;
 Id := FTransfers[0]; Transfer := TRemoteMediaTransfer(FTransfers.Objects[0]);
 try
  if Send(Transfer.Peek) then Transfer.Accepted;
  if Transfer.Done then CancelMedia(Id)
  else FTransfers.Move(0, FTransfers.Count - 1);
 except
  CancelMedia(Id);
  Error := TJSONObject.Create(['type', 'song.preview.error', 'requestId', Id, 'reason', 'media_read_failed']);
  try Send(Error); finally Error.Free; end;
 end;
end;

procedure TRemoteRelayProtocol.FromRelay(Message: TJSONObject);
var Kind, Id: string;
    Reply: TJSONObject;
    Data: TJSONData;
    Players: TJSONArray;
    I: integer;
begin
  Kind := Message.Get('type', '');
  if (Kind = 'room.created') or (Kind = 'room.resumed') then
  begin
    FReady := true;
    if FRoomId <> Message.Get('roomId', '') then
    begin
      FPlayers.Clear;
      FResults.Clear;
      FreeAndNil(FCurrentRound);
      UpdateResults;
      FRoomId := Message.Get('roomId', '');
      Reply := TJSONObject.Create(['type', 'remote.players.snapshot', 'protocol', 1]);
      Reply.Add('players', TJSONArray.Create);
      try Deliver(Reply); finally Reply.Free; end;
    end;
    Reply := CopyPublic(Message);
    try Deliver(Reply); finally Reply.Free; end;
    Replay;
    Exit;
  end;
  if Kind = 'song.preview.request' then begin MediaRequest(Message); Exit; end;
  if Kind = 'song.preview.cancel' then begin CancelMedia(Message.Get('requestId', '')); Exit; end;
  if Kind = 'bridge.disconnected' then
  begin
    FReady := false;
    while FTransfers.Count > 0 do CancelMedia(FTransfers[0]);
    Deliver(Message);
    Exit;
  end;
  if Kind = 'clock.sync.ping' then
  begin
    Reply := TJSONObject.Create(['type', 'clock.sync.pong',
      'playerId', Message.Get('playerId', ''), 'hostReceiveUs', NowUs]);
    try
      Data := Message.Find('clientSendUs');
      if Data <> nil then Reply.Add('clientSendUs', Data.Clone);
      Reply.Add('hostSendUs', NowUs);
      Send(Reply);
    finally Reply.Free; end;
    Exit;
  end;
  if Kind = 'remote.players.snapshot' then
  begin
    Data := Message.Find('players');
    if (Data = nil) or (Data.JSONType <> jtArray) then Exit;
    Players := TJSONArray(Data);
    FPlayers.Clear;
    for I := 0 to Players.Count - 1 do
      if Players.Items[I].JSONType = jtObject then
        PlayerUpdate(TJSONObject(Players.Items[I]), false);
    Deliver(Message);
    Exit;
  end;
  if (Kind = 'player.joined') or (Kind = 'player.assigned') or
    (Kind = 'player.profile.updated') or (Kind = 'player.renamed') then
  begin
    PlayerUpdate(Message);
    Exit;
  end;
  if Kind = 'player.left' then RemoveField(FPlayers, Message.Get('playerId', ''));
  if Kind = 'player.disconnected' then
  begin
    Data := FPlayers.Find(Message.Get('playerId', ''));
    if (Data <> nil) and (Data.JSONType = jtObject) then
      TJSONObject(Data).Booleans['connected'] := false;
  end;
  if (Kind = 'control.command') and (Message.Get('command', '') = 'song.list') then
  begin
    Data := Message.Find('args');
    Reply := TJSONObject.Create(['type', 'ack',
      'playerId', Message.Get('playerId', ''),
      'commandId', Message.Get('commandId', int64(0))]);
    try
      if (Data = nil) or (Data.JSONType <> jtObject) then
      begin
        Reply.Add('accepted', false);
        Reply.Add('reason', 'invalid_args');
      end
      else
      begin
        Reply.Add('data', FSongs.Query(TJSONObject(Data)));
        Reply.Add('accepted', Reply.Objects['data'].Find('error') = nil);
        Reply.Add('reason', Reply.Objects['data'].Get('error', ''));
      end;
      Send(Reply);
    finally Reply.Free; end;
    Exit;
  end;
  if (Kind = 'control.command') or (Kind = 'settings.update') then
  begin
    Reply := CloneObject(Message);
    try
      Id := Message.Get('playerId', '');
      Data := FPlayers.Find(Id);
      if (Data <> nil) and (Data.JSONType = jtObject) then
      begin
        Reply.Integers['slot'] := TJSONObject(Data).Get('slot', 0);
        Reply.Strings['role'] := TJSONObject(Data).Get('role', 'controller');
      end;
      Deliver(Reply);
    finally Reply.Free; end;
    Exit;
  end;
  if Kind = 'song.state.request' then
  begin
    Replay;
    Exit;
  end;
  // The service's roster state can lag the game. Never feed it back as a
  // gameplay screen or overwrite the authoritative cached game.state.
  if (Kind = 'game.state') or (Kind = 'ack') then Exit;
  Deliver(Message);
end;

function TRemoteRelayProtocol.FromGame(Message: TJSONObject): boolean;
var Kind: string;
    PublicMessage, ApiState: TJSONObject;
    FieldName: string;
    Media: int64;
    Previous, LibraryData: TJSONData;
begin
  Kind := Message.Get('type', '');
  if Kind = 'bridge.ping' then Exit(true);
  if Kind = 'input.state' then
  begin
    Previous := FCache.Find('api.state');
    LibraryData := Message.Find('playerColors');
    if (Previous is TJSONObject) and (LibraryData is TJSONArray) then
    begin
      ApiState := TJSONObject(Previous.Clone);
      try
        if (ApiState.Find('playerColors') = nil) or
          (ApiState.Find('playerColors').AsJSON <> LibraryData.AsJSON) then
        begin
          RemoveField(ApiState, 'playerColors');
          ApiState.Add('playerColors', LibraryData.Clone);
          Cache(ApiState);
          Send(ApiState);
        end;
      finally ApiState.Free; end;
    end;
  end;
  RecordRound(Message);
  if (Kind = 'song.select.state') or (Kind = 'song.library') or (Kind = 'playlist.library') then
  begin
    LibraryData := Message.Find('library');
    if (LibraryData <> nil) and (LibraryData.JSONType = jtArray) then
    begin
      FMediaSources.Replace(TJSONArray(LibraryData));
      FSongs.Replace(TJSONArray(LibraryData));
    end;
    if ((LibraryData <> nil) and (LibraryData.JSONType = jtArray)) or
       (Kind = 'playlist.library') then
    begin
      ApiState := TJSONObject.Create(['type', 'api.state', 'libraryHash', FSongs.Id,
        'totalSongs', FSongs.Count]);
      try
        ApiState.Add('apiCapabilities', TJSONArray.Create(['song.list', 'continuous.start',
          'continuous.queue', 'continuous.stop', 'continuous.skip']));
        Previous := FCache.Find('input.state');
        if (Previous is TJSONObject) and (TJSONObject(Previous).Find('playerColors') is TJSONArray) then
          ApiState.Add('playerColors', TJSONObject(Previous).Find('playerColors').Clone);
        for FieldName in ['playlists', 'playlistItems', 'curPlaylist'] do
          if Message.Find(FieldName) <> nil then
            ApiState.Add(FieldName, Message.Find(FieldName).Clone);
        StripLocalPaths(ApiState);
        Cache(ApiState);
        // A later replay of screen state must not restore pre-edit playlists.
        Previous := FCache.Find('song.select.state');
        if (Previous <> nil) and (Previous.JSONType = jtObject) then
          for FieldName in ['playlists', 'playlistItems', 'curPlaylist'] do
            if ApiState.Find(FieldName) <> nil then
            begin
              RemoveField(TJSONObject(Previous), FieldName);
              TJSONObject(Previous).Add(FieldName, ApiState.Find(FieldName).Clone);
            end;
        Send(ApiState);
      finally ApiState.Free; end;
    end;
  end;
  // This is a private game-thread snapshot, never live screen state.
  if (Kind = 'song.library') or (Kind = 'playlist.library') then Exit(true);
  PublicMessage := CopyPublic(Message);
  try
    if Kind = 'continuous.state' then
    begin
      if Message.Get('active', false) then Inc(FContinuousSeq);
      PublicMessage.Int64s['sessionSeq'] := FContinuousSeq;
    end;
    if Kind = 'game.state' then
    begin
      Previous := FCache.Find('game.state');
      if (Previous <> nil) and (Previous.JSONType = jtObject) and
        (TJSONObject(Previous).Get('state', '') <> Message.Get('state', '')) then
        RemoveField(FCache, 'screen.info');
    end;
    if Kind = 'song.started' then
    begin
      RemoveField(FCache, 'song.lyrics');
      RemoveField(FCache, 'score.sheet');
      RemoveField(FCache, 'score.snapshot');
    end;
    if Kind = 'song.select.state' then
    begin
      // Catalog and preview transfer are separate handlers. Never upload a
      // game's full private library (or local paths) as live screen state.
      RemoveField(PublicMessage, 'apiCapabilities');
      PublicMessage.Add('apiCapabilities', TJSONArray.Create(['song.list', 'continuous.start', 'continuous.queue', 'continuous.stop', 'continuous.skip']));
      RemoveField(PublicMessage, 'library');
      RemoveField(PublicMessage, 'audioPath');
      RemoveField(PublicMessage, 'coverPath');
      RemoveField(PublicMessage, 'txtPath');
      PublicMessage.Int64s['hostStateUs'] := PublicMessage.Get('hostStateUs', NowUs);
    end;
    if (Kind = 'song.started') or (Kind = 'song.resumed') or
      (Kind = 'song.paused') or (Kind = 'song.position') or (Kind = 'song.ended') then
    begin
      PublicMessage.Int64s['hostStateUs'] := PublicMessage.Get('hostStateUs', NowUs);
      Media := PublicMessage.Get('mediaStartUs', int64(0));
      if Media < 0 then Media := 0;
      PublicMessage.Int64s['hostSongStartUs'] := PublicMessage.Int64s['hostStateUs'] - Media;
      if Kind = 'song.ended' then
      begin
        RemoveField(FCache, 'song.clock');
        RemoveField(FCache, 'song.lyrics');
      end
      else
      begin
        RemoveField(FCache, 'song.clock');
        FCache.Add('song.clock', PublicMessage.Clone);
      end;
    end;
    if (Kind = 'audio.stop') then
    begin
      RemoveField(FCache, 'song.clock');
      RemoveField(FCache, 'song.lyrics');
    end;
    if (Kind = 'input.state') or (Kind = 'game.state') or (Kind = 'screen.info') or
      (Kind = 'playlist.state') or (Kind = 'song.select.state') or (Kind = 'continuous.state') or
      (Kind = 'song.lyrics') or (Kind = 'score.sheet') or (Kind = 'score.snapshot') then Cache(PublicMessage);
    // Cache state even offline. Obsolete ACKs/signaling must not block later
    // state/results or replay into a freshly negotiated connection.
    Result := Send(PublicMessage);
    if not FReady then Result := true;
  finally PublicMessage.Free; end;
end;

end.
