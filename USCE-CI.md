# Builds and validation

We build Windows installers and portable packages, Linux AppImages, and macOS
ARM and Intel DMGs. This retains the platform coverage inherited from USDX.
Build results identify the tested USCE revision; an upstream success does not
substitute for a passing USCE build.

## When builds run

Code, build scripts, workflows and embedded build resources run all four platform
builds. Documentation, repository banners and translation-only changes run
whitespace validation without starting platform builds or automation tests.
We do not rebuild unchanged code on a daily schedule.

The shared path definitions are in `tools/ci-build-paths.json`. A consistency
check keeps workflow filters and the required validation gate aligned. GitHub
evaluates path filters against at most 3,000 changed files. An unusually large
PR may need splitting if GitHub omits a required build trigger. The gate reports
that condition rather than treating the missing build as a pass.

## Required validation

The required `Check trailing whitespace` gate also waits for every build needed
by the changed files on the exact PR head revision. Workflow and automation
changes additionally require automation tests. Failed, cancelled or missing
required workflows block the gate. Passing results from an earlier revision
do not count.

Automated candidates receive equivalent validation on their exact source
revision. Candidate build jobs run separately from publication, without shared
dependency caches or repository write access. Missing or ambiguous results do
not count as passing checks. A human reviews the results before merging.

Required validation, resolved discussions and the published approval policy
apply to maintainers too.

## Dependencies and build times

Linux AppImages use an older Debian base for compatibility and build dependencies
from source when their cache is empty. The first build can take substantially
longer than compiling the game. Successful builds on `main` populate a cache
that later PRs can restore. GitHub isolates caches saved by individual PRs.

Windows builds its DLL dependencies from pinned, checksum-verified sources in
MSYS2 UCRT64. The dependency cache is keyed by the build recipes and patches.
A cold build takes longer; subsequent builds reuse the installed dependencies.
Dependency updates include their source versions and checksums in the PR.
