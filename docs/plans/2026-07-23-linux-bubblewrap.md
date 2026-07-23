# Linux bubblewrap support

## Problem

The Codex review gate runs optional Kimi reviews only through macOS
`sandbox-exec`. On Linux this disables Kimi even though Bubblewrap provides the
native process sandbox.

## Requirements

- Keep the existing macOS `sandbox-exec` path unchanged.
- On Linux, require `bwrap`; if it is unavailable or cannot start, continue
  with Claude only and never run Kimi unsandboxed.
- Match the macOS allow-by-default policy while denying Kimi read and write
  access to the live repository and its Git state.
- Preserve network access because Kimi is a remote CLI.
- Document the Linux dependency and cover platform selection and filesystem
  isolation with the existing gate test.

## Implementation

Select the native sandbox from `uname`: `sandbox-exec` on Darwin and `bwrap`
on Linux. Reuse the current Seatbelt profile on Darwin. On Linux, invoke Kimi
through Bubblewrap with a read-write root, a minimal device filesystem, and
empty `tmpfs` mounts over the live repository and any Git directory outside
it. Use a private PID namespace and `/proc` mount so host-process root links
cannot bypass those masks. Probe Bubblewrap before enabling Kimi so kernels
that prohibit unprivileged namespaces degrade to Claude-only. Other platforms
keep the current fail-closed optional-review behavior.

## Verification

1. Run `codex/skills/claude-gated-development/scripts/test-claude-review-session.sh`.
2. Run `sh tests/test-engineering-infrastructure.sh`.
3. Compare the repository skill with `~/.codex/skills/claude-gated-development`
   after synchronization.
