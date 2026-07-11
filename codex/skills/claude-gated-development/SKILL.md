---
name: claude-gated-development
description: Use when starting any non-trivial engineering implementation task or quant strategy backtest, before planning or coding begins.
---

# Claude-Gated Development

## Overview

Do not advance an artifact until an independent Claude review has cleared it. For quant work, review the backtest code before its first real run.

**Core principle:** Treat external review as a gate. Triage every finding: fix valid findings, rebut invalid findings with technical evidence, and escalate ambiguous findings or conflicts with user decisions. Never implement every comment blindly, and never stop because the reviewer is inconvenient.

Use two modes:

- **Engineering:** plan → Claude gate → implement → verify → Claude gate.
- **Quant backtest:** study → playbook + code → Claude gate → first real run.

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

The wrapper starts a fresh, non-persistent Claude session with `dontAsk` plus an explicit read-only tool surface. It precomputes the Git scope into a temporary review bundle, removes Bash and file-edit tools, and keeps only `Read`, `Glob`, `Grep`, `Skill`, and `Agent`. Among skills it denies only `Skill(codex-gated-development)` to prevent recursive delegation; Claude may use other skills and subagents within the same read-only surface. It disables user/project/plugin hooks, skill shell expansion, and MCP servers for the invocation, rejects empty review targets, and fingerprints repository state before and after Claude runs. Any detected mutation fails the gate.

Managed-policy hooks cannot be disabled by a session-level setting. If an untrusted managed hook is configured, do not run the reviewer against the live repository; report the gate blocked. A mutation failure detects but does not undo external changes.

If `claude` is missing, unauthenticated, or cannot complete the review, the gate is blocked. Report the failure; do not replace the independent gate with self-review.

## When to use

- Start a concrete feature, refactor, or bugfix beyond a trivial prose-only edit.
- Start a quant strategy backtest, from strategy idea through validated verdict.

Do not use for a typo, comment, or pure prose edit with no logic or bug surface. Any change to cost, slippage, risk sizing, stop/target, fill, signal timing, bar offsets, look-ahead, session timezone, aggressor polarity, data selection, rolling windows, field references, or config-valued strings is never trivial. If unsure, gate it.

## The shared gate

Claude reviews repository state, so write plans, specs, and playbooks to files first. Untracked files count.

The reviewed scope must be non-empty and contain the artifact's actual substance, not only a filename, comment, docstring, or whitespace hunk. Before accepting a pass, inspect the scope yourself:

- For an uncommitted artifact, use the default working-tree review and confirm `git status --short --untracked-files=all`, staged diff, unstaged diff, and relevant untracked files contain the substance.
- If any task artifact has been committed, find the commit before the task and use `--base <commit-before-task>`. The review must cover the full branch diff plus current working-tree changes.
- An empty review, “nothing to review,” or a partial/decoy hunk is a skipped gate, not a clean pass.

For every gate:

1. Write the artifact or ensure the complete code diff exists.
2. Run `claude-review.sh adversarial` for plans/designs or `claude-review.sh code` for final code. Point `--focus` at exact artifact paths and risks.
3. Triage every finding using `superpowers:receiving-code-review`:
   - Valid for this codebase: fix it.
   - Wrong, YAGNI, duplicate, or inapplicable: record a technical rebuttal; do not implement it.
   - Ambiguous or conflicting with a user decision: escalate to the user.
4. Re-run Claude against the current artifact.
5. Clear the gate only when a fresh re-run sees the final state and surfaces no valid, unaddressed blocking finding.

Any mutation after a clearing pass reopens the gate, including a rename, comment, constant, or cleanup. The clearing review must be the last operation that changes the artifact before it advances.

### Convergence discipline

- Split findings into **blocking** (correctness, look-ahead, sizing, spec violation, security) and **residual** (style, optional alternatives, speculative hardening).
- Presume correctness, look-ahead, sizing, and security findings valid until code evidence disproves them. Never relabel them residual to end the loop.
- Clear the gate when a fresh re-run has no valid unaddressed blocking finding. Record residuals instead of chasing a literally empty report.
- Require monotone progress. If a fix introduces a new blocking defect, or the blocking set fails to shrink for about three rounds, stop and escalate to the user. Do not silently ship an unconverged gate.

## Engineering Mode

