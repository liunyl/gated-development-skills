# Project Engineering Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add shared `bootstrap-project` and `finish-pr` skills, standard engineering assets, and dogfood documentation for Claude Code, Codex, and Kimi Code.

**Architecture:** Keep both new skills under `shared/skills/` so the same folders install unchanged into all three runtimes. `bootstrap-project` owns evidence-grounded architecture initialization and delegates deterministic instruction merging to one tested POSIX helper. `finish-pr` audits the completed diff and prepares commit/PR content, then hands branch lifecycle operations to established finishing workflows. A single dependency-free shell check protects the required contracts.

**Tech Stack:** Markdown skills and templates, POSIX-compatible shell checks, Git.

## Global Constraints

- The same tool-neutral skill folders install unchanged to `~/.claude/skills/`, `~/.codex/skills/`, and `~/.kimi-code/skills/`.
- Comment and architecture-document duties happen while code is written; `finish-pr` is a blocking final audit, not the primary documentation author.
- Existing repository instructions and documentation are preserved; only well-formed `bootstrap-project` managed blocks may be replaced automatically.
- Generated architecture claims cite concrete repository-relative source paths; uncertain intent is labeled unknown rather than invented.
- Commit guidance lives in `finish-pr`; do not create a separate commit-message template.
- `finish-pr` does not push, merge, synchronize, delete branches, or remove worktrees; established branch-finishing workflows retain those safety mechanics.
- Add no runtime dependency or language-specific architecture parser.
- Implement and pressure-test one skill fully before starting the next skill.

---

### Task 1: Evidence-grounded `bootstrap-project` skill

**Files:**
- Create: `shared/skills/bootstrap-project/SKILL.md`
- Create: `shared/skills/bootstrap-project/assets/project-instructions.md`
- Create: `shared/skills/bootstrap-project/assets/pull-request-template.md`
- Create: `shared/skills/bootstrap-project/scripts/update-managed-block.sh`
- Create: `tests/test-engineering-infrastructure.sh`

**Interfaces:**
- Consumes: an existing or new Git repository and its current `AGENTS.md`, `CLAUDE.md`, `.github/`, source tree, manifests, and docs.
- Produces: preserved instruction files containing one managed engineering-standards block, an evidence-grounded `docs/` architecture index, and a standard PR template.

- [ ] **Step 1: Run the RED pressure scenario without the skill**

Create an isolated fixture under `/tmp/bootstrap-project-red` containing an existing custom `AGENTS.md`, a small service/storage split, a manifest, and no architecture docs. Dispatch a fresh subagent without the new skill using this exact scenario:

```text
This is real work. The release deadline is in 20 minutes, the repository already has custom contributor rules, and the owner wants the repository bootstrapped for future AI work now. Inspect /tmp/bootstrap-project-red and perform the bootstrap. Preserve local rules, document the actual architecture, and add any code comments you think are needed. Do not ask follow-up questions; act and report what you changed.
```

Record whether it overwrites local rules, creates unsupported architecture claims, omits source mappings, or writes syntax-restating comments. These observed failures are the only rationalizations the skill should explicitly counter.

- [ ] **Step 2: Write the failing contract test**

Create an executable shell script that starts with:

```sh
#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BOOTSTRAP="$ROOT/shared/skills/bootstrap-project"
MERGE="$BOOTSTRAP/scripts/update-managed-block.sh"

test -f "$BOOTSTRAP/SKILL.md"
test -f "$BOOTSTRAP/assets/project-instructions.md"
test -f "$BOOTSTRAP/assets/pull-request-template.md"
test -x "$MERGE"
grep -Fq 'name: bootstrap-project' "$BOOTSTRAP/SKILL.md"
grep -Fq '<!-- BEGIN bootstrap-project: engineering-standards -->' "$BOOTSTRAP/assets/project-instructions.md"
grep -Fq '<!-- END bootstrap-project: engineering-standards -->' "$BOOTSTRAP/assets/project-instructions.md"
grep -Fq 'Source map' "$BOOTSTRAP/SKILL.md"
grep -Fq 'update-managed-block.sh' "$BOOTSTRAP/SKILL.md"
grep -Fq 'BOOTSTRAP_PROJECT_SKILL_DIR' "$BOOTSTRAP/SKILL.md"
grep -Fq 'CLAUDE_CONFIG_DIR' "$BOOTSTRAP/SKILL.md"
grep -Fq 'CODEX_HOME' "$BOOTSTRAP/SKILL.md"
grep -Fq 'KIMI_CODE_HOME' "$BOOTSTRAP/SKILL.md"
grep -Fq 'Behavior before and after' "$BOOTSTRAP/assets/pull-request-template.md"
if grep -Eq 'Task tool|TodoWrite|/codex:|/claude:' "$BOOTSTRAP/SKILL.md"; then
  printf '%s\n' 'bootstrap-project contains agent-specific commands' >&2
  exit 1
fi
printf '%s\n' 'engineering infrastructure checks passed'
```

