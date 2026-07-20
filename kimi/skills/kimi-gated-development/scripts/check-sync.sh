#!/usr/bin/env bash
# Drift guard: the kimi copies of claude-review.sh and its session test must
# stay byte-identical to the codex-skill originals. Run after editing either side.
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
upstream="$repo_root/codex/skills/claude-gated-development/scripts"
vendored="$repo_root/kimi/skills/kimi-gated-development/scripts"

diff "$upstream/claude-review.sh" "$vendored/claude-review.sh"
diff "$upstream/test-claude-review-session.sh" "$vendored/test-claude-review-session.sh"
printf 'claude wrapper copies in sync\n'
