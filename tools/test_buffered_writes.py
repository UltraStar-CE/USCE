"""Exercise the production INI/log methods with FPC and temporary files."""
import pathlib
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('fpc'), 'Free Pascal is required')
class BufferedWrites(unittest.TestCase):
    def test_cached_settings_and_log_lifecycle(self):
        ini = (ROOT / 'src/base/UIni.pas').read_text()
        log = (ROOT / 'src/base/ULog.pas').read_text()
        ini_class = re.search(r'  TSafeIniFile = class\(TIniFile\).*?\n  end;', ini, re.S).group()
        ini_methods = ini[ini.index('constructor TSafeIniFile.Create'):ini.index('(**', ini.index('procedure TSafeIniFile.DeleteKey'))]
        lifecycle = log[log.index('constructor TLog.Create'):log.index('procedure TLog.BenchmarkStart')]
        log_methods = log[log.index('procedure TLog.LogToFile'):log.index('procedure TLog.SetLogLevel')]
        source = r'''
program TestBufferedWrites;
{$mode delphi}{$H+}
uses SysUtils, Classes, IniFiles;
const LOG_LEVEL_DEFAULT=20; LOG_FILE_LEVEL_DEFAULT=10;
type
 TPath = record
   Value: string;
   function Append(const Name: string): TPath;
   function ToNative: string;
 end;
 TLog = class
 public
   ErrorLogFile, SongLogFile, BenchmarkFile: TextFile;
   ErrorLogFileOpened, SongLogFileOpened, BenchmarkFileOpened: boolean;
   ErrorLogBuffer, SongLogBuffer: array[0..65535] of byte;
   ErrorLogPending, SongLogPending, FileWriteFailed: boolean;
   LastFlushTime: QWord;
   Lock: TRTLCriticalSection;
   LogLevel, LogFileLevel, Errors: integer;
   FileOutputEnabled: boolean;
   Title: string;
   constructor Create;
   destructor Destroy; override;
   procedure LogToFile(const Text, LogName: string; var LogFileOpened: boolean; var LogFile: TextFile; Immediate: boolean=false);
   procedure FlushPending;
   procedure LogExceptionReport(const Report: string);
   procedure LogError(const Msg, Context: string);
 end;
''' + ini_class + r'''
 TCountIni = class(TSafeIniFile)
   procedure UpdateFile; override;
 end;
var LogPath: TPath; Log: TLog; Writes: integer;
function TPath.Append(const Name: string): TPath;
begin Result.Value := IncludeTrailingPathDelimiter(Value)+Name end;
function TPath.ToNative: string;
begin Result:=Value end;
procedure TLog.LogError(const Msg, Context: string);
begin Inc(Errors) end;
procedure TCountIni.UpdateFile;
begin Inc(Writes); inherited end;
''' + lifecycle + ini_methods + log_methods + r'''
procedure Check(OK: boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg) end;
function Contents(const Name: string): string;
var S:TStringList; F:TFileStream;
begin
 S:=TStringList.Create;
 try
   if FileExists(Name) then
   begin
     // The production logger intentionally keeps its buffered file open.
     F:=TFileStream.Create(Name, fmOpenRead or fmShareDenyNone);
     try S.LoadFromStream(F) finally F.Free end;
   end;
   Result:=S.Text;
 finally S.Free end;
end;
var C:TCountIni; I:integer; P,BeforeText:string;
begin
 LogPath.Value:=GetCurrentDir; Log:=TLog.Create; Log.FileOutputEnabled:=true;
 P:='settings.ini'; C:=TCountIni.Create(P,'test');
 for I:=1 to 100 do C.WriteInteger('Settings','Key'+IntToStr(I),I);
 Check(not FileExists(P),'settings written before save completed');
 C.Free; Check(Writes=1,'settings save must write once');
 C:=TCountIni.Create(P,'test');
 for I:=1 to 100 do begin Check(C.ReadInteger('Settings','Key'+IntToStr(I),0)=I,'setting lost'); C.WriteInteger('Settings','Key'+IntToStr(I),I) end;
 C.Free; Check(Writes=1,'unchanged settings must not rewrite');
 C:=TCountIni.Create('settings.ini/child.ini','test'); C.WriteString('S','K','V'); C.Free;
 Check(Log.Errors=1,'failed save must report once without raising');
 Log.LogToFile('first','Error.log',Log.ErrorLogFileOpened,Log.ErrorLogFile);
 BeforeText:=Contents('Error.log');
 for I:=1 to 100 do Log.LogToFile('buffered '+IntToStr(I),'Error.log',Log.ErrorLogFileOpened,Log.ErrorLogFile);
 Check(Contents('Error.log')=BeforeText,'routine lines flushed individually');
 Log.LastFlushTime:=GetTickCount64; Log.FlushPending;
 Check(Contents('Error.log')=BeforeText,'flush interval ignored');
 Log.LastFlushTime:=GetTickCount64-1001; Log.FlushPending;
 Check(Pos('buffered 100',Contents('Error.log'))>0,'periodic flush lost data');
 Log.LogToFile('pending before exception','Error.log',Log.ErrorLogFileOpened,Log.ErrorLogFile);
 Log.LogExceptionReport('test crash');
 Check(Pos('EXCEPTION: test crash',Contents('Error.log'))>0,'exception not immediately flushed');
 Check(Pos('pending before exception',Contents('Error.log'))>0,'exception flush lost preceding context');
 Log.LogToFile('close must drain','Error.log',Log.ErrorLogFileOpened,Log.ErrorLogFile);
 Log.Free;
 Check(Pos('close must drain',Contents('Error.log'))>0,'close lost buffered line');
 WriteLn('PASS: one settings write, no-op saves, save failure, buffered burst, timer, exception and close');
end.
'''
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            (tmp / 'test.pas').write_text(source)
            compiled = subprocess.run(['fpc', '-otest-buffered', 'test.pas'], cwd=tmp, capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(tmp / 'test-buffered')], cwd=tmp, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()