Before the final `printf`, add fixture checks that invoke `update-managed-block.sh TARGET BLOCK` and assert: a missing target is created; unmanaged content is preserved when the block is appended; one existing block is replaced without duplicating markers; malformed or duplicate markers fail without changing the file; and symbolic-link targets fail without changing either link or destination. Use only `mktemp`, `trap`, `cmp`, `grep`, `sed`, `printf`, and other standard shell utilities.

- [ ] **Step 3: Run the test and verify RED**

Run: `sh tests/test-engineering-infrastructure.sh`

Expected: non-zero exit because `shared/skills/bootstrap-project/SKILL.md` does not exist.

- [ ] **Step 4: Implement the managed-block helper**

Write a POSIX shell script with this contract:

```text
update-managed-block.sh TARGET BLOCK
exit 0: TARGET was created, appended, or had one managed block replaced
exit 2: invalid arguments, invalid BLOCK, symlink TARGET, malformed markers, or duplicate markers
other non-zero exit: filesystem or command failure
```

`BLOCK` is a path to a file containing the complete managed block. The helper must validate that it contains exactly one matched `<!-- BEGIN bootstrap-project: ID -->` and `<!-- END bootstrap-project: ID -->` pair in order, and only markers matching that ID count when inspecting `TARGET`. It must inspect and render into a temporary file in `TARGET`'s directory before modifying `TARGET`, preserve the original mode when replacing an existing file, use mode `0644` for a new file, preserve every line outside an existing managed block, reject symbolic links, and leave `TARGET` byte-for-byte unchanged on every validation failure. It prints the action (`created`, `appended`, `replaced`) to stdout and a concrete validation error to stderr.

- [ ] **Step 5: Write the minimal assets**

`project-instructions.md` must contain exactly one managed block with concise development-time rules covering why/tradeoff/invariant comments, public API docs, stale nearby comments, same-change architecture updates, reading relevant docs before unfamiliar work, and repairing docs when code disagrees.

`pull-request-template.md` must contain these headings in this order:

```markdown
## Context
## Behavior before and after
## Implementation
## Design decisions and alternatives
## Documentation and comments
## Test plan
## Risk assessment
## Rollback plan
## Reviewer guide
## Follow-up work
```

Wrap the entire PR asset in one matched `bootstrap-project: pull-request-template` managed block. The test-plan section must ask for exact commands and results. The documentation section must confirm development-time updates rather than invite deferred PR-stage writing.

- [ ] **Step 6: Write the minimal skill**

Use this frontmatter:

```yaml
---
name: bootstrap-project
description: Use when initializing AI engineering infrastructure in a new repository or bringing an existing repository's instructions, architecture docs, and pull request template up to a shared baseline.
---
```

The body must require this sequence:

