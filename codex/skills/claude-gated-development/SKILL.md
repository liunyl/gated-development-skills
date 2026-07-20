---
name: claude-gated-development
description: Use when a concrete complexity or high-risk trigger requires concurrent independent Claude + Kimi review; always use for a real quant strategy backtest before its first run.
---

# Claude-Gated Development

## Overview

External review is exceptional, not the default. Local, reversible, single-path work with an obvious implementation and direct check skips external review. When a concrete complexity or high-risk trigger applies, do not advance an artifact until concurrent independent Claude + Kimi review has cleared it. For quant work, review the backtest code before its first real run.

**Core principle:** Route by concrete risk, not diff size. The default is to skip external review; a triggered review is a strict dual-review gate. Triage every finding: fix valid findings, rebut invalid findings with technical evidence, and escalate ambiguous findings or conflicts with user decisions. Never implement every comment blindly, and never stop because a reviewer is inconvenient.

Use two modes:

- **Complex engineering:** plan → concurrent Claude + Kimi gate → implement → verify → concurrent Claude + Kimi gate.
- **Quant backtest:** study → playbook + code → concurrent Claude + Kimi gate → first real run.

## Reviewer command

Run from the repository root:

```bash
RUNNER="${CODEX_HOME:-$HOME/.codex}/skills/claude-gated-development/scripts/claude-review.sh"
```

Use:

```bash
"$RUNNER" adversarial --focus "Review the spec and plan at <path>; challenge the approach, assumptions, omissions, and repo fit."
"$RUNNER" adversarial --base <commit-before-task> --focus "Review <artifact paths> and the full task diff."
"$RUNNER" code --base <commit-before-task> --focus "Review the final implementation against <plan path>."
```

The wrapper runs Claude and Kimi concurrently against the same captured Git scope. It reuses one persistent session per reviewer for the same Codex task and repository, keyed by `CODEX_THREAD_ID`. Set `CLAUDE_REVIEW_SESSION_KEY` to override the task key; without either key it keeps the old fresh, non-persistent behavior. Session continuity trades cold-start independence for less repeated context loading: each reviewer remains independent from the implementer, but later gates retain its earlier review context. If a saved Claude session cannot resume, the wrapper retries once with a new Claude session. A failed Kimi continuation blocks the gate.

Claude uses `dontAsk` plus an explicit read-only tool surface. The wrapper precomputes the current Git scope into a temporary review bundle, removes Bash and file-edit tools, and keeps only `Read`, `Glob`, `Grep`, `Skill`, and `Agent`. Among skills it denies only `Skill(codex-gated-development)` to prevent recursive delegation; Claude may use other skills and subagents within the same read-only surface. Kimi receives a task-scoped tracked/untracked-only repository snapshot so its non-interactive auto-permission mode cannot mutate the live worktree. The wrapper disables user/project/plugin hooks, skill shell expansion, and MCP servers for the Claude invocation, rejects empty review targets, and fingerprints the live repository before and after both reviewers run. Any missing or failed reviewer, or detected live-repository mutation, fails the gate. Review calls for one task are serial; start a new Codex task or set a different session key when the task changes.

Managed-policy hooks cannot be disabled by a session-level setting. If an untrusted managed hook is configured, do not run the reviewer against the live repository; report the gate blocked. A mutation failure detects but does not undo external changes.

If `claude` or `kimi` is missing, unauthenticated, or cannot complete the review, the gate is blocked. Report the failure; do not replace the independent gate with self-review.

## When to use

First route the task. Skip external review when the work is local, reversible, single-path, has an obvious implementation, and has a direct check. If no concrete trigger below applies, skip the gate.

Require the complexity-routed Claude + Kimi gate when the work has any of these triggers:

- Cross-module design or an integration boundary.
- Ambiguous tradeoffs that need independent challenge.
- Concurrency, security, or destructive data work.
- Financial or quant logic, including any real strategy backtest.
- Failure modes that are hard to verify locally.

