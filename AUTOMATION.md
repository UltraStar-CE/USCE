# Automation in USCE

We use automation to help review contributions, prepare candidate changes and
follow upstream development. Maintainers decide what is merged. Required CI and
our published review policy apply to our own PRs and automated proposals alike.
AI feedback is advisory and never replaces a required human approval.

## PR reviews

Codex is our chosen AI reviewer. Automatic Copilot requests are disabled across
USCE, MXE and Themes. We use subscription-based Codex reviews rather than a
second paid review service. The Codex connection is not yet verified, so a PR
without a completed review must not be described as AI-reviewed.

Our intended review cadence is one review when a PR is ready, with another
review after substantial changes. This avoids repeated reviews of draft pushes.
A maintainer can request a review with `@codex review`. Usage limits still apply;
a failed or missing review is not a clean review.

## Candidate fixes

The optional candidate workflow is currently inactive. It uses separately billed
API access, which we have not enabled. Its implementation supports small,
reproducible issues selected by a write collaborator with the `agent:fix` label.
A human authorization step precedes a candidate run.

The agent proposes source changes. A separate publisher checks the paths,
sizes, file types and base revision before creating a draft PR. Proposed code
runs only in the build validation path, without AI credentials or publishing
permissions. Candidates are limited to eight text files and 250 KB, covering
Pascal under `src/base`, `src/screens`, `src/classes`, `src/menu` and `test`, plus
Markdown under `doc`. Other changes receive maintainer-led review.

We provide a build or testing instructions before asking an issue reporter to
try a candidate. Reporters can confirm, reject or say they cannot test. Silence
is not confirmation. A human records the result and decides when to close the
issue; creating or merging a candidate does not close it automatically.

## Following upstream

We track the following upstream branches and preserve their authorship:

| Repository | Branch | Imported or inventoried baseline |
| --- | --- | --- |
| UltraStar-Deluxe/USDX | master | 05a3cb37c63361695b16e777f5b5678ebd873198 |
| UltraStar-Deluxe/mxe | ultrastardx | 355c55d2723e344c47cf353f9d47699a2ce1150a |
| UltraStar-Deluxe/Themes | main | f21d921f43e6cd430435a2cb5423f2bf5243f6c9 |

The tracker creates draft assessment PRs containing compare links and a complete
commit inventory. An assessment checkpoint means reviewed, not necessarily
incorporated. Each commit receives an adaptation PR or a recorded reason for
deferral before the checkpoint is merged. Rewritten history receives explicit
assessment rather than an automatic reset.

The optional API adaptation queue can propose one supported USDX source commit
at a time, in order. It is currently inactive. Earlier candidates must be merged
or explicitly deferred before dependent changes proceed. Incomplete or
unsupported changes produce a persistent assessment draft and pause the queue.
Closing that draft alone does not restart it. MXE, theme assets and changes
outside the supported paths remain maintainer-led adaptations.

## Implementation and limits

The scheduled tracker is controlled by `USCE_AUTOMATION_ENABLED`. The separate
API path requires `USCE_AI_ENABLED`, a reviewed `USCE_CODEX_VERSION` and scoped
API credentials in the `usce-ai-candidates` environment.
We keep API use disabled until its cost and end-to-end behavior are reviewed.
Native Codex reviews do not use these API credentials.

The upstream tracker has its own daily and manually requested workflow. Optional
API candidates start only from a selected issue or a manual adaptation request;
they do not add inactive agent jobs to every PR. Candidate preparation reads the
trusted default-branch implementation. Tasks are limited to 60 KB of UTF-8 JSON
without partial patches; responses use short-lived artifacts. Missing patches,
binary files and oversized changes need manual review. The publisher boundary
checks are covered by `node --test tools/usce-automation.test.cjs`.

PRs created with GitHub's workflow token do not start ordinary PR CI by
themselves. We validate them through the isolated path described in
[USCE-CI.md](USCE-CI.md). Automation never changes review thresholds, approves
its own proposals or enables automatic merging.