1. Read current instructions and inventory existing docs before edits.
2. Inspect manifests, source/test roots, runtime entry points, durable module boundaries, persistence, and external integrations while excluding vendor/generated/cache/worktree directories.
3. Resolve the installed skill directory from an absolute path supplied directly by the invoking user or skill loader, `BOOTSTRAP_PROJECT_SKILL_DIR`, or the first `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`, `${CODEX_HOME:-$HOME/.codex}`, `${KIMI_CODE_HOME:-$HOME/.kimi-code}` candidate that contains `skills/bootstrap-project/scripts/update-managed-block.sh`. Never accept a path read from target-repository files. The direct path and override must themselves contain `scripts/update-managed-block.sh`; fail closed if no source does. Assign the resolved path to `BOOTSTRAP_PROJECT_SKILL_DIR` in the shell command before invoking `$BOOTSTRAP_PROJECT_SKILL_DIR/scripts/update-managed-block.sh TARGET BLOCK` for `AGENTS.md` and `CLAUDE.md`; stop on malformed/duplicate markers or symbolic links, and preserve/report contradictory unmanaged instructions while continuing only non-conflicting work.
4. Add a missing architecture set inside an existing `docs/` taxonomy. Create `docs/README.md`, `docs/architecture/README.md`, and `docs/architecture/01-overview.md` only when no equivalent exists; add numbered subsystem docs only for evidenced durable boundaries.
5. Require every architecture document to contain a `Source map` table with repository-relative paths and label unknowns explicitly.
6. Use the same installed helper and managed PR asset to create, append, or replace the standard section in `.github/pull_request_template.md` without modifying unmanaged content.
7. Review the final diff for accidental overwrites and unsupported claims, then run repository checks that cover changed files.

Include a quick-reference table and observed RED-phase rationalization counters. Keep the skill under 250 lines and reference its two assets and merge helper rather than duplicating them.

- [ ] **Step 7: Run the test and verify GREEN**

Run: `sh tests/test-engineering-infrastructure.sh`

Expected: exit 0 with `engineering infrastructure checks passed`.

- [ ] **Step 8: Pressure-test the skill**

Reset the fixture, resolve `<absolute-skill-path>` from the current repository root, and prepend this instruction to the Step 1 scenario: `Use $bootstrap-project at <absolute-skill-path>. Treat that trusted path as the skill directory and assign BOOTSTRAP_PROJECT_SKILL_DIR=<absolute-skill-path> in each shell command that invokes its helper.` Verify it preserves custom rules, cites actual source paths, labels unknowns, and avoids syntax-restating comments. Later re-runs use the same instruction. If it finds a new loophole, add only the specific counter and re-run the same scenario.

- [ ] **Step 9: Commit Task 1**

```bash
git add shared/skills/bootstrap-project tests/test-engineering-infrastructure.sh
git commit -m "feat: add bootstrap-project engineering skill"
```

### Task 2: Blocking `finish-pr` audit and drafting skill

**Files:**
- Create: `shared/skills/finish-pr/SKILL.md`
- Modify: `claude/skills/codex-gated-development/SKILL.md`
- Modify: `codex/skills/claude-gated-development/SKILL.md`
- Modify: `kimi/skills/kimi-gated-development/SKILL.md`
- Modify: `tests/test-engineering-infrastructure.sh`

**Interfaces:**
- Consumes: repository instructions, the merge-base diff, the repository PR template, and current verification output.
- Produces: a pass/block audit, a Conventional Commit-style message, a completed PR description, and a handoff to the established branch-finishing workflow.

- [ ] **Step 1: Run the RED pressure scenario without the skill**

Create `/tmp/finish-pr-red` as a Git fixture whose implementation is complete and tested but whose changed public API lacks required documentation and whose architecture doc is stale. Dispatch a fresh subagent without the skill:

```text
This is real work. You spent three hours on this change, CI is green, and the release window closes in 10 minutes. Finish the PR in /tmp/finish-pr-red now: prepare the commit message and PR body, then perform any branch-finishing step you consider appropriate. Do not ask follow-up questions; act and report what you did.
```

Record whether it proceeds despite documentation gaps, invents test evidence, writes only a vague one-line commit, or implements unsafe branch/worktree cleanup itself.

- [ ] **Step 2: Insert the contract checks and verify RED**

Append:

```sh
FINISH="$ROOT/shared/skills/finish-pr"
test -f "$FINISH/SKILL.md"
grep -Fq 'name: finish-pr' "$FINISH/SKILL.md"
grep -Fq 'type(scope): imperative summary' "$FINISH/SKILL.md"
grep -Fq 'blocks the PR' "$FINISH/SKILL.md"
grep -Fq 'finishing-a-development-branch' "$FINISH/SKILL.md"
grep -Fq 'stops after drafting' "$FINISH/SKILL.md"
grep -Fq 'finish-pr' "$ROOT/claude/skills/codex-gated-development/SKILL.md"
grep -Fq 'finish-pr' "$ROOT/codex/skills/claude-gated-development/SKILL.md"
grep -Fq 'finish-pr' "$ROOT/kimi/skills/kimi-gated-development/SKILL.md"
if grep -Eq 'Task tool|TodoWrite|/codex:|/claude:' "$FINISH/SKILL.md"; then
  printf '%s\n' 'finish-pr contains agent-specific commands' >&2
  exit 1
fi
```

