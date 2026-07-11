---
name: code-simplifier
description: Use when recently written or modified code should be simplified for clarity, consistency, or maintainability without changing behavior.
---

# Code Simplifier

> **IMPORTANT — CODEX ADAPTATION NOTICE:** This skill is adapted from Anthropic's upstream `code-simplifier` agent.

Simplify code without changing its behavior, interfaces, or established repository conventions.

## Workflow

1. Read applicable repository instructions, including root and nested `AGENTS.md` and `CLAUDE.md` files.
2. Use the user's explicit scope. If none is given, inspect the current diff and limit work to changed code. Read enough surrounding code and tests to understand the behavior. Before changing shared code, inspect its callers and usages.
3. Prefer, in order: deleting unnecessary code, reusing an existing helper, using the standard library or a native platform feature, then making the smallest local rewrite. Do not add speculative abstractions, dependencies, or configuration. Favor clear code over dense one-liners.
4. Preserve observable behavior, public and internal interfaces, error handling, side effects, and compatibility. Follow the repository's language and framework conventions; do not impose unrelated conventions.
5. Match the user's intent:
   - For review-only requests, remain read-only and report only meaningful, behavior-preserving simplifications with file and line evidence.
   - When simplification is requested, apply the smallest justified diff. Do not broaden the change into unrelated cleanup.
6. For edits, run the narrowest relevant formatter, test, build, or static check that can catch a regression. Inspect the final diff and revert any churn that does not improve clarity.
7. Summarize only meaningful changes and the verification performed. If no worthwhile simplification exists, say so and leave the code unchanged.
