# Native phone microphone integration

The game owns room registration, controls, generic song queries, playlists,
media transfers and PCM reception. It starts no local Node process or HTTP
server. The web app and hosted relay remain JavaScript; hosted Node is allowed.
USCE PR #168 contains the game/API/native changes, with web/service work in the
separate usrelay PR. The in-process Pascal client is the default when
RemoteBridge is enabled; no USCE_NATIVE_RELAY environment flag is required.

`URemoteRelaySocket` provides a bounded, TLS-verified outgoing WebSocket.
`URemoteRelaySession` handles registration, heartbeats and reconnect/resume.
Hosted Party delegates playback and screen timing to the game's continuous mode.
`python3 tools/test_native_relay.py` runs the Pascal/native loopback regressions.
Existing platform builds run native tests on Windows, Linux and Intel/ARM macOS;
the Linux job also runs the Pascal suites. Full feature readiness remains unproven.

### Idle digital calibration

An authenticated `audio.calibration.request` applies only to the requesting
player's mic. The game supplies a four-second up/down ladder and monotonic start
time, then fits observations from its own pitch detector. Fits include clock and
game-frame uncertainty; weak, stalled or interrupted measurements are rejected.

Normal packets are UAP1; calibration packets are UAC1. Both have bounded 980-byte
framing, sequence numbers and sample clocks, but use separate receiver queues,
polling functions and capture buffers. Test tones cannot enter microphone
metering, singing or scoring, or confirm microphone delivery. Normal capture
continues during calibration.

Compensation replaces the global baseline for the calibrated input and adds the
per-player trim once. Hardware/browser capture buffers are excluded. Automatic
browser triggering/display and compensated-gameplay validation remain unfinished.

### Alternating-note alignment experiment

A 20-second owned fixture alternates C2/F2 every second from song time 2 s.
The browser's optional alignment source generates PCM without capture devices.
`USCE_AUDIO_ALIGNMENT_TRACE=1` logs each actual scoring decision, its pitch,
expected note, both configured offsets, native queue diagnostics and the latest
consumed source sample counter. It does not record audio samples.

The test must follow the game's scoring clock rather than assuming the audio
playback clock is identical. Native score snapshots expose `scoringSongTimeUs`
with `hostStateUs` captured by the game thread. `TLyricsState.FrameTime` records
the same time used by UpdateBeats; reading diagnostics does not call the
stateful lyric synchronization routine again. The I/O thread preserves these
captured timestamps rather than replacing them after queueing.

Actual Windows/browser tests at 4096/CAMDF, Direct WebRTC, global delay 0 ms:

| Clock reference | Player offset | Matched scoring decisions |
| --- | --- | --- |
| Playback clock, initial experiment | 0 ms | 109 / 128 |
| Scoring clock | 0 ms | 127 / 128, twice |
| Scoring clock | +20 ms | 128 / 128, twice |

The +20 ms run showed 10,000 points in the normal browser app. This is a useful
scoring trim for the tested synthetic path, not a general input-latency default
or a one-way transport measurement. The initial clock mismatch invalidates
using its late transitions as a calibration estimate. At this song's tempo the
scoring decisions are 125 ms apart and already use a half-beat reference.

Idle digital calibration and its latency/compensation indicator are still to
be implemented. The intended correction is per device/player, accounting for
the existing global baseline: player trim = desired total compensation minus
global compensation. This prevents compensating the same delay twice or moving
other inputs. Physical capture delay is outside this requested calibration.

## What is implemented

The phone AudioWorklet emits 10 ms packets of mono signed 16-bit PCM at 48 kHz
(about 784 kbit/s before network overhead). The native module uses libdatachannel
for WebRTC and secure relay WebSockets. Pascal polls a bounded queue on the game
thread and submits PCM to `TCaptureBuffer`, using the existing game pitch detector
and scoring path. Network callbacks do not call game objects.

Integrated mode has twelve independent native receiver contexts, one per remote
mic slot. Assignment selects the matching game capture buffer. Local devices
retain their assignments and remote users cannot claim occupied local slots.
The game derives its player count from the highest assigned input (including
local slots through 24); no assigned input means zero players. Native audio is
neither played through the speakers nor added to the debug recording buffer.

