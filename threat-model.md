# USCE threat model

## Scope and assumptions

USCE is a desktop karaoke application run by a local user. Its normal use is
playing a locally installed song library, not serving requests from arbitrary
Internet clients. The baseline model assumes a trusted application installation,
an uncompromised operating system and execution with ordinary user privileges.
It does not assume that downloading a song gives its author permission to run
code on the user's computer.

Direct remote exploitation is not the main expected risk in this usage model.
Prioritize dependable playback, compatibility, and protection of songs, scores,
configuration and other user files. This is a qualitative model, not an exploit
audit or a guarantee that every input path is safe.

## Inputs and trust boundaries

| Input or component | Trust and expected behavior |
| --- | --- |
| Song TXT files | Structured data with a defined syntax. Parse metadata, timings, pitches and lyrics as data, never as commands. Files downloaded elsewhere remain external input after being copied locally. |
| Song media | Audio, video, covers and backgrounds referenced by the TXT file are also external input. Native media and image libraries decode their contents. |
| Themes and configuration | Local files that influence rendering and file selection. Protect unrelated files and preserve existing user data when loading or saving. |
| Lua plugins and native libraries | Executable extensions installed locally. Treat these as trusted code, not as harmless song data or a security sandbox. |
| Builds, dependencies and updates | Code and binaries that will run with the user's privileges. Their origin and integrity matter independently of song parsing. |
| Repository automation | PR text, issue reports and upstream changes are untrusted inputs. Keep them separate from credentials, publishing permissions and merge decisions. |

The song format is constrained, which reduces the functionality an input can
request. A format specification alone does not establish that every parser
enforces bounds, valid numeric ranges, safe paths and resource limits correctly.
Successful TXT validation also does not validate the referenced media files.

## Relevant failure and abuse cases

1. **Malformed or excessive song data.** Invalid numbers, extreme durations,
   oversized lines or large collections may cause incorrect playback, crashes
   or excessive memory and CPU use. Handle these as robustness issues unless
   there is evidence of a stronger security consequence.
2. **Unexpected file access.** Metadata and configuration can select paths.
   Review a concrete read or write path before claiming traversal or data loss.
   Intentionally configured external song directories are supported behavior,
   not automatically a vulnerability.
3. **Malformed media.** A song pack can exercise image, audio or video decoders.
   Keep dependencies maintained and investigate reproducible decoder faults.
   Do not infer arbitrary code execution from a crash alone.
4. **Untrusted executable additions.** A plugin, library or installer can run
   code locally by design. Do not present installing such code as equivalent to
   importing a TXT song. Running USCE as administrator is outside the normal
   baseline and increases the consequences of a fault.
5. **Compromised build or automation inputs.** A malicious dependency or PR must
   not gain release credentials or execute with a publishing token. AI output
   remains a proposal subject to validation and maintainer review.

## Evidence in the current implementation

- [`USong.pas`](src/base/USong.pas): `ParseLyricIntParam` and
  `ParseLyricFloatParam` use checked conversions and reject invalid values.
  `ReadTXTHeader` also accepts audio, cover, background and video references.
  These are useful checks, not a complete bounds or path safety audit.
- [`UImage.pas`](src/base/UImage.pas): image loading passes file contents to
  SDL_image through `IMG_Load`.
- [`UMediaCore_FFmpeg.pas`](src/media/UMediaCore_FFmpeg.pas): media opening calls
  FFmpeg's `avformat_open_input`.
- [`ULuaCore.pas`](src/lua/ULuaCore.pas): plugins are loaded and executed, and
  `PrepareState` opens the standard Lua libraries. No plugin sandbox is claimed.
- [`AUTOMATION.md`](AUTOMATION.md) describes the separate agent and publisher
  permissions, candidate validation and human merge decisions.

## Review priorities

Start with a reachable input and explain the resulting behavior. Distinguish a
playback error, denial of service, unintended file access and code execution.
For a security finding, identify the entry point, attacker control, relevant
checks, required user action and concrete impact. State uncertainty and any
reproduction performed. Do not turn theoretical parser concerns into claims of
an exploitable vulnerability without evidence.

Prefer focused validation and regression coverage for real failures. Avoid
blanket restrictions that break compatible song libraries without a demonstrated
benefit. Preserve user files when rejecting invalid input or changing formats.

## Outside the baseline and future changes

An attacker who already controls the operating system, application binaries or
trusted plugins is outside the baseline. Ordinary local execution does not
remove the boundary between passive content and executable code.

This document does not establish that all optional or legacy networking features
are disabled, or that native libraries cannot access network protocols. Revisit
the model when changing online downloads, network listeners, remote control,
automatic updates, archive extraction, media protocols, plugin permissions or
privilege requirements. Review new features on their actual data flow rather
than assuming the desktop baseline covers them.
