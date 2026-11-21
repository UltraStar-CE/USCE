; ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~
; UltraStar Community Edition Un/Installer: Variables
; ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~ ~+~

; Product Information:

; Generated version values are shared with the game and platform packages.
!include "${path_settings}\version.nsh"

!define installername " Installer"
!define installerexe "USCE_v${VersionStr}${ReleaseMeta}_installer"


; generated
!define version "${VersionStr}${ReleaseApp}"
!define meta StrLower($version)


!define name "UltraStar Community Edition"
!define publisher "USCE contributors"
!define homepage "https://github.com/UltraStar-CE/USCE"
!define song_editors "https://open-music-games.org/song-editors/"
!define forum "https://github.com/UltraStar-CE/USCE/issues"
!define wiki "https://github.com/UltraStar-CE/USCE"

!define exe "usce"
!define exeuninstall "Uninstall"
!define exeupdate "Update"

!define license ".\dependencies\documents\license.txt"
!define music1 ".\dependencies\loop.wav"
!define music2 "$PLUGINSDIR\loop.wav"

; Installer

!define installer_version_path "$LOCALAPPDATA\Temp\usceversion"
!define installer_exe_path "$LOCALAPPDATA\Temp\usceupdate.exe"
!define version_url "https://github.com/UltraStar-CE/USCE/releases/latest/download/VERSION"
!define update_url "https://github.com/UltraStar-CE/USCE/releases/download/v%VERSION%/USCE-windows-installer-%VERSION%.exe"
!define update_mask_online_version "%VERSION%"

; debug - uncomment for testing
;!define /redef update_url "http://downloads.sourceforge.net/project/ultrastardx/UltraStar%20Deluxe/Version%201.0.1a/ultrastardx-101a-installer-full.exe"
;!define /redef version_url "http://raw.githubusercontent.com/UltraStar-Deluxe/USDX/master/VERSION"

; Icons

!define img_install "install.ico"
!define img_uninstall "uninstall.ico"

; Header Images

!define img_header "header.bmp" ; Header image (150x57)
!define img_side "side.bmp" ; Side image (162x314)

; Registry for Start menu entries:

!define PRODUCT_NAME "${name}"
!define PRODUCT_VERSION "${version}"
!define PRODUCT_PUBLISHER "${publisher}"
!define PRODUCT_WEB_SITE "${homepage}"
!define PRODUCT_UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${name}"
!define PRODUCT_UNINST_ROOT_KEY "HKLM"
!define PRODUCT_PATH "$PROGRAMFILES\${name}"
