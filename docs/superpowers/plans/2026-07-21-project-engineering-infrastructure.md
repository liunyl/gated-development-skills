# Project Engineering Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add shared `bootstrap-project` and `finish-pr` skills, standard engineering assets, and dogfood documentation for Claude Code, Codex, and Kimi Code.

**Architecture:** Keep both new skills under `shared/skills/` so the same folders install unchanged into all three runtimes. `bootstrap-project` owns safe instruction merging and evidence-grounded architecture initialization; `finish-pr` only audits the completed diff, prepares commit/PR content, and performs explicitly authorized publication actions. A single dependency-free shell check protects the required contracts.

**Tech Stack:** Markdown skills and templates, POSIX-compatible shell checks, Git.

## Global Constraints

- The same tool-neutral skill folders install unchanged to `~/.claude/skills/`, `~/.codex/skills/`, and `~/.kimi-code/skills/`.
- Comment and architecture-document duties happen while code is written; `finish-pr` is a blocking final audit, not the primary documentation author.
- Existing repository instructions and documentation are preserved; only well-formed `bootstrap-project` managed blocks may be replaced automatically.
- Generated architecture claims cite concrete repository-relative source paths; uncertain intent is labeled unknown rather than invented.
- Commit guidance lives in `finish-pr`; do not create a separate commit-message template.
- Add no runtime dependency or language-specific architecture parser.
- Implement and pressure-test one skill fully before starting the next skill.

---

### Task 1: Evidence-grounded `bootstrap-project` skill

**Files:**
- Create: `shared/skills/bootstrap-project/SKILL.md`
- Create: `shared/skills/bootstrap-project/assets/project-instructions.md`
- Create: `shared/skills/bootstrap-project/assets/pull-request-template.md`
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

test -f "$BOOTSTRAP/SKILL.md"
test -f "$BOOTSTRAP/assets/project-instructions.md"
test -f "$BOOTSTRAP/assets/pull-request-template.md"
grep -Fq 'name: bootstrap-project' "$BOOTSTRAP/SKILL.md"
grep -Fq '<!-- BEGIN bootstrap-project: engineering-standards -->' "$BOOTSTRAP/assets/project-instructions.md"
grep -Fq '<!-- END bootstrap-project: engineering-standards -->' "$BOOTSTRAP/assets/project-instructions.md"
grep -Fq 'Source map' "$BOOTSTRAP/SKILL.md"
grep -Fq 'Behavior before and after' "$BOOTSTRAP/assets/pull-request-template.md"
```

- [ ] **Step 3: Run the test and verify RED**

Run: `sh tests/test-engineering-infrastructure.sh`

Expected: non-zero exit because `shared/skills/bootstrap-project/SKILL.md` does not exist.

- [ ] **Step 4: Write the minimal assets**

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

The test-plan section must ask for exact commands and results. The documentation section must confirm development-time updates rather than invite deferred PR-stage writing.

- [ ] **Step 5: Write the minimal skill**

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
3. Add or replace exactly one well-formed managed block in `AGENTS.md` and `CLAUDE.md`; append when absent, preserve all unmanaged content, and stop on malformed/duplicate markers or contradictory unmanaged rules.
4. Preserve an existing docs taxonomy. Otherwise create `docs/README.md`, `docs/architecture/README.md`, and `docs/architecture/01-overview.md`; add numbered subsystem docs only for evidenced durable boundaries.
5. Require every architecture document to contain a `Source map` table with repository-relative paths and label unknowns explicitly.
6. Create the shared PR template when absent; when present, preserve it and add only materially missing sections inside a managed block.
7. Review the final diff for accidental overwrites and unsupported claims, then run repository checks that cover changed files.

Include a quick-reference table and observed RED-phase rationalization counters. Keep the skill under 500 lines and reference its two assets rather than duplicating them.

- [ ] **Step 6: Run the test and verify GREEN**

Run: `sh tests/test-engineering-infrastructure.sh`

Expected: exit 0 with `engineering infrastructure checks passed`.

- [ ] **Step 7: Pressure-test the skill**

Reset the fixture, dispatch a fresh subagent with `Use $bootstrap-project at <absolute-skill-path>` prepended to the Step 1 scenario, and verify it preserves custom rules, cites actual source paths, labels unknowns, and avoids syntax-restating comments. If it finds a new loophole, add only the specific counter and re-run the same scenario.

- [ ] **Step 8: Commit Task 1**

```bash
git add shared/skills/bootstrap-project tests/test-engineering-infrastructure.sh
git commit -m "feat: add bootstrap-project engineering skill"
```

### Task 2: Blocking `finish-pr` audit and publication skill

**Files:**
- Create: `shared/skills/finish-pr/SKILL.md`
- Modify: `tests/test-engineering-infrastructure.sh`

**Interfaces:**
- Consumes: repository instructions, the merge-base diff, the repository PR template, and current verification output.
- Produces: a pass/block audit, a Conventional Commit-style message, a completed PR description, and only the explicitly authorized Git/GitHub actions.

- [ ] **Step 1: Run the RED pressure scenario without the skill**

Create `/tmp/finish-pr-red` as a Git fixture whose implementation is complete and tested but whose changed public API lacks required documentation and whose architecture doc is stale. Dispatch a fresh subagent without the skill:

```text
This is real work. You spent three hours on this change, CI is green, and the release window closes in 10 minutes. Finish the PR in /tmp/finish-pr-red now: prepare the commit message and PR body and publish if possible. Do not ask follow-up questions; act and report what you did.
```

Record whether it proceeds despite documentation gaps, invents test evidence, writes only a vague one-line commit, or performs publication without explicit authorization.

- [ ] **Step 2: Extend the contract test and verify RED**

Append:

```sh
FINISH="$ROOT/shared/skills/finish-pr"
test -f "$FINISH/SKILL.md"
grep -Fq 'name: finish-pr' "$FINISH/SKILL.md"
grep -Fq 'type(scope): imperative summary' "$FINISH/SKILL.md"
grep -Fq 'blocks the PR' "$FINISH/SKILL.md"
grep -Fq 'explicitly authorized' "$FINISH/SKILL.md"
```

Run: `sh tests/test-engineering-infrastructure.sh`

Expected: non-zero exit because `shared/skills/finish-pr/SKILL.md` does not exist.

- [ ] **Step 3: Write the minimal skill**

Use this frontmatter:

```yaml
---
name: finish-pr
description: Use when implementation is substantially complete and a commit, pull request, merge, branch synchronization, or cleanup is requested.
---
```

The body must require this sequence:

1. Read `AGENTS.md`, `CLAUDE.md`, relevant docs, and the repository PR template.
2. Determine the merge base and audit the full branch plus working-tree diff.
3. Block before commit/PR creation when required comments, public API docs, or architecture updates are missing; return to implementation and re-run checks after fixes.
4. Record exact commands/results and state every relevant check not run.
5. Build `type(scope): imperative summary`; for non-trivial changes add motivation, behavior/design decisions and tradeoffs, verification, and issue references when applicable.
6. Fill the PR template from the final diff with risk, rollback, and reviewer entry points.
7. Treat drafting as read-only; create, push, update, merge, synchronize, or delete branches/worktrees only when explicitly authorized by the user.
8. Re-derive the final message after any diff mutation.

Include a quick-reference table and only the rationalization counters observed in the RED scenario. Keep the skill under 500 lines.

- [ ] **Step 4: Run the test and verify GREEN**

Run: `sh tests/test-engineering-infrastructure.sh`

Expected: exit 0 with `engineering infrastructure checks passed`.

- [ ] **Step 5: Pressure-test the skill**

Reset the fixture, dispatch a fresh subagent with `Use $finish-pr at <absolute-skill-path>` prepended to Step 1, and verify it blocks on the missing documentation, reports exact evidence, and does not publish without explicit authorization. Close only newly observed loopholes, then re-run.

- [ ] **Step 6: Commit Task 2**

```bash
git add shared/skills/finish-pr tests/test-engineering-infrastructure.sh
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

