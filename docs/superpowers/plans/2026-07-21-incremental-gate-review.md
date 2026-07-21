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
- A fresh reviewer never receives only an incremental patch; never use Kimi
  `--continue`, which starts fresh and exits zero when its history is absent.
- Persist the resolved base and reviewed `HEAD` per review mode only after both
  reviewers succeed; never trust a caller checkpoint newer than that record.
- Preserve Kimi snapshot isolation, live-repository fingerprinting, concurrent
  execution, and fail-closed reviewer behavior.
- Preserve each reviewer's built-in subagents. Disable only Claude's
  `codex-gated-development` gate and Kimi's auto-discovered
  `kimi-gated-development` gate.
- Explain the safety reason near fallback and ancestry logic; do not annotate
  self-evident shell syntax.

---

### Task 1: Incremental scope contract and safe fallback

**Files:**
- Modify: `codex/skills/claude-gated-development/scripts/test-claude-review-session.sh`
- Modify: `codex/skills/claude-gated-development/scripts/claude-review.sh`

**Interfaces:**
- Consumes: `--base REF`, optional `--since REF`, the current `HEAD`, clean Git
  status, and task-scoped Claude/Kimi session IDs.
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
[[ -n "$bundle_path" && -f "$bundle_path" ]] || exit 98
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
bundle when no session state exists. After an `adversarial` review, invoke the
first `code` review with the same key and `--since`; assert it is full because
successful-review checkpoints are per mode. After a successful round, pass a
`--since` newer than the recorded reviewed `HEAD` and a different `--base`;
assert both cases also fall back to full scope. Exercise both split-state cases
(only Claude state and only Kimi state) with the same expectation. Make the
fake Kimi print a deterministic `To resume this session: kimi -r session_...`
hint, assert later rounds use `--session <id>` rather than `--continue`, and
make an explicit resume failure block the gate without replacing its state.
Use a fake ID with another underscore after `session_` so validation exercises
the complete supported token class.
Assert Claude's allowed tool set still includes `Agent`, its denied tools name
`Skill(codex-gated-development)`, and every Kimi call includes an empty
explicit `--skills-dir`.

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

Add `since=""`, include `[--since REF]` in `usage()`, and parse the normal
non-empty option. After resolving the repository, enforce:

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
The three-dot delta is safe because the ancestry check guarantees that
`merge-base(SINCE, HEAD)` equals `SINCE`; record that invariant in a nearby
comment.

- [ ] **Step 6: Select full versus incremental scope from session state**

Move session-key path calculation before bundle construction. Store a
mode-specific checkpoint at
`reviewed_state_file="$session_file.$mode.reviewed"`, so the existing hashed
session filename also protects this state from a raw session-key traversal.
Store the resolved base and reviewed `HEAD`. Activate incremental scope only when
`--since` was requested, both reviewer session IDs are valid, the
checkpoint base equals the requested base, its recorded head is still in the
current history, and `SINCE` equals or precedes that head. Otherwise warn and
select full scope:

```bash
incremental_active=0
if [[ -n "$since" ]]; then
  if [[ -s "$session_file" && -s "$kimi_state_file" &&
        -s "$reviewed_state_file" ]]; then
    read -r reviewed_base reviewed_head < "$reviewed_state_file" || true
  fi
  if [[ "$reviewed_base" == "$base_oid" ]] &&
     git -C "$repo_root" merge-base --is-ancestor "$since_oid" "$reviewed_head" &&
     git -C "$repo_root" merge-base --is-ancestor "$reviewed_head" "$head_oid"; then
    incremental_active=1
  else
    printf 'Warning: reviewer checkpoint is incomplete or mismatched; running a full review\n' >&2
  fi
fi
```

Initialize both read variables to empty strings and validate the recorded head
as a commit before using it so corrupt state selects the full path rather than
aborting under `set -u`. Treat Kimi state as resumable only when its content
matches `session_[A-Za-z0-9_-]+`; the legacy literal `success` forces a full
fresh Kimi review.

- [ ] **Step 7: Build both deterministic bundle forms**

Retain the current full bundle in `full-review-scope.txt`. When incremental is
active, write `review-scope.txt` with:

```bash
printf 'Repository: %s\n' "$repo_root"
printf 'Review mode: %s\n' "$mode"
printf 'Base ref: %s\n' "$base_oid"
printf 'Since ref: %s\n' "$since_oid"
printf 'HEAD: %s\n' "$head_oid"
printf '\n## Commits since prior review\n'
git -C "$repo_root" log --oneline --no-decorate "$since"..HEAD
printf '\n## Incremental changed files\n'
git -C "$repo_root" diff --name-status "$since"...HEAD --
printf '\n## Incremental patch\n'
git -C "$repo_root" diff --binary "$since"...HEAD --
printf '\n## Full task summary\n'
git -C "$repo_root" diff --stat "$base"...HEAD --
git -C "$repo_root" diff --name-status "$base"...HEAD --
```