The existing hosted service is `usdx.service` on `ssh g2www`, running Node from
`/var/www/usdx`. Apache proxies `usdx.at` and `/ws/{host,client}` to port 8080.
Use `https://usdx.at/` for integrated feature tests. The isolated
`/raw-audio-prototype/index.html` remains a developer tool. `ultrastar.at`
routing is not changed.

## Trying the prototype

The integrated packages include the native library and its dependencies. For a
developer build, build the module below and place it beside the executable.
Normal integrated startup needs no audio environment flags. Optional diagnostics:

```text
USCE_RAW_AUDIO=1
USCE_AUDIO_WINDOW=4096
USCE_AUDIO_DETECTOR=camdf
USCE_AUDIO_DIAGNOSTICS=1
```

For integrated testing set `[RemoteBridge] Enabled=On`, start the game, and enter
its room code in the normal phone app. Choose an available mic slot and tap
Start Mic. The Pascal relay handles controls and game state; the native receiver handles PCM. Standalone receiver testing instead uses
`Enabled=Off` and the isolated prototype page. Both devices need internet access.
The game uses its ordinary local song library.

`USCE_RAW_AUDIO_RELAY` overrides the host URL (`wss://usdx.at/ws/host`).
`USCE_RAW_AUDIO_ICE` overrides the ICE server URI. TURN credentials, if used,
belong in the URI format supported by libdatachannel. The prototype page exposes
its corresponding connection settings. `USCE_RAW_AUDIO_LIBRARY` overrides the
native library's absolute path. TLS verification remains enabled.

Normal game behavior remains 4096 samples with CAMDF unless these experimental
environment settings are supplied. `USCE_AUDIO_WINDOW` also allows 1024 for
comparison. `USCE_AUDIO_DETECTOR=amdf` selects the existing non-circular AMDF;
otherwise the existing CAMDF is retained. The prototype corrects short-window
indexing so analysis reads the newest samples, not the old front of the ring.

## P2P confirmation and fallback

The phone sends the same numbered PCM packets over both routes while probing
P2P. The native queue de-duplicates them. Once valid direct audio reaches the
receiver and the game polls audio, the receiver acknowledges through the direct
channel. Only that acknowledgment stops the server copy. An open connection
alone does not stop fallback. The direct path stays probed while server audio is
active; acknowledgments expire after 250 ms. A closed/failed channel resumes
server sending immediately. A silent path failure may therefore lose up to about
250 ms before fallback resumes; seamless crossfade/replay is not implemented.

The page's **Force server route** checkbox permits a live comparison without
changing the audio sequence. Server fallback uses authenticated room/player
identity and accepts only bounded PCM-v1 frames for a room advertising `rawPcmV1`.
The server processes audio in memory and forwards it; this is not end-to-end
encryption through the server. Direct WebRTC does not send audio through it.

## Latency measurements

The page reports packet counts, server/direct routing, send backlog, application
round trip, and the selected ICE candidate types. The native status reports
packet intervals, queue depth/high-water mark, late/duplicate packets, gaps,
sample drops, and maximum game polling interval.

With `USCE_AUDIO_DIAGNOSTICS=1`, `Audio timing` log lines cover physical as well
as phone inputs: sample rate, callback block duration, analysis window duration,
time since the latest input, pitch-analysis CPU time, and detected note.
`Native audio timing` lines add the receiver's transport diagnostics.

These are stage measurements, not mouth-to-screen latency. Browser/USB hardware
buffering, audio input processing, rendering, output delay, and scoring offsets
need separate measurement. A configured 200-300 ms mic offset is not proof that
the microphone transport alone takes that long. True end-to-end calibration
still needs a shared acoustic/electrical stimulus and an external timing reference.

## Build the native module

Requires CMake 3.24+, a C++17 compiler, OpenSSL development files, and Git.
Dependencies are pinned to libdatachannel v0.24.6's commit and nlohmann/json 3.12.0's
verified archive hash. The module has no WebRTC media codec dependency: it sends
uncompressed samples over data channels. An Opus/media-track comparison is future work.

```sh
cmake -S native/phone-audio -B build/phone-audio -DCMAKE_BUILD_TYPE=Release
cmake --build build/phone-audio --parallel 3
ctest --test-dir build/phone-audio --output-on-failure
node --test tools/tests/phone_audio_worklet.test.cjs
```

