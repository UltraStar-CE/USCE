{* UltraStar Deluxe - Karaoke Game
 *
 * UltraStar Deluxe is the legal property of its developers, whose names
 * are too numerous to list here. Please refer to the COPYRIGHT
 * file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; see the file COPYING. If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/screens/UScreenSongMenu.pas $
 * $Id: UScreenSongMenu.pas 2071 2010-01-12 17:42:41Z s_alexander $
 *}

unit UScreenSongMenu;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UDocumentUI,
  UDisplay,
  UFiles,
  UIni,
  UMenu,
  UMusic,
  UThemes,
  sdl2,
  SysUtils;

type
  TSongMenuEntry = record
    Caption: UTF8String;
    Visible, Enabled: boolean;
    Options: array of UTF8String;
  end;
  TScreenSongMenu = class(TMenu)
    private
      MenuUI: TDocumentUI;
      MenuHeading: UTF8String;
      Entries: array[0..7] of TSongMenuEntry;
      procedure SyncDocument;
      procedure ApplyNativeState;
      procedure SetChoiceOptions(Index: integer; const Values: array of UTF8String; var Value: integer);
      function ChoiceValue(Index: integer): integer;
      procedure ChangeChoice(Index, Delta: integer);
      procedure StepFocus(Delta: integer);
      function DocumentInput(Key: cardinal; CharCode: UCS4Char; Down: boolean): boolean;
    private
      CurMenu: byte; // num of the cur. shown menu
      ID:       String; //for help-system
    public
      Visible: boolean; // whether the menu should be drawn

      constructor Create; override;
      destructor Destroy; override;
      procedure SetInteraction(Num: integer); override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      procedure OnShow; override;
      function Draw: boolean; override;
      procedure MenuShow(sMenu: byte);
      procedure HandleReturn;
      function CountMedleySongs: integer;
  end;

const
  SM_Main = 1;

  SM_PlayList         = 64 or 1;
  SM_Playlist_Add     = 64 or 2;
  SM_Playlist_New     = 64 or 3;

  SM_Playlist_DelItem = 64 or 5;
  SM_Playlist_DelVisibleItems = 64 or 32 or 1;
  SM_Playlist_Sort            = 64 or 32 or 2;

  SM_Playlist_Load    = 64 or 8 or 1;
  SM_Playlist_Del     = 64 or 8 or 5;

  SM_Party_Main       = 128 or 1;
  SM_Party_Joker      = 128 or 2;
  SM_Party_Free_Main  = 128 or 5;

  SM_Refresh_Scores   = 64 or 6;
  SM_Song             = 64 or 8;
  SM_Medley           = 64 or 16;

var
  ISelections1: array of UTF8String;
  SelectValue1: integer;

  ISelections2: array of UTF8String;
  SelectValue2: integer;

  ISelections3: array of UTF8String;
  SelectValue3: integer;
  PlaylistAddVisible: boolean;

implementation

uses
  Math,
  UDatabase,
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UMain,
  UNote,
  UParty,
  UPlaylist,
  URenderer,
  USong,
  USongs,
  UUnicodeUtils;

destructor TScreenSongMenu.Destroy;
begin MenuUI.Free; inherited; end;

procedure TScreenSongMenu.SetInteraction(Num: integer);
begin
  if MenuUI <> nil then SelInteraction := Num else inherited SetInteraction(Num);
end;

procedure TScreenSongMenu.SetChoiceOptions(Index: integer; const Values: array of UTF8String; var Value: integer);
var I: integer;
begin
  SetLength(Entries[Index + 3].Options, Length(Values));
  for I := 0 to High(Values) do Entries[Index + 3].Options[I] := Values[I];
  if Length(Values) = 0 then Value := 0
  else Value := EnsureRange(Value, 0, High(Values));
end;

function TScreenSongMenu.ChoiceValue(Index: integer): integer;
begin
  case Index of 3: Result := SelectValue1; 4: Result := SelectValue2; else Result := SelectValue3; end;
end;

procedure TScreenSongMenu.ChangeChoice(Index, Delta: integer);
var Value: integer;
begin
  if (Index < 3) or (Index > 5) or not Entries[Index].Visible or not Entries[Index].Enabled then Exit;
  Value := ChoiceValue(Index);
  if Length(Entries[Index].Options) > 0 then Value := EnsureRange(Value + Delta, 0, High(Entries[Index].Options));
  case Index of 3: SelectValue1 := Value; 4: SelectValue2 := Value; 5: SelectValue3 := Value; end;
  SyncDocument;
end;

procedure TScreenSongMenu.StepFocus(Delta: integer);
var I, Next: integer;
begin
  Next := Interaction;
  if (Delta = 0) and (Next >= 0) and (Next <= High(Entries)) and
     Entries[Next].Visible and Entries[Next].Enabled then Exit;
  if Delta = 0 then Delta := 1;
  for I := 0 to High(Entries) do
  begin
    Next := (Next + Delta + Length(Entries)) mod Length(Entries);
    if Entries[Next].Visible and Entries[Next].Enabled then
    begin
      Interaction := Next; SetTextInput((CurMenu = SM_Playlist_New) and (Next = 1)); Exit;
    end;
  end;
end;

