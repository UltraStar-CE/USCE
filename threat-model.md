# USCE threat model

## Operating assumptions

USCE is a desktop karaoke game. The user runs local code with local files and
chooses the songs, media, themes and plugins installed on their computer. This
model treats that installation and its selected content as trusted.

Normal playback uses a local song library. The baseline does not include an
Internet service accepting arbitrary remote requests. Remote exploitation is
therefore not a primary concern for this operating model.

## Song format and local components

Song TXT files use a defined format for metadata, timing, pitches and lyrics.
The parser checks field types and format requirements. Song metadata can also
reference local audio, video, cover and background files. Media libraries handle
playback and image decoding. Local Lua plugins provide executable extensions.

Relevant implementation paths:

- [`src/base/USong.pas`](src/base/USong.pas): song headers and lyric parsing.
- [`src/base/UImage.pas`](src/base/UImage.pas): local image loading.
- [`src/media/UMediaCore_FFmpeg.pas`](src/media/UMediaCore_FFmpeg.pas): media opening.
- [`src/lua/ULuaCore.pas`](src/lua/ULuaCore.pas): local plugin initialization.

## Review priorities

Focus reviews on correct playback, compatible song handling, clear errors,
reasonable resource use and preserving songs, scores and settings. Invalid or
unsupported files should produce useful diagnostics rather than disrupt normal
use. Describe a concrete failure and its effect, with reproduction where possible.
Strict format requirements guide validation; they are not a claim that parser
implementations cannot contain bugs.

Keep repository and build automation in its own scope, as described in
[`AUTOMATION.md`](AUTOMATION.md). Revisit these operating assumptions if future
features introduce remote input or services.

## Optional remote bridge

The optional native phone-audio prototype (`USCE_RAW_AUDIO=1`) adds a direct
WebRTC receiver inside the game. Network callbacks only write bounded signaling
and PCM queues; the game thread consumes PCM for player 1. Frames have fixed
format/size limits, stale audio expires, and duplicate routes share sequence
de-duplication. A malformed signaling message is caught outside gameplay logic.
TLS verification remains enabled. The hosted relay can forward PCM in memory
as fallback; no audio is logged or recorded by this prototype. Only a paired
room's slot 1 is accepted. The room code is the current pairing boundary, not
an identity guarantee. See `docs/native-phone-audio-prototype.md` for experimental
scope and outstanding real-network tests. Normal local play remains unchanged.

The remote bridge is disabled by default. When enabled, the game exchanges
JSONL messages with a configured local adapter for control, pitch input and
game state. The adapter can connect to remote services. This optional feature
extends the local-playback assumptions; its contract is documented in
[`docs/usce-game-bridge-ipc.md`](docs/usce-game-bridge-ipc.md).

In native PCM mode, the existing local bridge accepts raw audio only after
server-side capability/slot/format validation and forwards it through JSONL.
The native ABI bounds incoming signals and PCM; the game bounds outbound IPC
at 128 messages / 32 MiB and writes them from its existing I/O thread so a
stalled bridge cannot block the main audio-consumption loop. Browser PCM is
not subjected to global physical-microphone boost. No microphone recordings
are created by these diagnostics.
