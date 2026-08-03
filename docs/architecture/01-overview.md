# System overview

## System context

This repository distributes three runtime-specific review gates, one shared
Kimi review runner, and two shared engineering workflow skills. Runtime-specific
policies remain under `claude/`, `codex/`, and `kimi/`; shared runtime code and
tool-neutral workflows live under `shared/`. (`claude/skills/codex-gated-development/`,
`codex/skills/claude-gated-development/`,
`kimi/skills/kimi-gated-development/`, `shared/scripts/kimi-review.sh`,
`shared/skills/bootstrap-project/`, `shared/skills/finish-pr/`)

## Components

| Component | Responsibility | Repository source |
|---|---|---|
| Claude Code gate | Routes complex or high-risk work through a mandatory Codex review in one persistent per-task session (`codex exec resume`) and may select the shared Kimi reviewer for named state-consistency risks. Every selected reviewer must return `PASS`. | `claude/skills/codex-gated-development/SKILL.md`; `claude/skills/codex-gated-development/scripts/codex-review.sh` |
| Codex gate | Routes complex or high-risk work through a mandatory Claude review and may select the shared Kimi reviewer for named state-consistency risks. Every selected reviewer must return `PASS`. | `codex/skills/claude-gated-development/SKILL.md`; `codex/skills/claude-gated-development/scripts/claude-review.sh` |
| Shared Kimi runner | Owns the disposable detached snapshot, keyed sandbox-hidden session/checkpoint state, isolated Kimi runtime, native sandbox, progress/heartbeat output, timeout, and verdict exit semantics used by both routed gates. | `shared/scripts/kimi-review.sh` |
| Kimi Code gate | Uses a judgment-based threshold and persistent Claude and Codex reviewer sessions. | `kimi/skills/kimi-gated-development/SKILL.md`; `kimi/skills/kimi-gated-development/scripts/` |
| `bootstrap-project` | Builds an evidence-backed module map and settles the architecture taxonomy before prose, while allowing a repository with at most one durable module to keep readable detail in one overview and preserving an existing equivalent current-architecture hierarchy. | `shared/skills/bootstrap-project/SKILL.md`; `shared/skills/bootstrap-project/assets/`; `shared/skills/bootstrap-project/scripts/update-managed-block.sh` |
| `finish-pr` | Audits the complete proposed diff, drafts commit and PR content, and hands branch lifecycle work to an established finishing workflow. | `shared/skills/finish-pr/SKILL.md` |

## Primary flow

