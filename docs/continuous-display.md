# Singing configuration

Press C in song selection to open Configuration. Continuous mode has its own
on/off selector. Each mode remembers its own display and result settings,
including after restarting the game. Switching modes saves the current settings
and restores the other set.

Song display is available with any number of players:

- Lyrics + progress
- Lyrics only
- Progress only
- Nothing

With singers, Singing display also offers:

- Full: notes, player information, rating popups and singing effects.
- Notes + player info: everything above except rating popups and effects.
- Notes only: note bars, pitch input, guide lines and the configured oscilloscope.
- Player info only: names, avatars and scores.
- Nothing: no player overlays.

These choices also apply to ordinary singing. They do not disable microphones,
scoring or score saving. The normal default remains the full display, with manual
results and highscores. Result screens can independently wait for input (Manual),
be skipped, or remain for 5, 10, 20, 30, 40, 50 or 60 seconds. Manual also works
in continuous mode. Zero-player playback skips results and highscores.

Esc stops a continuous session and returns to the current song in song selection.
It leaves continuous mode enabled; starting another song begins a new session.

Themes can place the song-selection indicator with `SongRouletteTextContinuousStatus`
(and the Chessboard/List equivalents). `TextConfiguration` controls the footer
label, and `StaticContinuousKey` controls its C-key icon. The default indicator
is near the heading; configuration remains in the footer's left third.

For jukebox playback with only the bottom progress bar, choose zero players and
Song display: Progress only. Nothing leaves just the background or video.
