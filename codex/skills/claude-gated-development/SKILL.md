---
name: claude-gated-development
description: Use when engineering or quant work crosses module or integration boundaries, involves ambiguous architecture, concurrency, security, destructive data, financial logic, a real backtest, or failure modes that are hard to verify locally.
---

# Claude-Gated Development

## Core policy

Route by concrete risk, not diff size. Skip external review for local, reversible, single-path work with an obvious implementation and direct check.

For triggered work, Claude is always selected. Select Kimi as an additional specialist reviewer only for concurrency, idempotency, database transactions, tenant isolation, or distributed-state risks. Reviewer selection is discretionary, but completion is not: once Kimi is selected, wait for both reviewers and require both to return `VERDICT: PASS`. Kimi may use its built-in subagents, but must not call Claude, Codex, CodeSearch, another external model, or another review-gate workflow. Kimi failure, quota exhaustion, invalid output, `NEEDS REVISION`, or timeout blocks that gate round.

For a real quant strategy, review the playbook and backtest code before the first real run.

## Commands

Run from the repository root:

```bash
RUNNER="${CODEX_HOME:-$HOME/.codex}/skills/claude-gated-development/scripts/claude-review.sh"

"$RUNNER" adversarial --focus "Challenge the spec and plan at <path>."
"$RUNNER" code --base <commit-before-task> --focus "Review the final implementation against <plan path>."
"$RUNNER" code --base <commit-before-task> --since <previous-reviewed-head> \
  --focus "Re-check prior findings and review the committed fixes."
```

Select one narrow Kimi pass only for the specialist risks above:

```bash
"$RUNNER" code --base <commit-before-task> \
  --focus "Review the complete final implementation." \
  --kimi-risk concurrency \
  --kimi-risk idempotency \
  --kimi-risk tenant-isolation
```

The default command invokes only Claude. Repeat `--kimi-risk` for `concurrency`, `idempotency`, `database-transactions`, `tenant-isolation`, or `distributed-state`. The shared Kimi runner executes concurrently against a detached snapshot, reuses an explicit Kimi session when a task key is available, and uses a verified checkpoint for later `--since` rounds. Kimi may use `Agent` and `AgentSwarm` internally; an empty skill directory and the review prompt prohibit chaining to external reviewers or review gates. Claude reviews through a read-only tool surface; Kimi cannot read or write the live worktree. Any detected repository mutation fails the command.

Each completed report must end with `VERDICT: PASS` or `VERDICT: NEEDS REVISION`. Every selected reviewer must return `PASS`; failure, missing output, an invalid verdict, `NEEDS REVISION`, or timeout blocks the gate. Valid `NEEDS REVISION` reports still establish review checkpoints so committed fixes can use an incremental rerun.

Persistent review sessions are keyed by `CODEX_THREAD_ID`, or explicitly by `--session-key`. A first review is full-scope; later committed fixes may use `--since`.

## Route the task

Require the Claude gate for any of these triggers:

- Cross-module design or an integration boundary.
- Ambiguous architectural tradeoffs.
- Concurrency, security, or destructive data work.
- Financial or quant logic, including a real strategy backtest.
- Failure modes that are hard to verify locally.

Risk triggers override artifact type. Operative Markdown — skill definitions,
reviewer prompts, policy documents, and agent configuration — is gated like
code when a trigger applies: prose can be the runtime surface. Diff size is
not a trigger by itself. Tiny changes to cost, slippage, sizing, fills, signal
timing, offsets, look-ahead, timezone, polarity, data selection, or rolling
windows remain gated because their risk is financial. The prose exemption
covers only non-operative documentation: typos, comments, and prose no runtime
or reviewer behavior depends on.

## Review the real scope

Write plans, specs, and playbooks to files before review. Untracked files count.

- For uncommitted work, review the complete staged, unstaged, and relevant untracked state.
- Once any task artifact is committed, use `--base <commit-before-task>` so the review covers the full task diff plus working-tree changes.
- Treat an empty target, partial hunk, or `SKIPPED` verdict as a failed Claude gate.

## Engineering workflow

1. Write the spec and implementation plan when the approach is not already fixed.
2. Run one Claude `adversarial` planning gate before coding.
3. Implement and run current verification.
4. Use `code-simplifier:code-simplifier` on the complete task diff and apply only justified behavior-preserving simplifications. Rerun affected verification after any edit.
5. Use `pr-review-toolkit:review-pr` on the complete task diff and follow its applicable-lane, subagent, confidence-filtering, and deduplication workflow. Triage every finding, fix valid findings, and rerun affected verification.
6. Run one Claude `code` gate on the complete final diff.
7. Finish the branch only after the latest Claude turn clears the final state.

When the task contains a Kimi specialist risk and Kimi is selected, add the matching `--kimi-risk` values at the relevant planning or final gate. Do not request a broad second review. Fix valid findings and rerun the same selected reviewer set; do not continue past a failed, incomplete, or timed-out Kimi round.

## Triage and convergence

Use `superpowers:receiving-code-review` to classify every finding:

- Fix findings supported by the repository, specification, or reproducible behavior.
- Record technical evidence for wrong, duplicate, YAGNI, or inapplicable findings.
- Escalate ambiguity or conflict with a user decision.

Separate blocking defects from residual style, alternatives, and speculative hardening. Clear the gate only when every reviewer selected for the newest round sees the final state and returns `PASS`. Any later artifact mutation reopens the gate.

For incremental reruns, save the reviewed commit, commit the fixes, then use the same task base, session key, mode, and `--since`. Omit `--since` for an evidence-only rebuttal or after rewritten history.

## Quant backtest workflow

1. Study the raw phenomenon without simulating strategy P&L.
2. Write the exact playbook and backtest code.
3. Run the Claude `adversarial` gate on both before the first real run, focusing on look-ahead, next-bar fills, polarity, timezone, degraded data, sizing, costs, and playbook fidelity.
4. Run the backtest only after Claude clears it.
5. Evaluate net results, t-statistics, yearly consistency, parameter plateaus, costs, and out-of-sample behavior honestly.

## Rationalizations to reject

| Excuse | Reality |
|---|---|
| “Claude passed earlier.” | A later mutation is unreviewed; rerun Claude or revert it. |
| “Kimi was selected, but Claude passed.” | Selection is optional; a selected reviewer is mandatory and must return `PASS`. |
| “Kimi timed out, so omit it from this round.” | Keep the selected reviewer set stable; timeout fails the round. |
| “It is one line.” | Small financial, security, and concurrency changes can carry maximal risk. |
| “Run the backtest first.” | A causal bug can manufacture the result and bias later review. |

## Quick reference

- Mandatory planning gate: `claude-review.sh adversarial`.
- Mandatory final gate: `claude-review.sh code`.
- Conditionally mandatory specialist review: add one or more supported `--kimi-risk` values.
- Once selected, Kimi may delegate internally, must not chain external review gates, and must complete with `PASS`.
- Codex simplification pass: `code-simplifier:code-simplifier`.
- Codex self-review: `pr-review-toolkit:review-pr`.
- Full task scope: add `--base <commit-before-task>`.
- Incremental fix scope: add `--since <previous-reviewed-head>`.
- Verification: use `superpowers:verification-before-completion`.
- Finish: use `finish-pr`, then `superpowers:finishing-a-development-branch` when applicable.