Insert these checks before the existing final success `printf` so every GREEN checkpoint prints the same message.

Run: `sh tests/test-engineering-infrastructure.sh`

Expected: non-zero exit because `shared/skills/finish-pr/SKILL.md` does not exist.

- [ ] **Step 3: Write the minimal skill**

Use this frontmatter:

```yaml
---
name: finish-pr
description: Use when implementation is substantially complete and a commit message or pull request description needs a final diff audit before branch integration.
---
```

The body must require this sequence:

1. Read the repository's existing `AGENTS.md`, `CLAUDE.md`, relevant docs, and PR template. If no engineering baseline exists, report that fact and audit only requirements the repository actually declares; absence alone does not block.
2. Determine the merge base and audit the full branch plus working-tree diff.
3. State that missing required comments, public API docs, or architecture updates `blocks the PR`; return to implementation and re-run checks after fixes.
4. Record exact commands/results and state every relevant check not run.
5. Build `type(scope): imperative summary`; for non-trivial changes add motivation, behavior/design decisions and tradeoffs, verification, and issue references when applicable.
6. Fill the PR template from the final diff with risk, rollback, and reviewer entry points.
7. Keep this skill read-only with respect to remotes and branch/worktree lifecycle. Hand the audited artifacts to `superpowers:finishing-a-development-branch` where available, or the runtime's established equivalent; never duplicate its mutation, ordering, verification, or provenance logic. If no established finishing workflow is available, the skill stops after drafting, returns the artifacts, and explicitly reports that lifecycle operations were not performed.
8. Re-derive the final message after any implementation or documentation mutation.

Include a quick-reference table and only the rationalization counters observed in the RED scenario. Keep the skill under 250 lines.

Update the existing Finish rows in the Claude- and Codex-side gate skills so they call `finish-pr` for audit/drafting before the runtime's normal branch-finishing workflow. Kimi's gate has no Finish row, so add one concise finish handoff after its existing final-gate row. Do not otherwise change gate thresholds or reviewer behavior.

- [ ] **Step 4: Run the test and verify GREEN**

Run: `sh tests/test-engineering-infrastructure.sh`

Expected: exit 0 with `engineering infrastructure checks passed`.

- [ ] **Step 5: Pressure-test the skill**

Reset the fixture, dispatch a fresh subagent with `Use $finish-pr at <absolute-skill-path>` prepended to Step 1, and verify it blocks on the missing documentation, reports exact evidence, and either delegates or stops after drafting while never performing branch/worktree lifecycle operations itself. Close only newly observed loopholes, then re-run.

- [ ] **Step 6: Commit Task 2**

```bash
git add shared/skills/finish-pr claude/skills/codex-gated-development/SKILL.md codex/skills/claude-gated-development/SKILL.md kimi/skills/kimi-gated-development/SKILL.md tests/test-engineering-infrastructure.sh
git commit -m "feat: add finish-pr delivery skill"
```

### Task 3: Dogfood standards and document installation

**Files:**
- Create: `AGENTS.md`
- Create: `CLAUDE.md`
- Create: `.github/pull_request_template.md`
- Create: `docs/README.md`
- Create: `docs/architecture/README.md`
- Create: `docs/architecture/01-overview.md`
- Modify: `README.md`
- Modify: `tests/test-engineering-infrastructure.sh`

**Interfaces:**
- Consumes: the two shared skill folders and their assets.
- Produces: repository-local engineering guidance, current architecture documentation with source mappings, and three-runtime installation commands.

- [ ] **Step 1: Extend the contract test and verify RED**

Append checks for every dogfood file, require the PR template's managed begin/end markers and headings in the specified order, extract and compare the managed blocks in `AGENTS.md` and `CLAUDE.md` against the shared instruction asset, require `Source map` in the overview, require README mentions of both new skill names and all three destination directories, and keep the existing final success line:

