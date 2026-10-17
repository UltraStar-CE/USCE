# Automation and human review

We use automation to help review contributions, test changes and follow upstream
development. People remain responsible for their contributions and merge
decisions. The same review policy applies to contributors, maintainers and
automated proposals.

## Review feedback

AI reviews help us keep up with contributions and give earlier feedback.
Findings should identify a concrete problem, explain its effect and help the
contributor decide what to change. We favor concise, conversational feedback
over repeated summaries or commentary on every update.

AI feedback is advisory. It cannot supply a required human approval. Contributors
must be able to read, modify, explain and defend their code, including code
written with AI assistance. [DEVELOPMENT.md](DEVELOPMENT.md) explains this policy.

## Candidate fixes and reporter feedback

Small, reproducible issues are good candidates for focused fixes. Whether a
proposal is prepared by a contributor, maintainer or automated tool, its PR
explains the problem, the change and the testing performed.

We review a candidate and provide a build or clear testing instructions before
asking the reporter to try it. Reporters can confirm that it works, explain
what still fails or say they cannot test. Silence is not confirmation. Creating
or merging a candidate does not automatically close the issue; we record the
outcome before making that decision.

## Following upstream

We track improvements from these projects and preserve their authorship:

| Project | Branch |
| --- | --- |
| [UltraStar Deluxe](https://github.com/UltraStar-Deluxe/USDX) | master |
| [UltraStar Deluxe Themes](https://github.com/UltraStar-Deluxe/Themes) | main |

Assessment PRs link the upstream comparison and record the changes considered.
Each change is incorporated through a reviewed adaptation or given a reason for
deferral. An assessment checkpoint records what was reviewed; it does not imply
that every change was adopted. Changes that depend on earlier work are reviewed
in order, with compatibility adjustments recorded in the PR.

## Validation and merge decisions

Automated proposals follow our [contribution policy](CONTRIBUTING.md), including
required validation and published human review rules. We limit automated Codex
review requests rather than the number of open PRs: two per author in a rolling
24-hour window, with the project owner exempt. Reviews wait in a queue; PRs stay
open. Requests are serialized, drafts are skipped, and each commit is requested
only once. Manual review requests outside the queue are not subject to this
scheduler's budget. Changes to a PR can be reviewed in a later slot.

The queue uses the subscription-backed GitHub integration. Native automatic
reviews must be disabled for these repositories so they do not bypass the queue.
The scheduled dispatcher reads GitHub metadata and requests reviews; it does not
check out or execute proposed code, merge PRs, or purchase additional usage.
Queue requests and their source commits are recorded in PR comments.
`tools/codex-review-queue.cjs` selects one eligible request from complete metadata
and the owner-authored request ledger; missing in-flight state stops dispatch. This local
schedule runs while its Codex host is available.

Build results identify the exact source revision tested. See
[USCE-CI.md](USCE-CI.md) for platform coverage.

Automation does not approve its own proposals, change review requirements or
merge PRs. A human evaluates the change, testing and review feedback before
deciding to merge.
