# Hardware-assisted video playback

USDX can use libmpv for video decoding and color conversion. This backend is
optional and disabled by default. Song audio and lyrics keep using USDX's audio
clock. The existing FFmpeg backend remains the default.

Build with libmpv development files installed:

```sh
./autogen.sh
./configure --with-mpv
make
```

Enable it in `config.ini` and restart USDX:

```ini
[Graphics]
VideoBackend=mpv
VideoHardwareDecoding=auto
```

`auto` asks libmpv to select a supported hardware decoder. Integrated and discrete
GPUs are supported according to libmpv, the codec, the driver, and the active
graphics context. This setting does not force the integrated GPU or select a
particular adapter. On hybrid systems the graphics adapter is selected by the
OS/driver when starting USDX. Check the actual decoder in USDX's log; selecting
the MPV backend alone does not prove hardware decoding is active.

Use `VideoHardwareDecoding=no` for a software-decoding comparison through the
same backend. Use `VideoBackend=ffmpeg` to restore the original video path.
Unknown values revert to the defaults.

When libmpv is unavailable, USDX selects its normal FFmpeg backend. When opening
a file or creating its render context fails, the MPV provider tries the
lower-priority FFmpeg provider. libmpv also performs its own software fallback
when a hardware decoder cannot handle a file. No hardware path is guaranteed
for every GPU or codec.

## Dependencies and distribution

The backend loads libmpv dynamically, so the regular USDX builds do not acquire
a mandatory runtime dependency. The library must include the OpenGL render API.

| Platform | Runtime library | Packaging |
| --- | --- | --- |
| Linux | `libmpv.so.2` or compatible `libmpv.so.1` | Install the distribution's libmpv package and video drivers. AppImage/Flatpak distributors must include libmpv and its dependencies explicitly. |
| Windows | `libmpv-2.dll` or `mpv-2.dll` | Place an architecture-matching libmpv build and all its dependencies alongside USDX. The MSYS2 UCRT64 mpv package is one source. |
| macOS | `libmpv.2.dylib` or compatible `libmpv.1.dylib` | Install libmpv, or bundle it and its dependencies with suitable loader paths. The existing dependency scanner cannot discover a dynamically loaded library automatically. |

The normal release packaging is unchanged. `--with-mpv=nocheck` is useful for
compiling the optional loader on a target without development metadata; it does
not package or install libmpv. Do not overwrite USDX's existing FFmpeg libraries
with incompatible versions when bundling dependencies.

The renderer uses an offscreen texture, with no fixed 1080p limit. It preserves
the original video presentation, aspect correction, cropping, alpha and
reflections. libmpv handles color conversion. Chroma upsampling uses bilinear
filtering to avoid a reproduced black first frame with libmpv 0.41.0 and Mesa
llvmpipe. Hardware decoding may use direct
GPU textures or copy decoded frames back, depending on the platform and graphics
interop supported by libmpv. This implementation does not force EGL or change
USDX's minimum GL/GLES requirements; unsupported render contexts fall back.

## Validation

Build both `--without-mpv` and `--with-mpv`. Run the independent clock checks:

```sh
mkdir -p build/video-tests
fpc -Fu./src/media -FU./build/video-tests -FE./build/video-tests test/VideoSyncTest.pas
./build/video-tests/VideoSyncTest
make whitespace-check
```

The integration test uses the real renderer and video backends, a generated
H.264 clip, and pixel comparisons for orientation, color, pause, seek, looping,
EOF and fallback:

```sh
python3 test/run-video-smoke.py --renderers gl gl2 gles2 gles3
```

It needs Python 3, an FFmpeg executable with the libx264 encoder, and a display.
On a headless Linux builder, run it under `xvfb-run`. The default checks software
decoding to make failures reproducible. On a physical GPU, add
`--hwdec auto --require-hardware`; this fails unless libmpv reports an active
hardware decoder. `--build-only --output-dir build/video-smoke` creates a
standalone test executable without opening a display or generating a fixture.

On each physical test machine, record the OS, GPU, driver, libmpv version, video
codec/resolution, active hardware decoder, and CPU usage. Compare FFmpeg, MPV
software, and MPV automatic decoding with the same song and settings.

- Play a five-minute song and check video against the lyrics/audio throughout.
- Check positive and negative video gaps, the pre-song transition, pause/resume,
  forward/back seeks, seeking while paused, EOF, and repeated background loops.
- Check a song preview, background video, singing, and jukebox playback. Confirm
  UI text, scissoring, reflections and the second screen still draw correctly.
- Test corrupt media, an audio-only file, and missing libmpv to verify fallback.
- Test both the integrated GPU and the desired discrete/external GPU, selected
  through the platform's normal graphics settings.

WSL software-rendered playback is useful for lifecycle and fallback checks, but
does not establish native Windows or Linux hardware-decoding support.
