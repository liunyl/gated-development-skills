---
name: kimi-gated-development
description: Use when starting any non-trivial engineering implementation task — from the moment a concrete task arrives, before planning or coding begins — especially multi-module or architectural changes, high-risk paths (data loss, security, concurrency, auth, irreversible operations), unfamiliar subsystems, or design forks with materially different costs.
---

# Kimi-Gated Development

## Overview

Gate complex engineering work with **two independent external reviewers — Claude and Codex — run in parallel**, each keeping **one persistent review session per task** across every review round.

**Core principle:** external review is a gate, not a formality. You converge each review loop by triaging findings — fix the valid ones, rebut the invalid ones with technical reasoning — never by blindly implementing everything, and never by stopping because the reviewers are annoying or you are out of time.

**Second principle — session continuity:** the same task is reviewed inside the SAME Claude session and the SAME Codex session on every round. Never open a fresh session per round: a fresh session re-loads the whole repository context, re-litigates rebuttals you already won, and multiplies token cost. Reviewer independence comes from being a different model than the implementer (you) — not from amnesia between rounds.

**Judgment-based trigger:** unlike the Claude/Codex mirror skills in this family, gates here are NOT mandatory for every task. You decide — using the observable threshold below, not vibes. When you do gate, the full loop discipline applies.

**Kimi Code only.** This skill orchestrates Claude and Codex as its two reviewers — they are the gate, not the orchestrator. It must never be adopted by Claude, Codex, or any other agent, which is why it installs to Kimi's private skill directory (`~/.kimi-code/skills/`) and never to the shared `~/.agents/skills/`. If you are not Kimi Code, stop here.

## When to Use

Gate when ANY of these is true:

- The change spans multiple modules/subsystems, or changes a public interface, protocol, schema, or data format.
- It touches a high-risk path: data loss, security/auth, concurrency, payments/money, irreversible operations.
- It involves an architectural decision: new dependency, new service, new persistence, a migration.
- You are in an unfamiliar subsystem and cannot confidently bound the blast radius.
- You face a design fork between two plausible approaches with materially different costs — gate the plan, not the code.
- The plan for a large task is written and implementation has not started — the cheapest gate that exists.

**When NOT to use:** a localized single-file change with a confidently bounded blast radius; trivial prose/typo edits; mechanical refactors covered by tests. If you skip the gate, you should be able to say in one sentence why none of the triggers above applies — "it's small" is not that sentence.

## The Reviewers

Two wrapper scripts (installed with this skill) run the reviewers. From the repository root:

```bash
SKILL_DIR="${KIMI_CODE_HOME:-$HOME/.kimi-code}/skills/kimi-gated-development"

# Planning / design gate (adversarial: challenges the approach itself)
"$SKILL_DIR/scripts/claude-review.sh" adversarial --session-key <task-key> --focus "Review the spec/plan at <path>; challenge approach, assumptions, omissions, repo fit."
"$SKILL_DIR/scripts/codex-review.sh"  adversarial --session-key <task-key> --focus "Review the spec/plan at <path>; challenge approach, assumptions, omissions, repo fit."

# Final code gate (code: strict defect finder)
"$SKILL_DIR/scripts/claude-review.sh" code --session-key <task-key> --base <commit-before-task> --focus "Review the full task diff against <plan path>."
"$SKILL_DIR/scripts/codex-review.sh"  code --session-key <task-key> --base <commit-before-task> --focus "Review the full task diff against <plan path>."
```

- `adversarial` challenges approach/design (planning gates). `code` is the strict defect-finder (implementation gates).
- **Run both reviewers in parallel** as background tasks with generous timeouts — a review round takes minutes. Rounds for the SAME reviewer must be serial (session continuity); the two reviewers are independent of each other.
- Each wrapper prints only the reviewer's final report to stdout. A non-zero exit means the gate could not run or its result is untrustworthy (missing CLI, empty review target, repo mutation detected, session-state write/capture failure, or the reviewer produced no report) — that is a BLOCKED gate: report it, never substitute self-review.
- Both wrappers are review-only: Claude gets a read-only tool surface (no Bash/Edit/Write, hooks and MCP disabled), Codex runs in a read-only sandbox, and each wrapper fingerprints the repository before and after — any detected mutation fails the gate.

