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
 * $URL: https://ultrastardx.svn.sourceforge.net/svnroot/ultrastardx/trunk/src/screens/UScreenPartyWin.pas $
 * $Id: UScreenPartyWin.pas 2246 2010-04-18 13:43:36Z tobigun $
 *}

unit UScreenPartyTournamentWin;

interface

{$IFDEF FPC}
  {$MODE Delphi}
{$ENDIF}

{$I switches.inc}

uses
  UCommon,
  UDisplay,
  UDocumentUI,
  UIni,
  UMenu,
  UMusic,
  UThemes,
  sdl2,
  SysUtils;

type
  TScreenPartyTournamentWin = class(TMenu)
    private
      DocumentUI: TDocumentUI;
      MatchScores: array[0..1] of integer;
      procedure SetDocumentResults;
    public
      TextScorePlayer1:    cardinal;
      TextScorePlayer2:    cardinal;

      TextNamePlayer1:     cardinal;
      TextNamePlayer2:     cardinal;

      StaticBGPlayer1:     cardinal;
      StaticBGPlayer2:     cardinal;

      constructor Create; override;
      destructor Destroy; override;
      function DrawBG: boolean; override;
      function DrawFG: boolean; override;
      function ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean; override;
      function ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean; override;
      procedure OnShow; override;
      procedure UpdateRounds;
  end;

const
  ID='ID_039';   //for help system
  uiTournamentWinRole = 'tournament-win';
  uiTournamentWinData = 'tournamentWin';
  uiTournamentWinContinue = 'tournament.win.continue';

implementation

uses
  UGraphic,
  UHelp,
  ULanguage,
  ULog,
  UMain,
  UNote,
  UPartyTournament,
  UScreenPartyTournamentRounds,
  UUnicodeUtils,
  Math;

procedure TScreenPartyTournamentWin.SetDocumentResults;
var I: integer; Prefix: UTF8String; Col: TRGB;
begin
  DocumentUI.SetArray(uiTournamentWinData + '.players', 2);
  for I := 0 to 1 do
  begin
    Prefix := uiTournamentWinData + '.players[' + IntToStr(I) + '].';
    DocumentUI.SetModel(Prefix + 'id', IntToStr(I), 1);
    if I = 0 then DocumentUI.SetModel(Prefix + 'name', PartyTournament.Next.NamePlayer1)
    else DocumentUI.SetModel(Prefix + 'name', PartyTournament.Next.NamePlayer2);
    DocumentUI.SetModel(Prefix + 'score', IntToStr(MatchScores[I]), 1);
    Col := GetPlayerColor(Ini.SingColor[I]);
    DocumentUI.SetModel(Prefix + 'color', '#' +
      IntToHex(EnsureRange(Round(Col.R * 255), 0, 255), 2) +
      IntToHex(EnsureRange(Round(Col.G * 255), 0, 255), 2) +
      IntToHex(EnsureRange(Round(Col.B * 255), 0, 255), 2));
  end;
end;

destructor TScreenPartyTournamentWin.Destroy;
begin
  DocumentUI.Free;
  inherited;
end;

function TScreenPartyTournamentWin.DrawBG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(true) else Result := inherited;
end;

function TScreenPartyTournamentWin.DrawFG: boolean;
begin
  if DocumentUI <> nil then Result := DocumentUI.Draw(false, true) else Result := inherited;
end;

function TScreenPartyTournamentWin.ParseMouse(MouseButton: integer; BtnDown: boolean; X, Y: integer): boolean;
var Action: UTF8String;
begin
  if DocumentUI = nil then Exit(inherited);
  if RightMbESC and (MouseButton = SDL_BUTTON_RIGHT) and BtnDown then
    Exit(ParseInput(SDLK_ESCAPE, 0, true));
  if MouseButton = SDL_BUTTON_LEFT then DocumentUI.Mouse(X, Y, 0, BtnDown)
  else DocumentUI.Mouse(X, Y);
  Action := DocumentUI.TakeAction;
  Result := true;
  if (Action = uiTournamentWinContinue) or (Action = uiNavigationBack) then
    Result := ParseInput(SDLK_RETURN, 0, true);
end;