Diff size alone is not a trigger. A local one-line change to cost, slippage, risk sizing, stop/target, fill, signal timing, bar offsets, look-ahead, session timezone, aggressor polarity, data selection, rolling windows, field references, or config-valued strings has financial/quant risk and remains triggered. A typo, comment, or pure prose edit has no trigger and skips the gate.

## The shared gate

Claude and Kimi review repository state, so write plans, specs, and playbooks to files first. Untracked files count.

The reviewed scope must be non-empty and contain the artifact's actual substance, not only a filename, comment, docstring, or whitespace hunk. Before accepting a pass, inspect the scope yourself:

- For an uncommitted artifact, use the default working-tree review and confirm `git status --short --untracked-files=all`, staged diff, unstaged diff, and relevant untracked files contain the substance.
- If any task artifact has been committed, find the commit before the task and use `--base <commit-before-task>`. The review must cover the full branch diff plus current working-tree changes.
- An empty review, “nothing to review,” or a partial/decoy hunk is a skipped gate, not a clean pass.

For every dual gate:

1. Write the artifact or ensure the complete code diff exists.
2. Run `claude-review.sh adversarial` for plans/designs or `claude-review.sh code` for final code. The wrapper runs Claude and Kimi concurrently; point `--focus` at exact artifact paths and risks.
3. Triage both reports using `superpowers:receiving-code-review`:
   - Valid for this codebase: fix it.
   - Wrong, YAGNI, duplicate, or inapplicable: record a technical rebuttal; do not implement it.
   - Ambiguous or conflicting with a user decision: escalate to the user.
4. Re-run the concurrent Claude + Kimi review against the current artifact.
5. Clear the gate only when both new reviewer turns see the final state and both surface no valid, unaddressed blocking finding.

Any mutation after a clearing pass reopens the dual gate, including a rename, comment, constant, or cleanup. The clearing reviews must be the last operations that change the artifact before it advances.

### Convergence discipline

- Split findings into **blocking** (correctness, look-ahead, sizing, spec violation, security) and **residual** (style, optional alternatives, speculative hardening).
- Presume correctness, look-ahead, sizing, and security findings valid until code evidence disproves them. Never relabel them residual to end the loop.
- Clear the gate when both new reviewer turns have no valid unaddressed blocking finding. Record residuals instead of chasing literally empty reports.
- Require monotone progress. If a fix introduces a new blocking defect, or the blocking set fails to shrink for about three rounds, stop and escalate to the user. Do not silently ship an unconverged gate.

## Engineering Mode

