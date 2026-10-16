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
| [UltraStar Deluxe MXE](https://github.com/UltraStar-Deluxe/mxe) | ultrastardx |
| [UltraStar Deluxe Themes](https://github.com/UltraStar-Deluxe/Themes) | main |

Assessment PRs link the upstream comparison and record the changes considered.
Each change is incorporated through a reviewed adaptation or given a reason for
deferral. An assessment checkpoint records what was reviewed; it does not imply
that every change was adopted. Changes that depend on earlier work are reviewed
in order, with compatibility adjustments recorded in the PR.

## Validation and merge decisions

Automated proposals follow our [contribution policy](CONTRIBUTING.md), including
required validation and published human review rules. Automated issue candidates
follow the five-open-PR limit. Automated upstream assessments and adaptations of
merged upstream changes are exempt and do not count toward that limit.
Build results identify the exact source revision tested. See
[USCE-CI.md](USCE-CI.md) for platform coverage.

Automation does not approve its own proposals, change review requirements or
merge PRs. A human evaluates the change, testing and review feedback before
deciding to merge.
