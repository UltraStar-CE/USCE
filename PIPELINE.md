# USCE build and contribution pipeline

All changes use PRs and the published governance, including the recorded solo
bootstrap phase. Required checks cover Windows installer/portable builds,
Linux AppImage, Intel and ARM macOS DMG builds, and source whitespace.

Build jobs use read-only repository tokens. Windows dependencies are currently
downloaded from the pinned public upstream MXE release by `dldlls.py`; the fork
does not yet publish an equivalent dependency release. No broad cross-repository
personal access token is needed by these build jobs.

See [USCE-CI.md](USCE-CI.md) for isolated manual validation of agent candidates
and [AUTOMATION.md](AUTOMATION.md) for reviews, reporter confirmation, upstream
tracking and adaptation. AI work stays disabled until its separate activation
steps are completed. Successful builds create test artifacts, not public releases.