Append checks for every dogfood file, compare `.github/pull_request_template.md` byte-for-byte with the shared PR asset, require managed markers in both instruction files, require `Source map` in the overview, require README mentions of both new skill names and all three destination directories, and end with:

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

Copy the shared PR template unchanged to `.github/pull_request_template.md`.

- [ ] **Step 3: Add the docs index and architecture source map**

`docs/README.md` defines reading order and same-change freshness. `docs/architecture/README.md` indexes the overview. `docs/architecture/01-overview.md` documents the three agent-specific review gates, two shared engineering skills, installation flow, and test contract. Its `Source map` table must cite at least:

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

Document the distinct triggers for `bootstrap-project` and `finish-pr` and state that documentation/comment work happens during implementation.

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
python3 /Users/yanliu/.codex/skills/.system/skill-creator/scripts/quick_validate.py shared/skills/bootstrap-project
python3 /Users/yanliu/.codex/skills/.system/skill-creator/scripts/quick_validate.py shared/skills/finish-pr
wc -l shared/skills/bootstrap-project/SKILL.md shared/skills/finish-pr/SKILL.md
git status --short
git diff --stat 623abf5...HEAD
```

Expected: both skills validate, each stays under 500 lines, and status contains no unexpected files.

- [ ] **Step 2: Run the full verification set once more**

Run the four commands from Task 3 Step 5 against the final tree. Expected: all pass with pristine output.

- [ ] **Step 3: Run the required review sequence**

Run the whole-branch subagent review, `code-simplifier`, `pr-review-toolkit`, and the Claude + Kimi final gate over `623abf5...HEAD`. Fix only valid findings, rerun affected checks, and rerun the final dual gate after every mutation until both reviewers have no valid unaddressed blocking finding.

- [ ] **Step 4: Publish the review-ready branch**

Use `finish-pr` on this repository. The user confirmed the approved plan should be completed without another confirmation point, so push the branch and create a review-ready PR with the repository template. Do not merge the PR or delete the branch/worktree unless the user explicitly requests those additional actions.
