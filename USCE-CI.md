# Builds and candidate validation

We build the Windows installer and portable package, Linux AppImage, and macOS
ARM and Intel DMGs. We inherited this platform coverage from USDX and retain its
source whitespace check. Build results belong to the tested USCE commit; an
upstream success does not substitute for a passing USCE build.

## Windows dependencies

The game currently downloads the pinned upstream MXE release for commit
`355c55d2723e344c47cf353f9d47699a2ce1150a`, using asset
`usdx-dlls-x86_64-v2026.8.0.zip` from `USDX-v2026.8.0`. These identifiers preserve
compatibility with the existing dependency package. Missing pinned artifacts
fail the build rather than silently selecting a different release.

Our Windows compiler installation incorporates dgruss's
[USDX PR #1417](https://github.com/UltraStar-Deluxe/USDX/pull/1417): direct compiler
downloads, fixed installer hashes, checked exits and bounded installation times.
This prevents a partial download from being launched as a complete installer.

The USCE MXE repository retains the application-specific dependency build. A
USCE-hosted dependency release will replace the upstream download only after we
have built and validated matching artifacts and reviewed the downloader change.

## Candidate builds

GitHub does not start ordinary PR workflows for PRs created by its workflow
token. For those candidates, our Build workflow supports an isolated manual run
from the protected `ci-validation-v1` tag, with the candidate branch or full SHA
as its `ref` input. The tag points to a reviewed workflow revision. Only `main`
remains as a permanent branch; the validation workflow uses a tag to keep cache
writes outside the default branch's scope.

Manual builds skip shared dependency caches and BuildKit cache import/export.
Build jobs check out the resolved commit with read-only repository permissions
and no stored Git credentials. They receive no AI key or publishing token. A
separate job that never executes candidate code publishes results on that exact
SHA. A new candidate commit requires new build results.

Manual jobs have distinct `Manual -` names. The publisher reports the required
status names against the candidate SHA; it cannot satisfy default-branch checks
with an unrelated dispatch result. Both macOS statuses require the whole macOS
matrix to pass. Failed, cancelled or skipped candidate builds report failure.

We review the changes, provenance, tests and reporter feedback before a human
merge decision. No build or candidate job merges a PR.

## Required checks

Our branch rules require these GitHub Actions checks:

- Build for Windows
- Build for Linux
- Build for MacOS (macos-latest)
- Build for MacOS (macos-15-intel)
- Check trailing whitespace

These checks use their exact workflow names. Required CI, resolved review
conversations and the published human approval policy apply to maintainers too.
