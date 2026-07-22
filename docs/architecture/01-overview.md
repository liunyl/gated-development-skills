# System overview

## System context

This repository distributes three runtime-specific review gates and two shared
engineering workflow skills. Runtime-specific policies remain under `claude/`,
`codex/`, and `kimi/`; the tool-neutral bootstrap and PR-finishing workflows
live under `shared/skills/`. (`claude/skills/codex-gated-development/`,
`codex/skills/claude-gated-development/`,
`kimi/skills/kimi-gated-development/`, `shared/skills/bootstrap-project/`,
`shared/skills/finish-pr/`)

## Components

| Component | Responsibility | Repository source |
|---|---|---|
| Claude Code gate | Requires independent Codex review for non-trivial engineering work and quant backtests. | `claude/skills/codex-gated-development/SKILL.md` |
| Codex gate | Routes complex or high-risk work through a mandatory Claude review, with optional targeted Kimi review for named state-consistency risks. | `codex/skills/claude-gated-development/SKILL.md`; `codex/skills/claude-gated-development/scripts/claude-review.sh` |
| Kimi Code gate | Uses a judgment-based threshold and persistent Claude and Codex reviewer sessions. | `kimi/skills/kimi-gated-development/SKILL.md`; `kimi/skills/kimi-gated-development/scripts/` |
| `bootstrap-project` | Builds an evidence-backed module map and settles the architecture taxonomy before prose, while preserving repository-specific guidance and installing managed instructions, a PR template, and current architecture docs. | `shared/skills/bootstrap-project/SKILL.md`; `shared/skills/bootstrap-project/assets/`; `shared/skills/bootstrap-project/scripts/update-managed-block.sh` |
| `finish-pr` | Audits the complete proposed diff, drafts commit and PR content, and hands branch lifecycle work to an established finishing workflow. | `shared/skills/finish-pr/SKILL.md` |

## Primary flow

1. Install each runtime-specific gate in its matching runtime skill directory,
   then copy both shared skill folders unchanged to all three runtimes.
   (`README.md`)
2. Invoke `bootstrap-project` when a repository needs the shared instruction,
   architecture, and PR-template baseline. It records an evidence-backed
   module map and chooses the taxonomy before drafting architecture prose; its
   deterministic helper then merges the managed assets while preserving
   unmanaged content.
   (`shared/skills/bootstrap-project/SKILL.md`;
   `shared/skills/bootstrap-project/scripts/update-managed-block.sh`)
3. During implementation, follow the selected runtime's review gate and keep
   comments and architecture documentation current under the managed
   engineering standards. The Codex gate performs a full first Claude review
   per mode, then can use a verified commit checkpoint for later incremental
   Claude rounds. Optional Kimi review is selected by named risk and always
   receives a fresh full snapshot. (`claude/skills/codex-gated-development/SKILL.md`;
   `codex/skills/claude-gated-development/SKILL.md`;
   `codex/skills/claude-gated-development/scripts/claude-review.sh`;
   `kimi/skills/kimi-gated-development/SKILL.md`;
   `shared/skills/bootstrap-project/assets/project-instructions.md`)
4. After implementation, invoke `finish-pr` to audit evidence and draft the
   integration artifacts before handing branch operations to the runtime's
   established finishing workflow. (`shared/skills/finish-pr/SKILL.md`)

## Cross-cutting invariants

- Shared skills install unchanged into Claude Code, Codex, and Kimi Code;
  runtime-specific gates are not interchanged. (`README.md`)
- Managed instruction and PR-template content comes from the bootstrap assets;
  repository-specific unmanaged content remains outside those blocks.
  (`shared/skills/bootstrap-project/assets/`;
  `shared/skills/bootstrap-project/scripts/update-managed-block.sh`)
- Documentation and comment work is a development-time responsibility;
  `finish-pr` audits it rather than silently repairing it.
  (`shared/skills/bootstrap-project/assets/project-instructions.md`;
  `shared/skills/finish-pr/SKILL.md`)
- Architecture overviews stay focused on system context, high-level flows,
  cross-cutting invariants, and navigation. Independently explainable durable
  modules grow into focused numbered subsystem documents instead.
  (`shared/skills/bootstrap-project/SKILL.md`;
  `shared/skills/bootstrap-project/assets/project-instructions.md`)
- `docs/architecture/` describes the current code. `docs/plans/` and
  `docs/superpowers/` preserve historical change context rather than
  authoritative current architecture.
  (`docs/README.md`; `shared/skills/bootstrap-project/SKILL.md`)
- Codex gate checkpoints are scoped by repository, task session, and review
  mode. Each `<session-file>.<mode>.reviewed` record stores the resolved task
  base and the Claude-reviewed `HEAD`. A later `--since` request uses
  `incremental-review-scope.txt` only when the Claude session and checkpoint
  are trustworthy. Otherwise Claude receives the full task bundle, while dirty
  or invalid commit ranges fail closed. Optional Kimi review has no checkpoint
  and always receives the full task. Claude checkpoints advance after a valid
  `PASS` or `NEEDS REVISION` report regardless of Kimi availability; a skipped
  or malformed Claude review cannot establish incremental scope.
  (`codex/skills/claude-gated-development/scripts/claude-review.sh`)
- Reviewer recursion is blocked at the external-gate boundary: Claude cannot
  load `codex-gated-development`, while optional Kimi receives an empty skill
  directory and instructions not to invoke Claude, Codex, CodeSearch, another
  external model, or another review gate. Native Claude subagents and Kimi
  `Agent`/`AgentSwarm` subagents remain available.
  (`codex/skills/claude-gated-development/scripts/claude-review.sh`)
- The dependency-free engineering infrastructure test exercises shared assets,
  managed-block behavior, dogfood files, and installation documentation.
  (`tests/test-engineering-infrastructure.sh`)

## Source map

| Claim | Repository source |
|---|---|
| Claude Code review gate | `claude/skills/codex-gated-development/` |
| Codex review gate | `codex/skills/claude-gated-development/` |
| Kimi Code review gate | `kimi/skills/kimi-gated-development/` |
| Repository bootstrap workflow and managed assets | `shared/skills/bootstrap-project/` |
| Final PR audit and drafting workflow | `shared/skills/finish-pr/` |
| Engineering infrastructure contract | `tests/test-engineering-infrastructure.sh` |