### Session continuity mechanics

- `--session-key <task-key>` scopes persistence. Use ONE stable key per task — e.g. `2026-07-20-auth-refactor` — minted when the task starts and reused for every gate and every round of that task, in both wrappers.
- State lives outside the working tree in the git common dir (`claude-review-sessions/`, `codex-review-sessions/`), hashed from (worktree path, key), mode 0600. Continuity is per-worktree: moving a task to another worktree starts fresh sessions there. State survives your own session restarts — a later session can resume the same reviewers by reusing the same key.
- The first round opens a new reviewer session and persists its id. Later rounds resume that id (`claude --resume` / `codex exec resume`), so the reviewer sees only the incremental delta plus its own memory of earlier rounds.
- If a saved session cannot be resumed, the wrapper warns and self-heals with ONE replacement session, then keeps reusing the replacement. A resume failure is never a reason to abandon continuity. An interrupted round is also not fatal: an interrupted FIRST round never persisted its id, so the next round opens one fresh session; an interrupted LATER round leaves the saved id untouched, and the next round resumes it as usual.
- With no key from any source (`--session-key`, `*_REVIEW_SESSION_KEY`, `CODEX_THREAD_ID`), the review runs non-persistent (Claude: `--no-session-persistence`, Codex: `--ephemeral`). Do that only for genuinely one-off questions, never for gate rounds.
- New task? Mint a NEW key. Never let two tasks share a reviewer session.

## The Shared Gate

The reviewers read repository state, so an artifact must exist as a file (or diff) for them to see it. Untracked files count.

**The gate must review a non-empty scope that contains the artifact's actual substance** — the logic lines, not just a filename, docstring, or whitespace hunk. If any part of the artifact was committed for this task, review with `--base <commit-before-this-task>` so the full artifact is in the diff; a working-tree-only review of a partially-committed artifact is a SKIPPED gate, not a pass. A review reporting "nothing to review" is SKIPPED, not clean.

```
LOOP, per gate:
  1. WRITE the artifact to a file (plan / spec), or ensure the complete code diff exists.
  2. RUN both reviewers in parallel, pointing --focus at the artifact.
  3. TRIAGE every finding from BOTH reviewers (superpowers:receiving-code-review):
       - valid & correct for THIS codebase  → fix it
       - wrong / YAGNI / doesn't apply here → rebut with technical reasoning; record it; do NOT implement
       - ambiguous, or conflicts with a decision the user already made → escalate to the user
  4. RE-RUN both reviewers — same sessions, same --session-key.
  5. STOP only after a re-run of BOTH reviewers on the CURRENT artifact state surfaces no
     valid-and-unaddressed blocking finding. Never stop on an iteration where you edited
     the artifact without re-running: the pass that clears the gate must have seen your
     final fixes. Any post-gate mutation — even a "trivial" rename or constant — re-opens
     the gate (re-run both unless the edit provably touches neither reviewer's scope).
```

**Convergence discipline:**

- "No new findings" means no new *valid blocking* finding — not silence, not fatigue.
- Split findings into **blocking** (correctness, security, data-loss, concurrency, spec-violation) and **residual** (style, alternatives, speculative hardening). The gate clears when a fresh re-run shows no blocking finding from either reviewer; log residuals, don't chase an empty report.
- Blocking-class findings are presumed valid until you have checked the code and shown otherwise — never relabel them to end the loop.
- Never blindly implement every finding — that never converges and breaks working code.
- **Monotone convergence or escalate:** each round must shrink the blocking set. If your fix introduces a new blocking defect, or the set is not shrinking after ~3 rounds, STOP and escalate to the user — the design is wrong, not the loop.
- The two reviewers will sometimes disagree. Their union is your blocking set; answer the reviewer that raised each finding — the persistent session remembers your rebuttal into the next round.

## Engineering Flow

No phase is mandatory — the When-to-Use threshold decides whether a gate opens at all. When a task crosses it, the typical gate points are:

