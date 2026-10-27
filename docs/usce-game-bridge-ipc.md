USCE keeps the upstream wire protocol and bridge script names for compatibility.
The bridge is disabled by default; enable it through the network options when configured.

# USCE game bridge IPC

JSON message contract between USDX and a local bridge process (adapter to remote services).

Out of scope: browser API, relay internals, WebRTC signaling, deployment,
storage, and room hosting.

## Overview

The game talks only to a local adapter process. Everything beyond that adapter
is implementation-specific: a remote-control app, phone web clients, a public
high-score service, a Discord bot, a Jitsi service, or another controller can
all use this boundary.

```text
       remote apps / web clients / bots / services
                         |
                         | adapter-defined protocol
                         v
                +------------------+
                |  local adapter   |
                | usdx-bridge.mjs  |
                +------------------+
                         ^
                         | localhost JSONL IPC
                         v
                +------------------+
                |      USDX        |
                +------------------+
```

Default startup:

```text
USDX
  |
  | if [RemoteBridge] Enabled=On and IPC is not already listening
  v
start bridge command
  |
  v
bridge listens on IpcHost:IpcPort
  |
  v
USDX connects and sends/receives JSON messages
```

Default generated command:

```text
node game/webs/usdx-bridge.mjs \
  --server wss://usdx.at/ws/host \
  --ipc-host 127.0.0.1 \
  --ipc-port 8765 \
  --mock-song=false \
  --auto-ack=false \
  --auto-assign=false
```

`[RemoteBridge] StartCommand` replaces the generated command. Otherwise
`NodeExecutable`, `BridgeScriptPath`, `ServerUrl`, `IpcHost`, and `IpcPort`
control the generated command.

Steady-state data flow:

```text
adapter -> game:
  bridge.ready / room.created
  remote.players.snapshot / player.*
  control.command
  pitch.batch

game -> adapter:
  game.state / song.select.state
  song.started / song.paused / song.resumed / song.position / song.ended
  song.lyrics / score.snapshot
  player.assigned / ack / error
```

Input flow:

```text
controller input -> control.command -> USDX command dispatcher -> ack
pitch source     -> pitch.batch     -> USDX remote input      -> scoring
USDX song clock  -> song.*          -> adapter/client timing
```

Party mode flow:

```text
external clients vote/configure party mode
          |
          v
adapter selects singers and songs
          |
          v
remote.players.snapshot + song.select + song.start
          |
          v
USDX sings song and reports score.snapshot + song.ended
          |
          v
adapter updates party state and schedules the next round
```

## Transport

The transport must provide ordered, bidirectional, framed UTF-8 JSON objects.
Newline-delimited JSON over localhost TCP is valid.

Every message is a JSON object with a string `type`.

All `*Us` fields are integer microseconds.

Common fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `displayCode` | string | Join code shown to users. |
| `playerId` | string | Opaque remote player id. |
| `slot` | number | 1-based USDX player slot. Slot 1 maps to game player index 0. |
| `role` | string | `singer` or `controller`. |
| `songSeq` | number | Song attempt id. Increment on every new song/restart. |
| `mediaStartUs` | number | Song media position. |
| `durationUs` | number | Song duration. |
| `hostSongStartUs` | number | Adapter monotonic timestamp for song position 0. |

## Adapter To Game

### Connection And Room

| Type | Required fields | Effect |
| --- | --- | --- |
| `bridge.ready` | `displayCode`, `hostMonoUs` | Adapter is connected; game may show `displayCode`. |
| `bridge.pong` | `hostMonoUs` | Reply to `bridge.ping`. |
| `bridge.disconnected` | | Clear room status and remote input state. |
| `room.created` | `displayCode`, `expiresAt` | Set active join code. |
| `room.resumed` | `displayCode`, `expiresAt` | Same as `room.created`. |

Example:

```json
{ "type": "room.created", "displayCode": "ABCD", "expiresAt": 1770000000000 }
```

### Player State

Preferred full roster update:

```json
{
  "type": "remote.players.snapshot",
  "gamePlayerCount": 3,
  "players": [
    {
      "playerId": "p_opaque",
      "name": "Lava",
      "slot": 3,
      "role": "singer",
      "connected": true,
      "difficultyMode": "hard",
      "difficulty": "hard",
      "avatarId": "avatar_id",
      "avatarFile": "avatar_file.webp",
      "micDelayMs": 0
    }
  ]
}
```

