# System overview

## System context

This repository distributes two reciprocal review gates and three shared
engineering workflow skills. Runtime-specific policies remain under `claude/`
and `codex/`; tool-neutral workflows live under `shared/` and still support
Claude Code, Codex, and Kimi Code. (`claude/skills/codex-gated-development/`,
`codex/skills/claude-gated-development/`, `shared/skills/bootstrap-project/`,
`shared/skills/finish-pr/`, `shared/skills/finish-branch/`) The Codex flow also
composes this repository's
`code-simplifier` adapter with the externally managed `code-review` skill from
`mattpocock/skills`.

## Components

| Component | Responsibility | Repository source |
|---|---|---|
| Claude Code gate | Routes complex or high-risk Claude-side work through a mandatory Codex review. | `claude/skills/codex-gated-development/SKILL.md`; `claude/skills/codex-gated-development/scripts/codex-review.sh` |
| Codex gate | Routes complex or high-risk Codex-side work through a mandatory Claude review. | `codex/skills/claude-gated-development/SKILL.md`; `codex/skills/claude-gated-development/scripts/claude-review.sh` |
| Codex simplifier adapter | Provides the behavior-preserving simplification step before general review. | `codex/plugins/code-simplifier/` |
| Upstream Codex reviewer | Owns the single general-purpose Codex review pass, keeping its `Standards` and `Spec` axes separate. It is installed and updated from `mattpocock/skills`, not vendored here. | Integration contract: `codex/skills/claude-gated-development/SKILL.md`; installation: `README.md` |
| `bootstrap-project` | Establishes an evidence-backed current-architecture hierarchy, managed engineering instructions, and a pull-request template while preserving repository-specific content and existing equivalent architecture structures. | `shared/skills/bootstrap-project/SKILL.md`; `shared/skills/bootstrap-project/assets/`; `shared/skills/bootstrap-project/scripts/update-managed-block.sh` |
| `finish-pr` | Audits the complete proposed diff, drafts commit and PR content, and hands branch lifecycle work to an established finishing workflow. | `shared/skills/finish-pr/SKILL.md` |
| `finish-branch` | Completes branch integration after the audit: verifies tests, presents merge/PR/keep/discard options, and owns worktree cleanup with provenance checks. Vendored from `superpowers:finishing-a-development-branch` (MIT) so the workflow works without the external skill collection. | `shared/skills/finish-branch/SKILL.md`; `shared/skills/finish-branch/LICENSE` |

## Primary flow

1. Install each reciprocal gate in its matching runtime skill directory, then
   copy the shared skill folders unchanged to all three supported runtimes.
   For the Codex workflow, install the local `code-simplifier` adapter and
   install `code-review` plus `setup-matt-pocock-skills` from
   `mattpocock/skills`. (`README.md`)
2. Invoke `bootstrap-project` when a repository needs the shared instruction,
   architecture, and PR-template baseline. It builds an evidence-backed module
   map, selects the repository's authoritative architecture hierarchy, drafts
   a compact current model, and merges managed assets while preserving
   unmanaged content. (`shared/skills/bootstrap-project/SKILL.md`;
   `shared/skills/bootstrap-project/scripts/update-managed-block.sh`)
3. During implementation, follow the selected runtime's review gate and keep
   comments current and apply the architecture freshness rule. The Codex
   workflow simplifies the complete task, reviews a clean committed checkpoint
   through upstream `code-review` with separate `Standards` and `Spec` results,
   and then sends the complete final working-tree scope through the Claude gate.
   Each reciprocal gate starts a task and review mode with a full-scope review;
   later rounds may narrow to committed fixes while preserving the same review
   context.
   (`claude/skills/codex-gated-development/SKILL.md`;
   `claude/skills/codex-gated-development/scripts/codex-review.sh`;
   `codex/skills/claude-gated-development/SKILL.md`;
   `codex/skills/claude-gated-development/scripts/claude-review.sh`;
   `shared/skills/bootstrap-project/assets/project-instructions.md`)
4. After implementation, invoke `finish-pr` to audit evidence and draft the
   integration artifacts before handing branch operations to the bundled
   `finish-branch` skill or the runtime's established finishing workflow.
   (`shared/skills/finish-pr/SKILL.md`; `shared/skills/finish-branch/SKILL.md`)

