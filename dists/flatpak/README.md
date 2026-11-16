# USCE Flatpak test bundles

The [Flatpak bundle workflow](https://github.com/UltraStar-CE/USCE/actions/workflows/flatpak.yml) builds the checked-out USCE commit for x86-64 and ARM64. Download the artifact for your architecture and extract it.

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
online features. projectM visualizations and presets are included.

Select a webcam and enable its preview in USCE to request access through the
desktop's Camera portal. The desktop may remember your choice. This requires a
working Camera portal and PipeWire on the host.
To ask again after denying access, reset the camera permission in your desktop's
privacy settings. You can also reset this app's saved portal permissions with
`flatpak permission-reset io.github.ultrastar_ce.USCE`.

To build locally with Flatpak Builder:

```sh
flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak-builder --user --install-deps-from=flathub --repo=flatpak-repo build-flatpak dists/flatpak/io.github.ultrastar_ce.USCE.yml
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo flatpak-repo USCE.flatpak io.github.ultrastar_ce.USCE
```

Keep the manifest's Themes commit in sync with `themes.json`. For publication,
replace the local Git source with the matching USCE release tag and commit SHA.