procedure TScreenSongMenu.ApplyNativeState;
const ButtonEntry: array[0..4] of integer = (0, 1, 2, 6, 7);
var I, Index: integer;
begin
  Text[0].Text := MenuHeading;
  for I := 0 to High(ButtonEntry) do
  begin
    Index := ButtonEntry[I];
    Button[I].Visible := Entries[Index].Visible;
    Button[I].Selectable := Entries[Index].Enabled;
    Button[I].Text[0].Text := Entries[Index].Caption;
  end;
  for I := 0 to 2 do SelectsS[I].Visible := Entries[I + 3].Visible;
  UpdateSelectSlideOptions(0, Entries[3].Options, SelectValue1);
  UpdateSelectSlideOptions(1, Entries[4].Options, SelectValue2);
  UpdateSelectSlideOptions(2, Entries[5].Options, SelectValue3);
end;

procedure TScreenSongMenu.SyncDocument;
var I, Count, Slot, Value: integer; Prefix, Kind, Caption: UTF8String;
begin
  if MenuUI = nil then Exit;
  MenuUI.SetModel('songMenu.heading', MenuHeading);
  Count := 0;
  for I := 0 to High(Entries) do if Entries[I].Visible then Inc(Count);
  MenuUI.SetArray('songMenu.entries', Count); Count := 0;
  for I := 0 to High(Entries) do
    if Entries[I].Visible then
    begin
      Prefix := 'songMenu.entries[' + IntToStr(Count) + '].';
      if I < 3 then Slot := I else Slot := I - 3;
      Kind := 'action'; Caption := Entries[I].Caption;
      if (I >= 3) and (I <= 5) then
      begin
        Kind := 'choice'; Value := ChoiceValue(I);
        if (Value >= 0) and (Value < Length(Entries[I].Options)) then Caption := Entries[I].Options[Value];
        MenuUI.SetModel(Prefix + 'previous', IntToStr(Ord(Value > 0)), 2);
        MenuUI.SetModel(Prefix + 'next', IntToStr(Ord(Value < High(Entries[I].Options))), 2);
      end;
      if (CurMenu = SM_Playlist_New) and (I = 1) then Kind := 'name';
      MenuUI.SetModel(Prefix + 'id', IntToStr(I), 1);
      MenuUI.SetModel(Prefix + 'slot', IntToStr(Slot), 1);
      MenuUI.SetModel(Prefix + 'kind', Kind);
      MenuUI.SetModel(Prefix + 'caption', Caption);
      MenuUI.SetModel(Prefix + 'enabled', IntToStr(Ord(Entries[I].Enabled)), 2);
      MenuUI.SetModel(Prefix + 'selected', IntToStr(Ord(I = Interaction)), 2);
      Inc(Count);
    end;
  if (Interaction >= 3) and (Interaction <= 5) then MenuUI.Focus('song-menu-choice-' + IntToStr(Interaction))
  else MenuUI.Focus('song-menu-entry-' + IntToStr(Interaction));
end;

function TScreenSongMenu.DocumentInput(Key: cardinal; CharCode: UCS4Char; Down: boolean): boolean;
var Modifiers: word;
begin
  Result := true;
  if not Down then Exit;
  if (CurMenu = SM_Playlist_New) and (Interaction = 1) then
  begin
    if IsAlphaNumericChar(CharCode) or (CharCode in [32, 45, 95, 33, 44, 60, 47, 42, 63, 39, 34]) then
    begin Entries[1].Caption := Entries[1].Caption + UCS4ToUTF8String(CharCode); SyncDocument; Exit; end;
    if Key = SDLK_BACKSPACE then
    begin
      if LengthUTF8(Entries[1].Caption) > 0 then UTF8Delete(Entries[1].Caption, LengthUTF8(Entries[1].Caption), 1);
      SyncDocument; Exit;
    end;
  end
  else if Key = SDLK_Q then Exit(false);
  Modifiers := SDL_GetModState and (KMOD_LSHIFT + KMOD_RSHIFT + KMOD_LCTRL + KMOD_RCTRL + KMOD_LALT + KMOD_RALT);
  case Key of
    SDLK_ESCAPE, SDLK_BACKSPACE: begin StopTextInput; AudioPlayback.PlaySound(SoundLib.Back); Visible := false; end;
    SDLK_TAB: begin Help.SetHelpID(ID); ScreenPopupHelp.ShowPopup; end;
    SDLK_RETURN: begin StopTextInput; if Entries[Interaction].Enabled then HandleReturn; end;
    SDLK_DOWN: StepFocus(1);
    SDLK_UP: StepFocus(-1);
    SDLK_LEFT: ChangeChoice(Interaction, -1);
    SDLK_RIGHT: ChangeChoice(Interaction, 1);
    SDLK_1: if CurMenu = SM_Party_Main then ScreenSong.DoJoker(0, Modifiers);
    SDLK_2: if CurMenu = SM_Party_Main then ScreenSong.DoJoker(1, Modifiers);
    SDLK_3: if CurMenu = SM_Party_Main then ScreenSong.DoJoker(2, Modifiers);
  end;
  if Visible then SyncDocument;
end;

