# USCE releases

We publish releases through a human decision after review and testing. Successful
CI runs provide development artifacts; they are not automatically releases.

## What a release includes

Version changes arrive in a reviewed PR covering VERSION, UConfig.pas, macOS
Info.plist, installer settings and dists/usce.appdata.xml. We require passing
Windows, Linux, ARM macOS and Intel macOS builds on the release commit, followed
by installation and launch testing of the actual artifacts.

Our release checks include songs, microphones, themes, configuration reuse and
dependency notices. The MXE dependency pin must identify a matching reviewed
release. Published notes identify the exact source SHA, completed testing and
known limitations. Downloads contain only matching tested artifacts and their
checksums, with USCE tags identifying the source revision.

The updater refers to the USCE repository and matching USCE installer names.
Updater metadata changes only when the corresponding installer is available.
We retain upstream credits, copyright notices and dependency licenses.

## Package availability

We have not published a USCE release yet. USCE Flathub packages, distribution
packages and signing identities are not currently available. Historical
Debian/Gentoo recipes and upstream release history remain source references;
distribution-specific USCE packages need their own maintenance and testing.
