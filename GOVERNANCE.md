# How USCE is run

UltraStar Community Edition is developed by its community. Players, translators,
designers, testers, and developers can propose improvements and take part in
public discussions. Decisions should have a recorded reason and a clear route
for reconsideration.

## Decisions

Small, reversible changes use an issue or pull request. Larger changes to the
game, compatibility, releases, or project policy need a public proposal stating
the problem, alternatives, likely impact, and a named person willing to carry
the work forward. Leave at least seven days for discussion before deciding.
Summarize the decision and substantive objections in that discussion.

Seek consensus first. If a proposal remains contested after fourteen days,
publish the exact question and hold a seven-day vote of active developers.
A decision needs participation by more than half of the active roster and a
simple majority of votes cast. A tie leaves the current behavior in place.
Anyone may contribute evidence and arguments, including people outside the
voting roster. Policy changes use the same process and a reviewed PR.

## People and responsibilities

Contributors choose their work. Maintainers help contributors, review changes,
coordinate releases, and look after repository access. Organization owners
handle administrative settings; ownership is not a technical veto. Maintainer
appointments and removals use a public proposal and the decision process above.
Publish responsibilities and the current roster in `MAINTAINERS.md`.

For the initial bootstrap, the organization owner handles administration until
more maintainers join. This temporary responsibility does not permit self-review
or direct changes to protected branches. Recruit at least one independent human
reviewer before merging project changes.

## Active developers and review requirements

An active developer is a human who has contributed at least two merged code,
documentation, translation, or test PRs, or two substantive PR reviews, across
USCE, its MXE repository, and its Themes repository during the preceding 90 days.
A substantive review contains technical reasoning, testing, or actionable
feedback; a bare approval or automated review does not qualify.

Review the roster monthly through a public PR with links to qualifying activity.
People can correct omissions or appeal a decision using the public proposal
process. Do not collect private activity or use commit counts as a proxy for
contribution quality. The initial bootstrap roster is explicitly identified.

Every PR needs **one independent human developer approval while there are four
or fewer active developers, and two when there are more than four**. The author
cannot approve their own PR. Maintainers, owners, and bots follow the same PR
route. AI feedback never counts as a required human approval.

When the fifth developer qualifies, update the roster and increase the GitHub
ruleset to two approvals before merging further project PRs. Keep two approvals
in place if a roster review is overdue; never lower the threshold automatically.
Record any later decrease publicly and apply it only after the roster review.

Require passing CI, resolved review conversations, and new approval after code
changes invalidate an earlier review. Protect the default and release branches,
with no bypass actors. Disable automatic merging. An administrator's ability
to edit rules is a responsibility, not an exception to this policy; record rule
changes publicly, without disclosing confidential security information.

## Transparency and conflicts

Discuss project decisions in issues, PRs, or Discussions. Summarize decisions
made in calls or chat in the relevant public thread. Disclose relevant conflicts
of interest and recuse yourself from personal moderation cases. Private reports,
security vulnerabilities, and personal data stay private; publish only redacted
outcomes when appropriate.

## Upstream collaboration

USCE builds on UltraStar Deluxe and the original UltraStar. Preserve authorship,
licenses, and commit history. Evaluate upstream improvements on their technical
merits and record adaptations or deferrals. Contributors may submit suitable
changes upstream; this is encouraged where useful and never a condition of
participation here.

## Review of this policy

Review this governance after the first three months and at least annually.
Anyone can propose an amendment through a public issue and reviewed PR.
