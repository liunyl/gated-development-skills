# Layered Architecture Documentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make bootstrap discover and classify durable modules before drafting, keep architecture documentation layered as projects grow, and distinguish current architecture from historical PR plans.

**Architecture:** Extend the existing tool-neutral `bootstrap-project` instructions and managed engineering-standard block. Keep enforcement in the existing dependency-free shell contract test, then dogfood the same rules in this repository's instructions and documentation entry point.

**Tech Stack:** Markdown skills and instructions; dependency-free `/bin/sh` contract test.

## Global Constraints

- `docs/README.md` is the documentation reading guide.
- `docs/architecture/` describes the current code and changes with it.
- `docs/plans/` and `docs/superpowers/` are historical change context, not current architecture authority.
- A durable module needs an independent responsibility plus a meaningful interface, data flow, or lifecycle; paths alone are insufficient evidence.
- Empty repositories receive minimal truthful documents, never speculative module docs.
- Reuse the existing test and managed-block helper; add no generator, validator, or dependency.

---

### Task 1: Lock the documentation contracts

**Files:**
- Modify: `tests/test-engineering-infrastructure.sh`

**Interfaces:**
- Consumes: Existing Markdown assets and dogfood files.
- Produces: Exact text contracts that fail until the bootstrap workflow and managed instructions implement the approved policy.

- [ ] **Step 1: Run a baseline skill pressure test**

Ask a fresh subagent, without the proposed wording, to bootstrap documentation for a hypothetical repository whose README and sampled code show three independent modules. Record whether it establishes a taxonomy before prose, delegates bounded module work, separates current architecture from historical plans, and explains how an initially empty repository grows beyond one overview.

- [ ] **Step 2: Add failing contract assertions**

Add these assertions near the existing bootstrap checks:

```sh
grep -Fq 'evidence-backed module map' "$BOOTSTRAP/SKILL.md"
grep -Fq 'before drafting architecture prose' "$BOOTSTRAP/SKILL.md"
grep -Fq 'two or more independent durable modules' "$BOOTSTRAP/SKILL.md"
grep -Fq 'Empty repositories' "$BOOTSTRAP/SKILL.md"
grep -Fq 'historical change context' "$BOOTSTRAP/SKILL.md"
grep -Fq 'introduces, removes, splits, or merges a durable module' "$BLOCK"
grep -Fq 'Keep the overview focused on system context' "$BLOCK"
grep -Fq 'docs/architecture/README.md' "$BLOCK"
grep -Fq 'not authoritative for the current code' "$DOCS_INDEX"
grep -Fq 'docs/superpowers/' "$DOCS_INDEX"
grep -Fq 'evidence-backed module map' "$OVERVIEW"
```

- [ ] **Step 3: Run the contract test and verify RED**

Run: `sh tests/test-engineering-infrastructure.sh`

Expected: FAIL at the first new missing-text assertion.

- [ ] **Step 4: Commit the failing contract**

```bash
git add tests/test-engineering-infrastructure.sh
git commit -m "test: define layered documentation contracts"
```

### Task 2: Implement module-map-first bootstrap and maintenance rules

**Files:**
- Modify: `shared/skills/bootstrap-project/SKILL.md`
- Modify: `shared/skills/bootstrap-project/assets/project-instructions.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/README.md`
- Modify: `docs/architecture/01-overview.md`

**Interfaces:**
- Consumes: The Task 1 text contracts and existing `update-managed-block.sh` behavior.
- Produces: Runtime-neutral bootstrap instructions, identical managed blocks in `AGENTS.md` and `CLAUDE.md`, and dogfood documentation that demonstrates the policy.

- [ ] **Step 1: Make bootstrap classify evidence before prose**

Update the required sequence and Architecture output so it requires:

```markdown
Read the root README, scan the source tree, and sample implementation and tests around apparent boundaries. Record an evidence-backed module map before drafting architecture prose. For every durable module, capture its responsibility, evidence paths, and architecture-document destination.

Use the module map to choose the documentation taxonomy. Keep the overview at system level and add focused numbered subsystem documents for independently explainable durable modules. Empty repositories receive a minimal truthful docs entry point, architecture index, and overview; do not invent module documents.

When two or more independent durable modules need documentation and subagents are available, delegate one bounded module investigation per subagent. The parent owns taxonomy, cross-cutting behavior, integration, source-map validation, and conflict resolution. Work locally when the project is smaller or subagents are unavailable.
```

