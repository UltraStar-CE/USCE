program LocalCaptureWindowTest;

{$mode Delphi}

uses Math, SysUtils, UIni, UMusic, URecord, UTime;

const
  SampleRate = 44100;
  CallbackSamples = 8192;

var
  Device: TAudioInputDevice;
  Capture: TCaptureBuffer;
  Samples: array[0..CallbackSamples - 1] of SmallInt;
  I: integer;
  FirstEndUs, CenterUs, WaitUntilUs: int64;

procedure Check(Value: boolean; const MessageText: string);
begin
  if not Value then
    raise Exception.Create(MessageText);
end;

begin
  Ini := TIni(TIni.NewInstance);
  Capture := TCaptureBuffer.Create;
  Device := TAudioInputDevice(TAudioInputDevice.NewInstance);
  try
    Device.AudioFormat := TAudioFormatInfo.Create(1, SampleRate, asfS16);
    SetLength(Device.CaptureChannel, 1);
    Device.LinkCaptureBuffer(0, Capture);
    for I := 0 to High(Samples) do
      Samples[I] := Round(15000 * Sin(2 * Pi * 440 * I / SampleRate));

    FirstEndUs := MonotonicMicroseconds;
    AudioInputProcessor.HandleMicrophoneData(@Samples[0], SizeOf(Samples), Device);
    CenterUs := FirstEndUs + 25000;
    Check(not Capture.AnalyzeLocalWindow(CenterUs, CaptureWindowSamples, WaitUntilUs),
      'The centered window needs the next callback');
    Check(WaitUntilUs >= CenterUs + 232000, 'Long callback and half-window must fit before the deadline');
    Check(WaitUntilUs <= CenterUs + 250000, 'A stalled input must still have a bounded deadline');

    for I := 0 to High(Samples) do
      Samples[I] := Round(15000 * Sin(2 * Pi * 440 * (I + CallbackSamples) / SampleRate));
    while MonotonicMicroseconds < FirstEndUs + Round(CallbackSamples * 1000000.0 / SampleRate) do
      Sleep(1);
    AudioInputProcessor.HandleMicrophoneData(@Samples[0], SizeOf(Samples), Device);
    Check(Capture.AnalyzeLocalWindow(CenterUs, CaptureWindowSamples, WaitUntilUs),
      'The next callback must retain the part of the window from the previous callback');
    Check(Capture.ToneValid and (Capture.Tone = 9), 'The recovered window must detect A');
    Check(not Capture.AnalyzeLocalWindow(FirstEndUs - 300000, CaptureWindowSamples, WaitUntilUs) and
      (WaitUntilUs = 0), 'Waiting cannot recover samples older than retained history');
    WriteLn('PASS: centered capture window waits for and spans 8192-sample callbacks at 44.1 kHz');
  finally
    Device.LinkCaptureBuffer(0, nil);
    Device.AudioFormat.Free;
    Device.FreeInstance;
    Capture.Free;
    Ini.FreeInstance;
    Ini := nil;
  end;
end.