| Phase | Action | Gate |
|---|---|---|
| 1. Spec + initial plan | Use `superpowers:brainstorming` when requirements are not already crisp; write the approved spec/design and initial plan to files. | — |
| 2. **Gate #1** | Run `claude-review.sh adversarial` on the spec/design and initial plan; converge the shared gate. | Required before code |
| 3. Detailed implementation plan | Use `superpowers:writing-plans`; write the task-by-task implementation plan to a file. | — |
| 4. **Gate #2** | Run `claude-review.sh adversarial` on the detailed implementation plan; converge the shared gate. | Required before code |
| 5. Implement | Use `superpowers:subagent-driven-development` or `superpowers:executing-plans`, as applicable. | — |
| 6. Verify | Use `superpowers:verification-before-completion`; run the relevant tests and checks with current output. | — |
| 7. Simplify/review | Use `code-simplifier:code-simplifier` on the complete task diff, then use `pr-review-toolkit:review-pr`; triage findings and rerun affected validation after fixes. | Required before final Claude gate |
| 8. **Gate #3** | Run `claude-review.sh code` on the complete final diff; converge the shared gate. | Required before done |
| 9. Finish | Use `superpowers:finishing-a-development-branch` when working on a branch. | — |

If a small task uses one document for both spec and implementation plan, run one planning gate on that document. At least one Claude planning gate must clear before the first implementation edit.

## Quant Backtest Mode

| Phase | Action | Gate |
|---|---|---|
| 1. Study | Characterize only the raw phenomenon: base rates and forward-return distribution/asymmetry. Do not simulate strategy entries, stops, targets, P&L, R-multiples, or t-stats. Stop if the base phenomenon is uninteresting. | — |
| 2. Playbook | Write `strategies/<name>/playbook.md` with thesis, exact signal, entry on next-bar open, stop, target/exit, parameters, and universe. Leave results/verdict TBD. | — |
| 3. Backtest code | Write `strategies/<name>/backtest.py` on `strategies/common/harness.py`; inherit the realistic `CostModel`, fixed 0.5%-risk sizing, 10× cap, and R-multiple/t-stat metrics. Analyze on NQ, execute on MNQ. | — |
| 4. Pre-run Claude gate | Run `claude-review.sh adversarial` on playbook and code together. Focus on look-ahead, next-bar fills, aggressor polarity, session timezone, degraded data, sizing/costs, and playbook fidelity. | Required before first real run |
| 5. Run | Run the real backtest only after the gate clears. | — |
| 6. Read skeptically | Evaluate full-sample net P&L, R-multiple t-stat, and per-year consistency. Treat the strategy as holding only when year behavior is consistent and t > 2. | — |
| 7. Robustness | Test parameter plateaus, micro-contract/2× slippage costs, and the pre/post-2024 OOS split. | — |
| 8. Verdict | Write the honest verdict into the playbook, including “not robust” when warranted. | — |

Any signal-timing, fill, aggressor-sign, or session-timezone logic shared by the study and backtest remains gated in Phase 4. A study result never pre-clears that code and is not evidence for rebutting a Phase-4 finding.

## Rationalizations to reject

| Excuse | Reality |
|---|---|
| “It is one line; skip the gate.” | Tiny changes to offsets, signs, costs, and comparisons carry maximal bug surface. |
| “I fixed everything; a re-run is unnecessary.” | Fixes are unreviewed until Claude sees the resulting state. |
| “The gate cleared before this final cleanup.” | A post-gate mutation ships state the gate never reviewed. Re-run or revert it. |
| “Run the backtest first to see whether it has legs.” | A look-ahead, fill, polarity, timezone, or sizing bug can manufacture the result and bias later review. |
| “The study already showed the edge.” | Ungated study output can contain the same causal bug and cannot rebut the cold code review. |
| “Claude always finds something.” | Triage findings; require blocking findings to reach zero, not the report to become empty. |
| “Loop until Claude emits nothing.” | Log residuals. Escalate if the blocking set stops shrinking. |
| “Implement every Claude comment to be safe.” | Blind implementation breaks working code and prevents convergence. |
| “Self-review or per-task review makes Claude redundant.” | Those reviews share implementation context; the Claude gate is the independent adversary. |
| “The plan is obvious.” | At least one planning gate clears before code. |
| “The deadline requires skipping steps.” | Time pressure does not waive the gates that catch expensive defects. |

## Red flags

Stop and run the missing gate when:

- Implementation is about to start without a cleared Claude planning gate.
- A real backtest is about to run before Claude reviews the playbook and backtest code.
- Work is about to be declared complete without current verification and a final Claude gate.
- A Claude finding is being implemented without checking it against the repository.
- A review loop is ending from fatigue instead of a triaged zero-blocking result.
- The artifact changed after the last clearing Claude review.

## Quick reference

- Planning/design gate: `claude-review.sh adversarial`.
- Codex simplification pass: `code-simplifier:code-simplifier`.
- Codex PR review: `pr-review-toolkit:review-pr`.
- Final code gate: `claude-review.sh code`.
- Full task/branch scope: add `--base <commit-before-task>`.
- Reviewer focus: add `--focus "<artifact paths and risk classes>"`.
- Triage: `superpowers:receiving-code-review`.
- Verify: `superpowers:verification-before-completion`.
- Finish: `superpowers:finishing-a-development-branch` when applicable.