| Gate point | When | Mode |
|---|---|---|
| Plan gate | Spec/plan written, before implementation | `adversarial` on the plan file(s) |
| Design-fork gate | Two plausible approaches, decision needed | `adversarial` on the comparison write-up |
| Pre-run gate | About to run something irreversible or costly | `adversarial` on the runbook/script |
| Final code gate | Implementation + self-verification done, before declaring done | `code` with `--base <commit-before-task>` |
| Finish handoff | After the final code gate clears | Use `finish-pr` for audit/drafting before the runtime's normal branch-finishing workflow. |

One task, one `--session-key`, reused at every gate point — by the final code gate, each reviewer already holds the plan-gate context and can check the implementation against what was agreed, at near-zero extra context cost.

For everything else (implement, verify, simplify, finish), use your normal skills — this skill adds only the external gates.

## Rationalizations — STOP if you catch one

| Excuse | Reality |
|---|---|
| "A fresh session per round is more independent" | Independence comes from the reviewer being a different model than you, not from amnesia. Fresh sessions re-load the whole context, re-litigate settled rebuttals, and multiply token cost. Reuse the session. |
| "Resume failed once — session reuse is broken, start fresh every time" | The wrapper self-heals with one replacement session and keeps reusing it. One resume failure is not a pattern; abandoning continuity is the expensive choice. |
| "A cold reviewer catches what an anchored one misses" | Then say so explicitly and pay for ONE deliberate cold review as an extra round — don't make amnesia the default. The persistent session still treats each round's bundle and files as authoritative. |
| "It's a small change, no gate needed" | Fine — if none of the threshold triggers applies and you can say why in one sentence. "Small" touching a high-risk path (auth, money, data-loss, concurrency, config values) is exactly what the threshold covers. |
| "I fixed/rebutted everything this round, so a re-run would be clean — skip it" | Your fixes are unreviewed until the reviewers see the resulting state; a fix can introduce the very defect the gate exists to catch. The gate clears only on a pass that ran against the state you ship. |
| "The gate cleared; this last cleanup is too trivial to re-gate" | A post-gate edit ships state the gate never saw. Re-run, or don't make the edit. |
| "Two reviewers always find *something*, a clean pass is impossible" | The loop ends when no *valid unaddressed blocking* finding remains across both — not when reports are literally empty. Triage first; log residuals. |
| "I'll implement every finding from both reviewers to be safe" | Blind implementation never converges and breaks working code — and the persistent session remembers your rebuttals, so a rebutted finding stays rebutted. Triage. |
| "Self-review makes the external gate redundant" | Reviews sharing the implementer's context are not independent. The external sessions are the adversary. |
| "The reviewers disagree, so the gate can never clear" | Disagreement is signal, not deadlock: the union of blocking findings is your work list; rebut what is wrong for this codebase with technical reasoning. |
| "Time pressure — skip the gate this once" | You chose to gate because the task crossed the threshold; the threshold doesn't move with the deadline. A shipped defect costs more than the loop. |

## Red Flags — STOP and fix the process

- About to run a review round with a NEW session instead of resuming the task's existing reviewer sessions.
- Reusing one `--session-key` across two different tasks.
- About to write implementation code on a task that crossed the threshold, and no planning gate has cleared.
- About to declare work done without a final `code`-mode re-run that saw the final state.
- Accepting a review whose scope is empty or lacks the artifact's substance as a PASS.
- Implementing a reviewer finding without checking it against this codebase.
- Ending a loop from fatigue or annoyance instead of a triaged zero-blocking result.
- Substituting self-review when a wrapper fails (missing CLI, auth, mutation detected). A blocked gate is reported to the user, never routed around.

## Quick Reference

- Planning/design gate → `claude-review.sh adversarial` + `codex-review.sh adversarial`, in parallel, same `--session-key`.
- Final code gate → both scripts in `code` mode with `--base <commit-before-task>`.
- One task = one `--session-key`, minted at task start, reused for every round in both wrappers.
- Triage findings → superpowers:receiving-code-review.
- Session state → git common dir `claude-review-sessions/` and `codex-review-sessions/`; a stale session self-heals once, then keeps being reused.
- Reviewers are review-only (read-only surface + repo fingerprint). Any mutation fails the gate.
