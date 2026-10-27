program phone_audio_pitch_test;
{$mode Delphi}{$H+}
uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  SysUtils, Math, UIni, URecord, UPhoneAudio;
var Capture: TCaptureBuffer;
    Samples: array[0..4095] of smallint;
    I, Note, Count, OctaveAlternatives: integer;
    Frequency: double;
    Started, NextReport, Total: QWord;
    DurationMs: integer;
procedure Benchmark;
const Sizes: array[0..2] of integer = (1024, 2048, 4096);
var Size, Pitch, J, Exact, CorrectClass, Step, ResponseMs: integer;
    CpuUs: double;
    Block: array[0..479] of smallint;
begin
  WriteLn('windowSamples,windowMs,exactNotes,pitchClasses,totalNotes,meanAnalysisUs,step220to330ms');
  for Size in Sizes do
  begin
    Capture.AnalysisBufferSize := Size;
    Exact := 0; CorrectClass := 0; CpuUs := 0;
    for Pitch := 0 to 48 do
    begin
      for J := 0 to High(Samples) do
        Samples[J] := Round(8192 * Sin(2 * Pi * 440 * Power(2, (Pitch - 33) / 12) * J / 48000));
      Capture.SubmitPhonePcm(@Samples[0], Length(Samples));
      Capture.AnalyzeBuffer;
      CpuUs := CpuUs + Capture.LastAnalysisMicroseconds;
      if Capture.ToneValid then
      begin
        if Capture.ToneAbs = Pitch then Inc(Exact);
        if Capture.ToneAbs mod 12 = Pitch mod 12 then Inc(CorrectClass);
      end;
      if not Capture.ToneValid or (Capture.ToneAbs mod 12 <> Pitch mod 12) then
        WriteLn('# window=', Size, ' inputHz=', 440 * Power(2, (Pitch - 33) / 12):0:2,
          ' expectedNote=', Pitch, ' detectedNote=', Capture.ToneAbs);
    end;
    for J := 0 to High(Samples) do Samples[J] := Round(8192 * Sin(2 * Pi * 220 * J / 48000));
    Capture.SubmitPhonePcm(@Samples[0], Length(Samples));
    ResponseMs := -1;
    for Step := 0 to 19 do
    begin
      for J := 0 to High(Block) do
        Block[J] := Round(8192 * Sin(2 * Pi * 329.6275569 * (Step * 480 + J) / 48000));
      Capture.SubmitPhonePcm(@Block[0], Length(Block));
      Capture.AnalyzeBuffer;
      if Capture.ToneValid and (Capture.ToneAbs = 28) and (ResponseMs < 0) then ResponseMs := (Step + 1) * 10;
    end;
    WriteLn(Size, ',', Size / 48:0:2, ',', Exact, ',', CorrectClass, ',49,', CpuUs / 49:0:1, ',', ResponseMs);
  end;
end;
// Measure acquisition of low-note changes through the actual rolling capture
// buffer and game detector. This excludes transport, capture and frame scheduling.
procedure TransitionWindowTest;
const Sizes: array[0..1] of integer = (2048, 4096);
var Size, Trial, Direction, J, Step, FirstMs, StableMs, Run, Expected,
    InitialNote, FinalNote: integer;
    Phase, Hz: double;
    Block: array[0..479] of smallint;
begin
  Capture.PitchAlgorithm := PDA_CAMDF;
  WriteLn('windowSamples,fromNote,toNote,phaseTrial,firstCorrectMs,threeConsecutiveCorrectMs,finalDetectedNote');
  for Size in Sizes do
  begin
    Capture.AnalysisBufferSize := Size;
    for Direction := 0 to 1 do
      for Trial := 0 to 11 do
      begin
        InitialNote := Direction * 5;
        FinalNote := (1 - Direction) * 5;
        Phase := Trial * 2 * Pi / 12;
        Hz := 440 * Power(2, (InitialNote - 33) / 12);
        for J := 0 to High(Samples) do
          Samples[J] := Round(8192 * Sin(2 * Pi * Hz * J / 48000 + Phase));
        Capture.Clear;
        Capture.SubmitPhonePcm(@Samples[0], Length(Samples));
        FirstMs := -1; StableMs := -1; Run := 0;
        Expected := FinalNote;
        // Preserve oscillator phase at the transition, as the browser generator does.
        Phase := Phase + 2 * Pi * Hz * Length(Samples) / 48000;
        Hz := 440 * Power(2, (FinalNote - 33) / 12);
        for Step := 0 to 29 do
        begin
          for J := 0 to High(Block) do
            Block[J] := Round(8192 * Sin(2 * Pi * Hz * (Step * 480 + J) / 48000 + Phase));
          Capture.SubmitPhonePcm(@Block[0], Length(Block));
          Capture.AnalyzeBuffer;
          if Capture.ToneValid and (Capture.ToneAbs mod 12 = Expected mod 12) then
          begin
            if FirstMs < 0 then FirstMs := (Step + 1) * 10;
            Inc(Run);
            if (Run = 3) and (StableMs < 0) then StableMs := (Step + 1) * 10;
          end
          else Run := 0;
        end;
        WriteLn(Size, ',', InitialNote, ',', FinalNote, ',', Trial, ',', FirstMs, ',', StableMs, ',', Capture.ToneAbs);
      end;
  end;
