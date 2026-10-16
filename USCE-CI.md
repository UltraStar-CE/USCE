# Builds and candidate validation

We build the Windows installer and portable package, Linux AppImage, and macOS
ARM and Intel DMGs. We inherited this platform coverage from USDX and retain its
whitespace check. Build results belong to the tested USCE commit; an
upstream success does not substitute for a passing USCE build.

## When builds run

Changes to code, build scripts, workflows and embedded build resources run the
four platform builds. Documentation, repository banners and translations alone
run the whitespace check without starting platform builds or automation tests.
The path definitions live in `tools/ci-build-paths.json`; a consistency check
keeps workflow filters and the required validation gate aligned. We do not
rebuild unchanged code on a daily schedule.

Linux AppImages use an older Debian base for compatibility and build their
dependencies from source when the dependency cache is empty. The first build
can therefore take substantially longer than compiling the game. Successful
builds on `main` provide a dependency cache that subsequent PRs can restore.
Caches saved by one PR cannot be restored by another PR.

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
token. For those candidates, the separate Candidate validation workflow supports
an isolated manual run from the protected `ci-validation-v2` tag, with the candidate branch or full SHA
as its `ref` input. The tag points to a reviewed workflow revision. Only `main`
remains as a permanent branch; the validation workflow uses a tag to keep cache
writes outside the default branch's scope.

Manual builds skip shared dependency caches and BuildKit cache import/export.
Build jobs check out the resolved commit with read-only repository permissions
and no stored Git credentials. They receive no AI key or publishing token. A
separate job that never executes candidate code publishes results on that exact
SHA. A new candidate commit requires new build results.

Candidate jobs appear only on manually requested validation runs. The publisher
reports results against the resolved candidate SHA. Its required gate succeeds
only when whitespace and all four platform jobs pass. Missing, failed,
cancelled, skipped or ambiguous platform results cannot satisfy that gate.

We review the changes, provenance, tests and reporter feedback before a human
merge decision. No build or candidate job merges a PR.

## Required checks

Our required GitHub Actions gate is `Check trailing whitespace`. For changes
that need builds, this check also waits for the complete Build workflow on the
exact PR head revision. Workflow and automation changes additionally require
the automation tests. Any failed, cancelled or absent required workflow blocks
the gate. A previous revision's passing build does not count.

For documentation-only changes, the same gate completes after whitespace.
This avoids leaving irrelevant platform checks pending or listing skipped
manual and agent jobs on ordinary PRs. Required validation, resolved review
conversations and the published human approval policy apply to maintainers too.
