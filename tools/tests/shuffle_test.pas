program ShuffleTest;
{$MODE Delphi}
uses SysUtils, UCommon, UParty;
var Candidates, Pool, Order, OtherPool, OtherOrder: CardinalArray;
    Cursor, OtherCursor: cardinal; Seen: array[0..99] of boolean;
    Seed, Cycle, I, Pick: integer; Game: TPartyGame;
procedure Check(Value: boolean; const Message: string);
begin if not Value then raise Exception.Create(Message); end;
begin
 for Seed := 0 to 99 do
 begin
  RandSeed := Seed;Pool := nil;Order := nil;Cursor := 0;
  SetLength(Candidates, 100);
  for I := 0 to 99 do Candidates[I] := I;
  for Cycle := 1 to 3 do
  begin
   FillChar(Seen,SizeOf(Seen),0);
   for I := 0 to 99 do
   begin
    Pick := NextShuffled(Candidates,Pool,Order,Cursor);
    Check((Pick >= 0) and (Pick <= 99),'eligible range');
    Check(not Seen[Pick],'repeat before exhaustion');Seen[Pick] := true;
   end;
  end;
 end;
 // Replacing a pool with an equal-sized set must invalidate its old order.
 Candidates := [101,102];Pick := NextShuffled(Candidates,Pool,Order,Cursor);
 Check((Pick=101) or (Pick=102),'same-size replacement');
 Candidates := [201,202];Pick := NextShuffled(Candidates,Pool,Order,Cursor);
 Check((Pick=201) or (Pick=202),'equal-count changed identities');
 OtherCursor := 0;Pick := NextShuffled(Candidates,OtherPool,OtherOrder,OtherCursor);
 Check(Cursor=1,'independent cursor');
 Candidates[0] := 999;Check(Pool[0]=201,'cached pool must own its copy');
 Candidates := [];Check(NextShuffled(Candidates,Pool,Order,Cursor)=-1,'empty pool');
 Check((Length(Order)=0) and (Cursor=0),'empty pool resets');
 Candidates := [7];for I := 1 to 5 do Check(NextShuffled(Candidates,Pool,Order,Cursor)=7,'single song');
 Cursor := High(cardinal);Check(NextShuffled(Candidates,Pool,Order,Cursor)=7,'explicit invalidation');
 Game := TPartyGame.Create;
 try
  Candidates := [11,22,33];FillChar(Seen,SizeOf(Seen),0);
  for I := 1 to 3 do
  begin
   Pick := Game.NextRandomSong(Candidates);Check(not Seen[Pick],'Party repeats');Seen[Pick] := true;
  end;
  Game.Clear;
  Check(Game.NextShuffleIndex=0,'new session resets cursor');
  Check(Length(Game.ShufflePool)=0,'new session resets pool');
  Check(Game.NextRandomSong([])=-1,'Party empty pool');
 finally Game.Free;end;
 Writeln('PASS: 100 seeded shuffle cycles, changed pools, empty/single pools and Party session reset');
end.
