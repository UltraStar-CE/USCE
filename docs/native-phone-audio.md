# Native remote audio runtime

The Pascal relay client and bundled C++ transport run inside USCE. Hosted relay
and web sources live in [usrelay](https://github.com/UltraStar-CE/usrelay).
The game starts no local Node process or HTTP server. The removed JS bridge and
isolated prototype pages are not part of game builds.

## Defaults

Remote connection is Off by default. Enable it in Network settings; the built-in
endpoint is `wss://usdx.at/ws/host`. The game displays a room code for usdx.at.
No server address, environment flag or local runtime setup is needed by players.
`USDX_REMOTE_SERVER` overrides the endpoint for development. The native library
is included in Windows, Linux and Intel/ARM macOS packages.

## Ownership

`URemoteRelaySocket` supplies bounded TLS-verified WebSocket I/O.
`URemoteRelaySession` owns registration, heartbeats and reconnect/resume.
`URemoteRelayProtocol` adapts and caches public API state and media transfers.
The C ABI has twelve independent PCM receiver contexts; the game thread drains
them into existing capture buffers. Local devices retain their assignments.
Pitch/scoring, player counts, continuous playback and theme rendering stay in
Pascal. No input assignments means zero players; a sparse assignment requires
players through the highest occupied local/remote slot.

P2P/server copies overlap until receiver confirmation and are de-duplicated.
Server/TURN routes remain visible in the web app. Automatic idle calibration uses
an isolated game-issued ladder and reports uncertainty; it replaces the global
baseline for that input and adds manual trim once. Hardware and browser capture
buffers are not measured. See the [API reference](usce-game-bridge-ipc.md).

## Building

Requires CMake 3.24+, C++17, OpenSSL development files and Git. CMake pins
libdatachannel and the nlohmann/json archive; dependency notices are staged by
`tools/stage-phone-audio.py`.

```sh
cmake -S native/phone-audio -B build/phone-audio -DCMAKE_BUILD_TYPE=Release
cmake --build build/phone-audio --parallel 3
ctest --test-dir build/phone-audio --output-on-failure
python3 tools/test_native_relay.py
```

Windows packages include `usce-phone-audio.dll` and compiler runtimes. Linux uses
`libusce-phone-audio.so`; macOS builds/signs `libusce-phone-audio.dylib` for each
architecture. OpenSSL is linked statically by default. Existing platform CI
builds/packages the native module and runs the relevant native/Pascal suites.

## Diagnostics and detector experiments

Normal analysis uses 4096 samples/CAMDF. `USCE_AUDIO_WINDOW` and
`USCE_AUDIO_DETECTOR` are developer experiments, not automatic recommendations:
short deep-note windows can cause octave errors. `USCE_AUDIO_DIAGNOSTICS=1` logs
block/window timing, input age, detector time and transport queue/gap/drop data.
`USCE_AUDIO_ALIGNMENT_TRACE=1` records scoring-clock decisions and offsets without
recording microphone samples. Lifetime high-water marks are not per-frame rates.

Direct clock replies use the game's monotonic clock. Network/audio round trips
include their return path and are not compensation values or mouth-to-screen
latency measurements. Remote audio is neither played through speakers nor added
to microphone debug recordings by this integration.