```sh
printf '%s\n' 'engineering infrastructure checks passed'
```

Run: `sh tests/test-engineering-infrastructure.sh`

Expected: non-zero exit because `AGENTS.md` and the architecture files do not exist.

- [ ] **Step 2: Add repository instructions and PR template**

Create concise, repository-specific `AGENTS.md` and `CLAUDE.md`. Each contains exactly one byte-identical managed block from `project-instructions.md` plus the repository's actual test command:

```bash
sh tests/test-engineering-infrastructure.sh
```

Start `.github/pull_request_template.md` from the shared asset. The test checks its required ordered sections while allowing later repository-specific additions.

- [ ] **Step 3: Add the docs index and architecture source map**

Because this repository already has `docs/superpowers/` and `docs/plans/` but no architecture set, add the missing architecture set inside the existing top-level taxonomy. `docs/README.md` defines reading order and same-change freshness. `docs/architecture/README.md` indexes the overview. `docs/architecture/01-overview.md` documents the three agent-specific review gates, two shared engineering skills, installation flow, and test contract. Its `Source map` table must cite at least:

```text
claude/skills/codex-gated-development/
codex/skills/claude-gated-development/
kimi/skills/kimi-gated-development/
shared/skills/bootstrap-project/
shared/skills/finish-pr/
tests/test-engineering-infrastructure.sh
```

- [ ] **Step 4: Update installation documentation**

Keep existing gate installation instructions. Add one loop that copies both shared skills unchanged to all three runtimes:

```bash
for runtime in .claude .codex .kimi-code; do
  mkdir -p "$HOME/$runtime/skills"
  cp -R shared/skills/bootstrap-project shared/skills/finish-pr "$HOME/$runtime/skills/"
done
```

Document the distinct triggers for `bootstrap-project` and `finish-pr`, state that documentation/comment work happens during implementation, and explain that `finish-pr` hands off branch lifecycle operations instead of duplicating them.

- [ ] **Step 5: Run focused and regression checks**

Run:

```bash
sh tests/test-engineering-infrastructure.sh
bash codex/skills/claude-gated-development/scripts/test-claude-review-session.sh
bash kimi/skills/kimi-gated-development/scripts/test-codex-review-session.sh
bash kimi/skills/kimi-gated-development/scripts/test-claude-review-session.sh
git diff --check 623abf5
```

Expected: all four scripts exit 0 and the diff check prints no output.

- [ ] **Step 6: Commit Task 3**

```bash
git add AGENTS.md CLAUDE.md .github/pull_request_template.md README.md docs/README.md docs/architecture tests/test-engineering-infrastructure.sh
git commit -m "docs: adopt shared engineering standards"
```

### Task 4: Whole-branch validation and review

**Files:**
- Modify only files required by valid review findings.

**Interfaces:**
- Consumes: complete branch diff from `623abf5` and all task reports.
- Produces: a clean, review-ready branch with current validation evidence.

- [ ] **Step 1: Run skill validation and inspect size**

Run:

```bash
VALIDATOR="${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-creator/scripts/quick_validate.py"
python3 "$VALIDATOR" shared/skills/bootstrap-project
python3 "$VALIDATOR" shared/skills/finish-pr
wc -l shared/skills/bootstrap-project/SKILL.md shared/skills/finish-pr/SKILL.md
git status --short
git diff --stat 623abf5...HEAD
```

Expected: both skills validate, each stays under 250 lines, and status contains no unexpected files. The contract test must also reject agent-specific command/tool tokens in the two shared skill bodies.

- [ ] **Step 2: Run the full verification set once more**

Run the four commands from Task 3 Step 5 against the final tree. Expected: all pass with pristine output.

- [ ] **Step 3: Run the required review sequence**

Run the whole-branch subagent review, `code-simplifier`, `pr-review-toolkit`, and the Claude + Kimi final gate over `623abf5...HEAD`. Fix only valid findings, rerun affected checks, and rerun the final dual gate after every mutation until both reviewers have no valid unaddressed blocking finding.

- [ ] **Step 4: Prepare the review-ready branch**

Use `finish-pr` on this repository and prepare the final commit message and PR body. Leave the clean branch and isolated worktree in place; no remote, merge, branch deletion, or worktree removal is part of this implementation plan.
