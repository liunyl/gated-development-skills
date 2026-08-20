#!/usr/bin/env bash
set -euo pipefail

runner="$(cd "$(dirname "$0")" && pwd)/claude-review.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-review-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/bundles"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cat > "$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
if [[ -t 0 || -p /dev/stdin ]]; then
  printf 'fake claude: stdin must be pinned to /dev/null\n' >&2
  exit 97
fi
prompt="$1"
[[ "$prompt" == *'End with exactly one machine-readable line: VERDICT: PASS'* ]] || exit 96
bundle_path="$(printf '%s\n' "$prompt" | sed -n 's/^Precomputed review bundle: //p')"
[[ -n "$bundle_path" && -f "$bundle_path" ]] || exit 98
call_no="$(($(wc -l < "$CLAUDE_LOG") + 1))"
cp "$bundle_path" "$BUNDLE_CAPTURE/claude-$call_no.txt"
[[ -z "${MUTATE_FILE:-}" ]] || chmod 400 "$MUTATE_FILE"
printf 'CALL' >> "$CLAUDE_LOG"
shift
printf '\t%q' "$@" >> "$CLAUDE_LOG"
printf '\n' >> "$CLAUDE_LOG"
if [[ -n "${HANG_CLAUDE:-}" ]]; then
  printf '%s' "$$" > "$CLAUDE_HANG_MARKER"
  sleep 600
  exit 0
fi
if [[ -n "${FAIL_RESUME_MARKER:-}" && ! -e "$FAIL_RESUME_MARKER" ]]; then
  for arg in "$@"; do
    if [[ "$arg" == "--resume" ]]; then
      : > "$FAIL_RESUME_MARKER"
      exit 1
    fi
  done
fi
if [[ -z "${NO_LAST_MESSAGE:-}" ]]; then
  printf 'fake claude review\n'
  if [[ -n "${SKIP_CLAUDE:-}" ]]; then
    printf 'VERDICT: SKIPPED\n'
  elif [[ -n "${NEEDS_CLAUDE:-}" ]]; then
    printf 'VERDICT: NEEDS REVISION\n'
  elif [[ -z "${UNRECOGNIZED_CLAUDE_VERDICT:-}" ]]; then
    printf 'VERDICT: PASS\n'
  fi
  [[ -z "${TRAILING_CLAUDE:-}" ]] || printf 'trailing Claude text\n'
fi
EOF
chmod +x "$tmp/bin/claude"

make_repo() {
  local path="$1"
  git init -q "$path"
  git -C "$path" config user.name Test
  git -C "$path" config user.email test@example.com
  printf 'before\n' > "$path/tracked.txt"
  git -C "$path" add tracked.txt
  git -C "$path" commit -qm baseline
  printf 'after\n' >> "$path/tracked.txt"
}

