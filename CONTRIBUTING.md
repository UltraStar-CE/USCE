# Contributing to USCE

Help with code, translations, documentation, themes, accessibility, bug reports,
and testing is welcome. You can start small. Ask in an issue if you need help
finding the right place to make a change.

## Report a problem

Include your operating system, the exact build or commit, steps to reproduce,
expected behavior, and what happened. Add a short log or screenshot if useful.
Share only files you have permission to distribute. Search for an existing
report first.

## Propose a change

Discuss substantial changes in an issue before implementing them. For code,
follow [COMPILING.md](COMPILING.md) and [DEVELOPMENT.md](DEVELOPMENT.md).
Use a branch and open a focused PR, including for maintainer changes. Draft PRs
are welcome. Explain the problem, the resulting behavior, and what you tested.
Say clearly when you could not test a platform. Preserve compatibility and
existing copyright and license notices; include asset provenance and permission.

Every change uses a PR and required CI under [GOVERNANCE.md](GOVERNANCE.md).
During the recorded solo bootstrap phase the sole maintainer can merge after
checking CI and review findings, with the absence of independent review stated.
Once a second human developer joins, one independent approval is required;
when there are more than four active developers, two are required. Authors
cannot approve their own work. Automation cannot merge or supply an approval.

AI-assisted contributions are welcome when the contributor can explain the
change, checks its correctness and provenance, and states how AI was used.
Treat generated output as a proposal. Reviews should focus on actionable
problems, not volume.

## Testing candidate fixes

An automated candidate is a draft for review. A maintainer checks it and provides
a build or clear testing instructions before asking the reporter to retry.
The reporter can confirm, reject, or say they cannot test. Silence is not
confirmation. Keep the original issue open until a human records the outcome;
do not close it automatically because a PR exists or was merged.

## Working with upstream

USCE derives from [UltraStar Deluxe](https://github.com/UltraStar-Deluxe/USDX),
which builds on UltraStar by corvus5. Thank you to their contributors. Preserve
authorship when porting changes, link the source commit, and document adaptations.
Changes useful to USDX can also be proposed there; contributors decide where
they wish to participate.

For conduct concerns, read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
