# Build parity and candidate validation

USCE inherits the upstream Windows installer/portable, Linux AppImage, and
macOS ARM/Intel DMG build matrix plus its source whitespace check. These files
preserve those builds. A successful upstream run is not proof that the new
fork's builds work; verify the first USCE runs before offering downloads.

## Windows dependencies

The inherited `dldlls.py` pins MXE commit
`355c55d2723e344c47cf353f9d47699a2ce1150a`. Its public release download path
is retained. Upstream publishes `usdx-dlls-x86_64-v2026.8.0.zip` under release
`USDX-v2026.8.0`. The CI no longer passes a cross-repository read secret into
candidate build jobs. If the pinned release cannot be found, the build must
fail; publish or select a reviewed dependency release in a follow-up PR.

The relevant MXE build workflow lives on `ultrastardx`, not `master`. The fork
must include that branch. Enable its Actions workflow before rebuilding DLLs.
Moving dependency downloads to USCE's MXE repository needs a reviewed release,
source SHA, artifact integrity check, and a corresponding downloader change.
Do not point at a repository with no matching artifacts or silently use latest.

## Validating bot-created candidate PRs

GitHub suppresses ordinary PR workflow triggers for PRs created with the workflow
token. To validate a candidate, run **Build** manually from the trusted default
branch and enter the candidate branch or full commit SHA in `ref`.

The build jobs check out the resolved commit with read-only permissions and no
stored Git credentials. They receive no AI key or cross-repository secret. A
separate job which never executes candidate code publishes the results against
that exact SHA. Both macOS checks require success of the entire macOS matrix.
Any failed, cancelled, or skipped build is reported as failure. The ordinary
source whitespace check is also run for manual candidate builds.

Manual jobs use distinct `Manual -` check names on the dispatch ref. Only the
separate publisher reports the normal required status names on the resolved
candidate SHA. Candidate results therefore cannot satisfy the default branch's
normal build checks. New PR pushes cancel obsolete builds for that PR; manual
and default-branch builds are not cancelled by this policy.

A human must inspect the PR, build results, tests, source provenance, and reporter
feedback. New commits require another build. This is a manual validation path,
not a merge action. No job enables automatic merging.

## Required checks

The following names intentionally match the workflow exactly, including `MacOS`:

- Build for Windows
- Build for Linux
- Build for MacOS (macos-latest)
- Build for MacOS (macos-15-intel)
- Check trailing whitespace

After the first workflows run, bind the ruleset's check sources to GitHub Actions
in the GitHub UI. The initial empty fork does not list GitHub Actions as a source
until it has reported checks. Keep fresh-branch and independent-review rules.