function TScreenSongMenu.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var Action: UTF8String; Target: integer;
begin
  if MenuUI = nil then Exit(inherited ParseMouse(MouseButton, BtnDown, X, Y));
  Result := true;
  if BtnDown and RightMbESC and (MouseButton = SDL_BUTTON_RIGHT) then
    Exit(DocumentInput(SDLK_ESCAPE, 0, true));
  if MouseButton = SDL_BUTTON_LEFT then MenuUI.Mouse(X, Y, 0, BtnDown)
  else MenuUI.Mouse(X, Y);
  if TryStrToInt(MenuUI.FocusedTarget, Target) and (Target >= 0) and (Target <= High(Entries)) and
     Entries[Target].Enabled and Entries[Target].Visible then
  begin Interaction := Target; SetTextInput((CurMenu = SM_Playlist_New) and (Target = 1)); end;
  Action := MenuUI.TakeAction;
  Target := StrToIntDef(MenuUI.ActionTarget, -1);
  if (Target >= 0) and (Target <= High(Entries)) and Entries[Target].Enabled and Entries[Target].Visible then
  begin
    Interaction := Target;
    if Action = 'song-menu.previous' then ChangeChoice(Target, -1)
    else if Action = 'song-menu.next' then ChangeChoice(Target, 1)
    else if (Action = 'song-menu.activate') and not ((CurMenu = SM_Playlist_New) and (Target = 1)) then
    begin StopTextInput; HandleReturn; end;
  end;
  if Visible then SyncDocument;
end;

function TScreenSongMenu.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
var
  SDL_ModState:  Word;

