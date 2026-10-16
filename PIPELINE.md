# From contribution to release

We develop through PRs under our [governance](GOVERNANCE.md). Contributors explain
the problem, the resulting behavior and what they tested. Maintainer changes and
automated proposals follow the same process.

Code and build changes require Windows installer and portable builds, a Linux
AppImage, Intel and ARM macOS DMGs, and whitespace validation. Documentation,
banners and translation-only changes require whitespace validation. The required
gate waits for the builds needed by the changed files on the exact PR revision.
Failed or missing required builds block merging.

AI reviews provide additional feedback; people remain responsible for their
contributions and merge decisions. [DEVELOPMENT.md](DEVELOPMENT.md) explains our
AI policy. [AUTOMATION.md](AUTOMATION.md) describes candidate fixes, reporter
feedback and upstream assessment.

Successful builds provide development artifacts for testing. A release is a
separate human decision after testing the packaged game, as described in
[RELEASING.md](RELEASING.md).