function TScreenPartyTournamentWin.ParseInput(PressedKey: cardinal; CharCode: UCS4Char; PressedDown: boolean; Repeated: boolean = false): boolean;
begin
  Result := true;
  if (PressedDown) then
  begin // Key Down
    // check normal keys
    case PressedKey of
      SDLK_Q:
        begin
          Result := false;
          Exit;
        end;
    end;

    // check special keys
    case PressedKey of
      SDLK_ESCAPE,
      SDLK_BACKSPACE,
      SDLK_RETURN :
        begin
          AudioPlayback.PlaySound(SoundLib.Start);

          if ((MatchScores[0] > PartyTournament.Rounds[PartyTournament.Phase] / 2) or (MatchScores[1] > PartyTournament.Rounds[PartyTournament.Phase] / 2)) then
          begin

            if (PartyTournament.Phase <> 3) then
            begin
              SetLength(PartyTournament.EliminatedPlayers, Length(PartyTournament.EliminatedPlayers) + 1);

              if (MatchScores[0] > MatchScores[1]) then
                PartyTournament.EliminatedPlayers[High(PartyTournament.EliminatedPlayers)] := PartyTournament.Next.Player2
              else
                PartyTournament.EliminatedPlayers[High(PartyTournament.EliminatedPlayers)] := PartyTournament.Next.Player1;

            end
            else
            begin
              if (MatchScores[0] > MatchScores[1]) then
                PartyTournament.Winner := PartyTournament.Next.NamePlayer1
              else
                PartyTournament.Winner := PartyTournament.Next.NamePlayer2;

              PartyTournament.TournamentFinish := true;

            end;
          end;

          PartyTournament.LastPlayer := PartyTournament.Next.Player2;

          if (PartyTournament.Phase = 3) then
          begin
            if not (PartyTournament.TournamentFinish) then
              FadeTo(@ScreenSong)
            else
              FadeTo(@ScreenPartyTournamentRounds);
          end
          else
            FadeTo(@ScreenPartyTournamentRounds);

        end;
      SDLK_TAB:
        begin
          ScreenPopupHelp.ShowPopup();
        end;
    end;
  end;
end;

constructor TScreenPartyTournamentWin.Create;
begin
  inherited Create;

  DocumentUI := TDocumentUI.Open(uiTournamentWinRole);
  if DocumentUI <> nil then Exit;

  LoadFromTheme(Theme.PartyTournamentWin);

  TextScorePlayer1 := AddText (Theme.PartyTournamentWin.TextScorePlayer1);
  TextScorePlayer2 := AddText (Theme.PartyTournamentWin.TextScorePlayer2);

  TextNamePlayer1 := AddText (Theme.PartyTournamentWin.TextNamePlayer1);
  TextNamePlayer2 := AddText (Theme.PartyTournamentWin.TextNamePlayer2);

  StaticBGPlayer1 := AddStatic (Theme.PartyTournamentWin.StaticBGPlayer1);
  StaticBGPlayer2 := AddStatic (Theme.PartyTournamentWin.StaticBGPlayer2);
end;

procedure TScreenPartyTournamentWin.OnShow;
var
  Col: TRGB;
begin
  if DocumentUI = nil then inherited;

  if not Help.SetHelpID(ID) then
    Log.LogError('No Entry for Help-ID ' + ID + ' (ScreenPartyTournamentWin)');

  UpdateRounds;
  MatchScores[0] := StrToInt(PartyTournament.ResultPlayer[PartyTournament.Phase, PartyTournament.Next.Player1].Text);
  MatchScores[1] := StrToInt(PartyTournament.ResultPlayer[PartyTournament.Phase, PartyTournament.Next.Player2].Text);
  if DocumentUI <> nil then
  begin
    SetDocumentResults;
    Exit;
  end;

  Col := GetPlayerColor(Ini.SingColor[0]);

  Statics[StaticBGPlayer1].Texture.ColR := Col.R;
  Statics[StaticBGPlayer1].Texture.ColG := Col.G;
  Statics[StaticBGPlayer1].Texture.ColB := Col.B;

  Col := GetPlayerColor(Ini.SingColor[1]);

  Statics[StaticBGPlayer2].Texture.ColR := Col.R;
  Statics[StaticBGPlayer2].Texture.ColG := Col.G;
  Statics[StaticBGPlayer2].Texture.ColB := Col.B;

  Text[TextNamePlayer1].Text := PartyTournament.Next.NamePlayer1;
  Text[TextNamePlayer2].Text := PartyTournament.Next.NamePlayer2;

  Text[TextScorePlayer1].Text := IntToStr(MatchScores[0]);
  Text[TextScorePlayer2].Text := IntToStr(MatchScores[1]);

end;

procedure TScreenPartyTournamentWin.UpdateRounds;
begin
  if (PartyTournament.ResultPlayer[PartyTournament.Phase, PartyTournament.Next.Player1].Text = '') then
    PartyTournament.ResultPlayer[PartyTournament.Phase, PartyTournament.Next.Player1].Text := '0';

  if (PartyTournament.ResultPlayer[PartyTournament.Phase, PartyTournament.Next.Player2].Text = '') then
    PartyTournament.ResultPlayer[PartyTournament.Phase, PartyTournament.Next.Player2].Text := '0';

  if (ScreenSing.SungToEnd) then
  begin
    if (player[0].ScoreTotalInt > player[1].ScoreTotalInt) then
      PartyTournament.ResultPlayer[PartyTournament.Phase, PartyTournament.Next.Player1].Text := IntToStr(StrToInt(PartyTournament.ResultPlayer[PartyTournament.Phase, PartyTournament.Next.Player1].Text) + 1);

    if (player[0].ScoreTotalInt < player[1].ScoreTotalInt) then
      PartyTournament.ResultPlayer[PartyTournament.Phase, PartyTournament.Next.Player2].Text := IntToStr(StrToInt(PartyTournament.ResultPlayer[PartyTournament.Phase, PartyTournament.Next.Player2].Text) + 1);
  end;

end;

end.