run_review() {
  local task_key="$1"
  local mode="${REVIEW_MODE:-adversarial}"
  local -a review_env runner_args
  review_env=(
    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    CLAUDE_LOG="$tmp/claude.log" BUNDLE_CAPTURE="$tmp/bundles"
  )
  runner_args=("$mode" --focus test)
  if (($# > 1)); then
    runner_args+=("${@:2}")
  fi
  if [[ -n "$task_key" ]]; then
    env -u CLAUDE_REVIEW_SESSION_KEY CODEX_THREAD_ID="$task_key" \
      "${review_env[@]}" \
      "$runner" "${runner_args[@]}" >/dev/null 2>>"$tmp/review.stderr"
  else
    env -u CODEX_THREAD_ID -u CLAUDE_REVIEW_SESSION_KEY \
      "${review_env[@]}" \
      "$runner" "${runner_args[@]}" >/dev/null 2>>"$tmp/review.stderr"
  fi
}

session_id_from() {
  sed -n "${1}s/.*--session-id[[:space:]]\([^[:space:]]*\).*/\1/p" "$tmp/claude.log"
}

resume_id_from() {
  sed -n "${1}s/.*--resume[[:space:]]\([^[:space:]]*\).*/\1/p" "$tmp/claude.log"
}

last_bundle() {
  local count
  count="$(awk 'END { print NR }' "$tmp/claude.log")"
  printf '%s/bundles/claude-%s.txt\n' "$tmp" "$count"
}

session_hash_for() {
  local repo_root task_key="$2"
  repo_root="$(cd "$1" && pwd -P)"
  printf '%s\0%s' "$repo_root" "$task_key" | git -C "$1" hash-object --stdin
}

repo_a="$tmp/repo-a"
repo_b="$tmp/repo-b"
repo_c="$tmp/repo-c"
repo_unborn="$tmp/repo-unborn"
make_repo "$repo_a"
make_repo "$repo_b"
make_repo "$repo_c"
git init -q "$repo_unborn"
printf 'uncommitted plan\n' > "$repo_unborn/plan.md"
: > "$tmp/claude.log"

if (cd "$repo_a" && run_review retired-kimi-risk --kimi-risk concurrency); then
  fail 'retired --kimi-risk was accepted'
fi
[[ ! -s "$tmp/claude.log" ]] || fail 'retired --kimi-risk started Claude'

(cd "$repo_a" && run_review task-a)
(cd "$repo_a" && run_review task-a)
first_id="$(session_id_from 1)"
[[ -n "$first_id" ]] || fail 'first task review did not create a session'
[[ "$(resume_id_from 2)" == "$first_id" ]] || fail 'second task review did not resume the session'
[[ "$(sed -n '1p' "$tmp/claude.log")" != *--no-session-persistence* ]] || fail 'persistent review disabled session persistence'
[[ "$(sed -n '2p' "$tmp/claude.log")" == *--allowedTools* ]] || fail 'resume omitted allowed tools'
[[ "$(sed -n '2p' "$tmp/claude.log")" == *--disallowedTools* ]] || fail 'resume omitted denied tools'
[[ "$(sed -n '2p' "$tmp/claude.log")" == *--strict-mcp-config* ]] || fail 'resume omitted strict MCP config'
[[ "$(sed -n '2p' "$tmp/claude.log")" == *disableAllHooks* ]] || fail 'resume omitted hook lockdown'
[[ "$(sed -n '1p' "$tmp/claude.log")" == *--allowedTools*Agent* ]] || fail 'Claude reviewer lost its own subagent tool'
[[ "$(sed -n '1p' "$tmp/claude.log")" == *codex-gated-development* ]] || fail 'Claude reviewer gate skill was not denied'

FAIL_RESUME_MARKER="$tmp/failed-resume"; export FAIL_RESUME_MARKER
(cd "$repo_a" && run_review task-a)
unset FAIL_RESUME_MARKER
replacement_id="$(session_id_from 4)"
[[ "$(resume_id_from 3)" == "$first_id" ]] || fail 'stale-session check did not try resume first'
[[ -n "$replacement_id" && "$replacement_id" != "$first_id" ]] || fail 'stale session was not replaced'
(cd "$repo_a" && run_review task-a)
[[ "$(resume_id_from 5)" == "$replacement_id" ]] || fail 'replacement session was not saved'

(cd "$repo_a" && run_review task-b)
task_b_id="$(session_id_from 6)"
[[ -n "$task_b_id" && "$task_b_id" != "$replacement_id" ]] || fail 'different tasks shared a session'

(cd "$repo_b" && run_review task-a)
repo_b_id="$(session_id_from 7)"
[[ -n "$repo_b_id" && "$repo_b_id" != "$replacement_id" ]] || fail 'different repositories shared a session'

(cd "$repo_a" && run_review '../../outside')
state_dir="$(git -C "$repo_a" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions"
repo_a_root="$(git -C "$repo_a" rev-parse --show-toplevel)"
expected_state="$(printf '%s\0%s' "$repo_a_root" '../../outside' | git -C "$repo_a" hash-object --stdin)"
[[ -f "$state_dir/$expected_state" ]] || fail 'session key was not hashed'
[[ "$(LC_ALL=C ls -l "$state_dir/$expected_state")" == -rw-------* ]] || fail 'session state is not mode 0600'
[[ ! -e "$tmp/outside" ]] || fail 'session key escaped the state directory'

(cd "$repo_a" && run_review '')
last_line="$(tail -n 1 "$tmp/claude.log")"
[[ "$last_line" == *--no-session-persistence* ]] || fail 'no-task review did not stay non-persistent'
[[ "$last_line" != *--session-id* && "$last_line" != *--resume* ]] || fail 'no-task review unexpectedly reused a session'

# An interrupted wrapper terminates the reviewer process group instead of
# leaving an orphan running against the persistent session.
rm -f "$tmp/claude.hang"
(
  cd "$repo_a" && exec env -u CODEX_THREAD_ID -u CLAUDE_REVIEW_SESSION_KEY \
    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    CLAUDE_LOG="$tmp/claude.log" BUNDLE_CAPTURE="$tmp/bundles" \
    HANG_CLAUDE=1 CLAUDE_HANG_MARKER="$tmp/claude.hang" \
    "$runner" adversarial --focus test --session-key interrupt-task
) >/dev/null 2>>"$tmp/review.stderr" &
runner_pid=$!
for _ in {1..100}; do
  [[ -s "$tmp/claude.hang" ]] && break
  sleep 0.1
done
[[ -s "$tmp/claude.hang" ]] || fail 'interruption scenario never reached the reviewer'
kill -TERM "$runner_pid"
if wait "$runner_pid"; then
  fail 'interrupted runner exited zero'
fi
hung_pid="$(cat "$tmp/claude.hang")"
for _ in {1..50}; do
  kill -0 "$hung_pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$hung_pid" 2>/dev/null; then
  fail 'interrupted runner left the reviewer process running'
fi
(cd "$repo_a" && run_review interrupt-task) || fail 'round after interruption failed'

readonly_state_dir="$(git -C "$repo_c" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions"
mkdir -p "$readonly_state_dir"
chmod 500 "$readonly_state_dir"
if (cd "$repo_c" && run_review cannot-save); then
  chmod 700 "$readonly_state_dir"
  fail 'session-state write failure did not fail the gate'
fi
chmod 700 "$readonly_state_dir"

(cd "$repo_a" && env -u CODEX_THREAD_ID CLAUDE_REVIEW_SESSION_KEY=env-loser \
  HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  CLAUDE_LOG="$tmp/claude.log" BUNDLE_CAPTURE="$tmp/bundles" \
  "$runner" adversarial --focus test --session-key arg-winner >/dev/null 2>>"$tmp/review.stderr")
arg_state="$(printf '%s\0%s' "$repo_a_root" 'arg-winner' | git -C "$repo_a" hash-object --stdin)"
env_state="$(printf '%s\0%s' "$repo_a_root" 'env-loser' | git -C "$repo_a" hash-object --stdin)"
[[ -f "$state_dir/$arg_state" ]] || fail '--session-key did not create its own session state'
[[ ! -e "$state_dir/$env_state" ]] || fail '--session-key did not override CLAUDE_REVIEW_SESSION_KEY'

(cd "$repo_a" && (sleep 5) | run_review stdin-detach) \
  || fail 'review with piped stdin did not detach stdin'

(cd "$repo_unborn" && run_review unborn-working-tree)

if (cd "$repo_a" && NO_LAST_MESSAGE=1 run_review no-claude-report); then
  unset NO_LAST_MESSAGE
  fail 'empty Claude report did not fail the gate'
fi
unset NO_LAST_MESSAGE

UNRECOGNIZED_CLAUDE_VERDICT=1; export UNRECOGNIZED_CLAUDE_VERDICT
if (cd "$repo_a" && run_review unrecognized-claude-verdict); then
  unset UNRECOGNIZED_CLAUDE_VERDICT
  fail 'unrecognized Claude verdict did not fail the gate'
fi
unset UNRECOGNIZED_CLAUDE_VERDICT

NEEDS_CLAUDE=1; export NEEDS_CLAUDE
if (cd "$repo_a" && run_review needs-claude-revision); then
  unset NEEDS_CLAUDE
  fail 'Claude NEEDS REVISION did not block the gate'
fi
unset NEEDS_CLAUDE

if (cd "$repo_a" && TRAILING_CLAUDE=1 run_review trailing-claude); then
  fail 'Claude PASS followed by trailing text did not block the gate'
fi

mut_target="$repo_a/untracked-mode.txt"
printf 'x\n' > "$mut_target"
if (cd "$repo_a" && MUTATE_FILE="$mut_target" run_review mode-mutation); then
  unset MUTATE_FILE
  fail 'mode-only mutation of an untracked file did not fail the gate'
fi
unset MUTATE_FILE

repo_incremental="$tmp/repo-incremental"
git init -q "$repo_incremental"
git -C "$repo_incremental" config user.name Test
git -C "$repo_incremental" config user.email test@example.com
printf 'baseline\n' > "$repo_incremental/tracked.txt"
git -C "$repo_incremental" add tracked.txt
git -C "$repo_incremental" commit -qm baseline
task_base="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'OLD_PATCH_BODY\n' > "$repo_incremental/old.txt"
git -C "$repo_incremental" add old.txt
git -C "$repo_incremental" commit -qm 'add old task change'
previous_review_head="$(git -C "$repo_incremental" rev-parse HEAD)"

(cd "$repo_incremental" && run_review incremental-task --base "$task_base")
printf 'NEW_PATCH_BODY\n' > "$repo_incremental/new.txt"
git -C "$repo_incremental" add new.txt
git -C "$repo_incremental" commit -qm 'add review fix'
(cd "$repo_incremental" && run_review incremental-task \
  --base "$task_base" --since "$previous_review_head")

claude_incremental="$tmp/bundles/claude-$(awk 'END { print NR }' "$tmp/claude.log").txt"
grep -Fq 'NEW_PATCH_BODY' "$claude_incremental" || fail 'Claude incremental bundle omitted the new commit body'
! grep -Fq 'OLD_PATCH_BODY' "$claude_incremental" || fail 'Claude incremental bundle repeated an old patch body'
grep -Fq '## Full task summary' "$claude_incremental" || fail 'Claude incremental bundle omitted the full-task summary'

incremental_hash="$(session_hash_for "$repo_incremental" incremental-task)"
incremental_state="$(git -C "$repo_incremental" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions/$incremental_hash.adversarial.reviewed"
[[ "$(cat "$incremental_state")" == "$task_base $(git -C "$repo_incremental" rev-parse HEAD)" ]] || fail 'Claude review checkpoint was not recorded'

review_calls_before="$(wc -l < "$tmp/claude.log")"
if (cd "$repo_incremental" && run_review invalid-no-base --since "$previous_review_head"); then
  fail '--since without --base did not fail'
fi
if (cd "$repo_incremental" && run_review invalid-empty --base "$task_base" --since HEAD); then
  fail 'empty incremental range did not fail'
fi
unrelated_commit="$(git -C "$repo_incremental" commit-tree "$(git -C "$repo_incremental" write-tree)" -m unrelated)"
if (cd "$repo_incremental" && run_review invalid-history --base "$task_base" --since "$unrelated_commit"); then
  fail 'unrelated incremental history did not fail'
fi
printf 'dirty\n' > "$repo_incremental/dirty.txt"
if (cd "$repo_incremental" && run_review invalid-dirty --base "$task_base" --since "$previous_review_head"); then
  fail 'dirty incremental review did not fail'
fi
rm -f "$repo_incremental/dirty.txt"
review_calls_after="$(wc -l < "$tmp/claude.log")"
[[ "$review_calls_after" -eq "$review_calls_before" ]] || fail 'invalid incremental input started a reviewer'

(cd "$repo_incremental" && run_review fresh-incremental \
  --base "$task_base" --since "$previous_review_head")
grep -Fq 'OLD_PATCH_BODY' "$(last_bundle)" || fail 'fresh Claude session did not receive the full task'

code_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'CODE_FIRST_BODY\n' > "$repo_incremental/code.txt"
git -C "$repo_incremental" add code.txt
git -C "$repo_incremental" commit -qm 'add code gate change'
(cd "$repo_incremental" && REVIEW_MODE=code run_review incremental-task \
  --base "$task_base" --since "$code_previous")
grep -Fq 'OLD_PATCH_BODY' "$(last_bundle)" || fail 'first code-mode review was not full'

unsafe_since="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'UNSAFE_CHECKPOINT_BODY\n' > "$repo_incremental/unsafe.txt"
git -C "$repo_incremental" add unsafe.txt
git -C "$repo_incremental" commit -qm 'add unsafe checkpoint fixture'
(cd "$repo_incremental" && run_review incremental-task \
  --base "$task_base" --since "$unsafe_since")
grep -Fq 'OLD_PATCH_BODY' "$(last_bundle)" || fail 'checkpoint ahead of reviewed HEAD did not force a full review'

changed_base="$previous_review_head"
changed_base_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'CHANGED_BASE_BODY\n' > "$repo_incremental/changed-base.txt"
git -C "$repo_incremental" add changed-base.txt
git -C "$repo_incremental" commit -qm 'add changed base fixture'
(cd "$repo_incremental" && run_review incremental-task \
  --base "$changed_base" --since "$changed_base_previous")
grep -Fq 'NEW_PATCH_BODY' "$(last_bundle)" || fail 'changed task base did not force a full review'

claude_fallback_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'CLAUDE_FALLBACK_BODY\n' > "$repo_incremental/claude-fallback.txt"
git -C "$repo_incremental" add claude-fallback.txt
git -C "$repo_incremental" commit -qm 'add Claude fallback fixture'
FAIL_RESUME_MARKER="$tmp/incremental-failed-resume"; export FAIL_RESUME_MARKER
(cd "$repo_incremental" && run_review incremental-task \
  --base "$changed_base" --since "$claude_fallback_previous")
unset FAIL_RESUME_MARKER
grep -Fq 'NEW_PATCH_BODY' "$(last_bundle)" || fail 'fresh Claude fallback did not receive the full task'

escaped_key='../../incremental-outside'
(cd "$repo_incremental" && run_review "$escaped_key" --base "$changed_base")
escaped_hash="$(session_hash_for "$repo_incremental" "$escaped_key")"
escaped_checkpoint="$(git -C "$repo_incremental" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions/$escaped_hash.adversarial.reviewed"
[[ -f "$escaped_checkpoint" ]] || fail 'hashed incremental checkpoint was not written'
[[ ! -e "$tmp/incremental-outside" ]] || fail 'incremental checkpoint key escaped its state directory'

checkpoint_failure_key='checkpoint-write-failure'
checkpoint_failure_hash="$(session_hash_for "$repo_incremental" "$checkpoint_failure_key")"
checkpoint_failure_path="$(git -C "$repo_incremental" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions/$checkpoint_failure_hash.adversarial.reviewed"
mkdir -p "$checkpoint_failure_path"
if (cd "$repo_incremental" && run_review "$checkpoint_failure_key" --base "$changed_base"); then
  fail 'checkpoint write failure did not fail the gate'
fi
rm -rf "$checkpoint_failure_path"

skipped_key='skipped-checkpoint'
(cd "$repo_incremental" && run_review "$skipped_key" --base "$changed_base")
skipped_hash="$(session_hash_for "$repo_incremental" "$skipped_key")"
skipped_checkpoint="$(git -C "$repo_incremental" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions/$skipped_hash.adversarial.reviewed"
skipped_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
checkpoint_before_skipped="$(cat "$skipped_checkpoint")"
printf 'SKIPPED_REVIEW_BODY\n' > "$repo_incremental/skipped.txt"
git -C "$repo_incremental" add skipped.txt
git -C "$repo_incremental" commit -qm 'add skipped review fixture'
SKIP_CLAUDE=1; export SKIP_CLAUDE
if (cd "$repo_incremental" && run_review "$skipped_key" \
  --base "$changed_base" --since "$skipped_previous"); then
  unset SKIP_CLAUDE
  fail 'SKIPPED Claude verdict did not block the gate'
fi
unset SKIP_CLAUDE
[[ "$(cat "$skipped_checkpoint")" == "$checkpoint_before_skipped" ]] || fail 'SKIPPED Claude verdict advanced its checkpoint'
! grep -Fq "ambiguous argument 'HEAD'" "$tmp/review.stderr" || fail 'unborn working-tree review emitted a raw HEAD error'

printf 'claude review session checks passed\n'
