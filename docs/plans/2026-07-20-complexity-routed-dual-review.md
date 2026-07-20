# Complexity-Routed Dual Review

## Decision

External review is exceptional, not the default. Skip it for local, reversible,
single-path changes with an obvious implementation and a direct check. Use it
when there is a concrete complexity or risk reason: cross-module design,
ambiguous tradeoffs, concurrency, security, destructive data changes, financial
or quant logic, or failure modes that are hard to verify locally. Diff size
alone is not the decision. If no concrete trigger applies, skip the gate.

Complex engineering work gets one planning review and one final implementation
review. A real quant backtest remains complex and must be reviewed before its
first run.

## Reviewer behavior

Keep `claude-review.sh` for compatibility, but run Claude and Kimi concurrently
against the same captured Git scope. Claude retains its restricted read-only
tool surface and task-scoped session. Kimi gets a task-scoped session and a
tracked/untracked-only repository snapshot so its non-interactive auto
permission mode cannot accidentally change the live worktree.

Print labeled results for both reviewers. A missing or failed reviewer, an
empty scope, or a live-repository fingerprint change fails the gate. The
implementer triages both reports; both must have no valid blocking finding.

Find Kimi through `PATH` first and its standard `~/.kimi-code/bin/kimi` install
location second so non-interactive Codex shells work without sourcing
`~/.zshrc`.
