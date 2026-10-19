# Lockdown

Open song search, choose the songs you want available, then select
**Lock current song selection** below the search results. Enter and confirm
a password. The selection can come from AGE, language, tags, text search,
a playlist, or the current category. An empty selection cannot be locked.

Lockdown removes other songs from the active in-memory library. It does not
delete or change song files. Clearing the search, searching again, changing
categories or opening a playlist can only use the reduced library. Newly
discovered files are not added during the session.

Opening Options, entering the editor and quitting require the password,
including closing the game window. Authorizing Options or the editor does not
unlock the library. Navigation within Options does not repeatedly ask for it.

To leave lockdown, open song search and choose **Unlock full song library**.
After a correct password, USCE restores the complete loaded library and
rebuilds its categories, song covers and playlist indexes. The temporary
password is discarded. A wrong password or cancellation leaves the restriction
in place.

Lockdown lasts for the current game process. It does not capture the desktop
or prevent operating-system shortcuts, forced termination or restarting USCE.

Developer check: compile `tools/tests/lockdown_test.pas` with Free Pascal and
`-Fusrc/base`, placing its executable and units in a temporary build directory.
In-game checks should also cover keyboard and mouse activation, password
confirmation/cancellation, Options, editor and window close, playlists and
repeated searches, and restoring the library after singing.
