program Presets;
{$mode Delphi}{$codepage utf8}
uses Classes,SysUtils,UPath,UFilterPresets,USongs;
var F:IPath;Store:TFilterPresets;Rows,Loaded:TSongFilterRows;Stream:TBinaryFileStream;Failed:boolean;
procedure Check(B:boolean;const Msg:string);begin if not B then raise Exception.Create(Msg);end;
begin
 SetMultiByteConversionCodePage(CP_UTF8);F:=Path(UTF8String(ParamStr(1)));
 Store:=TFilterPresets.Create(F);
 SetLength(Rows,3);Rows[0].Kind:=fltArtist;Rows[0].Query:='Grüße, Beatles';Rows[1].Kind:=fltAge;Rows[1].Query:='DE:<=12';Rows[2].Kind:=fltTags;Rows[2].Query:='   live ; fun   ';
 Store.Save('Kinder ä',Rows);Store.Save('Second',Rows);Store.Free;
 Store:=TFilterPresets.Create(F);Check(Length(Store.Names)=2,'persisted names');Loaded:=Store.Load('Kinder ä');
 Check((Length(Loaded)=3) and (Loaded[0].Query=Rows[0].Query) and (Loaded[1].Kind=fltAge) and (Loaded[2].Query=Rows[2].Query),'exact roundtrip');
 Rows[0].Query:='Changed';Store.Save('Kinder ä',Rows);Check(Length(Store.Names)=2,'replace no duplicate');
 Check(Store.Load('Kinder ä')[0].Query='Changed','replace value');
 Store.Delete('Second');Check(not Store.Contains('Second'),'delete');
 Failed:=false;try Store.Load('missing');except Failed:=true;end;Check(Failed,'missing explicit');
 Failed:=false;try Store.Save(' ',Rows);except Failed:=true;end;Check(Failed,'empty name');Store.Free;
 Stream:=TBinaryFileStream.Create(F,fmCreate);try Stream.WriteBuffer(PChar('{"bad":[{"kind":999,"query":"x"}]}')^,34);finally Stream.Free;end;
 Store:=TFilterPresets.Create(F);Failed:=false;try Store.Load('bad');except Failed:=true;end;Check(Failed,'invalid category rejected');Store.Free;
 Writeln('PASS: UTF8 names, filter types, exact queries, reload, replace/delete, missing and invalid categories');
end.
