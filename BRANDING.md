# USCE product identity and compatibility

The full product name is **UltraStar Community Edition**, abbreviated **USCE**.
The executable is `usce` or `usce.exe`, the macOS bundle is
`UltraStar Community Edition.app`, and build artifacts start with `USCE-`.
Linux desktop metadata and the macOS bundle use `org.ultrastarce.usce`.

The generated identity in `branding/` supplies the application, installer and
package icons. We package PNG sizes, Windows ICO, macOS ICNS and installer BMP
files from the reviewed raster source with `tools/package-usce-icons.ps1`.
`python tools/check-usce-branding.py` checks the platform references.

## Existing user data

Fresh installed builds use `~/.usce` on Linux, `%APPDATA%/usce` when the Windows
game directory is not writable, and `Library/Application Support/UltraStar
Community Edition` on macOS. A legacy config remains in use if it exists and no
new USCE config exists. The macOS song folder similarly keeps an existing legacy
collection discoverable. Portable builds continue using their writable game
directory. No configuration, database or song files are moved or deleted.
The USCE Windows uninstaller targets USCE data paths, not the upstream app's
legacy data folder. We preserve existing configuration and song discovery when
players switch editions.

## Intentional upstream references

The source scan preserves copyright and license headers, historical release
notes, original theme creators, contributor credits, and third-party source.
These are attribution, not claims about the current product name.

The MXE downloader uses a pinned dependency release and the inherited
`usdx-dlls-x86_64` asset identifier. Lua's `Usdx` API, `.usdx` plugin extensions,
translation keys and theme-format identifiers stay compatible with existing
community content. Legacy data-path strings remain only for discovery.

Older Debian/Gentoo recipes and external Flathub identifiers are historical
upstream package references. They do not identify a published USCE package.
We maintain and test distribution-specific USCE packages separately.
The installer updater only refers to the USCE repository; publishing a release
also requires matching installer assets and release metadata.
