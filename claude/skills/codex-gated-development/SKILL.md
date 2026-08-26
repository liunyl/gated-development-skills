---
name: codex-gated-development
description: Use when engineering or quant work crosses module or integration boundaries, involves ambiguous architecture, concurrency, security, destructive data, financial logic, durable interfaces, a real backtest, or failure modes that are hard to verify locally.
---

# Codex-Gated Development

## Core policy

Route by concrete risk, not diff size. Skip external review for local,
reversible, single-path work with an obvious implementation and a direct
check.

For triggered work, Codex is mandatory and must return `VERDICT: PASS`. It
runs against repositories you already trust enough to build and execute
locally; the gate reviews changes, it does not make an untrusted
repository safe to work in.

For a real quant strategy, review the playbook and backtest code before the
first real run.

## Commands

Run from the repository root. Pick one stable `--session-key` per task (a
short task slug) and reuse it for every round of that task; distinct tasks
take distinct keys, sequential or concurrent, and a fresh key starts with a
full first review:

```bash
RUNNER="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/codex-gated-development/scripts/codex-review.sh"

"$RUNNER" adversarial --session-key <task-key> --focus "Challenge the spec and plan at <path>."
"$RUNNER" code --session-key <task-key> --base <commit-before-task> \
  --focus "Review the final implementation against <plan path>."
"$RUNNER" code --session-key <task-key> --base <commit-before-task> --since <previous-reviewed-head> \
  --focus "Re-check prior findings and review the committed fixes."
```

Codex reviews headlessly in a read-only sandbox from a
neutral working root, with user config, rules, hooks, plugins, apps, and MCP
servers disabled for the run. Any detected repository mutation fails the
command.

Each completed report must end with `VERDICT: PASS` or
`VERDICT: NEEDS REVISION`. Failure, missing output, an invalid verdict, or
`NEEDS REVISION` blocks the gate. Valid `NEEDS REVISION` reports still
establish review checkpoints so committed fixes can use an incremental rerun.

Persistent review sessions are keyed by `--session-key`, or by
`CODEX_REVIEW_SESSION_KEY` / `CLAUDE_CODE_SESSION_ID` as fallbacks for ad-hoc
runs. One review round per key runs at a time; the runner's lock fails loudly
on overlap. A first review is full-scope; later committed fixes may use
`--since`.

## Route the task

Require the Codex gate for any of these triggers:

- Cross-module design or an integration boundary.
- Ambiguous architectural tradeoffs.
- Concurrency, security, or destructive data work.
- Financial or quant logic, including a real strategy backtest.
- Durable interfaces: schemas, protocols, migrations, persistence formats.
- Failure modes that are hard to verify locally.

Risk triggers override artifact type. Operative Markdown — skill definitions,
reviewer prompts, policy documents, agent configuration — is gated like code
when a trigger applies: in repositories like this one, prose is the runtime
surface. Diff size is not a trigger by itself. Tiny changes to cost, slippage,
sizing, fills, signal timing, offsets, look-ahead, timezone, polarity, data
selection, or rolling windows remain gated because their risk is financial.
The prose exemption covers only non-operative documentation: typos, comments,
and prose no runtime or reviewer behavior depends on.

## Review the real scope

Write plans, specs, and playbooks to files before review. Untracked files
count.

- For uncommitted work, review the complete staged, unstaged, and relevant
  untracked state.
- Once any task artifact is committed, use `--base <commit-before-task>` so
  the review covers the full task diff plus working-tree changes.
- Treat an empty target, partial hunk, or `SKIPPED` verdict as a failed Codex
  gate.

## Engineering workflow

1. Write the spec and implementation plan when the approach is not already
   fixed (`/brainstorming`, `/writing-plans`).
2. Run one Codex `adversarial` planning gate before coding.
3. Implement (`/subagent-driven-development` for larger work) and run current
   verification (`/verification-before-completion`).
4. Simplify and run the normal review pass (`/simplify`, then `/code-review`).
5. Run one Codex `code` gate on the complete final diff.
6. Finish the branch only after the latest Codex turn clears the final state.

## Triage and convergence

Use `/receiving-code-review` to classify every finding:

- Fix findings supported by the repository, specification, or reproducible
  behavior.
- Record technical evidence for wrong, duplicate, YAGNI, or inapplicable
  findings.
- Escalate ambiguity or conflict with a user decision.

Separate blocking defects from residual style, alternatives, and speculative
hardening. Clear the gate only when the newest Codex round sees the final
state and returns `PASS`. Any later artifact mutation reopens the gate.
Convergence must be monotone: if the blocking set is
not shrinking after about three rounds, or a fix keeps reintroducing
findings, stop looping and escalate to the human with the current state.

For incremental reruns, save the reviewed commit, commit the fixes, then use
the same task base, session key, mode, and `--since`. Omit `--since` for an
evidence-only rebuttal or after rewritten history.

## Quant backtest workflow

1. Study the raw phenomenon without simulating strategy P&L.
2. Write the exact playbook and backtest code.
3. Run the Codex `adversarial` gate on both before the first real run,
   focusing on look-ahead, next-bar fills, polarity, timezone, degraded data,
   sizing, costs, and playbook fidelity.
4. Run the backtest only after Codex clears it.
5. Evaluate net results, t-statistics, yearly consistency, parameter
   plateaus, costs, and out-of-sample behavior honestly.

## Rationalizations to reject

| Excuse | Reality |
|---|---|
| “Codex passed earlier.” | A later mutation is unreviewed; rerun Codex or revert it. |
| “It is one line.” | Small financial, security, and concurrency changes can carry maximal risk. |
| “It is only a doc edit.” | Operative Markdown is the runtime surface here; risk triggers override artifact type. |
| “Run the backtest first.” | A causal bug can manufacture the result and bias later review. |

## Quick reference

- Mandatory planning gate: `codex-review.sh adversarial`.
- Mandatory final gate: `codex-review.sh code`.
- Full task scope: add `--base <commit-before-task>`.
- Incremental fix scope: add `--since <previous-reviewed-head>`.
- One `--session-key` per task; a fresh key means a fresh full review.
- Verification: use `/verification-before-completion`.
- Finish: use `finish-pr`, then `finish-branch` when applicable.
