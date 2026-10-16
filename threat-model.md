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