Windows: use MSYS2 UCRT64 GCC/CMake/Ninja/OpenSSL; bundle `usce-phone-audio.dll`
with its compiler runtime DLLs. OpenSSL is linked statically by default; builds
overriding that option must also provide its runtime libraries. Linux: bundle/find
`libusce-phone-audio.so` and its matching runtime libraries. macOS: build separately
for Intel and ARM and bundle `libusce-phone-audio.dylib`, fixing dependency install
names/rpaths and signing it with the app. The CI matrix compiles/tests the native
module on all four targets; passing local Windows tests is not a claim that the
other targets have been tested on real hardware or that release packaging is done.

`tools/tests/phone_audio_receiver.pas` tests the Pascal/native ABI independently.
`phone_audio_pitch_test.pas` uses the actual game buffer/detector. Compile it with
the same unit/include/library paths as the game. `--live` runs a two-minute room
receiver; `--benchmark` measures a chromatic sine sweep and one synthetic note
transition; `--low-window` compares 65 Hz at 12 phases for three harmonic shapes.

## Evidence and limits

On Windows, the hosted browser test sent a 440 Hz tone into the compiled Pascal
receiver and the actual game detector, reporting A4. A roughly 94-second run
received 4,508,160 samples, with no sequence gaps or queue drops. The selected ICE
pair was host-to-host on this machine. This is a same-machine transport test,
not a real phone/Wi-Fi or cross-NAT test.

At 65 Hz, the synthetic phase/harmonic tests produced:

| Samples | Window at 48 kHz | CAMDF correct | AMDF correct |
| --- | --- | --- | --- |
| 512 | 10.7 ms | 0/36 | 0/36 |
| 1024 | 21.3 ms | 0/36 | 36/36 |
| 2048 | 42.7 ms | 12/36 | 36/36 |
| 4096 | 85.3 ms | 36/36 | 36/36 |

This supports testing 2048 + AMDF; it does not establish real-voice reliability
at 1024. The current search range starts at C2, about 65.4 Hz. Frequencies below
that range can produce harmonics or wrong notes and need a separate range change.
The baseline detector also chose A4 for a pure 880 Hz tone in one test, illustrating
its existing octave ambiguity. The analysis window has been 4096 samples since
at least the imported November 2015 snapshot; the May 2019 refactor retained it.

The hosted 65 Hz test also reached the real detector as C2 using 2048 + AMDF.
Server-only transport ran for about 77 seconds without reported sequence gaps or
queue drops. A subsequent automatic handover sent 28 server packets before P2P
was acknowledged; the server count then stopped while direct audio continued.
That run reported five sequence gaps and six late/duplicate packets during
startup/handover. These are recorded limitations, not a claim of seamless routing.

This prototype preserves the bridge's catalog, controls, lyrics and media
streaming. Party matchmaking now queues songs through the game's continuous
playback controller, which owns transitions and results. There is no adaptive
jitter/clock-drift correction or microphone audio playout.
Real microphone tests, cross-NAT/TURN tests, packet-loss tests, alignment with
song timing, low-voice recordings with explicit consent, and macOS/Linux hardware
tests remain required before considering it a supported feature.

## Route warning and rolling analysis

A fixed amber triangle with “Via server” stays visible on the prototype phone
page while direct PCM has no receiver acknowledgment younger than 250 ms.
An open data channel alone does not hide it. Forced fallback and acknowledgment
expiry restore it. The normal web app keeps a Direct / Via server corner badge.
The global game overlay shows only the room URL. Player cards have compact
local, direct Wi-Fi or server Wi-Fi badges on setup, singing and results screens.
Native diagnostics report the actual receiving route for testing. A confirmed
TURN candidate pair still counts as a server route.

The capture buffer already holds a rolling history: each callback appends new
samples and analysis reads the newest selected window when scoring requests it.
It does not wait for non-overlapping 2048/4096-sample blocks. It currently shifts
samples rather than maintaining circular indices. A ring buffer can reduce
copying and, with a snapshot outside the capture lock, callback contention;
it does not itself change the observation time needed for pitch detection.
At 48 kHz, 2048 samples span 42.67 ms and their average age is about 21.33 ms.
That average age is not a worst-case bound on recognizing a changed pitch.
The next latency experiment should separate window length from analysis hop,
produce timestamped overlapping estimates, and align them with scoring time.
No ring-buffer or scoring-timeline change is included in this prototype update.

