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

### English fallback coverage

English is the fallback for incomplete translations. New labels need an entry
in `game/languages/English.ini`, including labels passed through popup helpers
and generated player labels. Run `python3 tools/check_english.py` to check source
references, player labels, bundled party modes and built-in theme text. Use
`--themes PATH` to include a checkout of the pinned Themes package. Packaging
runs this check against every bundled theme before producing downloads.

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
