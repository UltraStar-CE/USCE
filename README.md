# UltraStar Community Edition

An open-source karaoke game for Windows, macOS and Linux, developed by the community.

Sing along with your music, score points for pitch and timing, and play together
with up to six players. USCE includes party modes, themes, and support for a range
of audio and video formats.

## Get started

USCE is being set up. There is no USCE release yet. Download links will be added
here after the first builds have been tested. Developers can build from source
using [COMPILING.md](COMPILING.md).

The inherited executable names and configuration locations still use UltraStar
Deluxe names. See the configuration notes below. Do not assume an upstream package is a
USCE build.

## Songs and setup

Use UltraStar-format songs that you have permission to use. Songs are managed
separately from the game. The upstream [controls](https://usdx.eu/docs/controls/)
and [configuration documentation](https://usdx.eu/docs/) describe the inherited
behavior while USCE documentation is being established.

### Configuration notes
- To set additional song directories change your config.ini like this:
```ini
  [Directories]
  SongDir1=C:\Users\My\Music\MyUSDXSongs
  SongDir2=F:\EvenMoreUSDXSongs
  SongDir...=... (some more directories)
```
- To enable joypad support change config.ini `Joypad=Off` to `Joypad=On`
- To enable 2 or 3 player each on 2 screens, disable the full screen mode, extend your desktop horizontally and set the resolution to fill one screen. Then, in the config.ini set `Screens=2` and restart the game.
- The primary folder for songs on macOS is `$HOME/Music/UltraStar Deluxe`, which is created when UltraStar Deluxe is run for the first time.
- On macOS, by default the `config.ini` file is created in `$HOME/Library/Application Support/UltraStarDeluxe` when UltraStar Deluxe is run for the first time.
- When running in borderless fullscreen mode, the monitor it runs on can be configured by setting `Graphics.PositionX/Y` to an offset in pixels.
- If installed via the flatpak package, the primary song folder is `~/.var/app/eu.usdx.UltraStarDeluxe/.ultrastardx/songs/` and the config.ini is located in `~/.var/app/eu.usdx.UltraStarDeluxe/.ultrastardx/` by default. To configure additional song directories, they first need to be made accessible to the flatpak app using the command: `flatpak override eu.usdx.UltraStarDeluxe --filesystem=/your/new/songfolder` - Afterwards, the directory can be added to the config.ini file as usual.


## Help and feedback

Report reproducible problems in [Issues](https://github.com/UltraStar-CE/USCE/issues).
Include your build, operating system, and steps to reproduce. Please remove
personal information from logs. Ideas, questions, and testing feedback help
shape the game.

## Take part

Code, translations, themes, documentation, accessibility improvements, and testing
are all useful contributions. Read [CONTRIBUTING.md](CONTRIBUTING.md) to get started.
Project proposals and decisions are discussed publicly; see
[GOVERNANCE.md](GOVERNANCE.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## Credits and license

USCE builds on [UltraStar Deluxe](https://github.com/UltraStar-Deluxe/USDX),
which derives from UltraStar by corvus5. We thank their contributors for the game
and the work that makes this edition possible. See [COPYRIGHT.txt](COPYRIGHT.txt),
the Git history, and [LICENSE](LICENSE) for authorship and license information.
Third-party libraries and assets retain their own notices.
