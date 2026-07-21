# Incremental Gate Review Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let persistent Claude and Kimi gate sessions review only newly
committed fixes after their first full review, without allowing a fresh or
stale session to approve a partial task diff.

**Architecture:** Keep `--base` as the full-task anchor and add an explicit
`--since` checkpoint owned by the caller. Build a compact incremental bundle
only when both reviewer sessions can continue; otherwise use the existing full
bundle, and retry a failed Claude resume with the full bundle.

**Tech Stack:** Bash, Git, existing Claude CLI, existing Kimi Code CLI, the
dependency-free fake-CLI shell test.

## Global Constraints

- Keep `claude-review.sh` as the public runner path and add no dependencies.
- The first round of every planning gate and final-code gate is full.
- Incremental scope is commit-only: reject staged, unstaged, or untracked work.
- Require `BASE` to be an ancestor of `SINCE` and `SINCE` to be an ancestor of
  `HEAD`; rewritten history returns to a full review.
- A fresh reviewer never receives only an incremental patch.
- Preserve Kimi snapshot isolation, live-repository fingerprinting, concurrent
  execution, and fail-closed reviewer behavior.
- Explain the safety reason near fallback and ancestry logic; do not annotate
  self-evident shell syntax.

---

### Task 1: Incremental scope contract and safe fallback

**Files:**
- Modify: `codex/skills/claude-gated-development/scripts/test-claude-review-session.sh`
- Modify: `codex/skills/claude-gated-development/scripts/claude-review.sh`

**Interfaces:**
- Consumes: `--base REF`, optional `--since REF`, the current `HEAD`, clean Git
  status, and task-scoped Claude/Kimi session markers.
- Produces: a full review bundle, or a delta bundle containing
  `SINCE...HEAD` plus a `BASE...HEAD` stat/name summary; starts reviewers only
  after scope validation.

- [ ] **Step 1: Capture the bundle each fake reviewer actually reads**

Before either fake CLI logs its arguments, extract/copy the named scope file
into a test-only capture directory:

```bash
prompt="$1"
bundle_path="$(printf '%s\n' "$prompt" |
  sed -n 's/^Precomputed review bundle: //p')"
call_no="$(($(wc -l < "$CLAUDE_LOG") + 1))"
cp "$bundle_path" "$BUNDLE_CAPTURE/claude-$call_no.txt"
```

For Kimi, copy `$PWD/review-scope.txt` with the next Kimi log line number.
Pass `BUNDLE_CAPTURE` from `run_review`, and let `run_review` forward optional
runner arguments after its first three parameters.

- [ ] **Step 2: Write failing incremental and fallback assertions**

Create a clean fixture with three distinguishable commits. Run the first
review with `--base "$task_base"`, then add a fix commit and run:

```bash
run_review "$repo" incremental-task "" \
  --base "$task_base" --since "$previous_review_head"
```

Assert both second-round bundles contain the newest marker, omit the old patch
body, and contain `Full task summary`. Then make Claude resume fail on a third
round and assert the fresh Claude retry bundle contains all task markers.
Use a new task key with `--since` and assert both reviewers receive the full
bundle when no session state exists.

- [ ] **Step 3: Write failing validation assertions**

Before changing production code, assert these invocations fail without adding
reviewer log lines:

```bash
"$runner" code --since "$previous_review_head"
"$runner" code --base "$task_base" --since "$unrelated_commit"
"$runner" code --base "$task_base" --since HEAD
```

Also dirty a tracked file and assert an otherwise valid `--since` call fails.

- [ ] **Step 4: Run the focused test and verify RED**

Run:

```bash
bash codex/skills/claude-gated-development/scripts/test-claude-review-session.sh
```

Expected: FAIL because `--since` is unknown (or because the captured second
round still contains the old patch before argument parsing is added).

- [ ] **Step 5: Parse and validate `--since`**

Add `since=""` and the normal non-empty option parsing. After resolving the
repository, enforce:

```bash
[[ -n "$base" ]] || die_usage "--since requires --base"
[[ -z "$status" ]] || die_usage "--since requires a clean worktree; commit review fixes first"
git -C "$repo_root" rev-parse --verify "${since}^{commit}" >/dev/null 2>&1 ||
  die_usage "invalid since ref: $since"
git -C "$repo_root" merge-base --is-ancestor "$base" "$since" ||
  die_usage "base must be an ancestor of since"
git -C "$repo_root" merge-base --is-ancestor "$since" HEAD ||
  die_usage "since must be an ancestor of HEAD; run a full review after history changes"
git -C "$repo_root" diff --quiet "$since"...HEAD -- && {
  printf 'Error: empty incremental review target for since %s\n' "$since" >&2
  exit 3
}
```

Resolve base/since/HEAD to commit IDs for bundle metadata after validation.

- [ ] **Step 6: Select full versus incremental scope from session state**

Move session-key path calculation before bundle construction. Activate
incremental scope only when `--since` was requested and both the saved Claude
session file and Kimi `.successful-review` marker are non-empty. Otherwise
warn and select full scope:

```bash
incremental_active=0
if [[ -n "$since" && -s "$session_file" && -s "$kimi_state_file" ]]; then
  incremental_active=1
elif [[ -n "$since" ]]; then
  printf 'Warning: reviewer continuity is incomplete; running a full review\n' >&2
fi
```

- [ ] **Step 7: Build both deterministic bundle forms**

Retain the current full bundle in `full-review-scope.txt`. When incremental is
active, write `review-scope.txt` with:

```bash
git -C "$repo_root" log --oneline --no-decorate "$since"..HEAD
git -C "$repo_root" diff --name-status "$since"...HEAD --
git -C "$repo_root" diff --binary "$since"...HEAD --
git -C "$repo_root" diff --stat "$base"...HEAD --
git -C "$repo_root" diff --name-status "$base"...HEAD --
```

