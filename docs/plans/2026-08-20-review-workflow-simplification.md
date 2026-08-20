# Review workflow simplification

## Decisions

- Use Matt Pocock's externally managed `code-review` skill as the only general
  Codex reviewer. Keep this repository responsible for workflow routing,
  `code-simplifier`, and the final Claude gate.
- Retire the Kimi gate completely. Keep only the reciprocal Claude and Codex
  external gates; tool-neutral shared skills may still support Kimi Code.

## Changes

- Remove the local `pr-review-toolkit` plugin and route Codex general review to
  upstream `code-review` from a clean committed checkpoint.
- Remove `kimi-gated-development`, the shared Kimi runner, all `--kimi-risk`
  handling, and Kimi execution from both primary review wrappers.
- Remove Kimi-specific wrapper tests, installation steps, architecture claims,
  metadata, and infrastructure assertions while preserving Claude/Codex
  session, incremental-review, isolation, and verdict behavior.
- Document the two exact legacy install paths that existing users must remove;
  do not delete user data automatically or add a compatibility shim.
- Replace positive Kimi assertions with negative checks that the retired paths,
  `--kimi-risk`, and `GATED_KIMI_REVIEW_RUNNER` are absent.
- Preserve historical plans and Kimi Code support in the tool-neutral
  `bootstrap-project` and `finish-pr` skills.

Do not add a replacement specialist reviewer or speculative hardening layer.

## Verification

- `sh tests/test-engineering-infrastructure.sh`
- Both primary wrapper session test scripts
- `git diff --check`
- Final Claude code gate over the complete working-tree diff
