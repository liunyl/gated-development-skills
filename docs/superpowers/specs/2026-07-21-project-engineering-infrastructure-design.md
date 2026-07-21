# Project Engineering Infrastructure Design

**Date:** 2026-07-21

## Goal

Extend this repository from review gates into shared engineering infrastructure for Claude Code, Codex, and Kimi Code. New and existing repositories should gain durable development instructions, evidence-grounded architecture documentation, a consistent pull request format, and a reliable final PR workflow.

## Decisions

- Keep one tool-neutral source for the new skills and install the same skill folders into all three runtimes.
- Put comment and documentation duties in repository instructions so they happen while code is written.
- Treat `finish-pr` as a final audit and commit/PR drafting workflow, not as the primary author of missing comments, architecture documentation, or branch-lifecycle mechanics.
- Bootstrap existing repositories by reading their real code and generating an initial architecture map with explicit source-file evidence.
- Preserve existing repository guidance. Only replace blocks previously managed by `bootstrap-project`; never overwrite unrelated content.
- Put commit-message guidance in `finish-pr` instead of adding a separate commit-message template.

## Repository Layout

```text
shared/skills/
  bootstrap-project/
    SKILL.md
    assets/
      project-instructions.md
      pull-request-template.md
    scripts/
      update-managed-block.sh
  finish-pr/
    SKILL.md
tests/
  test-engineering-infrastructure.sh
```

The shared skills are copied unchanged to `~/.claude/skills/`, `~/.codex/skills/`, and `~/.kimi-code/skills/`. Existing agent-specific gate skills remain where they are because their reviewer topology differs by runtime.

This repository also adopts its own standards by adding root `AGENTS.md`, `CLAUDE.md`, `.github/pull_request_template.md`, `docs/README.md`, and `docs/architecture/`.

## Development-Time Instructions

`bootstrap-project` adds a concise managed block to both `AGENTS.md` and `CLAUDE.md`. The block requires agents to:

- Explain non-obvious intent, invariants, ownership, failure behavior, compatibility constraints, and performance or safety tradeoffs near the affected code.
- Avoid comments that merely restate syntax or names.
- Add or update documentation comments for public APIs when the language supports them.
- Correct stale nearby comments while changing behavior.
- Update the corresponding architecture document in the same change when module boundaries, core flows, durable formats, lifecycle, or external integrations change.
- Read `docs/README.md` and the relevant architecture documents before modifying an unfamiliar subsystem.
- Treat code as authoritative when code and documentation disagree, then repair the documentation in the same change.

These are development-time obligations. Agents should not defer them to PR preparation.

## Safe Instruction Merge

The managed block uses stable comments:

```markdown
<!-- BEGIN bootstrap-project: engineering-standards -->
...
<!-- END bootstrap-project: engineering-standards -->
```

The skill resolves its installed directory through an explicit `BOOTSTRAP_PROJECT_SKILL_DIR` override or the known Claude/Codex/Kimi skill roots, never relative to the target repository. It then uses its dependency-free `update-managed-block.sh` helper for deterministic instruction and PR-template merges. The helper accepts a target path and a block-file path; the block file supplies one matched pair of `bootstrap-project` markers. For each instruction file:

1. If the file is absent, create it with the managed block.
2. If exactly one well-formed managed block exists, replace only that block.
3. If no managed block exists, append the block after preserving all existing content.
4. If markers are malformed or duplicated, stop and report the conflict rather than guessing.
5. If existing unmanaged instructions contradict the shared standards, preserve and report the conflicting text; continue only with non-conflicting bootstrap steps.
6. If an instruction path is a symbolic link, stop and report it rather than replacing or dereferencing it implicitly.

The same preservation rule applies to existing documentation and PR templates: retain repository-specific material and add only missing shared requirements.

## Evidence-Grounded Architecture Bootstrap

For an existing repository, `bootstrap-project` first reads the repository instructions and then inspects manifests, build and test entry points, source roots, runtime entry points, module boundaries, persistence, external integrations, and representative tests. Generated statements must cite concrete repository-relative paths. Vendored, generated, cache, and worktree directories are excluded.

The minimum documentation set is:

- `docs/README.md`: purpose, reading order, freshness rule, and architecture index.
- `docs/architecture/README.md`: subsystem map and links to architecture documents.
- `docs/architecture/01-overview.md`: system context, component responsibilities, primary control/data flows, cross-cutting invariants, and a source map.

Create additional numbered subsystem documents only when the code shows a durable boundary that would otherwise make the overview unwieldy. Every architecture document includes a `Source map` table linking claims to files or directories. Unknowns are labeled as unknown; the agent must not invent intent from names alone.

When `docs/` already exists, add the missing architecture set inside its existing taxonomy. For repositories with existing architecture documentation, preserve its organization, update the relevant index, fill material gaps, and avoid creating a competing hierarchy. Create the top-level `docs/` structure only when it is absent.

## Pull Request Template

The standard template contains:

- Context
- Behavior before and after
- Implementation
- Design decisions and alternatives
- Documentation and comments
- Test plan with exact commands and results
- Risk assessment
- Rollback plan
- Reviewer guide
- Follow-up work

The shared PR asset is itself one managed block. When `.github/pull_request_template.md` is absent, bootstrap creates it from the asset. When one exists, the same tested helper preserves its unmanaged content and appends or replaces the managed standard section.

## `finish-pr` Workflow

Use `finish-pr` after implementation and before creating or updating a pull request. It reads repository instructions and the PR template, then audits the complete merge-base diff. In repositories that have not adopted engineering instructions, it reports the missing baseline and audits only requirements the repository actually declares; absence of the managed standards alone does not block delivery.

The audit checks that comments and architecture documentation were already updated with the code. Missing required material blocks the PR workflow and returns the task to implementation. Once the audit passes, the skill:

1. Runs or verifies repository-appropriate checks and records exact evidence.
2. Builds a Conventional Commit-style subject (`type(scope): imperative summary`) and, for non-trivial changes, a body covering motivation, behavior or design decisions, and verification.
3. Fills the repository PR template from the final diff, including risks, rollback, and reviewer entry points.
4. Hands the audited commit message and PR body to the runtime's established branch-finishing workflow. If none is available, it stops after drafting and reports that lifecycle operations were not performed. `finish-pr` itself does not push, merge, synchronize, delete branches, or remove worktrees.

The skill never claims an unrun check passed and never hides a documentation or comment gap inside the PR description.

## Validation

Skill development follows RED-GREEN-REFACTOR with fresh subagent pressure scenarios:

- Baseline without `bootstrap-project`: test whether an agent preserves existing instructions, grounds architecture claims in source files, and writes comments explaining why rather than syntax.
- Baseline without `finish-pr`: test whether an agent proceeds despite missing documentation, vague validation evidence, an incomplete commit message, or unsafe branch/worktree handling.
- Re-run each scenario with the corresponding skill and close only observed loopholes.

One shell test exercises managed-block creation, replacement, append, malformed/duplicate marker rejection, symlink rejection, and preservation of unmanaged content. It also verifies that the skill references the helper through installed-skill resolution, required skill metadata, expected PR sections, self-contained shared assets, repository dogfooding files, neutral wording, and installation instructions for all three runtimes. Existing gate-session tests remain unchanged and must continue to pass.

## Non-Goals

- No language-specific documentation generator or AST analysis.
- No forced rewrite of existing repository-specific instructions or documentation taxonomies.
- No separate commit-message template file or additional review-response skill.
- No direct branch/worktree lifecycle implementation in `finish-pr`; established finishing workflows retain those safety mechanics.
