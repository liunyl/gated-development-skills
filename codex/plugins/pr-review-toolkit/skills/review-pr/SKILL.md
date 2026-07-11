---
name: review-pr
description: Use when reviewing a pull request, branch diff, commit range, or working-tree changes for correctness, comments, tests, error handling, type design, or simplification.
---

# Review PR

Review only the selected changes. Treat review and mutation as separate operations.

## Workflow

1. Determine the exact scope: user-selected PR, branch diff, commit range, or working-tree diff. Read repository instructions (`AGENTS.md`, `CLAUDE.md`, and nested equivalents), inspect the diff, and open enough surrounding code and tests to verify behavior.
2. Select the requested lanes, or all applicable lanes when none are named. Read every selected reference in full:
   - `code`: [code-reviewer.md](references/code-reviewer.md)
   - `comments`: [comment-analyzer.md](references/comment-analyzer.md)
   - `tests`: [pr-test-analyzer.md](references/pr-test-analyzer.md)
   - `errors`: [silent-failure-hunter.md](references/silent-failure-hunter.md)
   - `types`: [type-design-analyzer.md](references/type-design-analyzer.md)
   - `simplify`: [code-simplifier.md](references/code-simplifier.md)
   - `all`: every applicable lane
3. Keep every lane read-only. When Codex subagents are available, use `spawn_agent` to dispatch one per selected lane in parallel, giving each the same scope, repository instructions, diff, and selected reference. Otherwise run the lanes sequentially. Require each lane to cite diff evidence with an exact file and line. The `simplify` lane proposes changes; it never applies them.
4. Normalize each candidate to: severity, confidence (0-100), file, line, impact, and minimal fix. Discard findings below confidence 80, then deduplicate overlapping root causes while retaining the strongest evidence and relevant lane names.
5. Report findings first, ordered by severity, followed by a brief scope summary. If none survive filtering, say so and note residual testing or inspection limits.

Never post PR comments, submit reviews, edit files, or apply suggested fixes without explicit authorization for that separate action.