Rules:

- `players` is the complete remote roster.
- Omitted players are removed.
- `slot: 0` means unassigned.
- `gamePlayerCount` is the desired game player count.
- Unoccupied slots use no remote player, medium difficulty, and default avatar.

Incremental player messages:

| Type | Effect |
| --- | --- |
| `player.joined` | Add or update a player. |
| `player.assigned` | Add/update slot, role, and profile. |
| `player.disconnected` | Mark disconnected, keep identity. |
| `player.left` | Remove player. |

Player fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `name` | string | Display name. |
| `connected` | boolean | Connection state. |
| `difficultyMode` | string | `easy`, `medium`, `hard`, or `free`. |
| `difficulty` | string or number | Effective difficulty. |
| `avatarId` | string | Persistent avatar id; empty means default. |
| `avatarFile` | string | Adapter-visible avatar filename; empty means default. |
| `micDelayMs` | number | Remote player mic delay in milliseconds. Applied only to that player's remote pitch frames. |

### Pitch

`pitch.batch` sends detected pitch, not audio.

```json
{
  "type": "pitch.batch",
  "playerId": "p_opaque",
  "slot": 1,
  "role": "singer",
  "songSeq": 17,
  "batchSeq": 42,
  "baseSongTimeUs": 12000000,
  "frameDurUs": 10000,
  "frames": [
    [0, 6900],
    [10000, 6912]
  ]
}
```

The game ignores the batch if `slot` is invalid or `frames` is not an array.

Frame layout:

| Index | Type | Meaning |
| --- | --- | --- |
| `0` | number | Delta song time in microseconds. Add `baseSongTimeUs` if present. |
| `1` | number | Pitch in cents. MIDI note 69/A4 is `6900`. |

Every accepted frame is a valid tone observation.

### Control

```json
{
  "type": "control.command",
  "playerId": "p_opaque",
  "slot": 1,
  "role": "controller",
  "commandId": 123,
  "command": "menu.select",
  "args": {},
  "clientIssuedUs": 123456000
}
```

The game executes valid commands for the current state and answers with `ack`.

Command arguments:

| Argument | Type | Meaning |
| --- | --- | --- |
| `text` | string | Search text or playlist name. |
| `songIds` | number[] | Song ids to add to a playlist. |
| `playlistIndex` | number | Zero-based playlist index. |
| `songId` | number | Song id. |
| `index` | number | Generic zero-based index. Used like `playlistIndex` when no dedicated field exists. |
| `itemIndex` | number | Zero-based playlist item index. |

Command reference:

