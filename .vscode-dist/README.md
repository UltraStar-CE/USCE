# VS Code starter configuration

Copy this directory to `.vscode` in the repository root. These optional settings
provide build tasks and launch configurations for USCE. Install the recommended
extensions and follow [COMPILING.md](../COMPILING.md) to install build dependencies.

Adjust the Free Pascal source directory in `settings.json` and the debugger paths
in `launch.json` for your installation. Windows uses the MSYS2 UCRT64 GDB debugger;
Linux uses GDB, and macOS uses LLDB. Debug launches build with `make debug`.

On Windows, configure the VS Code task terminal to use your MSYS2 UCRT64 shell
before running the shell tasks. The configure and make tasks require the same
compiler and dependency environment as a terminal build. Run the Windows dependency
installation step from COMPILING.md before launching the game.

The song-path prompt is relative to the game directory unless an absolute path is
provided. The copied `.vscode` directory is ignored by Git, so local paths and
settings remain local.
