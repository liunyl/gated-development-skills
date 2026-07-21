# Incremental Gate Review Design

## Problem

The Codex gate already preserves one Claude session and one Kimi session per
task, but every invocation rebuilds and asks both reviewers to read the full
`TASK_BASE...HEAD` patch. Real session traces confirmed that later review
rounds reread progressively larger bundles even when the latest fix touched
only one or two files. Session reuse therefore avoids a cold conversation but
does not avoid repeated patch ingestion.

## Goals

- Keep the first planning review and first final-code review comprehensive.
- Let later rounds in the same gate review only commits made after the prior
  reviewed `HEAD`.
- Preserve enough full-task context to detect scope drift without resending the
  full task patch.
- Fall back to a full review whenever reviewer continuity cannot be trusted.
- Reject incremental requests that would omit dirty or rewritten history.

## Non-goals

- Do not infer a checkpoint from branch history. Persist only the base and
  `HEAD` of a review that both reviewers actually completed.
- Do not change the Claude-side or Kimi-side gate skills.
- Do not optimize Kimi's local repository snapshot; the expensive input is the
  review prompt and patch, while the snapshot lets the reviewer inspect final
  files safely.
- Do not permit uncommitted changes in an incremental review.

## Interface

Add `--since <previous-reviewed-ref>` to `claude-review.sh`:

```bash
claude-review.sh code --base "$TASK_BASE" --since "$PREVIOUS_REVIEW_HEAD" \
  --focus "Re-check the prior blocking findings and review the new fixes."
```

`--base` continues to identify the complete task. `--since` identifies the
last commit successfully seen in the current planning or final-code gate. The
caller supplies this checkpoint explicitly:

1. Run the first round with `--base` and without `--since`.
2. Save `git rev-parse HEAD` after both reviewers complete.
3. Fix valid findings and commit all changes.
4. Re-run with the same `--base`, the saved commit as `--since`, and the same
   session key.
5. Repeat from step 2 until the gate clears.

The first round of each distinct gate remains full even if the task session
already exists. In particular, the final-code gate must not use the planning
gate's last reviewed commit as `--since`.

The wrapper verifies the caller's checkpoint against its own successful-review
record. For each persistent task and review mode (`adversarial` or `code`), it
stores the resolved task base and reviewed `HEAD` only after both reviewers
succeed on a clean committed scope, produce non-empty reports, and leave the
repository unchanged. A `--since` commit may equal or precede that reviewed
`HEAD`, which permits a caller to deliberately re-review a larger delta; it may
not be newer. The stored base must equal the current resolved base. Per-mode
records mechanically make the first `code` review full even after an
`adversarial` planning review. A successful full review that includes working-
tree changes does not create a commit checkpoint.

## Scope construction

### Full review

Without `--since`, retain the current bundle: the binary task diff
`BASE...HEAD`, status, staged diff, unstaged diff, and untracked file list.

### Incremental review

With an active, resumable reviewer pair, send:

- resolved task base, previous reviewed commit, and current `HEAD`;
- commit list for `SINCE..HEAD`;
- binary patch and name-status for `SINCE...HEAD`;
- stat and name-status for the complete `BASE...HEAD` task;
- instructions to use prior-session findings and inspect affected final files,
  callers, and tests when necessary.

The bundle deliberately omits the full `BASE...HEAD` patch. The complete-task
summary exposes scope growth while the persistent conversation supplies prior
findings and rationale.

## Preconditions and fallbacks

Incremental review requires all of the following:

- `--base` is present and both refs resolve to commits;
- `BASE` is an ancestor of `SINCE`, and `SINCE` is an ancestor of `HEAD`;
- `SINCE...HEAD` is non-empty;
- the worktree is clean;
- a saved Claude session and a saved explicit Kimi session ID both exist for
  the current repository and session key;
- the same review mode has a successful-review record with the same resolved
  base, and `SINCE` is not newer than its recorded reviewed `HEAD`.

Invalid refs, ancestry, an empty delta, or a dirty worktree fail before either
reviewer starts. Missing, mismatched, or stale reviewer/checkpoint state is not
an error: the wrapper warns and sends both reviewers the full bundle so a fresh
session, a different review mode, or an unverifiable checkpoint never receives
a delta without its prior context. A dirty incremental request fails instead
of degrading because uncommitted state cannot be represented by the reviewed
`HEAD`; the caller must commit it before a checkpoint can be recorded safely.

If the Claude resume command fails after preflight, retry the new Claude
session once with the full bundle. Do not use Kimi's `--continue`: a real CLI
probe showed that it starts a fresh session and exits successfully when no
history exists for the workspace. Capture the `session_<uuid>` resume hint from
every successful Kimi review, persist it in the task workspace, and resume only
with `--session <id>`. A missing explicit session fails non-zero and blocks the
gate instead of silently approving a partial patch. A missing, legacy, or
malformed Kimi state selects a full fresh review and is replaced only after a
successful response exposes a valid session ID.

A rebase, squash, force-push, or other history rewrite that invalidates
`--since` therefore requires another full review.

## Reviewer contract

The incremental prompt names the delta as the primary review scope. Reviewers
must re-check earlier blocking findings affected by the delta and may inspect
the final versions of changed files, callers, tests, and repository guidance.
They are not required to reread unchanged task patches merely to reconstruct
context, but may inspect any final task file when session compaction or an
interaction risk makes that necessary.
The verdict and mutation-detection rules remain unchanged.

Reviewer independence stops at the selected Claude and Kimi processes. Neither
reviewer may invoke another gated-development skill or delegate its review to a
third-party agent. In particular, disable Claude's own
`codex-gated-development` skill and Kimi's own `kimi-gated-development` skill.
Remove Claude's `Agent` tool, explicitly deny all three gate skill names as
defense in depth, and retain only its read-only inspection tools plus non-gate
skills. Start Kimi with an empty explicit `--skills-dir`, which replaces its
auto-discovered user and project skills, and instruct it not to launch external
reviewers. This prevents recursive review gates while allowing both selected
reviewers to inspect the supplied repository state directly.

## Verification

Extend the dependency-free shell test to prove:

- a first `--base` review still contains the full task patch;
- a later `--since` review contains only the new commit patch plus the
  full-task summary, for both Claude and Kimi;
- missing session state and a failed Claude resume use a full bundle;
- Kimi is resumed by explicit session ID, and an absent explicit session
  blocks instead of silently starting fresh on an incremental bundle;
- a checkpoint newer than the recorded reviewed `HEAD`, a changed base, and a
  first invocation in a different review mode use a full bundle;
- dirty worktrees, missing `--base`, invalid ancestry, and empty deltas are
  rejected before reviewers run;
- existing session reuse, sandboxing, fingerprinting, and failure behavior
  remain intact.
- Claude cannot spawn agents or load a gated-development skill, and Kimi is
  launched without auto-discovered gate skills.