| Command | Valid state | Effect | Example |
| --- | --- | --- | --- |
| `menu.up` | Any menu screen | Move selection up. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1001,"command":"menu.up","args":{}}` |
| `menu.down` | Any menu screen | Move selection down. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1002,"command":"menu.down","args":{}}` |
| `menu.left` | Any menu screen | Move selection left or decrease the focused option. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1003,"command":"menu.left","args":{}}` |
| `menu.right` | Any menu screen | Move selection right or increase the focused option. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1004,"command":"menu.right","args":{}}` |
| `menu.select` | Any menu screen | Activate the focused item. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1005,"command":"menu.select","args":{}}` |
| `menu.back` | Any menu screen | Go back/cancel. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1006,"command":"menu.back","args":{}}` |
| `game.pause` | Singing | Pause the active song if not already paused. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1007,"command":"game.pause","args":{}}` |
| `game.resume` | Singing | Resume the active song if paused. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1008,"command":"game.resume","args":{}}` |
| `song.skipIntro` | Singing | Skip to the first playable note. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1009,"command":"song.skipIntro","args":{}}` |
| `song.restart` | Singing | Restart the active song. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1010,"command":"song.restart","args":{}}` |
| `song.menu` | Song select | Open the song menu. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1011,"command":"song.menu","args":{}}` |
| `song.playlistMenu` | Song select | Open playlist controls. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1012,"command":"song.playlistMenu","args":{}}` |
| `song.jumpTo` | Song select | Open jump-to/search UI. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1013,"command":"song.jumpTo","args":{}}` |
| `song.random` | Song select | Select a random visible song. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1014,"command":"song.random","args":{}}` |
| `song.select` | Song select | Select a visible song by id. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1015,"command":"song.select","args":{"songId":123}}` |
| `song.start` | Song select | Start the currently selected song. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1016,"command":"song.start","args":{}}` |
| `song.skip` | Singing | Finish/skip the active song. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1017,"command":"song.skip","args":{}}` |
| `preview.start` | Song select | Start preview playback for the selected song. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1018,"command":"preview.start","args":{}}` |
| `preview.stop` | Song select | Stop preview playback. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1019,"command":"preview.stop","args":{}}` |
| `search.setText` | Song select | Set song-search text. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1020,"command":"search.setText","args":{"text":"queen"}}` |
| `playlist.load` | Song select | Load/select a playlist by index. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1021,"command":"playlist.load","args":{"playlistIndex":0}}` |
| `playlist.create` | Song select | Create a playlist named by `text`. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1022,"command":"playlist.create","args":{"text":"Party"}}` |
| `playlist.delete` | Song select | Delete a playlist by index. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1023,"command":"playlist.delete","args":{"playlistIndex":0}}` |
| `playlist.removeItem` | Song select | Remove one playlist entry by playlist index and item index. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1024,"command":"playlist.removeItem","args":{"playlistIndex":0,"itemIndex":2}}` |
| `playlist.addSelected` | Song select | Add the currently selected song to a playlist. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1025,"command":"playlist.addSelected","args":{"playlistIndex":0}}` |
| `playlist.removeSelected` | Song select | Remove the currently selected song from a playlist. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1026,"command":"playlist.removeSelected","args":{"playlistIndex":0}}` |
| `playlist.addSongs` | Song select | Add all valid `songIds` to a playlist. Existing items are skipped. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1027,"command":"playlist.addSongs","args":{"playlistIndex":0,"songIds":[123,456]}}` |
| `playlist.removeSong` | Song select | Remove a song from a playlist by song id. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1028,"command":"playlist.removeSong","args":{"playlistIndex":0,"songId":123}}` |
| `playlist.moveItemUp` | Song select | Move one playlist entry one position earlier. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1029,"command":"playlist.moveItemUp","args":{"playlistIndex":0,"itemIndex":2}}` |
| `playlist.moveItemDown` | Song select | Move one playlist entry one position later. | `{"type":"control.command","playerId":"p1","slot":1,"role":"controller","commandId":1030,"command":"playlist.moveItemDown","args":{"playlistIndex":0,"itemIndex":2}}` |

Commands outside their valid state are acknowledged with `accepted: false`.

### Adapter Error

```json
{
  "type": "error",
  "code": "join.bad_code",
  "reason": "optional text",
  "source": "adapter"
}
```

## Game To Adapter

### Connection

```json
{ "type": "bridge.ping" }
```

Adapter replies with `bridge.pong`.

### Game State

```json
{
  "type": "game.state",
  "seq": 18,
  "state": "song_select",
  "songSeq": 0,
  "players": [
    {
      "slot": 1,
      "playerId": "p_opaque",
      "name": "Lava",
      "connected": true,
      "singing": true,
      "role": "singer"
    }
  ],
  "controllerPlayerId": "p_opaque",
  "playlistSize": 0
}
```

Treat as state, not an event stream. Known `state` values:

```text
boot lobby song_select singing paused song_ended
```

### Song Select State

Current song-selection UI state. Not a full song catalog transfer.

```json
{
  "type": "song.select.state",
  "selectedSongId": 123,
  "currentSong": { "songId": 123, "artist": "Artist", "title": "Title" },
  "visibleSongs": 30,
  "totalSongs": 28223,
  "searchActive": true,
  "playlistActive": false,
  "results": [],
  "playlists": [],
  "playlistItems": [],
  "curPlaylist": 0
}
```

Playlist summaries may include `fixedOrder`.

### Song Clock

`song.started`:

```json
{
  "type": "song.started",
  "songSeq": 17,
  "songId": 123,
  "mediaStartUs": 0,
  "durationUs": 210000000,
  "title": "Title",
  "artist": "Artist",
  "hostSongStartUs": 1234500000
}
```

These share `songSeq`, `mediaStartUs`, and `durationUs`:

| Type | Meaning |
| --- | --- |
| `song.paused` | Song paused. |
| `song.resumed` | Song resumed. |
| `song.position` | Clock correction. |
| `song.ended` | Song ended; includes final `players` scores. |

`song.ended`:

```json
{
  "type": "song.ended",
  "songSeq": 17,
  "mediaStartUs": 210000000,
  "durationUs": 210000000,
  "players": [
    { "slot": 1, "score": 5000, "scoreLine": 1200, "scoreGolden": 300, "scoreTotal": 6500 }
  ]
}
```

### Lyrics

```json
{
  "type": "song.lyrics",
  "songSeq": 17,
  "mediaStartUs": 0,
  "tracks": [
    {
      "track": 0,
      "line": 4,
      "text": "lyrics",
      "lineStartUs": 12000000,
      "lineEndUs": 15000000,
      "notes": [],
      "nextLines": []
    }
  ]
}
```

### Scores

`score.snapshot` reports current scores for all game player slots. USDX sends
one when singing starts and throttled updates while singing. Consumers that only
need final results can read `song.ended.players`.

```json
{
  "type": "score.snapshot",
  "songSeq": 17,
  "mediaStartUs": 43000000,
  "durationUs": 210000000,
  "players": [
    {
      "slot": 1,
      "score": 5000,
      "scoreLine": 1200,
      "scoreGolden": 300,
      "scoreTotal": 6500
    }
  ]
}
```

### Party Mode

Party mode is adapter-owned at this boundary. The adapter drives USDX with the
same game-facing messages as normal play:

| Direction | Messages |
| --- | --- |
| Adapter to game | `remote.players.snapshot`, `control.command` with `song.select`, `song.start`, `song.skip` |
| Game to adapter | `song.started`, `song.ended`, `score.snapshot`, `game.state` |

Party adapter sequence:

```text
1. Send `remote.players.snapshot` with the singers assigned to USDX slots.
2. Send `control.command` `song.select` with `args.songId`.
3. Send `control.command` `song.start`.
4. Watch `game.state`, `song.started`, and `score.snapshot`.
5. On `song.ended`, read `players` for final scores.
6. Send `control.command` `song.skip` only when aborting/skipping the active song.
```

USDX does not receive party votes, matchmaking state, leaderboard state, or
phone notifications over this API.

### Replies

`player.assigned` confirms a slot:

```json
{ "type": "player.assigned", "playerId": "p_opaque", "slot": 1, "role": "singer" }
```

`ack` confirms a command:

```json
{
  "type": "ack",
  "playerId": "p_opaque",
  "commandId": 123,
  "accepted": true,
  "reason": null,
  "gameStateSeq": 18
}
```

Use `accepted: false` with `reason` when the command was understood but not run.

## Errors

```json
{
  "type": "error",
  "code": "message.invalid",
  "reason": "optional text",
  "source": "game_or_adapter"
}
```

Recommended codes:

| Code | Meaning |
| --- | --- |
| `message.unknown_type` | Unknown `type`. |
| `message.invalid` | Invalid shape. |
| `command.rejected` | Valid command rejected in current state. |

### Paged song metadata queries

The native adapter accepts `song.list` through the existing `control.command`
envelope. This is a game capability for any authorized client, independent of
frontend type. The relay applies its normal command permission policy; an app
name does not grant access. Forwarding destination policy belongs to the
connection configuration, not to this song query.

Request example:

```json
{"type":"control.command","protocol":1,"commandId":42,"command":"song.list","args":{"offset":0,"limit":100}}
```

The targeted `ack` has `accepted`, `reason` and `data`. Successful `data` contains
`snapshotId`, `total`, `offset`, `limit` and `songs`. IDs are the game's existing
song IDs. Metadata excludes local audio, cover, TXT and file paths. The caller
may pass `snapshotId` on subsequent pages. A changed snapshot returns
`accepted:false` with `reason:"snapshot_changed"`; restart paging from zero.
Offsets must be nonnegative integers and limits must be integers from 1 to 100.
Malformed pagination returns `invalid_page`. A non-string snapshot ID returns
`invalid_snapshot`.

The game initializes the snapshot after library loading, independently of the
active screen. A cached `api.state` event advertises `apiCapabilities`, the
`libraryHash`, `totalSongs`, `playlists`, `playlistItems` and `curPlaylist`.
It never includes private file paths or changes the current game screen.
Song-selection updates refresh this metadata; joining clients receive it even
before song selection has been opened.

The `continuous.start` capability works from the main menu or song selection.
Remote queues use library song IDs, independently of which songs are visible
in the current folder/search; category entries are not playable. Normal
continuous-mode player setup, results and highscore timing still apply.
The query itself does not implement media transfer, votes or playlist mutation;
those retain their separate commands and game-state restrictions.