end;
procedure LowWindowTest;
const Sizes: array[0..3] of integer = (512, 1024, 2048, 4096);
var Size, Trial, Shape, J, Passed, Detector: integer;
    Phase, T, V: double;
begin
  WriteLn('algorithm,windowSamples,windowMs,frequencyHz,correctNearestNote,totalTrials');
  for Detector := 0 to 1 do
  begin
  Capture.PitchAlgorithm := TPDAType(Detector);
  for Size in Sizes do
  begin
    Capture.AnalysisBufferSize := Size;
    Passed := 0;
    for Shape := 0 to 2 do
      for Trial := 0 to 11 do
      begin
        Phase := Trial * 2 * Pi / 12;
        for J := 0 to High(Samples) do
        begin
          T := 2 * Pi * 65 * J / 48000 + Phase;
          case Shape of
            0: V := Sin(T);
            1: V := 0.6 * Sin(T) + 0.25 * Sin(2 * T) + 0.15 * Sin(3 * T);
            else V := 0.2 * Sin(T) + 0.6 * Sin(2 * T) + 0.2 * Sin(3 * T);
          end;
          Samples[J] := Round(8192 * V);
        end;
        Capture.SubmitPhonePcm(@Samples[0], Length(Samples));
        Capture.AnalyzeBuffer;
        if Capture.ToneValid and (Capture.ToneAbs = 0) then Inc(Passed);
      end;
    WriteLn(Detector, ',', Size, ',', Size / 48:0:2, ',65,', Passed, ',36');
  end;
  end;
end;
begin
  Ini := TIni.Create;
  Ini.ThresholdIndex := 0;
  Capture := TCaptureBuffer.Create;
  Capture.AnalysisBufferSize := 4096;
  OctaveAlternatives := 0;
  try
    Ini.MicBoost := 3;
    for I := 0 to High(Samples) do Samples[I] := 8000;
    Capture.SubmitPhonePcm(@Samples[0], Length(Samples));
    if (Capture.AnalysisBuffer[High(Capture.AnalysisBuffer)] <> 8000) or
       (Samples[0] <> 8000) then
      raise Exception.Create('Phone PCM inherited physical microphone boost/clipping');
    Ini.MicBoost := 0;
    Capture.Clear;
    for Note := 21 to 45 do
    begin
      Frequency := 440 * Power(2, (Note - 33) / 12);
      for I := 0 to High(Samples) do
        Samples[I] := Round(8192 * Sin(2 * Pi * Frequency * I / 48000));
      Capture.SubmitPhonePcm(@Samples[0], Length(Samples));
      Capture.AnalyzeBuffer;
      if not Capture.ToneValid or (Capture.ToneAbs mod 12 <> Note mod 12) then
      begin
        WriteLn('Pitch mismatch at ', Frequency:0:2, ' Hz: ', Capture.ToneAbs, ' expected ', Note);
        Halt(1);
      end;
      if Capture.ToneAbs <> Note then
      begin
        Inc(OctaveAlternatives);
        WriteLn('Existing detector octave alternative at ', Frequency:0:2, ' Hz: ', Capture.ToneAbs, ' expected ', Note);
      end;
    end;
    FillChar(Samples, SizeOf(Samples), 0);
    Capture.SubmitPhonePcm(@Samples[0], Length(Samples));
    Capture.AnalyzeBuffer;
    if Capture.ToneValid then Halt(2);
    WriteLn('Existing game detector: 25 pitch classes (220-880 Hz) and silence passed; octave alternatives=', OctaveAlternatives);
    if ParamStr(1) = '--benchmark' then Benchmark;
    if ParamStr(1) = '--low-window' then LowWindowTest;
    if ParamStr(1) = '--transition-window' then TransitionWindowTest;
    if ParamStr(1) = '--live' then
    begin
      case StrToIntDef(GetEnvironmentVariable('USCE_AUDIO_WINDOW'), 4096) of
        1024: Capture.AnalysisBufferSize := 1024;
        2048: Capture.AnalysisBufferSize := 2048;
      end;
      if not PhoneAudio.Start('', '', GetEnvironmentVariable('USCE_RAW_AUDIO_LIBRARY')) then
      begin
        WriteLn(PhoneAudio.LastError);
        Halt(3);
      end;
      Started := GetTickCount64;
      NextReport := Started;
      Total := 0;
      DurationMs := StrToIntDef(GetEnvironmentVariable('USCE_RAW_AUDIO_TEST_DURATION_MS'), 120000);
      if (DurationMs < 1000) or (DurationMs > 600000) then DurationMs := 120000;
      while GetTickCount64 - Started < QWord(DurationMs) do
      begin
        Count := PhoneAudio.Poll(@Samples[0], Length(Samples));
        if Count > 0 then
        begin
          Capture.SubmitPhonePcm(@Samples[0], Count);
          Inc(Total, Count);
        end;
        if GetTickCount64 >= NextReport then
        begin
          Capture.AnalyzeBuffer;
          WriteLn(PhoneAudio.Status);
          WriteLn('gamePitch=', Capture.ToneString, ' totalSamples=', Total);
          Flush(Output);
          NextReport := GetTickCount64 + 1000;
        end;
        Sleep(10);
      end;
      PhoneAudio.Stop;
    end;
  finally
    Capture.Free;
    Ini.Free;
  end;
end.