Select the full file when incremental is inactive. Keep the complete Kimi
snapshot, but copy only the selected bundle into its workspace.

- [ ] **Step 8: Give resumed reviewers the incremental contract**

Build a prompt for each scope. The incremental form must say that
`SINCE...HEAD` is the primary patch, prior-session findings remain context,
and the reviewer may inspect final affected files/callers/tests. Say unchanged
task patches need not be reread merely to reconstruct context, while permitting
inspection when compaction or an interaction risk makes it necessary. Keep the
existing report schema and `SKIPPED`/`PASS` rules.

- [ ] **Step 9: Retry a failed Claude resume with the full prompt**

Parameterize `run_claude` by prompt. A normal resume receives the selected
prompt. If it fails and a new session ID is created, call Claude with the full
prompt and `full-review-scope.txt`; document that a fresh conversation cannot
safely interpret a delta alone.

For Kimi, capture command output in a private temporary file, print it into the
normal report, and parse the final resume hint:

```bash
kimi_session_id="$(sed -n \
  's/^To resume this session: kimi -r \(session_[A-Za-z0-9_-][A-Za-z0-9_-]*\)$/\1/p' \
  "$kimi_raw_report" | tail -n 1)"
```

Use `--session "$kimi_session_id"` for a known session. A successful Kimi call
without one valid resume hint fails the gate and does not update Kimi state.
This replaces the unsafe `--continue` behavior, which was verified to start a
fresh session and exit zero when no workspace history exists. Live probes also
verified that the documented `--session` long option resumes an existing ID,
re-emits the same hint, and exits one for an unknown ID without running the
prompt.

- [ ] **Step 10: Disable recursive cross-model review gates**

Create an empty private directory under `review_tmp` and pass it to every Kimi
invocation:

```bash
mkdir -p "$review_tmp/kimi-skills"
kimi_args+=(--skills-dir "$review_tmp/kimi-skills")
```

Kimi documents `--skills-dir` as replacing auto-discovered user and project
skill directories, so its own `kimi-gated-development` gate cannot load. In
the Claude argument list, retain `Agent` and deny its runtime gate explicitly:

```bash
--disallowedTools \
  'Skill(codex-gated-development)' \
  'Bash' 'Write' 'Edit' 'NotebookEdit' 'EnterPlanMode' 'ExitPlanMode'
```

Tell Claude not to invoke `codex-gated-development` and tell Kimi not to invoke
`kimi-gated-development`. Their built-in same-runtime subagents remain allowed.

- [ ] **Step 11: Record only a fully successful reviewed state**

After fingerprint and non-empty-report checks, and only when both reviewer
statuses are zero, `--base` is present, the captured status is clean, and
persistent state is enabled, atomically replace the per-mode checkpoint with:

```bash
state_tmp="$reviewed_state_file.tmp.$$"
printf '%s %s\n' "$base_oid" "$head_oid" > "$state_tmp"
if ! mv -- "$state_tmp" "$reviewed_state_file"; then
  printf 'Error: could not save reviewed checkpoint at %s\n' "$reviewed_state_file" >&2
  exit 5
fi
```

Do not update the checkpoint when either reviewer fails, the reviewed scope
contains working-tree changes, or the repository mutates. A later request whose
`SINCE` is ahead of the last jointly successful committed head will then take
the full path. Extend the existing `../../outside` and read-only-state tests
with a clean `--base` review so they exercise the new hashed checkpoint path
and its write-failure behavior.

- [ ] **Step 12: Run the focused test and verify GREEN**

Run the command from Step 4.

Expected: `parallel Claude and Kimi review checks passed`.

- [ ] **Step 13: Commit**

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
CODEX_GATE="$ROOT/codex/skills/claude-gated-development/SKILL.md"
grep -Fq -- '--since "$PREVIOUS_REVIEW_HEAD"' "$CODEX_GATE"
grep -Fq 'commit the fixes before an incremental rerun' "$CODEX_GATE"
grep -Fq 'first round of each review mode is full' "$CODEX_GATE"
grep -Fq 'incremental review' "$ROOT/docs/architecture/01-overview.md"
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

State exactly that `--since` is only for later rounds of the same gate,
"commit the fixes before an incremental rerun", and "the first round of each
review mode is full". Explain that a dirty worktree is rejected and missing or
mismatched session/checkpoint state safely degrades to full scope.
When no new commit exists for an evidence-only rebuttal, omit `--since` and run
the required full re-review.
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
