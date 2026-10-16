# Compiling
[Free Pascal](http://freepascal.org/) 3.0.0 or newer is required to compile UltraStar Community Edition. Using the newest version is suggested.
For linking and running the game, the following libraries are also required:
- SDL2, SDL2_image
- FFmpeg 4.0-9.0
- SQLite 3
- [BASS](http://www.un4seen.com/bass.html)
- some fonts like DejaVu
- PortAudio
- Lua 5.1, 5.2, 5.3, 5.4, or 5.5
- OpenCV if you want webcam support
- projectM 4,x if you want audio visualisation support

Prebuilt DLLs for SDL2, SDL2_image, FFmpeg, SQLite, PortAudio, and Lua can be found in the releases section of [the pinned upstream MXE releases](https://github.com/UltraStar-Deluxe/mxe). You can use the dldlls.py script to download the DLLs for the checked out code. The remaining DLLs needed for Windows builds are part of this repository.

## Compiling using make
### Install prequisites
#### Linux/BSD
Required libraries:
- Debian/Ubuntu: `git automake make gcc fpc libsdl2-image-dev libavformat-dev libavcodec-dev libavutil-dev libswresample-dev libswscale-dev libsqlite3-dev libfreetype6-dev portaudio19-dev libportmidi-dev liblua5.3-dev libopencv-videoio-dev fonts-dejavu`
- Fedora: `git automake make gcc fpc SDL2_image-devel ffmpeg-devel sqlite-devel freetype-devel portaudio-devel portmidi-devel lua-devel opencv-devel`
- Archlinux: see the dependencies in the [ultrastardx-git](https://aur.archlinux.org/packages/ultrastardx-git) AUR package

Optional libraries:
- [ProjectM](https://github.com/projectM-visualizer/projectm) visualization: You may need to compile this from source because 4.0 or later is required, but many distros still ship 2.x or 3.x
- Webcam: `g++ libopencv-dev` (Debian/Ubuntu)

#### MacOS (High Sierra and above)
- Install Homebrew. Follow instructions from [brew.sh](http://brew.sh)
- `brew install fpc` or get it from [freepascal.org](http://www.freepascal.org/down/i386/macosx.var)
- `xcode-select --install`
- `brew install sdl2 sdl2_image automake portaudio binutils sqlite freetype lua libtiff pkg-config ffmpeg opencv`

#### Windows using MSYS2
- Install [MSYS2](https://www.msys2.org)
- Install [FPC](https://www.freepascal.org). Use the Win32 cross-to-Win64 installer so you get the Win64 RTL units.
- `pacman -S autoconf-wrapper automake-wrapper git make mingw-w64-x86_64-gcc mingw-w64-x86_64-tools`
- Add some information to `.bash_profile`:
  * Path to the cross compiler: `PATH="${PATH}:/c/FPC/3.2.2/bin/i386-win32"`
  * FPC config and base: `FPCCFG="/c/FPC/3.2.2/bin/i386-win32/fpc.cfg"` and `FPCDIR="/c/FPC/3.2.2"`

### Compile and run
- `git clone https://github.com/UltraStar-CE/USCE`
- `cd USCE`
- `./autogen.sh`
- `./configure` (see optional flags below)
- `make` (on macOS: `make macos-standalone-app`)
- `./game/usce[.exe]` (on MacOS: `open "UltraStar Community Edition.app"`)

#### configure flags
* `--enable-debug`: Outputs warnings and errors from Error.log also to the console, and prints stacktraces when an EAccessViolation occurs.
* `--with-portaudio`: This is the default.
* `--without-portaudio`: Use SDL audio input instead.
  This should support newer platforms like PulseAudio and PipeWire.
  Might not be able to detect the number of channels correctly when used with PulseAudio.
  Might fix issues experienced when using PortAudio on certain distributions.
* `--with-opencv`: Enable webcam support with OpenCV. By default, configure
  auto-detects OpenCV 3+ and disables webcam support if OpenCV is not found.
* `--without-opencv`: Build without webcam support even if OpenCV is installed.

## Flatpak packaging

USCE does not yet have a published Flathub package. The upstream USDX manifest
at https://github.com/flathub/eu.usdx.UltraStarDeluxe is a reference only;
installing it installs USDX, not this edition. A USCE manifest must select the
USCE source commit, app ID `org.ultrastarce.usce`, executable `usce`, and the
matching reviewed dependencies before publication.

# Windows installer
The CI does this for you, but if you need to do it manually:
- Complete the set of DLLs in the `game` directory using a matching release from [here](https://github.com/UltraStar-Deluxe/mxe).
- Create Windows portable version: zip the contents of the `game` directory
- Create Windows installer:
  * Install NSIS (also install the Graphics and Language components during setup)
  * Copy the DLLs from `game` to `installer/dependencies/dll`
  * `C:\...\makensis "installer/UltraStar Community Edition.nsi"` (this will take a while)
  * The .exe will be placed in `installer/dist`
