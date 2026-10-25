# Configuration reference

[Back to USCE](../README.md) · [Getting started](getting-started.md)

Most everyday settings are available in **Tools → Options**. This guide explains
`config.ini`, including options for setups that need more control. Use the file's
English values below even when menus are translated.

**Jump to:** [Song folders](#add-song-folders) · [Game](#game) ·
[Graphics](#graphics) · [Sound](#sound-and-volume) · [Microphones](#microphones) ·
[Controls](#controls) · [Themes and lyrics](#themes-and-lyrics) ·
[Advanced](#advanced-behavior) · [Webcam](#webcam) ·
[Players and teams](#saved-players-and-teams) · [Piano keys](#piano-key-bindings)

## Find and edit your configuration

Start the game once, then close it before editing. Keep a copy of `config.ini`
if you want to undo several changes. Use a plain-text editor, save and restart.
Editing while the game is running can lose changes when it saves its settings.

| Installation | Usual configuration location |
| --- | --- |
| Windows with a writable game folder | `config.ini` next to `usce.exe` |
| Windows when the game folder is not writable | `%APPDATA%\usce\config.ini` |
| Installed Linux build | `~/.usce/config.ini` |
| macOS app | `~/Library/Application Support/UltraStar Community Edition/config.ini` |
| Local source/portable build | Usually `config.ini` next to the executable |

An existing USDX configuration may still be selected if no USCE configuration
exists in the corresponding user directory. Legacy locations are
`%APPDATA%\ultrastardx`, `~/.ultrastardx` and
`~/Library/Application Support/UltraStar Deluxe`. No files are moved or deleted.
Check the log's `Using config :` line for the file actually in use. The launch
option `-configfile "path/to/config.ini"` selects a different file.

```ini
[Graphics]
FullScreen=Off
Resolution=1280x720
```

Change a key in its existing section instead of adding duplicates. Leave paths
unquoted in the INI file. To restore a default, remove that key and restart.
Defaults below apply when a key is absent; devices, fonts and themes affect some
defaults. Manual edits take effect on the next launch.

## Add song folders

Add a separate entry for each collection under `[Directories]`:

```ini
[Directories]
SongDir1=C:\Music\Karaoke
SongDir2=D:\More songs
```

On Linux or macOS, use an absolute path such as `/home/alex/Music/Karaoke` or
`/Users/alex/Music/Karaoke`. Use the full path rather than shell shortcuts such
as `~` or `$HOME`. USCE searches subfolders too. These entries add to the standard
song folders; they do not move your collection.

On macOS, the standard music folder is `~/Music/UltraStar Community Edition`.
An existing `~/Music/UltraStar Deluxe` folder remains discoverable if the new
folder does not exist. Portable installations also search their `songs` folder.

| Key in `[Directories]` | Default | What it does |
| --- | --- | --- |
| `SongDir1`, `SongDir2`, … | No extra folders | Adds song collections. Leave unused entries blank. |
| `WebScoresDir` | First available `webs` folder | Selects website score definitions; normally leave unchanged. An unavailable folder falls back to the standard one. |

## Game

File section: `[Game]`. Most settings are under **Options → Game**.

| Key | Values; default | What it does |
| --- | --- | --- |
| `Players` | `1`, `2`, `3`, `4`, `6`; `1` | Number of singers. Assign microphone channels separately under Record. |
| `Difficulty` | `Easy`, `Medium`, `Hard`; `Medium` | How accurately singers need to match notes. |
| `Language` | Installed language name; `English` | Menu language. Falls back to an available language if necessary. |
| `SongMenu` | `Roulette`, `Chessboard`, `List`; `Roulette` | Song browser layout. |
| `Tabs` | `Off`, `On`; `Off` | Groups songs into categories using the sorting method. |
| `Sorting` | `Edition`, `Genre`, `Language`, `Folder`, `Title`, `Artist`, `Artist2`, `Year`, `Year Reversed`, `Decade`; `Artist` | Organizes the collection. Some choices depend on song metadata. |
| `ShowScores` | `Off`, `When exists`, `On`; `On` | Whether scores appear in the song browser. |
| `AVDelay` | Integer milliseconds; `0` | Audio/video timing compensation. Adjust in small steps using a familiar song. |
| `MicDelay` | Integer milliseconds, normally nonnegative; `140` | Compensates for microphone input delay when matching notes. |
| `Debug` | `Off`, `On`; `Off` | Additional diagnostic logging. |
| `ShowWebScore` | Installed website definition name; first available | Website score source when definitions are installed. Prefer the score screen's selection. |

## Graphics

File section: `[Graphics]`. Common settings are under **Options → Graphics**;
positions, frame limits and codec preferences are advanced file settings.

| Key | Values; default | What it does |
| --- | --- | --- |
| `FullScreen` | `Off`, `On`, `Borderless`; `Borderless` | Windowed, exclusive fullscreen or borderless display. |
| `Resolution` | `WIDTHxHEIGHT`; detected desktop size | Window/rendering resolution, for example `1280x720`. Falls back if unusable. |
| `ResolutionFullscreen` | Supported display mode; detected desktop size | Resolution for exclusive fullscreen. |
| `MaxFramerate` | `10`, `20`, `30`, `40`, `50`, `60`, `70`, `80`, `90`, `100`, `150`, `200`; `60` | Frame-rate limit. Higher values require more rendering work. |
| `Screens` | `1`, `2`; `1` | Number of game screens. Two screens need suitable desktop and resolution settings. |
| `Split` | `Off`, `On`; `Off` | Splits the game display rather than extending it across screens. |
| `PositionX`, `PositionY` | Integer pixels; `0` each | Window position, useful for placing a borderless window on another monitor. |
| `Depth` | `16 bit`, `32 bit`; `32 bit` | Display color depth. Keep the default unless troubleshooting. |
| `TextureSize` | `64`, `128`, `256`, `512`; `256` | Cached cover texture size. Larger covers use more memory. |
| `Oscilloscope` | `Off`, `On`; `On` | Shows the microphone waveform during singing. |
| `MovieSize` | `Half`, `Full [Vid]`, `Full [BG+Vid]`; `Full [BG+Vid]` | Background/video size during singing. |
| `VideoPreview` | `Off`, `On`; `On` | Song video previews in the browser. |
| `VideoEnabled` | `Off`, `On`; `On` | Video playback during songs. |
| `Visualization` | `Off`, `WhenNoVideo`, `WhenNoVideoAndImage`, `On`; `Off` | When to use visualizations. Needs projectM support and installed presets. |
| `PreferredCodecs` | Decoder names separated by spaces or commas; empty | Video decoder preference. Leave empty for automatic selection. Availability depends on FFmpeg. |

For two monitors, first use the operating system's extended desktop. A windowed
two-screen setup can use `Screens=2`, `FullScreen=Off` and a resolution for one
screen; the game can expand its window across both. Monitor sizes and placement
must suit that arrangement. To place one borderless window on a second monitor,
use its desktop pixel offset in `PositionX` and `PositionY` instead.

## Sound and volume

File section: `[Sound]`. Most settings are under **Options → Sound**.

| Key | Values; default | What it does |
| --- | --- | --- |
| `AudioVolume` | `0`–`100`; `100` | Song music volume. |
| `VocalsVolume` | `0`–`100`; `100` | Separate vocal-track volume when the song provides one. |
| `LastPartialVocalsVolume` | `0` to `100`; `0` | Remembers a manually chosen partial vocal volume. With a remembered level between 1 and 99, K cycles through full volume, that level, and muted vocals. Otherwise K switches between full and muted vocals. |
| `SfxVolume` | `0`–`100`; `100` | Menu and game sound effects. |
| `PreviewVolume` | `0`–`100`; `30` | Song preview volume. |
| `BackgroundMusicVolume` | `0`–`100`; `40` | Menu background music volume. |
| `BackgroundMusic` | `Off`, `On`; `On` | Background music in menus. |
| `PreviewFading` | `Off`, `1 Sec`, `2 Secs`, `3 Secs`, `4 Secs`, `5 Secs`; `3 Secs` | Fade duration for song previews. |
| `ReplayGain` | `Off`, `On`; `Off` | Uses available ReplayGain information to reduce loudness differences. |
| `VoicePassthrough` | `Off`, `On`; `Off` | Plays microphone input through speakers. This can cause feedback; use suitable volume or headphones. |
| `ClickAssist` | `Off`, `On`; `Off` | Plays a click at the start of each note. |
| `BeatClick` | `Off`, `On`; `Off` | Plays a beat click during singing. |
| `AudioOutputBufferSize` | `Auto`, `256`, `512`, `1024`, `2048`, `4096`, `8192`, `16384`, `32768`, `65536`; `Auto` | Output buffer size in samples. Larger buffers can reduce dropouts but add delay. Prefer Auto. |
| `SavePlayback` | `Off`, `On`; `Off` | Saves captured microphone audio during singing. Keep off unless you want recordings. |

Volumes also accept a percent sign, for example `30%`; the game saves whole
numbers. `Off` is accepted as a legacy volume value for zero.

## Microphones

Prefer **Options → Record** for device and channel assignments. Mic boost and
Threshold are on the Record page too. All are stored in `[Record]`.

| Key in `[Record]` | Values; default | What it does |
| --- | --- | --- |
| `MicBoost` | `Off`, `+6dB`, `+12dB`, `+18dB`; `Off` | Amplifies microphone input. Check the system input level first. |
| `Threshold` | `5%`, `10%`, `15%`, `20%`, `25%`, `30%`, `40%`, `60%`; `10%` | Minimum level for pitch detection. Lower values pick up quieter singing and more background noise. |
| `DeviceName[n]` | Exact device name; no saved devices initially | Identifies device `n`. Let the Record menu write the name. |
| `Input[n]` | Device-specific integer; `0` | Selected input for device `n`. Available inputs depend on the audio backend. |
| `Latency[n]` | Milliseconds, or `-1` for automatic; `-1` | Requested device latency where supported by the backend. |
| `Channelc[n]` | `0` unassigned, or player number `1`–`12`; `0` | Assigns channel `c` of device `n`. The normal player-count menu offers up to six singers. |

The game saves device entries starting at `1`, for example `DeviceName[1]` and
`Channel1[1]`. Disconnected devices remain saved for use when reconnected.
Device names and input numbers are specific to your computer.

## Controls

File section: `[Controller]`. Available under **Options → Input**.

| Key | Values; default | What it does |
| --- | --- | --- |
| `Joypad` | `Off`, `On`; `Off` | Enables controller input. |

Mouse input is always available. The pointer appears when moved or clicked and
starts fading after one second without activity. Older `Mouse` settings are ignored.

## Themes and lyrics

Available under **Options → Themes** and **Options → Lyrics**.

| Section | Key | Values; default | What it does |
| --- | --- | --- | --- |
| `[Themes]` | `Theme` | Installed theme name; `Modern` | Game appearance. Falls back to an available theme if missing. |
| `[Themes]` | `Skin` | Skin supplied by the theme; theme default | Variation of the selected theme. |
| `[Themes]` | `Color` | `Blue`, `Green`, `Pink`, `Red`, `Violet`, `Orange`, `Yellow`, `Brown`, `Black`; skin default | Accent color where supported. |
| `[Lyrics]` | `LyricsFont` | Installed font family; first available | Singing lyric font. |
| `[Lyrics]` | `LyricsStyle` | `Regular`, `Bold`, `Outline`; `Outline` | Text styling. |
| `[Lyrics]` | `LyricsEffect` | `Simple`, `Zoom`, `Slide`, `Ball`, `Shift`; `Slide` | Current-syllable animation. |
| `[Lyrics]` | `NoteLines` | `Off`, `On`; `On` | Shows pitch guide lines. |
| `[Lyrics]` | `Encoding` | `Auto`, `UTF8`, `CP1250`, `CP1252`, `LOCALE`; `Auto` | Fallback text encoding for songs. Prefer Auto unless text is misread. |

Legacy lyric styles `Plain`, `Oline1`, `Oline2` map to `Regular`, `Bold`, `Outline`.
Changing theme can change available skins and their defaults.

## Advanced behavior

File section: `[Advanced]`. Common effects are under **Options → Advanced**;
score and time-bar choices are also saved from their respective screens.

| Key | Values; default | What it does |
| --- | --- | --- |
| `LoadAnimation` | `Off`, `On`; `On` | Loading animation. |
| `ScreenFade` | `Off`, `On`; `On` | Fades between screens. |
| `EffectSing` | `Off`, `On`; `On` | Singing effects. |
| `AskbeforeDel` | `Off`, `On`; `On` | Asks for confirmation before quitting, including with Q during singing playback. Despite its name, this setting does not control song deletion. |
| `OnSongClick` | `Sing`, `Select Players`, `Open Menu`; `Sing` | Action after selecting a song. |
| `PartyPopup` | `Off`, `On`; `On` | Automatically opens the party menu where applicable. |
| `SingScores` | `Off`, `On`, `Bar Rating`, `Remaining Score`; `On` | Chooses the in-song score display: `Off` hides it, `On` shows both bars, `Bar Rating` shows the line-rating bar, and `Remaining Score` shows the remaining-score bar. Numeric scores accompany each enabled mode; party mode keeps scores visible. |
| `DuetScores` | `Off`, `Separate`, `Combined`, `Both`; `Separate` | Chooses which duet scores are stored. Combined scores average adjacent singers with matching difficulty. The older `On` setting is read as `Separate`. |
| `TopScores` | `All`, `Player`; `Player` | Includes all entries (`All`) or limits repeated entries for each player (`Player`). |
| `HighScoreScreenEntries` | Integer `5`–`20`; `5` | Number of high-score entries shown. Values outside the range are limited to it. |
| `SyncTo` | `Music`, `Lyrics`, `Off`; `Music` | Synchronization mode. Keep Music for normal playback. |
| `SingTimebarMode` | `Current`, `Remaining`, `Total`; `Remaining` | Elapsed, remaining or total song time during singing. |

## Webcam

File section: `[Webcam]`. Requires a build with webcam support. Use the game's
webcam controls for device selection and image adjustments.

| Key | Values; default | What it does |
| --- | --- | --- |
| `ID` | Device index; `0` | Camera selected by OpenCV. Numbering depends on the system. |
| `Resolution` | `160x120`, `176x144`, `320x240`, `352x288`, `640x480`, `800x600`; `320x240` | Requested capture size; hardware support varies. |
| `FPS` | `10`, `12`, `15`, `18`, `20`, `22`, `25`, `28`, `30`; `20` | Requested capture rate. |
| `Flip` | `Off`, `On`; `On` | Flips the camera image. |
| `Brightness` | `-100` through `+100`; `0` | Brightness adjustment. Include `+` on positive values. |
| `Saturation` | `-100` through `+100`; `0` | Saturation adjustment. Include `+` on positive values. |
| `Hue` | `-180` through `+180`; `0` | Hue adjustment. Include `+` on positive values. |
| `Effect` | Integer `0`–`10`; `0` | In order: normal, grayscale, black and white, negative, binary image, dilate, threshold, edges, Gaussian blur, equalized and erode. |

## Saved players and teams

Prefer player and party screens to editing numeric appearance values. Player
slots run from `P1` to `P12`; the normal game menu selects up to six singers.

| Section | Keys; default | What it stores |
| --- | --- | --- |
| `[Name]` | `P1`–`P12`; `Player1`–`Player12` | Player names. |
| `[PlayerColor]` | `P1`–`P12`; `1,4,3,2,5,6,7,8,9,10,11,12` for successive slots | Color IDs `1`–`16`; prefer the player screen. |
| `[PlayerAvatar]` | `P1`–`P12`; empty | Avatar selections. |
| `[PlayerLevel]` | `P1`–`P12`; `1` | Difficulty: `0` Easy, `1` Medium, `2` Hard. |
| `[TeamColor]` | `T1`–`T3`; `1`, `2`, `3` | Team color IDs; prefer the party screen. |
| `[NameTeam]` | `T1`–`T3`; `Team1`–`Team3` | Party team names. |
| `[NameTemplate]` | `Name1`–`Name12`; `Template1`–`Template12` | Reusable name templates. |

Player color IDs `1`–`16` are, in order: Blue, Red, Green, Yellow, Orange, Pink,
Violet, Brown, Gray, Dark Blue, Sky, Cyan, Flame, Orchid, Harlequin and Lime.

## Per-player microphone delay

File section: `[PlayerDelay]`. Set `P1` through `P12` to an additional timing
correction in milliseconds; the default is `0` for every player. Positive values
compensate for later microphone input by scoring it against earlier song beats.
The correction follows the player slot, so keep microphone assignments consistent.

These values supplement the global microphone delay. Start with small adjustments
and compare timing during a familiar song. Changes take effect when the next song starts. They do not change audio playback or the displayed lyric timing.

## Piano key bindings

File section: `[KeyBindings]`. These advanced mappings control piano input in
the editor, not menu navigation. Values are comma-separated integer key codes,
with exactly 19 entries for `PianoKeysLow` and 21 for `PianoKeysHigh`. A list with
a different length falls back to its built-in mapping.

| Key | Default key codes |
| --- | --- |
| `PianoKeysLow` | `60,97,121,115,120,100,99,118,103,98,104,110,109,107,44,108,46,246,45` |
| `PianoKeysHigh` | `49,113,50,119,51,101,114,53,116,54,122,117,56,105,57,111,48,112,252,96,43` |

## Compatibility and related files

This reference follows the current [configuration reader](../src/base/UIni.pas).
Older builds can have different settings and defaults. `Spectrum` and
`Spectrograph` are no longer read here. `AudioInputBufferSize` is not a current
INI key. Adding these keys does not enable those features.

Theme definitions, song TXT files, plugin settings and projectM's own
configuration are separate files. Do not paste their sections into `config.ini`.

`[Game] StatisticsView=Reduced` selects compact statistics; `Full` includes
averages, recent activity and performance facts. Also available in Options → Game.

### Age rating country

`[Game] AgeCountry=DE` selects Germany for AGE searches. An empty value uses
the unprefixed local/default entry. Choose it in Options → Game; the initial
default comes from the OS country/region, not timezone.

### Song-screen configuration

Press C in song selection to edit these settings. `[Playback] Continuous=0` or
`1` chooses which saved configuration is active. `[Playback0]` holds ordinary
singing settings; `[Playback1]` holds continuous settings. Both contain `Repeat`,
`Results`, `HighScores`, `SongDisplay` and `SingingDisplay`.

`Results` and `HighScores` use 0 for Manual, 1 for Skip, then 2 through 8 for
5, 10, 20, 30, 40, 50 and 60 seconds. `Repeat` affects continuous playback only.
Display values follow the order shown in Configuration. Missing settings retain
the full display, manual results for ordinary singing and skipped results for
continuous playback.