| Phase | Action | Gate |
|---|---|---|
| 1. Spec + plan | Use `superpowers:brainstorming` when requirements are not already crisp; write the approved spec/design and implementation plan to files. | — |
| 2. **Dual planning gate** | Run `claude-review.sh adversarial` on the complete plan; converge concurrent Claude + Kimi review. | Required before code |
| 3. Implement | Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`, as applicable. | — |
| 4. Verify | Use `superpowers:verification-before-completion`; run the relevant tests and checks with current output. | — |
| 5. Simplify/review | Use `code-simplifier:code-simplifier` on the complete task diff, then use `pr-review-toolkit:review-pr`; triage findings and rerun affected validation after fixes. | Required before final dual gate |
| 6. **Dual final gate** | Run `claude-review.sh code` on the complete final diff; converge concurrent Claude + Kimi review. | Required before done |
| 7. Finish | Use `superpowers:finishing-a-development-branch` when working on a branch. | — |

Complex engineering has exactly one dual planning gate and one dual final gate. Both Claude and Kimi reports must clear each gate before the artifact advances.

## Quant Backtest Mode

| Phase | Action | Gate |
|---|---|---|
| 1. Study | Characterize only the raw phenomenon: base rates and forward-return distribution/asymmetry. Do not simulate strategy entries, stops, targets, P&L, R-multiples, or t-stats. Stop if the base phenomenon is uninteresting. | — |
| 2. Playbook | Write `strategies/<name>/playbook.md` with thesis, exact signal, entry on next-bar open, stop, target/exit, parameters, and universe. Leave results/verdict TBD. | — |
| 3. Backtest code | Write `strategies/<name>/backtest.py` on `strategies/common/harness.py`; inherit the realistic `CostModel`, fixed 0.5%-risk sizing, 10× cap, and R-multiple/t-stat metrics. Analyze on NQ, execute on MNQ. | — |
| 4. Pre-run Claude + Kimi gate | Run `claude-review.sh adversarial` on playbook and code together. Focus on look-ahead, next-bar fills, aggressor polarity, session timezone, degraded data, sizing/costs, and playbook fidelity. Both reports must clear. | Required before first real run |
| 5. Run | Run the real backtest only after the gate clears. | — |
| 6. Read skeptically | Evaluate full-sample net P&L, R-multiple t-stat, and per-year consistency. Treat the strategy as holding only when year behavior is consistent and t > 2. | — |
| 7. Robustness | Test parameter plateaus, micro-contract/2× slippage costs, and the pre/post-2024 OOS split. | — |
| 8. Verdict | Write the honest verdict into the playbook, including “not robust” when warranted. | — |

Any signal-timing, fill, aggressor-sign, or session-timezone logic shared by the study and backtest remains gated in Phase 4. A study result never pre-clears that code and is not evidence for rebutting a Phase-4 finding.

## Rationalizations to reject

| Excuse | Reality |
|---|---|
| “It is one line; skip the gate.” | Tiny changes to offsets, signs, costs, and comparisons carry maximal bug surface. |
| “I fixed everything; a re-run is unnecessary.” | Fixes are unreviewed until Claude and Kimi see the resulting state. |
| “The gate cleared before this final cleanup.” | A post-gate mutation ships state the gate never reviewed. Re-run or revert it. |
| “Run the backtest first to see whether it has legs.” | A look-ahead, fill, polarity, timezone, or sizing bug can manufacture the result and bias later review. |
| “The study already showed the edge.” | Ungated study output can contain the same causal bug and cannot rebut the independent code review. |
| “Claude or Kimi always finds something.” | Triage findings; require each reviewer's blocking findings to reach zero, not either report to become empty. |
| “Loop until Claude emits nothing.” | Log residuals. Escalate if the blocking set stops shrinking. |
| “Implement every Claude comment to be safe.” | Blind implementation breaks working code and prevents convergence. |
| “Self-review makes Claude and Kimi redundant.” | Reviews sharing the implementer's reasoning are not independent; the external reviewer sessions are the adversaries. |
| “The plan is obvious.” | A triggered complex task still needs its one dual planning gate before code. |
| “The deadline requires skipping steps.” | Time pressure does not waive a triggered dual gate. |

## Red flags

Stop and run the missing gate when:

- A triggered implementation is about to start without a cleared Claude + Kimi planning gate.
- A real backtest is about to run before Claude and Kimi review the playbook and backtest code.
- Triggered work is about to be declared complete without current verification and a final Claude + Kimi gate.
- A Claude or Kimi finding is being implemented without checking it against the repository.
- A review loop is ending from fatigue instead of a triaged zero-blocking result.
- The artifact changed after the last clearing Claude + Kimi reviews.

## Quick reference

- Complexity decision: skip unless a concrete trigger applies.
- Dual planning/design gate: `claude-review.sh adversarial` (concurrent Claude + Kimi).
- Codex simplification pass: `code-simplifier:code-simplifier`.
- Codex PR review: `pr-review-toolkit:review-pr`.
- Dual final code gate: `claude-review.sh code` (concurrent Claude + Kimi).
- Full task/branch scope: add `--base <commit-before-task>`.
- Reviewer focus: add `--focus "<artifact paths and risk classes>"`.
- Triage: `superpowers:receiving-code-review`.
- Verify: `superpowers:verification-before-completion`.
- Finish: `superpowers:finishing-a-development-branch` when applicable.
