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

Automated proposals retain upstream links and contributor mentions, including
maintainers. Upstream issues and PRs use fully qualified references such as
`UltraStar-Deluxe/USDX#1460` so they point to the correct repository. The tracker
links both the source proposal and its USCE counterpart. Release notes retain
relevant source references and attribution alongside links to the USCE changes.

The same daily assessment also monitors the upstream USDX and Themes issue
trackers, even when there are no new commits. Only reports created on or after
the fixed cutoff in `doc/upstream/issues-watch.json` are included. Older issues
stay excluded even when updated or reopened. Later activity on the new reports,
including comments and changes of state, prompts reassessment. Titles, source
links, description excerpts, labels and comment counts provide context for
assessing bugs, regressions, feature requests and workarounds against current
USCE. An upstream report is not automatically a confirmed USCE bug.

Issue assessments contain up to 20 reports, with one outstanding assessment per
source repository. Decisions and related USCE issue or PR links are recorded in
`doc/upstream/usdx-issues.json` or `doc/upstream/themes-issues.json` before merge.
Unchanged reports are not proposed again; new activity prompts reassessment and
retains the prior decision. Closing an assessment without merging does not mark
its reports as assessed. The workflow neither posts upstream nor generates or
merges game changes from issue text, and requires no additional paid AI service.

The daily assessment also discovers USDX forks pushed within the last two years,
including forks listed in GitHub's active-forks view. Archived and disabled
repositories and USCE itself are excluded. All branch tips are checked, including feature branches. New tips with commits ahead of
USDX produce a draft assessment with immutable comparisons and commit excerpts.
These commits may already have equivalent ports in USCE; they are discovery
candidates, not automatic imports. Assessments contain up to 20 branch tips, with one
outstanding fork assessment at a time. Decisions and existing USCE references
are recorded in `doc/upstream/usdx-forks.json`. Unchanged assessed heads do not
produce duplicate proposals. Closing an unmerged assessment leaves it eligible
for reassessment. The scan reads metadata only and does not execute fork code.

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

Only an unverified request on the current head of an open PR blocks dispatch.
`classifyRequests` requires fresh PR metadata for every request, including closed
and merged PRs. Superseded heads and closed PRs remain outstanding, count toward
historical usage, and are monitored for completion and late findings. They do
not block current-head reviews. Never infer completion from age, rebase or merge,
cancel an existing review, or retry a stale request. Surface new actionable late
findings on merged PRs for follow-up without repeating unchanged stale blockers.
Only verified native completion evidence enters `completedCommentIds`.

Build results identify the exact source revision tested. See
[USCE-CI.md](USCE-CI.md) for platform coverage.

Automation does not approve its own proposals, change review requirements or
merge PRs. A human evaluates the change, testing and review feedback before
deciding to merge.

### Incremental fork assessment

Known branches are compared with their last recorded head. Newly discovered
branches are compared with USCE main, excluding commits already in its history.
The complete commit inventory is paginated before applying the six-month author-date cutoff; eligible commits and the number excluded are recorded. Excerpts are only a summary.
Prior heads and decisions remain in assessment history. Shared commits are
presented once across the batch and previous inventories. A new push elsewhere
in a fork does not make its old branch history new development.

Assessors check rebased/adapted equivalents against USCE source and existing
PRs, record covered/superseded/rejected work with evidence, and link unresolved
work to existing follow-ups. These semantic decisions are not inferred from
commit titles or ancestry. Commits older than six calendar months are excluded using their original author date, including recently rebased commits. Old-only branches produce no proposal. Reports should
provide recommendations and concrete follow-ups rather than another reading list.