1. Install each runtime-specific gate in its matching runtime skill directory,
   install the shared Kimi runner once under the user's data directory, then
   copy both shared skill folders unchanged to all three runtimes.
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
   engineering standards. Both routed gates perform a full first external
   review per mode, then can use a verified commit checkpoint for later
   incremental rounds in the same persistent reviewer session. Kimi may be
   selected by named risk; once selected, the gate waits for it and requires
   `PASS`. With a task/session key, its shared runner independently resumes an
   explicit Kimi session and activates incremental scope only from a matching
   verified checkpoint; keyless rounds always start full. It scrubs the
   detached repository snapshot after each round.
   (`claude/skills/codex-gated-development/SKILL.md`;
   `claude/skills/codex-gated-development/scripts/codex-review.sh`;
   `codex/skills/claude-gated-development/SKILL.md`;
   `codex/skills/claude-gated-development/scripts/claude-review.sh`;
   `shared/scripts/kimi-review.sh`;
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
  cross-cutting invariants, and navigation. A repository with
  at most one durable module may keep readable detail in its overview; multiple
  durable modules or detail that needs independent navigation require
  focused numbered subsystem documents under the default hierarchy or the
  existing equivalent's conventions.
  (`shared/skills/bootstrap-project/SKILL.md`;
  `shared/skills/bootstrap-project/assets/project-instructions.md`)
- `docs/architecture/` is the default current-architecture hierarchy; an
  existing equivalent current-architecture hierarchy retains authority. This
  repository uses `docs/architecture/` for current code, while `docs/plans/`
  and `docs/superpowers/` preserve historical change context.
  (`docs/README.md`; `shared/skills/bootstrap-project/SKILL.md`)
- Gate checkpoints are scoped by repository, task session key, and review
  mode. Each primary wrapper records the resolved task base and reviewed
  `HEAD`; the Claude-side wrapper additionally binds the Codex session id.
  With a task/session key, the shared Kimi runner separately stores an explicit
  Kimi session id and a per-mode checkpoint bound to that session under the
  sandbox-hidden `kimi-review-state/` root. A later `--since` request uses
  the incremental bundle only for reviewers whose session and checkpoint are
  trustworthy; another reviewer may independently fall back to the full task.
  Dirty `--since` requests or invalid commit ranges fail before reviewers
  start. The Kimi repository fingerprint must remain stable through snapshot
  preparation and review before its session or checkpoint advances. Valid
  `PASS` or `NEEDS REVISION` reports advance that reviewer's checkpoint, while
  only `PASS` clears the gate and skipped or malformed output establishes no
  state.
  (`claude/skills/codex-gated-development/scripts/codex-review.sh`;
  `codex/skills/claude-gated-development/scripts/claude-review.sh`;
  `shared/scripts/kimi-review.sh`)
- Claude-side rounds sharing a session key are serialized by a `mkdir` lock
  that fails loudly on overlap and is never removed silently, and the Codex
  reviewer executes from a neutral working root outside the repository with
  user config, rules, hooks, plugins, apps, and MCP servers disabled — the
  reviewed repository can never configure its own reviewer, and
  `mcp_servers={}` alone is insufficient because TOML table overrides merge.
  (`claude/skills/codex-gated-development/scripts/codex-review.sh`)
- Reviewer chaining is prohibited at the external-gate boundary: Claude cannot
  load `codex-gated-development`, the Codex reviewer is instructed not to
  invoke gate skills, wrapper scripts, or other agent CLIs inside its
  read-only sandbox, and selected Kimi receives an empty skill directory plus
  the same no-chaining instruction from both routed gates. Kimi retains Bash
  and built-in `Agent`/`AgentSwarm` inside its disposable snapshot, so its
  no-chaining rule is contractual; the native sandbox separately prevents it
  from reading gate state or modifying the host outside its detached workspace
  and isolated Kimi runtime.
  (`claude/skills/codex-gated-development/scripts/codex-review.sh`;
  `codex/skills/claude-gated-development/scripts/claude-review.sh`;
  `shared/scripts/kimi-review.sh`)
- Selected Kimi execution fails closed when the platform sandbox is unavailable.
  macOS denies host writes by default and hides live repository, Git, and
  gate-state reads with `sandbox-exec`; Linux mounts the host read-only, masks
  those protected paths, and uses a private PID namespace and `/proc` mount to
  prevent host-root path bypasses. Both platforms allow writes only to the
  detached workspace and an isolated `KIMI_CODE_HOME`
  partitioned by the source Kimi profile and containing review-only
  credentials, sessions, and logs. The shared runner
  forwards Kimi's native progress, emits periodic `ACTIVE`/`IDLE` heartbeats,
  scrubs each repository
  snapshot on exit, and terminates the Kimi process group after
  `KIMI_REVIEW_TIMEOUT_SECONDS` (default 1800); timeout blocks the gate.
  (`shared/scripts/kimi-review.sh`; `README.md`)
- The dependency-free engineering infrastructure test exercises shared assets,
  managed-block behavior, dogfood files, and installation documentation.
  (`tests/test-engineering-infrastructure.sh`)

## Source map

| Claim | Repository source |
|---|---|
| Claude Code review gate and Codex-session runner | `claude/skills/codex-gated-development/`; `claude/skills/codex-gated-development/scripts/codex-review.sh` |
| Codex review gate | `codex/skills/claude-gated-development/` |
| Shared Kimi review runner | `shared/scripts/kimi-review.sh` |
| Kimi Code review gate | `kimi/skills/kimi-gated-development/` |
| Repository bootstrap workflow and managed assets | `shared/skills/bootstrap-project/` |
| Final PR audit and drafting workflow | `shared/skills/finish-pr/` |
| Engineering infrastructure contract | `tests/test-engineering-infrastructure.sh` |
