# Native remote API

USCE connects directly to the hosted relay through its Pascal client and bundled
native transport. This contract serves any authorized frontend; the catalog is
one consumer. No local Node adapter is required. Messages use `protocol: 1` and
a `type`; internal unit names retaining IPC terminology do not imply a process.

## Connection and authority

`URemoteRelaySession` registers/resumes the game room and sends heartbeats.
`URemoteRelayProtocol` adapts roster/control/media messages and caches state for
reconnect. Game objects are accessed on the game thread; network callbacks use
bounded queues. The game owns its screen, song clock, pitch, scores and inputs.
Relay roster echoes cannot replace the current game screen.

The relay authenticates each room/player, binds audio to the assigned slot and
applies command policy. A room code is a pairing mechanism, not a personal
identity guarantee. Clients cannot choose another player's identity or access
arbitrary local files. Local microphones retain their slot assignments.

## State

| Event | Purpose |
| --- | --- |
| `game.state` | Current screen/sequence and public roster. |
| `api.state` | Screen-independent capabilities, catalog and playlist metadata. |
| `input.state` | Highest occupied input count, assigned local/remote inputs and resolved player palette. |
| `continuous.state` | Native continuous-session activity. |
| `song.select.state` | Selection-screen metadata without defining API availability. |
| `song.started`, `song.paused`, `song.resumed`, `song.position`, `song.ended` | Song lifecycle. |
| `song.lyrics`, `score.snapshot`, `screen.info` | Timed lyrics, scores and screen information. |
| `song.results` | Bounded result journal for missed-ending recovery. |

`api.state` includes `apiCapabilities`, `libraryHash`, `totalSongs`, `playlists`,
`playlistItems`, `curPlaylist` and `playerColors`. `playerColors` is an array of
resolved `#RRGGBB` values indexed by player slot minus one, including unassigned
slots. It follows configured and mixed colors and survives catalog refresh.
Snapshots exclude private song/media paths.

## Commands and replies

```json
{"type":"control.command","protocol":1,"commandId":42,"command":"song.list","args":{"offset":0,"limit":100}}
```

The targeted `ack` contains the same `commandId`, `accepted`, `reason` and any
`data`. Requests must handle rejection, cancellation, disconnect and timeout.
Menu/navigation, playback and playlist commands retain game-state restrictions.
Capabilities describe supported operations; frontend names do not grant access.

`song.list` returns `snapshotId`, `total`, `offset`, `limit` and `songs` in `data`.
Offsets must be nonnegative integers; limits are 1 through 100. Pass `snapshotId`
on subsequent pages. `snapshot_changed` requires restarting at offset zero;
invalid arguments return `invalid_page` or `invalid_snapshot`.

Each entry's numeric `songId` belongs to that catalog snapshot. Its opaque
`catalogKey` distinguishes same-title files and remains stable through sorting,
filtering and playlist reordering within an installation. Moving the file changes
the key. It does not reveal the path or grant access.

## Playlists and continuous playback

Playlist metadata includes `fixedOrder` and complete ordered `items` membership
(`itemIndex`, `songId`). Frontend browsing does not load the playlist into the
game or reorder game IDs. Explicit `playlist.load` acts on song selection.
Create/delete, add/remove explicit songs, move items and toggle fixed order are
available at the main menu or song selection, outside transitions. Edits save
without starting previews; removing the last item retains an empty playlist.
Browsing remains available during gameplay.

`continuous.start` accepts library `songIds` independently of category/search
visibility, from the main menu or song selection. Category entries are not songs.
`continuous.queue`, `continuous.stop` and `continuous.skip` manage the session.
Optional `playerSetupSeconds`, `resultSeconds` and `highScoreSeconds` are seconds:
-1 means Manual, 0 Skip, positive values timed; omitted values use the game's
continuous profile. `songDisplay` and `singingDisplay` use the game option order.
Overrides do not overwrite the saved playback profile.

Hosted Party owns votes/matching and delegates playback stages to this native
continuous API. Votes and played history follow stable catalog keys. A changed
catalog is validated before queue decisions; obsolete requests cannot replace
a newer snapshot.

## Raw audio and calibration

Normal microphone packets use UAP1: bounded mono S16 PCM, 48 kHz, numbered frames
and sample counters. USCE performs pitch detection and scoring. Direct and server
copies overlap until the receiver confirms direct delivery, then fallback stops.
Loss of confirmation restores fallback; duplicate frames are de-duplicated.
TURN remains a server route. Controls continue through the hosted relay.

Authenticated `audio.calibration.request` starts a game-issued four-second note
ladder for the requesting slot. UAC1 calibration packets have separate queues
and capture buffers; they cannot enter microphone metering or scoring, or confirm
the microphone route. Results include accepted delay and uncertainty. A calibrated
input replaces the global delay baseline and adds manual player trim once.
Hardware/browser capture buffers are outside this digital measurement.

## Recovery and bounds

Temporary disconnects retain assignments and scores while obsolete audio frames
are cleared. Reconnect replays authoritative state; stale ACK/signaling cannot
block newer snapshots. The 32-round result journal captures original song-start
singer IDs, stable file identity and final scores, scoped to the continuous
session. Hosted Party waits for fresh API/continuous/results state and deduplicates
replayed rounds before advancing. This is bounded recovery, not persistent history.

Relay receive batches are limited to 128 messages/20 ms, with heartbeats around
draining. Media transfer is chunked, bounded, cancellable and restricted to the
current catalog. Slow-stage diagnostics distinguish relay, output and media work.

## Manual song handoff

With `playerSetupSeconds: -1`, remote continuous playback waits on the normal
player-setup screen. `continuous.handoff` identifies the selected `songId` and
initial configured `singers` (slot/name), including local singers. It is replayed
on reconnect and discarded once the song starts or the session stops.
Each handoff includes a generation `handoffId`; pass it in the confirmation args.
`continuous.confirm` accepts the normal setup action only while this remote
session is waiting on that screen, outside a screen transition or modal popup, and only for that handoff generation. Else it returns
an unsuccessful ACK; it never starts or skips a different song. A successful ACK
still needs the normal `song.started` event before clients show playback.
`apiCapabilities` now uses the native command-name table plus `song.list`, so
frontends can discover supported operations without relying on a UI screen.
