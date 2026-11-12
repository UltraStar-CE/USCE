[![License](https://img.shields.io/badge/license-GPLv2-blue.svg)](LICENSE)

# USCE development

This guide introduces the inherited USDX codebase. For the USCE contribution and review process, read [CONTRIBUTING.md](CONTRIBUTING.md).

## AI assistance and human responsibility

We use AI reviews to help maintainers keep up with a fast pace of development
and community contributions. An additional review can surface mistakes, clarify
tradeoffs and give contributors earlier feedback. It helps us manage review
work; it does not transfer responsibility for a change to a tool.

Contributors remain responsible for everything they submit, whether written by
hand or with AI assistance. A human responsible for the contribution must be
able to read, modify, explain and defend the code: how it works, why the approach
fits, what it affects and how it was checked. We welcome AI assistance when the
contributor has credible understanding of the submitted work.

During review, we may ask for an explanation, a focused revision or evidence
that supports a claim. We judge those answers and the code, not a contributor's
credentials or confidence. If doubts remain and the contributor cannot
plausibly demonstrate the expertise needed to own the change, we may decline it
or ask for a smaller contribution they can support. Producing code with a tool
is not, by itself, evidence of understanding it.

AI suggestions are proposals. Contributors check them before submission, and
maintainers assess review findings before acting on them. A human decides what
is merged under our governance; an AI review never supplies a required human
approval or authorizes an automatic merge.

## Development direction and upstream

Contributions to [UltraStar Deluxe](https://github.com/UltraStar-Deluxe/USDX) are
welcome too. USDX has its own focus, priorities and development cadence. With
USCE, we aim to move quickly on new features and community-led experiments,
including ideas that need time to mature. AI-assisted reviews help us support
that pace while keeping responsibility with the people contributing the code.

We favor configurable additions and clear defaults, so players can try new
features or keep the experience they prefer. We consider compatibility and
existing workflows as part of each change. What we build next is shaped by
community proposals, testing and discussion. We value upstream's work and
preserve credit when incorporating improvements.

### Commits older than 2016
In 2016 the project was moved from SourceForge (SVN) to Github (git).
Generally, you don't need to look at commits that aren't in the git history, but sometimes you'll want to check something.
A git version of this SVN can be found in the [legacy-sourceforge-svn-mirror](https://github.com/UltraStar-Deluxe/legacy-sourceforge-svn-mirror) repository.

### General information:
- Freepascal 3.0.0 or later is required for development
- Please use CamelCase naming. Classes/Units/Types/Functions should start with a capital letter and constants/values/instances should start with small letters
- You can use Windows or Linux or macOS for development just fine. See readme.md for Linux / macOS install instructions.
- Use a feature branch and open a draft PR early so others can help. Required CI and the review policy in GOVERNANCE.md apply to maintainers too, including the published policy for a project with one human developer. Independent approval becomes required when a second human developer joins.
- Code and build changes run Windows, Linux, Intel macOS and ARM macOS builds on pull requests and pushes to `main`. Documentation, banners and translation changes only need whitespace validation. Contributors can download build artifacts from GitHub Actions to help test changes. See [USCE-CI.md](USCE-CI.md) for the required validation gate.
- If you start working on something that is more then just a small code change, please create an issue in the git repository issue tracker for that and assign it to yourself, so the other developers don't touch it in the mean time.
- Please write somewhat reusable code and split big problems into smaller functions. :)
- Ask development questions in the USCE issue tracker.
- Don't let anyone else tell you what to work on. Do what you like and be free!
Thank you for helping improve the game.

### Singing countdown theme settings

The optional `[SingCountdown]` section styles the shared intro, medley and
instrumental-gap countdown. `X` and `Y` are its center in the 800x600 reference
layout (defaults 400 and 300). `Size` defaults to 300; `Font` and `Style` use the
usual theme font identifiers. `ColR`, `ColG`, `ColB` and `Alpha` control its color
and opacity. Missing fields retain the existing blue countdown appearance.
The Lyrics option selects Off or the minimum gap duration, from 5 to 60 seconds.
Qualifying gaps show only their final ten seconds.
All voices contribute to gap detection; the countdown does not hide lyrics or
change the notes, progress bar or scoring.

### Song selection keyboard and search layout

Input options selects Modern (default) or Classic, stored as
`Controller/SongKeyboard=Modern` or `Classic`. Modern typing adds an All row
within the current filters or playlist. Ctrl+F opens the full filter dialog;
that typed row becomes an ordinary editable filter. Esc clears the current
typed query first. Commands use Ctrl, with Ctrl+Shift+F for custom medley.
Classic keeps bare-letter commands and Alt artist/title jumps.

Themes can override `[SongSearchPanel]`, `[SongSearchText]` and
`[SongModernFooterText1]` onwards using the normal static/text fields. Search
panel coordinates and hit testing share the same scale mode. The Blue skin uses
a widescreen song background with the USCE logo at the right of the header. The Modern legend
replaces key hints while retaining the theme's existing footer bars.
`TMenu.AddKeyHint` enables the existing `**bold**` text markup for trusted footer
hints, so keys can be bold and action labels regular. Other text stays literal.

### English fallback coverage

English is the fallback for incomplete translations. New labels need an entry
in `game/languages/English.ini`, including labels passed through popup helpers
and generated player labels. Run `python3 tools/check_english.py` to check source
references, player labels, bundled party modes and built-in theme text. Use
`--themes PATH` to include a checkout of the pinned Themes package. Packaging
runs this check against every bundled theme before producing downloads.

When testing a separately copied executable, validate its installed fallback too:
`python3 tools/check_english.py --english /path/to/game/languages/English.ini`.
Use the source tree matching that executable; a passing source-tree check alone
does not verify the language files in a different installation. The command
reports missing, empty and duplicate keys and returns a failing exit status.

This static check cannot evaluate arbitrary plugin-generated text. Test changed
screens in game as well, including labels, formatting arguments and text fit.

### Whitespace checks
- CI checks trailing whitespace in changed text files (excluding vendored `src/lib` and `src/webSDK`).
- Local one-liner (same check as CI, with `origin/main` as base):
  `git --no-pager -c core.whitespace=blank-at-eol diff --no-ext-diff --color --check "$(git merge-base HEAD origin/main)" -- . ':!./src/lib' ':!./src/webSDK'`
- Make targets:
  `make whitespace-check` (fails on issues), `make whitespace-warn` (warning only).
- Normal build targets (`make`, `make debug`, `make release`, ...) now run `whitespace-warn` after the compile step.
- If your base branch is different, override it:
  `BASE_REF=origin/main make whitespace-check`

### About the engine / used libraries:
- **SDL2** is used as general framework for spawning the window, getting keyboard / other input, and getting microphone and speaker device lists stuff. SDL2 also gets the OpenGL context for the window for us.
- **OpenGL** is used for all the graphics drawing + rendering stuff. Currently, this is using OpenGL 2.0 and later or OpenGL ES 2.0 and later.
- **projectM** is used for visualisation.
- **ffmpeg** is used for most video and audio stuff. On Windows, the bass library is used for playing mp3 files because of licensing issues of mp3 codecs.
- **OpenCV** videoio is used for getting images from the webcam.
- **sqlite** is used for creating and accessing databases to store song scores and already scanned songs. Remember that changing database setup will require adding an automatic upgrade script or resetting the database file for all users and loosing ist content.


### Where the game starts...:
At the end of the `usce.dpr` file is the program start. It calls the main function from the `src/base/UMain.pas` file, which does all the initialisation (creating the instances of the screen classes, setting up the window, OpenGL, audio and scanning the song folders for song .txt/.xml files).
After that, the game starts a while() in which it first cleans the screen, shows the last calculated new screen frame, checks for key-presses, calculates the next screen frame and then restarts the while until the user decided to close the game (->break). Everything is recalculated and freshly drawn for every single frame. (if you have some free time and know SDL2/OpenGL, feel free to improve this so that for example static background images are only sent once from system memory to graphics card memory and then drawn from there.) 
The logic code about how to handle key pressed events for each screen can be found in `src/screens/Uscreen[*].pas` (this will later on be split up into models, views and controllers by refactoring. Feel free to help)

### Where to find stuff:
- `UMain`: main game loop, fps limiter, game initialization, mouse + keyboard handling (which is then passed to the specific game screen UScreen...)
- `UGraphic`: initializes graphics stuff + much of the game initialization, gets OpenGL handle, sets up SDL window
- `UDraw`: draws the notes, lyrics, ...
- `UScreenEditSub`: songs editor stuff
- `USong`: reads + parses single song xml or txt files
- `USongs`: scans folders for song files to load, provides song filtering, category and sorting
- `UIni`: reads + writes settings form the config.ini file
- `UTheme`: loads all the theme files and processes them
- `UScreenOptions`...: displays the various game screens + handles mouse + keyboard input


`PartyOptionsSelectHighscores` styles the Party highscore selector. Without that
section it inherits the mode selector style and sits below the playlist fields.

### Optional rounded theme images

`CornerRadius=0..0.5` on static images and avatar rectangles rounds their
corners by a fraction of the shorter displayed side. Zero (the default) retains
the existing square image. The same key in `SongChessboardCover`,
`SongRouletteCover` or `SongListCover` applies to the dynamic song covers;
`ScaleMode=crop` optionally fills their bounds without stretching the image.
This is a draw-time mask: source images and shared texture caches are unchanged.
An absent key retains legacy behavior; inherited sections can supply the key.


### Optional song-list details

`SongListRowCover` positions each visible row's existing cover widget. Its X/Y
are the first row's coordinates; following rows use the normal list row stride.
W/H, ScaleMode and CornerRadius style the cover. Without this section the old
list layout is retained. Existing list-row selection and hit testing still apply.
`SongListSelectedTitle`, `SongListSelectedArtist` and `SongListSelectedYear` are
optional ordinary text sections for an independent selected-song detail panel.
They use the highlighted song, including when browsing a filtered playlist.


### Optional theme-local text font

Ordinary text and button-text sections may set `FontFile=fonts/Inter-Regular.ttf`.
The path uses the active theme/base-theme asset lookup. The numeric `Font` remains
the fallback; no new family is added to the user's lyric-font choices. The face
is loaded lazily once per file/fallback, with regular, synthetic bold and outline
styles. A missing or unreadable face falls back to the existing family. Loaded
families live until graphics/font teardown so outgoing screens remain valid
through a theme transition. Font licenses must accompany theme font files.


### Optional singing lane backplates

`SingLanePanel` is an optional ordinary image-style section (Tex, Type, color,
Alpha, CornerRadius and Z). Its bounds follow the existing note-guide layout for
each visible player on each screen. `Padding=0..40` adds space around the guides,
scaled with the lane. X/Y/W/H are not used. With no section, nothing is drawn.
Panels follow note visibility, so hiding notes or using zero-player playback
also hides them. They do not change note drawing, scoring, voices or lyrics.


### Explicit base-section inheritance

A derived theme can set `Inherits=base:DefaultLegendText` inside
`DefaultLegendText` to keep the nearest base theme's values and override only
individual keys. `base:` searches after the file defining the current section,
so chained base themes can extend their own parent sections. It also works for
`Colors`: inherited names remain available and derived names override them.
Ordinary `Inherits=OtherSection` and sections without Inherits keep their previous
lookup behavior. This avoids implicitly changing existing derived-theme layouts.

### Optional button focus outline

Ordinary button and button-collection sections may opt into a focus outline:

```ini
FocusWidth=3
FocusInset=3
FocusRadius=12
FocusColor=White
FocusAlpha=1
FocusDuration=200
```

Width, inset and radius use the button's logical theme coordinates. Positive
inset draws inside the existing bounds; negative inset draws outside. The
outline follows the button's current selected/fading bounds and scale mode,
without changing layout or the mouse hit region. Its center remains transparent.
FocusColor defaults to the selected button color; FocusAlpha defaults to 1.
FocusDuration is a reversible opacity transition in milliseconds (0..2000),
with 0 switching immediately. FocusWidth defaults to 0, so existing themes keep
their current appearance and allocate no outline texture. This does not replace
the theme's existing selection texture or change the user's keyboard controls.

### Optional texture-background motion

Texture background sections may set `Motion=1` for slow gradient drift. The
value controls speed (0 through 10); the default 0 retains the existing static
background. It does not affect videos, controls or screen-transition scaling.
The enlarged texture always covers the viewport, including multiple screens.

### Optional main-menu preview groups

Themes may declare `MainPreviewSingStatic1`, `MainPreviewPartyStatic1`,
`MainPreviewStatisticsStatic1`, `MainPreviewSettingsStatic1`,
`MainPreviewAboutStatic1` and `MainPreviewExitStatic1`, followed by consecutively
numbered ordinary static sections per group. Only the selected action's group
is visible. `[MainPreview]` may set `FadeTime` in seconds (default 0, maximum 5)
and `SlideX` in theme coordinates (default 0). Transitions reverse smoothly on
rapid input. Groups are decorative: input stays with the existing buttons.
Absent groups retain the existing main menu.


### Optional player cards and singing HUD styling

These settings are opt-in. Themes without them keep the existing menu, setup
carousel, player headers, note textures and progress colors. No theme name is
checked by the renderer.

`[NameCards] Enabled=1` displays player cards using the normal setup controls.
`X/Y/W/H` define their area, `Columns` and `Rows` the page size (defaults 3x2),
`Gap` their spacing and `MaxH` their height limit. The selected player's page
follows keyboard navigation. Clicking a card selects its player. Names, avatars,
colors, difficulty and multi-voice assignments use the existing state and save
path. `NameCardPanel` and `NameCardFocus` are ordinary static sections; their
W/H are the reference dimensions for the card contents. `NameCardAvatar` and
`NameCardName` position its avatar and name. The regular name button and select
slides use card-local coordinates, or screen coordinates with `EditOutside=1`.
`ShowLabel`, `Initials`, `LevelSegments` and `TintControls` customize the view.
The difficulty segments retain the existing arrow-key control and also accept
mouse clicks. The shared count selector still supports every player count.

`[SingPlayerHeader]` adds an ordinary static panel behind each shared player
header. `SingPlayerWidgetPlacement` can set `DockTop=1`, `DockY` and `DockW` for
a row of headers across the top. Multi-voice songs retain lane-local headers
so the top lyric bank stays clear. The existing anchors and reference rectangle
still control widget placement and scaling.

`[SingScoreStyle]` can set `ThemedText=1` to use the score text's position,
alignment, font file and color, `Digits` (default 5), `PlayerColor` (default 1)
and `BackgroundAlpha` (default 1). `[Sing]` supports `NoteScale` (default 1),
`PlainNotesUsePlayerColor` (default 1), `GuideAlpha` (default 0.4), an optional
`DefaultAvatarTex` for the singing screen alone, and `HelperAbove=1` for a thin
lyric count-in cue. Custom player avatars are retained. `SingLanePanel` can add
an `AccentWidth` stripe in the player's color. `SingTimeProgress VoiceColors=0`
uses its theme color for every lyric section; `SingTimeText ShowSongTitle=1`
includes the title beside the time. All voices use the same rendering path.

`[Main] DynamicDescription=0` keeps the theme's own heading text. Buttons can
set `DAlpha` for a separate deselected background opacity. A button text section
can opt into its selected/deselected colors with `FocusColors=1`; existing text
color behavior remains the default. Select slides can set `EmptyText=1` to omit
their label while retaining the option text. Required text sections may use
`Enabled=0` to omit their text, as numbered optional text sections already do.
