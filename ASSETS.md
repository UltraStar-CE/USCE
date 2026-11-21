# Assets: sources and licenses

The UltraStar Community Edition code is licensed under GPL-2.0-or-later (see [LICENSE](LICENSE)). The licenses of bundled third-party libraries are in `game/LICENSE.*.txt`.

This file lists the non-code assets in `game/` with their source and license, as far as they are known. Entries marked **unknown** have no recorded source. If you know where one of them comes from, please open an issue or pull request.

Historical commit hashes refer to USDX or, for the SourceForge SVN era (2007–2016), to the [legacy SVN mirror](https://github.com/UltraStar-Deluxe/legacy-sourceforge-svn-mirror).

## Fonts (`game/fonts/`)

| Files | Source | License |
|---|---|---|
| `DejaVu/` | [DejaVu fonts](https://dejavu-fonts.github.io/) | Bitstream Vera license; DejaVu changes are public domain (see `DejaVu/LICENSE`) |
| `FreeSans/` | [GNU FreeFont](https://www.gnu.org/software/freefont/) | GPL-3.0-or-later with font exception (see `FreeSans/COPYING`, `FreeSans/README`) |
| `NotoSans/` | [Go Noto Universal](https://github.com/satbyy/go-noto-universal), based on Google Noto fonts | SIL Open Font License 1.1 (see `NotoSans/LICENSE_OFL.txt`) |

## Sounds (`game/sounds/`)

| Files | Source | License |
|---|---|---|
| `background track.ogg` | DJad, "Walking Alone", via Jamendo (http://www.jamendo.com/de/track/543970). Added to SVN trunk on 2010-10-08 by canni0 as the winner of a background-track vote (SVN mirror commit 1d9027ed, r2644). | CC BY-SA 3.0 (see `background track license.txt`) |
| `dismissed.ogg` | **unknown**. Added to SVN trunk on 2007-05-17 by mota23 ("Added: dismissed sound for party-mode", SVN mirror commit fb785ffe, r202) | **unknown** |
| `Common back.ogg`, `Common start.ogg`, `menu swoosh.ogg`, `option change col.ogg`, `select music change music.ogg`, `select music change music 50.ogg` | **unknown**. Added to SVN branch `1.01` on 2007-10-09 by jaybinks ("these are needed to do a full build.", SVN mirror commit 0a944483, r486). | **unknown** |
| `Applause.ogg` | **unknown**. Added to SVN branch `experimental` on 2009-12-09 by brunzelchen ("added missing file", SVN mirror commit 5196a888, r2012) | **unknown** |

## Theme graphics (`game/themes/`)

| Files | Source | License |
|---|---|---|
| `Modern/[score]rating_0.png` | [Face-monkey.svg](https://commons.wikimedia.org/wiki/File:Face-monkey.svg) by the Tango! Desktop Project, via Wikimedia Commons. Converted to PNG for USDX (2018). | Public domain |
| `Modern/[score]rating_1.png` … `rating_7.png` | GNOME Project emote icons (GNOME icon theme version 3), via Wikimedia Commons: 1 = [Gnome3-wink](https://commons.wikimedia.org/wiki/File:Gnome3-wink.svg), 2 = [Gnome3-glasses](https://commons.wikimedia.org/wiki/File:Gnome3-glasses.svg), 3 = [Gnome3-smile](https://commons.wikimedia.org/wiki/File:Gnome3-smile.svg), 4 = [Gnome3-smile-big](https://commons.wikimedia.org/wiki/File:Gnome3-smile-big.svg), 5 = [Gnome3-laugh](https://commons.wikimedia.org/wiki/File:Gnome3-laugh.svg), 6 = [Gnome3-surprise](https://commons.wikimedia.org/wiki/File:Gnome3-surprise.svg), 7 = [Gnome3-devilish](https://commons.wikimedia.org/wiki/File:Gnome3-devilish.svg). Converted to PNG for USDX (2018). | Wikimedia Commons lists two licenses: [CC BY-SA 3.0 US](https://creativecommons.org/licenses/by-sa/3.0/us/) and [LGPL-3.0-or-later](https://www.gnu.org/licenses/lgpl-3.0.html). The PNG versions are distributed under the same licenses. Attribution: "GNOME Project". |

## Avatars (`game/avatars/`)

| Files | Source | License |
|---|---|---|
| `female1.jpg` … `female10.jpg`, `male1.jpg` … `male10.jpg` | **unknown**. Not in the SourceForge SVN history; first appear in the git import of 2015-11-13 (commit c4fc4aaf, "codebase of USDX V1.2 trunk (alpha)") | **unknown** |

## Visualizer presets (`game/visuals/projectM/presets/`)

| Files | Source | License |
|---|---|---|
| `*.milk` (about 250 files) | MilkDrop presets by community authors (Rovastar, Aderrasi, Geiss, Fvese, Krash and others; the author is part of each file name) | No license statement in the files |

## Scope

The Modern rating icons listed above are inherited from USDX. USCE also packages a pinned Themes bundle. This inventory does not assign licenses to other theme assets or to files with undocumented provenance.