## Cross-cutting invariants

- Shared skills install unchanged into Claude Code, Codex, and Kimi Code;
  runtime-specific gates install only in their matching Claude or Codex
  runtime. (`README.md`)
- General-purpose Codex review has one owner: upstream `code-review`. This
  repository neither vendors nor patches it, and distributes only the
  `code-simplifier` adapter through its marketplace. The overlay requires a
  clean committed checkpoint because the upstream fixed-point diff does not
  include working-tree changes; the final Claude gate still covers them.
  (`codex/skills/claude-gated-development/SKILL.md`; `README.md`;
  `.agents/plugins/marketplace.json`)
- Managed instruction and PR-template content comes from the bootstrap assets;
  repository-specific unmanaged content remains outside those blocks.
  (`shared/skills/bootstrap-project/assets/`;
  `shared/skills/bootstrap-project/scripts/update-managed-block.sh`)
- Comments are a development-time responsibility. Architecture is revised
  during implementation only when a current architecture claim or core model
  would otherwise become false or materially incomplete; dedicated
  documentation work may correct the current model or consolidate sediment.
  `finish-pr` audits this work rather than silently repairing it.
  (`shared/skills/bootstrap-project/assets/project-instructions.md`;
  `shared/skills/finish-pr/SKILL.md`)
- Branch lifecycle mutation has one bundled owner: `finish-branch`, vendored
  from `superpowers:finishing-a-development-branch` (MIT; see
  `shared/skills/finish-branch/LICENSE`). `finish-pr` stays read-only for
  remotes and branch/worktree lifecycle and never duplicates that workflow's
  mutation, ordering, verification, or provenance logic.
  (`shared/skills/finish-pr/SKILL.md`; `shared/skills/finish-branch/`)
- Architecture overviews stay focused on system context, high-level flows,
  cross-cutting invariants, and navigation.
  A repository with at most one durable module may keep readable detail in its
  overview; multiple durable modules or detail that needs independent
  navigation require focused numbered subsystem documents under the default
  hierarchy or the existing equivalent's conventions.
  (`shared/skills/bootstrap-project/SKILL.md`;
  `shared/skills/bootstrap-project/assets/project-instructions.md`)
- `docs/architecture/` is the default current-architecture hierarchy; an
  existing equivalent current-architecture hierarchy retains authority. This
  repository uses `docs/architecture/` for current code, while `docs/plans/`
  and `docs/superpowers/` preserve historical change context.
  (`docs/README.md`; `shared/skills/bootstrap-project/SKILL.md`)
- Review continuity is scoped to one repository, task, and review mode.
  Incremental rounds require an established full-scope baseline and a verified
  committed checkpoint; otherwise the gate returns to a full review.
  (`claude/skills/codex-gated-development/SKILL.md`;
  `codex/skills/claude-gated-development/SKILL.md`)
- The Codex reviewer executes from a neutral working root outside the
  repository with user config, rules, hooks, plugins, apps, and MCP servers
  disabled, so reviewed repository configuration cannot configure its own
  reviewer.
  (`claude/skills/codex-gated-development/scripts/codex-review.sh`)
- Reviewer chaining is prohibited at the external-gate boundary: Claude cannot
  load `codex-gated-development`, and the Codex reviewer is instructed not to
  invoke gate skills, wrapper scripts, or other agent CLIs inside its read-only
  sandbox. (`claude/skills/codex-gated-development/scripts/codex-review.sh`;
  `codex/skills/claude-gated-development/scripts/claude-review.sh`)

## Source map

| Claim | Repository source |
|---|---|
| Claude Code gate, Codex review boundary, and review continuity | `claude/skills/codex-gated-development/`; `claude/skills/codex-gated-development/scripts/codex-review.sh` |
| Codex review gate and review continuity | `codex/skills/claude-gated-development/` |
| Codex simplification adapter | `codex/plugins/code-simplifier/` |
| Upstream Codex review integration | `codex/skills/claude-gated-development/SKILL.md`; `README.md` |
| Repository bootstrap workflow and managed assets | `shared/skills/bootstrap-project/` |
| Final PR audit and drafting workflow | `shared/skills/finish-pr/` |
| Branch integration and worktree cleanup workflow | `shared/skills/finish-branch/` |
