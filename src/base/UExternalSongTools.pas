unit UExternalSongTools;

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

interface

uses USong;

procedure OpenExternalSongEditor(Song: TSong);

implementation

uses SysUtils, {$IFDEF MSWINDOWS}ProcessUnicode{$ELSE}Process{$ENDIF},
  UPath, UIni, ULanguage, UGraphic, ULibraryLockdown, ULog;

procedure Launch(const Executable: UTF8String; const Args: array of UTF8String);
var
  ProgramPath: IPath;
  Child: TProcess;
  Arg: UTF8String;
begin
  if LibraryLockdown.Active then Exit;
  try
    ProgramPath := Path(UTF8Decode(Executable));
    if not ProgramPath.IsAbsolute or not ProgramPath.IsFile then
      raise Exception.Create('Executable path is missing or invalid');

    Child := TProcess.Create(nil);
    try
      {$IFDEF MSWINDOWS}
      Child.Executable := ProgramPath.ToWide;
      Child.CurrentDirectory := ProgramPath.GetParent.ToWide;
      for Arg in Args do
        Child.Parameters.Add(UTF8Decode(Arg));
      {$ELSE}
      Child.Executable := ProgramPath.ToNative;
      Child.CurrentDirectory := ProgramPath.GetParent.ToNative;
      for Arg in Args do
        Child.Parameters.Add(Arg);
      {$ENDIF}
      Child.Execute;
    finally
      Child.Free;
    end;
  except
    on E: Exception do
    begin
      Log.LogError(E.Message, 'External song tools');
      ScreenPopupError.ShowPopup(Language.Translate('EXTERNAL_SONG_LAUNCH_ERROR'));
    end;
  end;
end;

procedure OpenExternalSongEditor(Song: TSong);
var
  Folder, SongFile: IPath;
begin
  if (Ini.ExternalSongEditor = 0) or LibraryLockdown.Active then Exit;
  Folder := Song.Path.GetAbsolutePath;
  SongFile := Folder.Append(Song.FileName);
  case Ini.ExternalSongEditor of
    1:
      begin
        // A trailing backslash can escape the closing quote on Windows.
        if Folder.RemovePathDelim.IsAbsolute then
          Folder := Folder.RemovePathDelim;
        Launch(Ini.ExternalSongEditorPath, [Folder.ToUTF8]);
      end;
    2: Launch(Ini.ExternalSongEditorPath, ['preview', SongFile.ToUTF8]);
    3: Launch(Ini.ExternalSongEditorPath, [SongFile.ToUTF8]);
  end;
end;

end.
