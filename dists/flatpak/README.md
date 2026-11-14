# USCE Flatpak test bundles

The [Flatpak bundle workflow](https://github.com/UltraStar-CE/USCE/actions/workflows/flatpak.yml) builds the pinned USCE release for x86-64 and ARM64. Download the artifact for your architecture and extract it.

```sh
sha256sum -c USCE-x86_64.flatpak.sha256
flatpak install --user ./USCE-x86_64.flatpak
flatpak run io.github.ultrastar_ce.USCE
```

The bundle keeps its settings, playlists, scores and private song folder in
`~/.var/app/io.github.ultrastar_ce.USCE/.usce`. Copy songs to its `songs` subfolder
or pass a path inside the desktop's Music directory, which is accessible read-only.

```sh
flatpak run io.github.ultrastar_ce.USCE -songpath "$(xdg-user-dir MUSIC)/Karaoke"
```

The package uses SDL audio through PulseAudio or PipeWire's PulseAudio service.
It requests network access for optional phone microphones, companion views and
online features. Webcam and projectM support are omitted from these test bundles.

To build locally with Flatpak Builder:

```sh
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak-builder --user --install-deps-from=flathub --repo=flatpak-repo build-flatpak dists/flatpak/io.github.ultrastar_ce.USCE.yml
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo flatpak-repo USCE.flatpak io.github.ultrastar_ce.USCE
```

When advancing the release, update the USCE tag, its commit SHA and the Themes
commit from that tag's `themes.json` together.
