# How we run USCE

We maintain UltraStar Community Edition as a community project. Players,
translators, designers, testers and developers can propose improvements and take
part in public discussions. We record decisions, explain the reasons and keep
a route open for reconsideration.

## Decisions

Small, reversible changes use an issue or PR. Larger changes to gameplay,
compatibility, releases or policy start with a public proposal describing the
problem, alternatives, likely impact and someone willing to carry the work
forward. We allow at least seven days for discussion and summarize both the
decision and substantive objections in that discussion.

We seek consensus first. If a proposal remains contested after fourteen days,
we publish the exact question and hold a seven-day vote of active developers.
Participation by more than half the active roster and a simple majority of votes
cast are required. A tie keeps the current behavior. Everyone can contribute
evidence and arguments, including people outside the voting roster. Policy
changes follow the same process and use a reviewed PR.

## People and responsibilities

Contributors choose their work. We help contributors, review changes, coordinate
releases and look after repository access. Organization ownership carries
administrative responsibilities, not a technical veto. Maintainer appointments
and removals follow the public proposal process. Our current responsibilities
and roster appear in [MAINTAINERS.md](MAINTAINERS.md).

The project currently has one human developer, dgruss. During this recorded
solo phase, the maintainer may merge their own PR after required CI passes,
review findings are addressed, and testing and the absence of independent human
review are recorded. Direct pushes, force pushes and automatic merges remain
prohibited. We review this status monthly. The exception ends when a second
human developer joins the roster, without waiting for that newcomer to earn
two merged PRs.

## Active developers and approvals

An active developer is a human with at least two merged code, documentation,
translation or test PRs, or two substantive PR reviews, across
[USCE](https://github.com/UltraStar-CE/USCE),
[MXE](https://github.com/UltraStar-CE/mxe) and
[Themes](https://github.com/UltraStar-CE/Themes) in the preceding 90 days.
A substantive review includes technical reasoning, testing or actionable
feedback; a bare approval or automated review does not qualify.

We review the roster monthly through a public PR with contribution links.
Anyone can correct an omission or question a decision through the public
proposal process. Contribution quality matters; raw commit counts do not define
it. The initial solo roster is explicitly identified.

Outside the solo exception, every PR needs **one independent human developer
approval with four or fewer active developers, and two with more than four**.
The author cannot approve their own PR. Maintainers, owners and bots follow the
same PR route. AI feedback never counts as a required human approval.

When the fifth developer qualifies, we raise the enforced requirement to two
before further merges. An overdue roster review keeps the existing threshold;
it never lowers it automatically. Any decrease is publicly recorded after review.

We require passing CI, resolved review discussions and renewed approval when
code changes invalidate a review. Default and release branches have no bypass
actors. Administrative rule changes are publicly recorded.

## Transparency and reconsideration

We discuss project decisions in issues, PRs or Discussions and summarize relevant
outcomes from calls or chat in the public thread. We disclose relevant conflicts
of interest and ask an uninvolved maintainer to handle moderation where possible.
Moderation decisions include an explanation and a route for reconsideration.

## Upstream and policy review

USCE builds on UltraStar Deluxe and the original UltraStar. We preserve their
authorship, licenses and history, assess upstream improvements on their technical
merits and record adaptations or deferrals.

We review this governance after the first three months and at least annually.
Anyone can propose improvements through a public issue and PR.
