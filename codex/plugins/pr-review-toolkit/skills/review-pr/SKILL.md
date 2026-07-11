---
name: review-pr
description: Use when reviewing a pull request, branch diff, commit range, or working-tree changes for correctness, comments, tests, error handling, type design, or simplification.
---

# Review PR

Review only the selected changes. Treat review and mutation as separate operations.

## Workflow

1. Determine the exact scope: user-selected PR, branch diff, commit range, or working-tree diff. Read repository instructions (`AGENTS.md`, `CLAUDE.md`, and nested equivalents), inspect the diff, and open enough surrounding code and tests to verify behavior.
2. Always select explicitly requested lanes. Otherwise select each applicable lane using the criteria below; `all` means every applicable lane. Read every selected reference in full:
   - `code`: any code, configuration, build, or dependency change — [code-reviewer.md](references/code-reviewer.md)
   - `comments`: comments or documentation changed — [comment-analyzer.md](references/comment-analyzer.md)
   - `tests`: behavior or tests changed — [pr-test-analyzer.md](references/pr-test-analyzer.md)
   - `errors`: error handling, validation, fallback, retry, or null handling changed — [silent-failure-hunter.md](references/silent-failure-hunter.md)
   - `types`: types, schemas, or data models changed — [type-design-analyzer.md](references/type-design-analyzer.md)
   - `simplify`: implementation code changed — [code-simplifier.md](references/code-simplifier.md)
   - `all`: every applicable lane
3. Keep every lane read-only. When Codex subagents are available, determine the available child-agent capacity and use `spawn_agent` for batches no larger than that capacity, giving each lane the same scope, repository instructions, diff, and its selected reference. Wait for and collect every result in a batch before dispatching the next. Run any unspawned lane or lane whose subagent failed sequentially before normalization; if no capacity exists, run all lanes sequentially. Require each lane to cite diff evidence with an exact file and line. The `simplify` lane proposes changes; it never applies them.
4. Normalize each candidate to: severity, confidence (0-100), file, line, impact, and minimal fix. Discard findings below confidence 80, then deduplicate overlapping root causes while retaining the strongest evidence and relevant lane names.
5. Report findings first, ordered by severity, followed by a brief scope summary. If none survive filtering, say so and note residual testing or inspection limits.

Never post PR comments, submit reviews, edit files, or apply suggested fixes without explicit authorization for that separate action.
