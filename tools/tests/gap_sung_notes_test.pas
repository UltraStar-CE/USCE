program GapSungNotesTest;
{$mode Delphi}
uses Math, SysUtils, UNote, URecord, UIni, UMusic;
var I: integer; Device: TAudioInputDevice; Sound: TCaptureBuffer;
procedure Check(V: boolean; const Msg: string);
begin if not V then raise Exception.Create(Msg); end;
begin
 Ini:=TIni(TIni.NewInstance); Ini.ThresholdIndex:=0;
 SetLength(Player,24);
 for I:=0 to High(Player) do begin Player[I].HighNote:=-1;Player[I].Score:=1000;end;
 AddGapSungNote(0,0,9);Check(Length(Player[0].Note)=0,'no octave reference before singing');
 Player[0].HasLastSungTone:=true;Player[0].LastSungTone:=9;
 Player[1].HasLastSungTone:=true;Player[1].LastSungTone:=21;
 Device:=TAudioInputDevice(TAudioInputDevice.NewInstance);
 Device.AudioFormat:=TAudioFormatInfo.Create(1,44100,asfS16);SetLength(Device.CaptureChannel,1);
 Sound:=AudioInputProcessor.Sound[0];Device.LinkCaptureBuffer(0,Sound);
 for I:=0 to High(Sound.AnalysisBuffer) do Sound.AnalysisBuffer[I]:=Round(15000*Sin(2*Pi*440*I/44100));
 Sound.AnalyzeBuffer;Check(Sound.ToneValid,'real PCM detector produces pitch');
 AddGapSungNote(0,2,Sound.Tone);AddGapSungNote(0,3,Sound.Tone);
 Check((Length(Player[0].Note)=1) and (Player[0].Note[0].Duration=2),'same pitch extends normal bar representation');
 Check(Player[0].Note[0].IsGap and not Player[0].Note[0].Perfect and not Player[0].Note[0].Hit,'gap is display-only');
 Check(Player[0].Note[0].Tone=9,'last sung octave');
 AddGapSungNote(1,2,Sound.Tone);Check(Player[1].Note[0].Tone=21,'independent player octave');
 AddGapSungNote(0,5,Sound.Tone);Check(Length(Player[0].Note)=2,'silence breaks a gap bar');
 AddGapSungNote(0,6,11);Check(Length(Player[0].Note)=3,'pitch changes start another bar');
 for I:=0 to High(Player) do Check(Player[I].Score=1000,'gap samples do not score');
 ResetSungPitchReference;for I:=0 to High(Player) do Check(not Player[I].HasLastSungTone,'song and seek reset references');
 Device.AudioFormat.Free;Device.FreeInstance;Ini.FreeInstance;Ini:=nil;
 Writeln('PASS: real PCM analysis, shared sung-bar representation, gap extension, octave retention, silence, 24 player references and unchanged scores');
end.
