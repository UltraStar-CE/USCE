# USCE releases

We aim for one monthly release, following a stable USDX release with additional
USCE features and bug fixes. Release preparation becomes eligible 24 hours after
GitHub's USDX publication timestamp. An hourly check runs at 15 minutes past the
hour; GitHub scheduling delays can postpone it. If no current-month upstream
release is available, preparation starts on or after the 24th in Europe/Vienna.
An upstream release published around that fallback still gets the full 24-hour
wait. A missing publication timestamp stops preparation for investigation.
A delayed run catches up. An existing draft, published release or preparation PR
prevents a second automatic release for the same month. Later upstream changes
can enter the next monthly release or a separately reviewed patch.

Release highlights include concrete examples of additional features and bugs
fixed compared with the referenced USDX release, with links to the USCE changes.
Each release retains the two comparison
sections and their graphics: changes since USCE's previous release, and changes
compared with the referenced USDX release.

## Preparation and publication

Automation opens a draft preparation PR updating VERSION and release-plan.json.
The plan records whether upstream or the calendar triggered it, and identifies
an upstream reference separately from the USCE version. That reference does not
claim every upstream change has been incorporated. We review that coverage,
USCE additions, compatibility and release notes before merging. Marking the draft
ready for review starts PR checks, including when the workflow token created it.

After the preparation PR merges, release CI builds Windows, Linux, ARM macOS and
Intel macOS from that exact revision. It creates a draft GitHub release containing
the Windows installer, portable ZIP, Linux AppImage, two macOS DMGs, the VERSION
update feed and SHA256SUMS.
All platforms must succeed. Retries retain matching assets and refuse to replace
different files or move an existing tag. An already published version is never
overwritten. No workflow merges PRs or publishes a release automatically.

We test installation, launch, songs, microphones, scoring, themes and settings
reuse using the actual draft packages. Before publication, we complete the
release notes with testing results and known limitations, check licenses and
upstream credit, and verify dependency source versions and checksums. A human
decides when to publish.
The updater reads VERSION from the latest published release and downloads its
matching installer tag. Draft assets become available to users only after human
publication. README download links point to publicly available tested packages. The first release remains subject to these checks.

## Generated versions

VERSION contains only the numeric release base, such as 2026.10.0. Normal CI
builds use a development version containing the commit count and source SHA;
modified local checkouts also carry a dirty marker. Exact release tags identify
stable local builds. Release CI explicitly selects the reviewed release version
and rejects a dirty checkout or a mismatch with VERSION.

tools/generate-version.py generates VERSION.build, the Pascal version include,
Windows installer version definitions, macOS Info.plist and build-version.json.
The autogen script runs it before configure, so no stable/development toggle
commits are needed. Generated metadata is ignored by Git. For direct IDE builds,
run `python3 tools/generate-version.py` first. Python 3 is required. Git provides the source revision and commit count.
Source archives use an unknown-revision development label and need the same
generation step before configuration. Stable release builds require Git metadata.

## Themes in release packages

Every platform package includes all themes and their assets from the reviewed
`themes.json` commit in the separate Themes repository. Monthly preparation
proposes the current Themes revision alongside the release plan. The release
plan and theme pin must agree before a release build can start. Creator credits
and accompanying notices are preserved. `themes/BUNDLE-SOURCE.json` records the
source commit, theme definitions and asset checksums inside each package.

Themes remain developed in the Themes repository. Bundling does not change the
default selection. Experimental themes are available to choose, and we test
their compatibility with the release candidate before publication.

CI package artifacts are retained for seven days. Draft and published release
assets are stored separately and are not affected by that retention period.
