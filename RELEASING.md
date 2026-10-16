# Publishing a USCE release

1. Use a reviewed PR to update VERSION, the Pascal version in UConfig.pas,
   macOS Info.plist, installer version settings, and dists/usce.appdata.xml.
2. Confirm passing Windows, Linux, ARM macOS and Intel macOS CI on the release
   commit. Download and test each artifact, including installation and launch.
3. Verify songs, microphones, configuration reuse, themes and dependency notices.
   Confirm the public MXE dependency pin has a matching reviewed release.
4. Create a USCE tag only after review. Draft a release in UltraStar-CE/USCE
   with the exact source SHA and honest test results. Attach only the matching
   tested artifacts and their checksums. Publish through a human decision.
5. Update the release branch VERSION and installer download naming only when
   the matching USCE installer exists. Never redirect the updater to USDX.

No USCE Flathub, distribution package, website or signing identity is assumed.
The legacy Debian/Gentoo packaging and upstream release history remain source
references until maintained USCE packages are prepared and tested separately.
Preserve upstream credits, copyright notices and dependency licenses.
