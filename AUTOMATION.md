# USCE automation

Automation proposes changes and reports evidence. Humans decide what is merged.
The repository rules require independent approvals and CI for maintainer and
automated changes alike. AI reviews are advisory comments, never approvals.

## Automatic reviews

The `USCE human review` ruleset requests Copilot reviews on new PRs, draft PRs,
and new pushes. GitHub makes this conditional on the author's Copilot access
and available AI credits; verify coverage using an external contributor's PR.
It is not a guarantee that every author receives a review.

The optional Codex workflow covers PRs through `pull_request_target`. It checks
out only trusted default-branch code, downloads diffs as data, gives the agent
read-only access without a write token, and publishes a COMMENT review from a
separate job. It discards feedback if the PR head changed. Oversized changes
require human review. Binary files and missing patches need manual review.

## Candidate issue fixes

A write collaborator applies `agent:fix` to a small, reproducible issue. This
starts a candidate run after the configured environment approval. The workflow
checks the collaborator's permission and the current issue state and label.
The agent reads the code and returns a proposed set of source files. A separate
publisher validates paths, sizes, file types, and the base commit before opening
a draft PR. It does not execute agent-generated code with secrets or write
permissions. It asks the reporter to test once a maintainer provides a build or
instructions. No reply is not confirmation. A human closes the issue.

Candidates are limited to eight text files and 250 KB. Pascal files under
`src/base`, `src/screens`, `src/classes`, `src/menu`, and `test`, plus Markdown
under `doc`, are supported. Build changes, workflows, deletions, third-party
code, and binary assets require a maintainer-led PR. This intentionally limits
the initial automation's reach; it must explain when a task is outside scope.

## Upstream tracking and adaptation

The daily tracker follows:

| Repository | Branch | Initial imported or inventoried baseline |
| --- | --- | --- |
| UltraStar-Deluxe/USDX | master | 05a3cb37c63361695b16e777f5b5678ebd873198 |
| UltraStar-Deluxe/mxe | ultrastardx | 355c55d2723e344c47cf353f9d47699a2ce1150a |
| UltraStar-Deluxe/Themes | main | f21d921f43e6cd430435a2cb5423f2bf5243f6c9 |

New tips create draft assessment PRs with compare links and a paginated commit
inventory. A checkpoint means assessed, not incorporated. Before merging one,
record an adaptation PR or explicit reason for deferral for every source commit.
History rewrites fail for manual assessment rather than silently resetting.

With AI enabled, daily runs also propose one USDX source-commit adaptation at a
time, in commit order. Each source SHA has a stable candidate branch; open or
closed PRs are not recreated automatically. Dependencies may require merging
earlier adaptations first. Use workflow dispatch with kind `upstream` and a full
source SHA for a selected commit. Large commits, merge commits with incomplete
patches, unsupported paths, and MXE/Themes changes need maintainer-led adaptation.
The automatic tracker covers all three repositories; automatic code adaptation
in this first version covers only the supported USDX source paths.

## Activation after review and merge

1. Enable Actions on the fork and permit Actions to create PRs. Default workflow
   token permission should remain read-only; only the publishing jobs request
   the narrowly scoped writes they need.
2. Create label `agent:fix`. Set repository variable `USCE_AUTOMATION_ENABLED` to
   `true` to activate upstream assessment PRs.
3. Create environments `usce-ai-reviews` and `usce-ai-candidates`, restricted to
   the default branch. Require a human reviewer for candidate runs. Store a
   dedicated, budget-limited `OPENAI_API_KEY` in each environment. No key is
   included in this PR. Configure provider spending limits before enabling.
4. Set `USCE_CODEX_VERSION` to a reviewed CLI release and optionally set
   `USCE_AI_MODEL`. Set `USCE_AI_ENABLED=true` only after the environments,
   permissions, API budget, and first end-to-end trial have been checked.
   Native Copilot reviews can remain the only reviewer to avoid duplicate
   automated feedback. The optional Codex path provides broader author coverage.
5. Run a small internal PR, a fork PR, a labeled test issue, and a known upstream
   commit. Check that generated PRs stay draft, approvals are required, and the
   original issue remains open. Inspect the full changes and provenance.

PRs created by `GITHUB_TOKEN` do not automatically start ordinary PR workflows.
A maintainer must run CI using the manual build trigger proposed in the CI PR,
or push a reviewed commit to the candidate branch to start PR CI. Do not weaken
required checks or merge while checks are missing. An independently configured
GitHub App token could trigger CI in a future revision, but is not required or
silently provisioned here.

## Operations and limitations

Run `node --test tools/usce-automation.test.cjs` for the publisher boundary tests.
New external actions are pinned to reviewed commit SHAs. The CLI version is a
separate explicit activation setting. Watch failed workflow runs, API quotas,
and stalled assessment PRs; failures must not be treated as a clean review.
Review the active developer roster monthly and change required approvals to two
when the fifth developer qualifies. The workflow never changes that threshold.

No automation has been enabled merely by adding these files. The workflow only
becomes scheduled once merged into the default branch and explicitly enabled.
