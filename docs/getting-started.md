# Your first karaoke night

[Back to USCE](../README.md) · [Configuration reference](config.ini.md)

## Get the game

USCE runs on Windows, macOS and Linux. Our first release is in preparation;
tested downloads will appear on the [releases page](https://github.com/UltraStar-CE/USCE/releases).
For now, [COMPILING.md](../COMPILING.md) explains how to build it.

The program is called `usce.exe` on Windows, `usce` on Linux, and
`UltraStar Community Edition.app` on macOS. USCE has no published Flathub package yet.

## Connect your microphone

Connect your microphone before starting USCE. Open **Tools → Options → Record**,
choose the sound device and input, and assign its channel to **Player 1**.
For more singers, assign each microphone channel to the corresponding player.
The menu labels can differ with your language or theme.

Speak or sing and check the input meter before starting a song. Your computer's
microphone permissions and input volume must also allow the game to receive audio.
Choose the number of players and difficulty under **Options → Game**.

## Add songs

USCE uses UltraStar-format song collections. Each song normally has a TXT file
containing timed lyrics and pitch notes, together with its audio file. Covers,
backgrounds and videos are optional. An audio file alone is not a playable song.
Keep each song's files together in its own folder.

Song collections are separate from the game. Use songs you have permission to use.
If you already have an UltraStar collection, you can point USCE at the same folder
without copying it. Follow [Add song folders](config.ini.md#add-song-folders).

For a writable portable game folder, you can also place song folders in its
`songs` directory. On macOS, a new collection can go in
`~/Music/UltraStar Community Edition`. Restart USCE after adding songs.

## Choose a song and sing

Open **Sing**, browse your collection and select a song. Follow the on-screen
lyrics and aim for the pitch bars. Longer notes need to be held; your score
reflects how well you match the notes.

Use the arrow keys to navigate, **Enter** to select and **Escape** to go back.
The game displays additional controls for the current screen.
Try an easier difficulty while getting used to the pitch display.

## Make it yours

Open **Tools → Options → Themes** to change the theme and skin.
Other option pages control sound, display, lyrics and input. Prefer the in-game
menus for everyday changes; the [configuration reference](config.ini.md)
covers advanced settings and extra song folders.

## If something does not work

| Problem | What to try |
| --- | --- |
| No songs appear | Check the folder path and that each song contains its TXT file and the audio file named in it. Restart after changing folders. |
| No microphone input | Check the selected device, input and player assignment in Record settings, then the operating system's input volume and permissions. Restart after connecting a new device. |
| The pitch display does not react to quiet singing | Check input volume first, then try the Threshold and Mic boost settings under Record. |
| Notes or video feel out of sync | Try Game's Audio/Video Delay or Microphone Delay settings. Change one at a time and test the same song again. |
| No sound | Check the system output device, volume and the game's Sound settings. |
| Display settings prevent normal use | Close the game and edit the active configuration to use `FullScreen=Off` and a supported resolution. See [display settings](config.ini.md#graphics). |

For questions, use [Discussions](https://github.com/UltraStar-CE/USCE/discussions).
For a reproducible bug, [open an issue](https://github.com/UltraStar-CE/USCE/issues)
with your build, operating system, what you tried and what happened. A screenshot
or a relevant part of the log can help.