begin
  if MenuUI <> nil then Exit(DocumentInput(PressedKey, CharCode, PressedDown));
  Result := true;
  if (PressedDown) then
  begin // key down
    if (CurMenu = SM_Playlist_New) and (Interaction=1) then
    begin
      // check normal keys
      if IsAlphaNumericChar(CharCode) or
         (CharCode in [Ord(' '), Ord('-'), Ord('_'), Ord('!'),
                       Ord(','), Ord('<'), Ord('/'), Ord('*'),
                       Ord('?'), Ord(''''), Ord('"')]) then
      begin
        Button[Interaction].Text[0].Text := Button[Interaction].Text[0].Text +
                                            UCS4ToUTF8String(CharCode);
        exit;
      end;

      // check special keys
      case PressedKey of
        SDLK_BACKSPACE:
          begin
            Button[Interaction].Text[0].DeleteLastLetter;
            exit;
          end;
      end;
    end;

    // check normal keys unless a text field is actively selected
    if not ((CurMenu = SM_Playlist_New) and Button[1].Selected) then
    begin
      case PressedKey of
        SDLK_Q:
          begin
            Result := false;
            Exit;
          end;
      end;
    end;

    SDL_ModState := SDL_GetModState and (KMOD_LSHIFT + KMOD_RSHIFT
    + KMOD_LCTRL + KMOD_RCTRL + KMOD_LALT  + KMOD_RALT);

    // check special keys
    case PressedKey of
      SDLK_ESCAPE,
      SDLK_BACKSPACE:
        begin
          StopTextInput;
          AudioPlayback.PlaySound(SoundLib.Back);
          Visible := false;
        end;

      SDLK_TAB:
        begin
          Help.SetHelpID(ID);
          ScreenPopupHelp.ShowPopup();
        end;

      SDLK_RETURN:
        begin
          StopTextInput;
          HandleReturn;
        end;

      SDLK_DOWN:
        begin
          InteractNext;
          SetTextInput((CurMenu = SM_Playlist_New) and (Button[1].Selected));
        end;

      SDLK_UP:
        begin
          InteractPrev;
          SetTextInput((CurMenu = SM_Playlist_New) and (Button[1].Selected));
        end;

      SDLK_RIGHT:
        begin
          if (Interaction=3) or (Interaction=4) or (Interaction=5)
            or (Interaction=8) or (Interaction=9) or (Interaction=10) then
              InteractInc;
        end;
      SDLK_LEFT:
        begin
          if (Interaction=3) or (Interaction=4) or (Interaction=5)
            or (Interaction=8) or (Interaction=9) or (Interaction=10) then
              InteractDec;
        end;

      SDLK_1:
        begin // joker
            // use joker
          case CurMenu of
            SM_Party_Main:
            begin
              ScreenSong.DoJoker(0, SDL_ModState)
            end;
          end;
        end;
      SDLK_2:
        begin // joker
            // use joker
          case CurMenu of
            SM_Party_Main:
            begin
              ScreenSong.DoJoker(1, SDL_ModState)
            end;
          end;
        end;
      SDLK_3:
        begin // joker
            // use joker
          case CurMenu of
            SM_Party_Main:
            begin
              ScreenSong.DoJoker(2, SDL_ModState)
            end;
          end;
        end;
    end; // case
  end; // if
end;

constructor TScreenSongMenu.Create;
var I: integer;
begin
  inherited Create;

  // create dummy selectslide entrys
  SetLength(ISelections1, 1);
  ISelections1[0] := 'Dummy';

  SetLength(ISelections2, 1);
  ISelections2[0] := 'Dummy';

  SetLength(ISelections3, 1);
  ISelections3[0] := 'Dummy';

  for I := 0 to High(Entries) do
  begin Entries[I].Visible := true; Entries[I].Enabled := true; end;
  Entries[7].Caption := Language.Translate('SONG_MENU_CANCEL');
  SetChoiceOptions(0, ISelections1, SelectValue1);
  SetChoiceOptions(1, ISelections2, SelectValue2);
  SetChoiceOptions(2, ISelections3, SelectValue3);
  MenuUI := TDocumentUI.Open('song-menu');
  if MenuUI <> nil then begin SelInteraction := 0; Exit; end;

  AddText(Theme.SongMenu.TextMenu);

  LoadFromTheme(Theme.SongMenu);

  AddButton(Theme.SongMenu.Button1);
  if (Length(Button[0].Text) = 0) then
    AddButtonText(14, 20, 'Button 1');

  AddButton(Theme.SongMenu.Button2);
  if (Length(Button[1].Text) = 0) then
    AddButtonText(14, 20, 'Button 2');

  AddButton(Theme.SongMenu.Button3);
  if (Length(Button[2].Text) = 0) then
    AddButtonText(14, 20, 'Button 3');

  AddSelectSlide(Theme.SongMenu.SelectSlide1, SelectValue1, ISelections1);
  AddSelectSlide(Theme.SongMenu.SelectSlide2, SelectValue2, ISelections2);
  AddSelectSlide(Theme.SongMenu.SelectSlide3, SelectValue3, ISelections3);

  AddButton(Theme.SongMenu.Button4);
  if (Length(Button[3].Text) = 0) then
    AddButtonText(14, 20, 'Button 4');

  AddButton(Theme.SongMenu.Button5);
  if (Length(Button[4].Text) = 0) then
    AddButtonText(14, 20, 'Button 5');

  Interaction := 0;
end;

function TScreenSongMenu.Draw: boolean;
begin
  if MenuUI <> nil then begin SyncDocument; Exit(MenuUI.Draw(false, true)); end;
  Renderer.ClearFrameBuffer(CLEAR_DEPTH);
  Result := inherited Draw;
end;

procedure TScreenSongMenu.OnShow;
begin
  if MenuUI = nil then inherited;
end;

function TScreenSongMenu.CountMedleySongs: integer;
var
  Count, I: integer;
begin

  Count := 0;

  for I:= 0 to High(CatSongs.Song) do
  begin

    if (CatSongs.Song[I].Visible) and not CatSongs.Song[I].Main then
      Count := Count + 1;

    if (Count = 5) then
      break;

  end;

  Result := Count;
end;

procedure TScreenSongMenu.MenuShow(sMenu: byte);
var
  I, MSongs: integer;
begin
  Interaction := 0; // reset interaction
  Visible := true;  // set visible
  case sMenu of
    SM_Main:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;

        MenuHeading := Language.Translate('SONG_MENU_NAME_MAIN');

        Entries[0].Visible := true;
        Entries[1].Visible := (Length(PlaylistMedley.Song) > 0) or
          not CatSongs.Song[ScreenSong.Interaction].Main;
        Entries[2].Visible := (CatSongs.CatNumShow = -2);
        Entries[6].Visible := true;
        Entries[7].Visible := (ScreenSong.Mode = smNormal) and not Party.bPartyGame;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := false;

        Entries[0].Caption := Language.Translate('SONG_MENU_SONG');
        Entries[1].Caption := Language.Translate('SONG_MENU_MEDLEY');
        Entries[2].Caption := Language.Translate('SONG_MENU_PLAYLIST_ADD_SHOWN');
        Entries[6].Caption := Language.Translate('SONG_MENU_REFRESH_SCORES');
        Entries[7].Caption := Language.Translate('CONTINUOUS_TITLE');
      end;
    SM_Song:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_NAME_SONG');

        Entries[0].Visible := true;
        Entries[1].Visible := true;
        Entries[2].Visible := true;
        Entries[6].Visible := true;
        Entries[7].Visible := true;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := false;

        Entries[0].Caption := Language.Translate('SONG_MENU_PLAY');
        Entries[1].Caption := Language.Translate('SONG_MENU_CHANGEPLAYERS');
        Entries[2].Caption := Language.Translate('SONG_MENU_PLAYLIST_ADD');
        Entries[6].Caption := Language.Translate('SONG_MENU_EDIT');
        Entries[7].Caption := Language.Translate('SONG_MENU_CANCEL');
      end;

    SM_Medley:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;
        MSongs := CountMedleySongs;

        MenuHeading := Language.Translate('SONG_MENU_NAME_MEDLEY');

        Entries[0].Visible := not CatSongs.Song[ScreenSong.Interaction].Main;
        Entries[1].Visible := (Length(PlaylistMedley.Song)>0);
        Entries[2].Visible := (Length(PlaylistMedley.Song)>0) or
          not CatSongs.Song[ScreenSong.Interaction].Main;
        Entries[6].Visible := (not ScreenSong.MakeMedley) and (MSongs > 1);
        Entries[7].Visible := true;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := false;

        Entries[0].Caption := Language.Translate('SONG_MENU_ADD_SONG');
        Entries[1].Caption := Language.Translate('SONG_MENU_DELETE_SONG');
        Entries[2].Caption := Language.Translate('SONG_MENU_START_MEDLEY');
        Entries[6].Caption := Format(Language.Translate('SONG_MENU_START_5_MEDLEY'), [MSongs]);
        Entries[7].Caption := Language.Translate('SONG_MENU_CANCEL');
      end;

    SM_PlayList:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_NAME_PLAYLIST');

        Entries[0].Visible := true;
        Entries[1].Visible := true;
        Entries[2].Visible := true;
        Entries[6].Visible := true;
        Entries[7].Visible := true;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := false;

        Entries[0].Caption := Language.Translate('SONG_MENU_PLAY');
        Entries[1].Caption := Language.Translate('SONG_MENU_CHANGEPLAYERS');
        Entries[2].Caption := Language.Translate('SONG_MENU_PLAYLIST_DEL');
        Entries[6].Caption := Language.Translate('SONG_MENU_PLAYLIST_SORT');
        Entries[7].Caption := Language.Translate('SONG_MENU_PLAYLIST_DEL_SHOWN');
      end;

    SM_Playlist_Add:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;
        if PlaylistAddVisible then
          MenuHeading := Language.Translate('SONG_MENU_NAME_PLAYLIST_ADD_SHOWN')
        else
          MenuHeading := Language.Translate('SONG_MENU_NAME_PLAYLIST_ADD');

        Entries[0].Visible := true;
        Entries[1].Visible := false;
        Entries[2].Visible := false;
        Entries[6].Visible := true;
        Entries[7].Visible := true;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := true;

        Entries[0].Caption := Language.Translate('SONG_MENU_PLAYLIST_ADD_NEW');
        Entries[6].Caption := Language.Translate('SONG_MENU_PLAYLIST_ADD_EXISTING');
        Entries[7].Caption := Language.Translate('SONG_MENU_CANCEL');

        SetLength(ISelections3, Length(PlaylistMan.Playlists));
        PlaylistMan.GetNames(ISelections3);

        if (Length(ISelections3)>=1) then
        begin
          SetChoiceOptions(2, ISelections3, SelectValue3);
        end
        else
        begin
          Entries[6].Visible := false;
          Entries[3].Visible := false;
          Entries[4].Visible := false;
          Entries[5].Visible := false;
          Entries[2].Visible := true;
          Entries[2].Caption := Language.Translate('SONG_MENU_PLAYLIST_NOEXISTING');
        end;
      end;

    SM_Playlist_New:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_NAME_PLAYLIST_NEW');

        Entries[0].Visible := false;
        Entries[1].Visible := true;
        Entries[2].Visible := false;
        Entries[6].Visible := true;
        Entries[7].Visible := true;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := false;

        Entries[1].Caption := Language.Translate('SONG_MENU_PLAYLIST_NEW_UNNAMED');
        Entries[6].Caption := Language.Translate('SONG_MENU_PLAYLIST_NEW_CREATE');
        Entries[7].Caption := Language.Translate('SONG_MENU_CANCEL');

        Interaction := 1;
        // button 1 = a text field and pre-selected
        // it's necessary to start text input manually because it doesn't get here by Up/Down keypresses
        StartTextInput;
      end;

    SM_Playlist_DelItem:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_NAME_PLAYLIST_DELITEM');

        Entries[0].Visible := true;
        Entries[1].Visible := false;
        Entries[2].Visible := false;
        Entries[6].Visible := true;
        Entries[7].Visible := false;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := false;

        Entries[0].Caption := Language.Translate('SONG_MENU_YES');
        Entries[6].Caption := Language.Translate('SONG_MENU_CANCEL');
      end;

    SM_Playlist_DelVisibleItems:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_NAME_PLAYLIST_DEL_SHOWN');

        Entries[0].Visible := true;
        Entries[1].Visible := false;
        Entries[2].Visible := false;
        Entries[6].Visible := true;
        Entries[7].Visible := false;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := false;

        Entries[0].Caption := Language.Translate('SONG_MENU_YES');
        Entries[6].Caption := Language.Translate('SONG_MENU_CANCEL');
      end;

    SM_Playlist_Sort:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_NAME_PLAYLIST_SORT');

        Entries[0].Visible := false;
        Entries[1].Visible := false;
        Entries[2].Visible := false;
        Entries[6].Visible := true;
        Entries[7].Visible := true;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := true;

        Entries[6].Caption := Language.Translate('SONG_MENU_PLAYLIST_SORT');
        Entries[7].Caption := Language.Translate('SONG_MENU_CANCEL');

        SetLength(ISelections3, 6);
        ISelections3[0] := Language.Translate('OPTION_VALUE_ARTIST');
        ISelections3[1] := Language.Translate('OPTION_VALUE_TITLE');
        ISelections3[2] := Language.Translate('OPTION_VALUE_EDITION');
        ISelections3[3] := Language.Translate('OPTION_VALUE_GENRE');
        ISelections3[4] := Language.Translate('OPTION_VALUE_LANGUAGE');
        ISelections3[5] := Language.Translate('OPTION_VALUE_RANDOM');
        SelectValue3 := 0;
        SetChoiceOptions(2, ISelections3, SelectValue3);
        Interaction := 4;
      end;

    SM_Playlist_Load:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_NAME_PLAYLIST_LOAD');

        // show delete curent playlist button when playlist is opened
        Entries[0].Visible := (CatSongs.CatNumShow = -3);

        Entries[1].Visible := false;
        Entries[2].Visible := false;
        Entries[6].Visible := true;
        Entries[7].Visible := false;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := true;

        Entries[0].Caption := Language.Translate('SONG_MENU_PLAYLIST_DELCURRENT');
        Entries[6].Caption := Language.Translate('SONG_MENU_PLAYLIST_LOAD');

        SetLength(ISelections3, Length(PlaylistMan.Playlists));
        PlaylistMan.GetNames(ISelections3);

        if (Length(ISelections3)>=1) then
        begin
          SetChoiceOptions(2, ISelections3, SelectValue3);
          Interaction := 3;
        end
        else
        begin
          Entries[6].Visible := false;
          Entries[3].Visible := false;
          Entries[4].Visible := false;
          Entries[5].Visible := false;
          Entries[2].Visible := true;
          Entries[2].Caption := Language.Translate('SONG_MENU_PLAYLIST_NOEXISTING');
          Interaction := 2;
        end;
      end;

    SM_Playlist_Del:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_NAME_PLAYLIST_DEL');

        Entries[0].Visible := true;
        Entries[1].Visible := false;
        Entries[2].Visible := false;
        Entries[6].Visible := true;
        Entries[7].Visible := false;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := false;

        Entries[0].Caption := Language.Translate('SONG_MENU_YES');
        Entries[6].Caption := Language.Translate('SONG_MENU_CANCEL');
      end;

    SM_Party_Main:
      begin
        ID := 'ID_018';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_NAME_PARTY_MAIN');

        Entries[0].Visible := true;
        Entries[1].Visible := false;
        Entries[2].Visible := false;
        Entries[6].Visible := true;
        Entries[7].Visible := false;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := false;

        Entries[0].Caption := Language.Translate('SONG_MENU_PLAY');
        //Entries[1].Caption := Language.Translate('SONG_MENU_JOKER');
        //Entries[2].Caption := Language.Translate('SONG_MENU_PLAYMODI');
        Entries[6].Caption := Language.Translate('SONG_MENU_JOKER');
      end;

    SM_Party_Joker:
      begin
        ID := 'ID_018';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_NAME_PARTY_JOKER');
        // to-do : Party
        Entries[0].Visible := (Length(Party.Teams) >= 1) AND (Party.Teams[0].JokersLeft > 0);
        Entries[1].Visible := (Length(Party.Teams) >= 2) AND (Party.Teams[1].JokersLeft > 0);
        Entries[2].Visible := (Length(Party.Teams) >= 3) AND (Party.Teams[2].JokersLeft > 0);
        Entries[6].Visible := True;
        Entries[7].Visible := false;

        Entries[3].Visible := False;
        Entries[4].Visible := False;
        Entries[5].Visible := False;

        if (Entries[0].Visible) then
          Entries[0].Caption := UTF8String(Party.Teams[0].Name);
        if (Entries[1].Visible) then
          Entries[1].Caption := UTF8String(Party.Teams[1].Name);
        if (Entries[2].Visible) then
          Entries[2].Caption := UTF8String(Party.Teams[2].Name);
        Entries[6].Caption := Language.Translate('SONG_MENU_CANCEL');

        // set right interaction
        if (not Entries[0].Visible) then
        begin
          if (not Entries[1].Visible) then
          begin
            if (not Entries[2].Visible) then
              Interaction := 4
            else
              Interaction := 2;
          end
          else
            Interaction := 1;
        end;

      end;

    SM_Refresh_Scores:
      begin
        ID := 'ID_019';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_REFRESH_SCORES_TITLE');

        Entries[0].Visible := false;
        Entries[1].Visible := false;
        Entries[2].Visible := false;
        Entries[6].Visible := false;
        Entries[7].Visible := true;

        Entries[3].Visible := true;
        Entries[4].Visible := true;
        Entries[5].Visible := true;

        Entries[7].Caption := Language.Translate('SONG_MENU_REFRESH_SCORES_REFRESH');

        if (High(DataBase.NetworkUser) > 0) then
          SetLength(ISelections3, Length(DataBase.NetworkUser) + 1)
        else
          SetLength(ISelections3, Length(DataBase.NetworkUser));

        if (Length(ISelections3) >= 1) then
        begin
          if (High(DataBase.NetworkUser) > 0) then
          begin
            ISelections3[0] := Language.Translate('SONG_MENU_REFRESH_SCORES_ALL_WEB');
            for I := 0 to High(DataBase.NetworkUser) do
              ISelections3[I + 1] := DataBase.NetworkUser[I].Website;
          end
          else
          begin
            for I := 0 to High(DataBase.NetworkUser) do
              ISelections3[I] := DataBase.NetworkUser[I].Website;
          end;

          SetChoiceOptions(0, [Language.Translate('SONG_MENU_REFRESH_SCORES_ONLINE'), Language.Translate('SONG_MENU_REFRESH_SCORES_FILE')], SelectValue1);
          SetChoiceOptions(1, [Language.Translate('SONG_MENU_REFRESH_SCORES_ONLY_SONG'), Language.Translate('SONG_MENU_REFRESH_SCORES_ALL_SONGS')], SelectValue2);
          SetChoiceOptions(2, ISelections3, SelectValue3);

          Interaction := 3;
        end
        else
        begin
          Entries[6].Visible := false;
          Entries[3].Visible := false;
          Entries[4].Visible := false;
          Entries[5].Visible := false;
          Entries[2].Visible := true;
          Entries[2].Caption := Language.Translate('SONG_MENU_REFRESH_SCORES_NO_WEB');
          Entries[2].Enabled := false;
          Entries[6].Caption := Theme.Options.Description[OPTIONS_DESC_INDEX_NETWORK];
          Interaction := 7;
        end;
      end;

    SM_Party_Free_Main:
      begin
        ID := 'ID_017';
        CurMenu := sMenu;
        MenuHeading := Language.Translate('SONG_MENU_NAME_PARTY_MAIN');

        Entries[0].Visible := true;
        Entries[1].Visible := false;
        Entries[2].Visible := false;
        Entries[6].Visible := false;

        Entries[3].Visible := false;
        Entries[4].Visible := false;
        Entries[5].Visible := false;

        Entries[0].Caption := Language.Translate('SONG_MENU_PLAY');
      end;
  end;
  if not Help.SetHelpID(ID) then
    Log.LogWarn('No Entry for Help-ID ' + ID, 'ScreenSongMenu');
  if MenuUI <> nil then
  begin
    if not Entries[Interaction].Visible or not Entries[Interaction].Enabled then StepFocus(0);
    SyncDocument;
  end
  else ApplyNativeState;
end;

procedure TScreenSongMenu.HandleReturn;
var
  I: integer;
  SDL_ModState:  Word;
begin
  if MenuUI = nil then Entries[1].Caption := Button[1].Text[0].Text;
  SDL_ModState := SDL_GetModState and (KMOD_LSHIFT + KMOD_RSHIFT
    + KMOD_LCTRL + KMOD_RCTRL + KMOD_LALT  + KMOD_RALT);
  case CurMenu of
    SM_Main:
      begin
        case Interaction of
          0: // button 1
            begin
              MenuShow(SM_Song);
            end;

          1: // button 2
            begin
              MenuShow(SM_Medley);
            end;

          2: // button 3
            begin
              PlaylistAddVisible := true;
              MenuShow(SM_Playlist_Add);
            end;

          3: // selectslide 1
            begin
              //Dummy
            end;

          4: // selectslide 2
            begin
              //Dummy
            end;

          5: // selectslide 3
            begin
              //Dummy
            end;

          7: // continuous playback
            begin
              Visible := false;
              ScreenSong.OpenContinuousPlayback;
            end;
          6: // button 4
            begin
              // show refresh scores menu
              MenuShow(SM_Refresh_Scores);
              ScreenSong.StopMusicPreview();
              ScreenSong.StopVideoPreview();
            end;
          end;
      end;

      SM_Song:
      begin
        case Interaction of
          0: // button 1
            begin

              //if (CatSongs.Song[ScreenSong.Interaction].isDuet and ((PlayersPlay=1) or
              //   (PlayersPlay=3) or (PlayersPlay=6))) then
              //  ScreenPopupError.ShowPopup(Language.Translate('SING_ERROR_DUET_NUM_PLAYERS'))
              //else
              //begin
                ScreenSong.StartSong;
                Visible := false;
              //end;
            end;

          1: // button 2
            begin
              // select new players then sing:
              ScreenSong.SelectPlayers;
              Visible := false;
            end;

          2: // button 3
            begin
              // show add to playlist menu
              PlaylistAddVisible := false;
              MenuShow(SM_Playlist_Add);
            end;

          3: // selectslide 1
            begin
              //Dummy
            end;

          4: // selectslide 2
            begin
              //Dummy
            end;

          5: // selectslide 3
            begin
              //Dummy
            end;

          6: // button 4
            begin
              ScreenSong.OpenEditor;
              Visible := false;
            end;

          7: // button 5
            begin
              // show main menu
              MenuShow(SM_Main);
            end;
          end;
      end;

    SM_Medley:
      begin
        Case Interaction of
          0: //Button 1
            begin
              ScreenSong.MakeMedley := true;
              ScreenSong.StartMedley(99);

              Visible := False;
            end;

          1: //Button 2
            begin
              SetLength(PlaylistMedley.Song, Length(PlaylistMedley.Song)-1);
              PlaylistMedley.NumMedleySongs := Length(PlaylistMedley.Song);

              if Length(PlaylistMedley.Song)=0 then
                ScreenSong.MakeMedley := false;

              Visible := False;
            end;

          2: //Button 3
            begin

              if ScreenSong.MakeMedley then
              begin
                ScreenSong.Mode := smMedley;
                PlaylistMedley.CurrentMedleySong := 0;

                //Do the Action that is specified in Ini
                case Ini.OnSongClick of
                  0: FadeTo(@ScreenSing);
                  1: ScreenSong.SelectPlayers;
                  2: FadeTo(@ScreenSing);
                end;
              end
              else
                ScreenSong.StartMedley(0);

              Visible := False;

            end;

          6: //Button 4
            begin
              ScreenSong.StartMedley(5);
              Visible := False;
            end;

          7: // button 5
            begin
              // show main menu
              MenuShow(SM_Main);
            end;
        end;
      end;

    SM_PlayList:
      begin
        Visible := false;
        case Interaction of
          0: // button 1
            begin
              ScreenSong.StartSong;
              Visible := false;
            end;

          1: // button 2
            begin
              // select new players then sing:
              ScreenSong.SelectPlayers;
              Visible := false;
            end;

          2: // button 3
            begin
              // show add to playlist menu
              MenuShow(SM_Playlist_DelItem);
            end;

          3: // selectslide 1
            begin
              // dummy
            end;

          4: // selectslide 2
            begin
              // dummy
            end;

          5: // selectslide 3
            begin
              // dummy
            end;

          6: // button 4
            begin
              MenuShow(SM_Playlist_Sort);
            end;

          7: // button 5
            begin
              MenuShow(SM_Playlist_DelVisibleItems);
            end;
        end;
      end;

    SM_Playlist_Add:
      begin
        case Interaction of
          0: // button 1
            begin
              MenuShow(SM_Playlist_New);
            end;

          4: // selectslide 3
            begin
              // dummy
            end;

          6: // button 4
            begin
              if PlaylistAddVisible then
              begin
                if PlaylistMan.AddVisibleItems(SelectValue3) = 0 then
                  ScreenPopupInfo.ShowPopup(Language.Translate('SONG_MENU_PLAYLIST_NO_NEW_SONGS'));
              end
              else
              begin
                if not PlaylistMan.AddItem(ScreenSong.Interaction, SelectValue3) then
                  ScreenPopupInfo.ShowPopup(Language.Translate('SONG_MENU_PLAYLIST_ALREADY_EXISTS'));
              end;
              Visible := false;
            end;

          7: // button 5
            begin
              // show song menu
              MenuShow(SM_Song);
            end;
        end;
      end;

      SM_Playlist_New:
      begin
        case Interaction of
          1: // button 1
            begin
              // nothing, button for entering name
            end;

          6: // button 4
            begin
              if PlaylistAddVisible then
              begin
                if PlaylistMan.AddVisibleItems(PlaylistMan.AddPlaylist(Entries[1].Caption)) = 0 then
                  ScreenPopupInfo.ShowPopup(Language.Translate('SONG_MENU_PLAYLIST_NO_NEW_SONGS'));
              end
              else
              begin
                // create playlist and add song
                if not PlaylistMan.AddItem(
                  ScreenSong.Interaction,
                  PlaylistMan.AddPlaylist(Entries[1].Caption)) then
                  ScreenPopupInfo.ShowPopup(Language.Translate('SONG_MENU_PLAYLIST_ALREADY_EXISTS'));
              end;
              Visible := false;
            end;

          7: // button 5
            begin
              // show add song menu
              MenuShow(SM_Playlist_Add);
            end;

        end;
      end;

    SM_Playlist_DelItem:
      begin
        Visible := false;
        case Interaction of
          0: // button 1
            begin
              // delete
              PlayListMan.DelItem(PlayListMan.GetIndexbySongID(ScreenSong.Interaction));
              Visible := false;
            end;

          6: // button 4
            begin
              MenuShow(SM_Playlist);
            end;
        end;
      end;

    SM_Playlist_DelVisibleItems:
      begin
        Visible := false;
        case Interaction of
          0: // button 1
            begin
              PlayListMan.DelVisibleItems;
              Visible := false;
            end;

          6: // button 4
            begin
              MenuShow(SM_Playlist);
            end;
        end;
      end;

    SM_Playlist_Sort:
      begin
        case Interaction of
          4: // selectslide 3
            begin
              // dummy
            end;

          6: // button 4
            begin
              PlaylistMan.SortPlaylist(TPlaylistSortOrder(SelectValue3));
              Visible := false;
              ScreenSong.SetScrollRefresh;
            end;

          7: // button 5
            begin
              MenuShow(SM_Playlist);
            end;
        end;
      end;

    SM_Playlist_Load:
      begin
        case Interaction of
          0: // button 1 (Delete playlist)
            begin
              MenuShow(SM_Playlist_Del);
            end;
          6: // button 4
            begin
              // load playlist
              PlaylistMan.ReloadPlaylist(SelectValue3);
              PlaylistMan.SetPlayList(SelectValue3);
              Visible := false;
              ScreenSong.SetScrollRefresh;
            end;
        end;
      end;

    SM_Playlist_Del:
      begin
        Visible := false;
        case Interaction of
          0: // button 1
            begin
              // delete
              PlayListMan.DelPlaylist(PlaylistMan.CurPlayList);
              Visible := false;
            end;

          6: // button 4
            begin
              MenuShow(SM_Playlist_Load);
            end;
        end;
      end;

    SM_Party_Main:
      begin
        case Interaction of
          0: // button 1
            begin
              // start singing
              Party.CallAfterSongSelect;
              Visible := false;
            end;

          6: // button 4
            begin
              // joker
              MenuShow(SM_Party_Joker);
            end;
        end;
      end;

    SM_Party_Free_Main:
    begin
      case Interaction of
        0: // button 1
          begin
            // start singing
            Party.CallAfterSongSelect;
            Visible := false;
          end;
      end;
    end;

    SM_Party_Joker:
      begin
        Visible := false;
        case Interaction of
          0: // button 1
            begin
              // joker team 1
              ScreenSong.DoJoker(0, SDL_ModState);
            end;

          1: // button 2
            begin
              // joker team 2
              ScreenSong.DoJoker(1, SDL_ModState);
            end;

          2: // button 3
            begin
              // joker team 3
              ScreenSong.DoJoker(2, SDL_ModState);
            end;

          6: // button 4
            begin
              // cancel... (go back to old menu)
              MenuShow(SM_Party_Main);
            end;
        end;
      end;

    SM_Refresh_Scores:
      begin
        case Interaction of
          7: // button 5
            begin
              if (Length(ISelections3)>=1) then
              begin
                // Refresh Scores
                Visible := false;
                ScreenPopupScoreDownload.ShowPopup(SelectValue1, SelectValue2, SelectValue3);
              end
              else
              begin
                Entries[2].Enabled := true;
                MenuShow(SM_Main);
              end;
            end;
        end;
      end;

  end;
end;

end.
