"""Check the production worker reporter with actual Pascal thread exceptions."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class WorkerExceptionTests(unittest.TestCase):
    def test_thread_failure_logging_failure_and_missing_logger(self):
        compiler = os.environ.get('USCE_FPC') or shutil.which('fpc')
        if not compiler:
            self.skipTest('Free Pascal is not installed')
        source = (Path(__file__).resolve().parents[1] / 'src/base/ULog.pas').read_text()
        method = source.split('procedure LogWorkerException(const Context: string);\nvar', 1)[1]
        method = 'procedure LogWorkerException(const Context: string);\nvar' + method.split('constructor TLog.Create;', 1)[0]
        harness = '''program WorkerLog;
{$mode Delphi}
uses {$IFDEF UNIX}cthreads,{$ENDIF} SysUtils, Classes;
type
  TLogger = class
    procedure LogExceptionReport(const Report: string);
  end;
  TTestPlatform = class
    function GetBacktraceFunction: TBacktraceStrFunc;
  end;
  TWorker = class(TThread)
    procedure Execute; override;
  end;
var Log: TLogger; Platform: TTestPlatform; Text: string; FailWrite: boolean;
procedure TLogger.LogExceptionReport(const Report: string);
begin
  if FailWrite then raise Exception.Create('log write failed');
  Text := Report;
end;
function TTestPlatform.GetBacktraceFunction: TBacktraceStrFunc;
begin Result := BackTraceStrFunc; end;
''' + method + '''
procedure TWorker.Execute;
begin
  try
    raise ERangeError.Create('original worker failure');
  except
    LogWorkerException('test worker');
    raise;
  end;
end;
procedure Check(Value: boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;
var W: TWorker; I: integer;
begin
  Platform := TTestPlatform.Create;
  for I := 0 to 2 do
  begin
    Text := ''; FailWrite := I = 1;
    if I <> 2 then Log := TLogger.Create else Log := nil;
    W := TWorker.Create(false);
    try
      W.WaitFor;
      Check(W.FatalException is ERangeError, 'original exception type replaced');
      Check(Exception(W.FatalException).Message = 'original worker failure', 'original message replaced');
      if I = 0 then
      begin
        Check(Pos('Worker: test worker', Text) > 0, 'worker context missing');
        Check(Pos('Exception class: ERangeError', Text) > 0, 'class missing');
        Check(Pos('Message: original worker failure', Text) > 0, 'message missing');
        Check(Length(Text) > Pos('Message: original worker failure', Text) + 40, 'stack missing');
      end;
    finally W.Free; Log.Free; Log := nil; end;
  end;
  Platform.Free;
  WriteLn('PASS: actual worker exception, stack report, failing log and missing logger');
end.
'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'worker_log.pas'
            path.write_text(harness)
            result = subprocess.run([compiler, '-Mdelphi', '-Ciro', '-gl', str(path)],
                                    cwd=directory, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            subprocess.run([str(path.with_suffix('.exe' if os.name == 'nt' else ''))],
                           check=True, timeout=10)
