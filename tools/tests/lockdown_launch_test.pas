program Launch;
{$mode Delphi}{$codepage utf8}
uses Classes,SysUtils,UCommandLine,ULockdownLaunch,ULibraryLockdown,UPlaylist,USong;
var P:TCMDParams;Lists:APlaylist;LibrarySongs:array of TSong;Selected,LibraryList:TList;Error:UTF8String;I,PlaylistIndex:integer;
procedure Check(B:boolean;const Msg:string);begin if not B then raise Exception.Create(Msg);end;
begin
 SetMultiByteConversionCodePage(CP_UTF8);
 if ParamCount>0 then begin
   P:=TCMDParams.Create;
   Writeln('lock=',Ord(P.Lockdown),' playlist=',P.PlaylistName,' error=',P.StartupError);
   Writeln('settings=',P.PlaybackResults,',',P.PlaybackHighScores,',',P.PlaybackSongDisplay,',',P.PlaybackSingingDisplay);
   if P.LockdownPassword<>'' then Writeln('password-set');
   P.Free;Halt;
 end;
 SetLength(LibrarySongs,4);LibraryList:=TList.Create;Selected:=TList.Create;
 for I:=0 to 3 do begin LibrarySongs[I]:=TSong.Create;LibraryList.Add(LibrarySongs[I]);end;
 LibrarySongs[0].Main:=true;
 SetLength(Lists,3);Lists[0].Name:='First';Lists[1].Name:='Grüße';Lists[2].Name:='Empty';
 SetLength(Lists[0].Items,4);Lists[0].Items[0].SongID:=2;Lists[0].Items[1].SongID:=1;
 Lists[0].Items[2].SongID:=0;Lists[0].Items[3].SongID:=999;
 SetLength(Lists[1].Items,2);Lists[1].Items[0].SongID:=1;Lists[1].Items[1].SongID:=3;
 Check(CollectLaunchSongs('first',Lists,LibrarySongs,Selected,PlaylistIndex,Error),'single playlist');
 Check((Selected.Count=2) and (Selected[0]=LibrarySongs[2]) and (Selected[1]=LibrarySongs[1]),'dedup order');
 Check(LibraryLockdown.Activate(LibraryList,Selected,'pw'),'activate');
 Check((LibraryList.Count=2) and LibraryLockdown.Active,'restricted library');
 Check(not LibraryLockdown.Unlock(LibraryList,'wrong'),'wrong password');
 Check(LibraryLockdown.Unlock(LibraryList,'pw') and (LibraryList.Count=4),'restore library');
 Check(not CollectLaunchSongs('Missing',Lists,LibrarySongs,Selected,PlaylistIndex,Error),'missing rejects');
 Check(CollectLaunchSongs('Grüße',Lists,LibrarySongs,Selected,PlaylistIndex,Error),'Unicode');
 Check(not CollectLaunchSongs('Empty',Lists,LibrarySongs,Selected,PlaylistIndex,Error),'empty rejects');
 Lists[2].Name:='FIRST';Check(not CollectLaunchSongs('first',Lists,LibrarySongs,Selected,PlaylistIndex,Error),'ambiguous rejects');
 for I:=0 to 3 do LibrarySongs[I].Free;Selected.Free;LibraryList.Free;
 Writeln('PASS: single playlist, deduplication, first-song order, missing/empty/ambiguous rejection and actual lockdown restore');
end.