Select the full file when incremental is inactive. Keep the complete Kimi
snapshot, but copy only the selected bundle into its workspace.

- [ ] **Step 8: Give resumed reviewers the incremental contract**

Build a prompt for each scope. The incremental form must say that
`SINCE...HEAD` is the primary patch, prior-session findings remain context,
and the reviewer may inspect final affected files/callers/tests without
re-reading unchanged task patches. Keep the existing report schema and
`SKIPPED`/`PASS` rules.

- [ ] **Step 9: Retry a failed Claude resume with the full prompt**

Parameterize `run_claude` by prompt. A normal resume receives the selected
prompt. If it fails and a new session ID is created, call Claude with the full
prompt and `full-review-scope.txt`; document that a fresh conversation cannot
safely interpret a delta alone. Keep Kimi's continuation failure blocking.

- [ ] **Step 10: Run the focused test and verify GREEN**

Run the command from Step 4.

Expected: `parallel Claude and Kimi review checks passed`.

- [ ] **Step 11: Commit**

```bash
git add codex/skills/claude-gated-development/scripts
git commit -m "feat: add incremental dual gate reviews"
```

### Task 2: Teach callers the checkpoint workflow

**Files:**
- Modify: `codex/skills/claude-gated-development/SKILL.md`
- Modify: `README.md`
- Modify: `docs/architecture/01-overview.md`

**Interfaces:**
- Consumes: the approved design and `claude-review.sh --help` contract.
- Produces: concise instructions for full first rounds, committed fixes, and
  same-gate `--since` follow-ups.

- [ ] **Step 1: Write failing documentation contract checks**

Add assertions to `tests/test-engineering-infrastructure.sh` that the Codex
skill documents `--since`, `PREVIOUS_REVIEW_HEAD`, the clean/committed-fix
requirement, and full first rounds. Add an architecture assertion only for the
new durable scope flow.

```bash
grep -Fq -- '--since "$PREVIOUS_REVIEW_HEAD"' "$codex_gate" ||
  fail 'Codex gate does not show an incremental review command'
grep -Fq 'commit all review fixes' "$codex_gate" ||
  fail 'Codex gate does not require committed incremental fixes'
grep -Fq 'first round of each' "$codex_gate" ||
  fail 'Codex gate does not preserve full first rounds'
grep -Fq 'incremental review' "$root/docs/architecture/01-overview.md" ||
  fail 'architecture does not describe incremental review scope'
```

- [ ] **Step 2: Run the infrastructure test and verify RED**

Run:

```bash
sh tests/test-engineering-infrastructure.sh
```

Expected: FAIL because the current skill does not mention `--since`.

- [ ] **Step 3: Update skill and architecture guidance**

Document this exact loop in the shared-gate section:

```bash
"$RUNNER" code --base "$TASK_BASE" --focus "..."
PREVIOUS_REVIEW_HEAD="$(git rev-parse HEAD)"
# fix every valid blocking finding, then commit the fixes
"$RUNNER" code --base "$TASK_BASE" --since "$PREVIOUS_REVIEW_HEAD" --focus "..."
```

State that `--since` is only for later rounds of the same gate, requires a
clean worktree, and safely degrades to full scope if sessions are missing.
Update the README summary and architecture primary flow/invariants without
duplicating implementation details.

- [ ] **Step 4: Run documentation and runner validation**

```bash
sh tests/test-engineering-infrastructure.sh
bash -n codex/skills/claude-gated-development/scripts/claude-review.sh
git diff --check
```

Expected: all commands exit zero.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/architecture/01-overview.md \
  tests/test-engineering-infrastructure.sh \
  codex/skills/claude-gated-development/SKILL.md
git commit -m "docs: adopt commit-scoped gate reruns"
```

### Task 3: Final verification and deployment

**Files:**
- Verify: complete branch diff from the commit before this task.
- Update after all gates pass: `~/.codex/skills/claude-gated-development/`

**Interfaces:**
- Consumes: the complete committed branch and current installed skill.
- Produces: a validated source skill and an exact local installation copy.

- [ ] **Step 1: Run all repository checks with fresh output**

```bash
bash codex/skills/claude-gated-development/scripts/test-claude-review-session.sh
sh tests/test-engineering-infrastructure.sh
bash -n codex/skills/claude-gated-development/scripts/claude-review.sh
git diff --check ea8bf43...HEAD
```

Expected: both suites report their pass messages; syntax and diff checks are
silent and exit zero.

- [ ] **Step 2: Run the simplification and PR-review passes**

Use `code-simplifier:code-simplifier` and `pr-review-toolkit:review-pr` on
`ea8bf43...HEAD`. Fix only validated findings, commit fixes, and rerun affected
checks.

- [ ] **Step 3: Run the final dual gate**

Run the first final-code round without `--since`. For each correction round,
save the reviewed `HEAD`, commit fixes, and use the new `--since` interface.
Stop only after Claude and Kimi both have no valid blocking finding.

- [ ] **Step 4: Sync and compare the installed skill**

After the source branch is final, replace the installed Codex skill from
`codex/skills/claude-gated-development/`, then verify:

```bash
diff -ru codex/skills/claude-gated-development \
  /Users/yanliu/.codex/skills/claude-gated-development
```

Expected: no output.

- [ ] **Step 5: Record final repository state**

```bash
git status --short --branch
git log --oneline ea8bf43..HEAD
```

Expected: a clean `agent/incremental-gate-review` branch with the design,
plan, implementation, documentation, and any reviewed fixes committed.