Also state that `docs/plans/` and `docs/superpowers/` are historical change context and not current architecture authority.

- [ ] **Step 2: Add ongoing durable-module rules to the managed asset**

Add concise bullets with these contracts:

```markdown
- When a change introduces, removes, splits, or merges a durable module, update the architecture taxonomy, the relevant focused documents, and `docs/architecture/README.md` in the same change.
- Keep the overview focused on system context, high-level flows, cross-cutting invariants, and navigation; put independently explainable subsystem detail in focused documents rather than continually growing one overview.
- Treat `docs/plans/` and `docs/superpowers/` as historical change context, not authoritative descriptions of the current code.
```

- [ ] **Step 3: Synchronize dogfood instructions with the helper**

Run:

```sh
BOOTSTRAP_PROJECT_SKILL_DIR="$PWD/shared/skills/bootstrap-project"
"$BOOTSTRAP_PROJECT_SKILL_DIR/scripts/update-managed-block.sh" AGENTS.md "$BOOTSTRAP_PROJECT_SKILL_DIR/assets/project-instructions.md"
"$BOOTSTRAP_PROJECT_SKILL_DIR/scripts/update-managed-block.sh" CLAUDE.md "$BOOTSTRAP_PROJECT_SKILL_DIR/assets/project-instructions.md"
```

Expected: both commands print `replaced`.

- [ ] **Step 4: Make `docs/README.md` the authority guide**

State the reading order and exact roles:

```markdown
Start with the architecture index and relevant current-architecture documents. Use plans only when reconstructing the reasoning behind a particular commit or PR.

`docs/architecture/` tracks the current code. `docs/plans/` and `docs/superpowers/` preserve historical design and implementation plans; they are not authoritative for the current code and are not maintained as the architecture evolves.
```

- [ ] **Step 5: Dogfood the new bootstrap policy in the architecture overview**

Update the `bootstrap-project` component, primary flow, and cross-cutting invariants to mention the evidence-backed module map, taxonomy-before-prose workflow, focused subsystem growth, and separation between current architecture and historical plans. Keep the existing source map.

- [ ] **Step 6: Run the contract test and verify GREEN**

Run: `sh tests/test-engineering-infrastructure.sh`

Expected: `engineering infrastructure checks passed`.

- [ ] **Step 7: Commit the implementation**

```bash
git add shared/skills/bootstrap-project/SKILL.md \
  shared/skills/bootstrap-project/assets/project-instructions.md \
  AGENTS.md CLAUDE.md docs/README.md docs/architecture/01-overview.md
git commit -m "feat: layer project architecture documentation"
```

### Task 3: Pressure-test, review, and synchronize the skill

**Files:**
- Verify: all files changed in Tasks 1 and 2
- Install from: `shared/skills/bootstrap-project/`
- Install to: `~/.claude/skills/bootstrap-project/`
- Install to: `~/.codex/skills/bootstrap-project/`
- Install to: `~/.kimi-code/skills/bootstrap-project/`

**Interfaces:**
- Consumes: Completed skill and managed assets.
- Produces: Evidence that the instructions change agent behavior and identical local runtime installations.

- [ ] **Step 1: Repeat the skill pressure test with the new skill**

Give a fresh subagent the same hypothetical repository scenario plus the updated `bootstrap-project` skill. Require an answer that contains a pre-prose module map, a docs hierarchy, bounded delegation for the three modules, a minimal empty-project path, and the current-versus-historical authority rule.

- [ ] **Step 2: Run repository verification**

```sh
sh tests/test-engineering-infrastructure.sh
git diff --check master...HEAD
git status --short
```

Expected: test passes, diff check is silent, and status is clean after commits.

- [ ] **Step 3: Run the complexity gate**

Use the repository's `claude-gated-development` planning/final review workflow. Reviewers may spawn native subagents but must not invoke their cross-model review-gate skills. Address material findings and rerun the contract test after fixes.

- [ ] **Step 4: Synchronize local installations**

Replace each installed `bootstrap-project` directory with the verified contents of `shared/skills/bootstrap-project/`, preserving no runtime-specific variation.

- [ ] **Step 5: Verify installed copies**

```sh
diff -ru shared/skills/bootstrap-project "$HOME/.claude/skills/bootstrap-project"
diff -ru shared/skills/bootstrap-project "$HOME/.codex/skills/bootstrap-project"
diff -ru shared/skills/bootstrap-project "$HOME/.kimi-code/skills/bootstrap-project"
```

Expected: all three commands are silent.
