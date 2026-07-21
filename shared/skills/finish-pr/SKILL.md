---
name: finish-pr
description: Use when implementation is substantially complete and a commit message or pull request description needs a final diff audit before branch integration.
---

# Finish PR

## Overview

Audit the exact state proposed for integration, then draft accurate commit and PR artifacts. This skill does not repair gaps or mutate branch, remote, or worktree state.

## Required sequence

1. Read the repository's `AGENTS.md`, `CLAUDE.md`, relevant documentation, and PR template. If no engineering baseline exists, report that fact and audit only requirements the repository actually declares; absence alone does not block.
2. Determine the merge base. Audit the full branch diff from that base plus staged, unstaged, and untracked working-tree changes.
3. Compare that complete diff with the declared requirements. Missing required comments, public API docs, or architecture updates **blocks the PR**. Report the exact gaps, return to implementation, and re-run checks after the fixes; do not repair them inside this skill.
4. Record every relevant verification command and its exact result. Explicitly list every relevant check not run. Never infer or invent evidence.
5. Draft a Conventional Commit message with the subject `type(scope): imperative summary`. For a non-trivial change, add a body covering motivation, behavior and design decisions, tradeoffs, verification, and issue references when applicable.
6. Fill the repository's PR template from the final diff. Include risk, rollback, reviewer entry points, and exact verification evidence without deleting required sections.
7. Keep this skill read-only with respect to remotes and branch/worktree lifecycle: it does not push, merge, synchronize, delete branches, or delete worktrees. Hand the audited artifacts to **superpowers:finishing-a-development-branch** where available, or the runtime's established equivalent. Never duplicate that workflow's mutation, ordering, verification, or provenance logic. If no established finishing workflow is available, this skill **stops after drafting**, returns the artifacts, and explicitly reports that lifecycle operations were not performed.
8. If implementation or documentation changes after the audit, discard stale drafts, re-audit, and re-derive the final commit message and PR description.

## Output contract

Return these items in order:

1. `PASS` or `BLOCKED`, with exact audit evidence.
2. Verification commands and results, followed by relevant checks not run.
3. The complete commit message.
4. The completed PR description.
5. The branch-finishing handoff, or the explicit no-lifecycle-operation report.

Do not produce final commit or PR drafts when blocked; name what implementation work must happen before the audit is rerun.

## Quick reference

| Question | Required action |
|---|---|
| What is being audited? | Merge-base branch diff plus all working-tree changes |
| Required docs missing? | Block and return to implementation |
| Test evidence? | Exact command, exit/result, and relevant checks not run |
| Commit shape? | Subject plus body fields for non-trivial changes |
| PR shape? | Repository template, risk, rollback, reviewer entry points |
| Lifecycle action? | Delegate to the established finishing workflow; otherwise stop |

## Rationalizations to reject

| Excuse | Reality |
|---|---|
| "The deadline is close; I can add the missing docs while finishing." | A documentation gap blocks the audit. Return to implementation, then re-audit the resulting diff. |
| "The subject summarizes it; a body is unnecessary." | Non-trivial changes require motivation, decisions and tradeoffs, verification, and applicable issue references. |
| "The test command is enough because I ran it." | Evidence includes the exact result; command-only claims are incomplete. |
| "Finishing the PR means I should commit now." | This skill audits and drafts only; lifecycle mutation belongs to the established finishing workflow. |

## Red flags

- Editing implementation or documentation while performing this audit.
- Omitting results or checks not run from verification evidence.
- Producing only a one-line message for a non-trivial change.
- Committing, pushing, opening a PR, merging, or cleaning a worktree here.

Any red flag means stop, restore the audit/drafting boundary, and follow the required sequence.
