# Complexity-Routed Dual Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Skip external review for simple work and run strict concurrent Claude
and Kimi reviews for complex or high-risk work.

**Architecture:** The skill makes the complexity decision before planning. The
existing runner captures Git state once, gives Claude its current read-only
surface, gives Kimi an isolated repository snapshot, runs both processes in
parallel, and fails if either process fails or the live repository changes.

**Tech Stack:** Bash, Git, existing Claude CLI, existing Kimi Code CLI.

## Global Constraints

- Keep `claude-review.sh` as the public runner path.
- Add no dependencies.
- Find Kimi in `PATH` or `~/.kimi-code/bin/kimi`.
- Preserve task-scoped reviewer sessions.
- This task itself skips the old Claude gate at the user's request.

---

### Task 1: Concurrent reviewer runner

**Files:**
- Modify: `codex/skills/claude-gated-development/scripts/claude-review.sh`
- Test: `codex/skills/claude-gated-development/scripts/test-claude-review-session.sh`

**Interfaces:**
- Consumes: `CODEX_THREAD_ID` or `CLAUDE_REVIEW_SESSION_KEY`, current Git state.
- Produces: labeled Claude and Kimi reports; zero only when both CLIs succeed
  and the repository fingerprint is unchanged.

- [x] **Step 1: Write the failing test**

Add a Kimi stub at the standard install path. Make both stubs wait for the
other's start marker, require Kimi's snapshot, verify task-scoped reuse, and
make a Kimi failure fail the gate.

- [x] **Step 2: Run the test to verify it fails**

Run:

```bash
codex/skills/claude-gated-development/scripts/test-claude-review-session.sh
```

Expected: exit `8` because the old runner never starts Kimi.

- [x] **Step 3: Implement the minimum runner change**

Use the existing review bundle and fingerprint. Resolve Kimi with:

```bash
kimi_bin="$(command -v kimi 2>/dev/null || true)"
[[ -n "$kimi_bin" ]] || kimi_bin="${HOME:-}/.kimi-code/bin/kimi"
[[ -x "$kimi_bin" ]] || die_usage "kimi CLI is not installed"
```

Copy only tracked and unignored untracked files into a stable task workspace,
run Kimi there with `-p`, use `--continue` after the first successful task
review, and start the existing Claude call and Kimi call in the background.
Wait for both and return the first non-zero status.

- [x] **Step 4: Run the test to verify it passes**

Run the command from Step 2.

Expected: `parallel Claude and Kimi review checks passed`.

- [x] **Step 5: Commit**

```bash
git add codex/skills/claude-gated-development/scripts
git commit -m "Run Claude and Kimi reviews concurrently"
```

### Task 2: Complexity routing

**Files:**
- Modify: `codex/skills/claude-gated-development/SKILL.md`
- Modify: `codex/skills/claude-gated-development/agents/openai.yaml`
- Modify: `README.md`

**Interfaces:**
- Consumes: task scope, reversibility, risk, and verification difficulty.
- Produces: a default skip decision or a strict dual-review workflow.

- [x] **Step 1: Replace the broad activation rule**

State that local, reversible, single-path work with an obvious direct check
skips external review. Require a concrete trigger such as cross-module design,
ambiguous tradeoffs, concurrency, security, destructive data work, financial
or quant logic, or hard-to-test failure modes. If no trigger applies, skip.

- [x] **Step 2: Collapse the complex engineering workflow**

Use one dual planning review and one dual final review. Keep the quant pre-run
review mandatory for real backtests.

- [x] **Step 3: Update naming**

Describe the gate and default prompt as complexity-routed Claude + Kimi review
while retaining the existing skill and runner names.

- [x] **Step 4: Validate**

```bash
rg -n "simple|complex|Claude|Kimi|concurrent" \
  codex/skills/claude-gated-development README.md
git diff --check
```

- [x] **Step 5: Commit**

```bash
git add README.md codex/skills/claude-gated-development
git commit -m "Route only complex tasks through dual review"
```

### Task 3: Install and verify

**Files:**
- Update after validation: `~/.codex/skills/claude-gated-development/`

- [x] **Step 1: Run the runner test and shell syntax check**

```bash
bash -n codex/skills/claude-gated-development/scripts/claude-review.sh
codex/skills/claude-gated-development/scripts/test-claude-review-session.sh
```

- [x] **Step 2: Verify the installed Kimi CLI**

```bash
/Users/yanliu/.kimi-code/bin/kimi --version
/Users/yanliu/.kimi-code/bin/kimi doctor
```

- [x] **Step 3: Sync the skill**

Copy the validated source skill over
`~/.codex/skills/claude-gated-development/`, then compare every file.

- [x] **Step 4: Review final state**

```bash
git diff master...HEAD --check
git status -sb
```