## Integrated normal web app

### Player input badges

Setup, singing and results use a filtered, antialiased badge inside the avatar
bounds. Unassigned slots display the existing translated "None" label, while
saved local names stay intact. A remote Mic 2 assignment creates two slots;
only slot 2 carries the phone's name and Wi-Fi badge.

Themes can define shared defaults in `[InputSourceBadge]` and override them in
`[NameInputSourceBadge]`, `[SingInputSourceBadge]` and `[ScoreInputSourceBadge]`:

```ini
[InputSourceBadge]
Visible=1
Size=16
Inset=3
Corner=TopRight
Alpha=1
Red=1
Green=1
Blue=1
ServerRed=1
ServerGreen=0.77
ServerBlue=0.2
```

Size and inset use the theme's layout coordinates and are clamped to fit the
avatar. Corner accepts TopLeft, TopRight, BottomLeft or BottomRight. Badges follow
avatar visibility and opacity. Optional `LocalTexture`, `DirectTexture` and
`ServerTexture` keys name skin textures, replacing the built-in glyphs. Theme
inheritance applies to these sections like other theme sections.

### Screen-share test audio

The normal phone app offers 65, 220 and 440 Hz synthetic PCM under Settings,
Advanced microphone and timing. It opens neither microphone capture nor an
AudioContext, allowing Android screen sharing to remain active. Generated packets
use the same sender, direct acknowledgment/fallback and native game receiver as
real capture. The visible TEST AUDIO label stays on while active; Stop audio
ends generation, and reload resets the choice. Synthetic runs measure transport
and game processing, excluding hardware capture and the browser audio graph.

For feature testing, enable RemoteBridge in the test configuration and start
normally; the Pascal relay and native receiver are the defaults.
Use normal https://usdx.at, join the shared room, select an available Mic and Start Mic.
There is no second room or separate phone UI. Controls, song browsing, playlists,
lyrics and device playback keep their existing routes. All twelve remote slots
use native PCM with this game build. The
phone shows level and capture status, with no pitch/confidence decisions. Its
native-rate capture is resampled to the 48 kHz wire format. The native channel carries unreliable PCM;
room/control/clock messages use the outgoing Pascal relay WebSocket.

The native C ABI accepts optional bounded external JSON signaling (ipc://),
and exposes outgoing WebRTC events to the Pascal main loop. The Pascal relay
forwards authenticated server PCM and signaling to its matching native context. Pascal scores each
assigned slot from its own capture buffer, including remote player profiles.
Standalone hosted-room mode remains available for isolated developer tests.

Phone PCM bypasses the global physical-microphone boost. A user's USB +18 dB
setting must not multiply phone samples by eight and clip them. For the next
real-voice comparison the installed test launcher uses the normal 4096/CAMDF
baseline. 2048/AMDF remains an optional synthetic-tested experiment; the earlier
65 Hz tests do not establish real-voice reliability.

Live control responsiveness: unchanged preview clocks reuse the in-memory
catalog, hidden song lists do not render, retained bridge state rows are cloned
without deep-copying the complete catalog, and oversized state updates omit
catalog rows rather than dropping the clock/selection. Full catalogs continue
through their existing chunked transfer. Pascal uses a string stream to build
full library snapshots instead of repeatedly copying their growing strings.

Device playback no longer targets a temporary 500 ms startup lead. Large drift
can recover after startup through a guarded seek (no overlapping seeks and a
2 s cooldown); smaller drift uses bounded rate correction, checked every 250 ms.
These policy tests pass; physical-phone seek duration and audible sync still
need user testing. No microphone recording was created for this investigation.
Native-audio mode queues outbound JSONL messages for the existing I/O thread
(maximum 128 messages / 32 MiB), with a 20 ms read poll interval. The game thread
never performs the potentially blocking socket write. The paused-reader
regression submits an 8 MiB message to a deliberately non-reading loopback
bridge and requires the caller to return within 250 ms; it returned below the
clock's millisecond resolution on the Windows test machine. This protects the
game's PCM polling from bridge write backpressure. Full catalog construction
and game rendering can still consume frame time, so real-run stalls remain
measured rather than claimed eliminated.
