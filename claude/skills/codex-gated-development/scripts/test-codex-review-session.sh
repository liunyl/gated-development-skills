#!/usr/bin/env bash
set -euo pipefail

runner="$(cd "$(dirname "$0")" && pwd)/codex-review.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/codex-review-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/bundles"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cat > "$tmp/bin/codex" <<'EOF'
#!/usr/bin/env bash
if [[ -t 0 || -p /dev/stdin ]]; then
  printf 'fake codex: stdin must be pinned to /dev/null\n' >&2
  exit 97
fi
seen_resume=0
out=""
prompt=""
prev=""
for arg in "$@"; do
  if [[ "$arg" == "resume" ]]; then
    seen_resume=1
  fi
  if [[ "$seen_resume" -eq 1 && "$arg" == --sandbox ]]; then
    printf "error: unexpected argument '--sandbox' found\n" >&2
    exit 2
  fi
  if [[ "$prev" == "--output-last-message" ]]; then
    out="$arg"
  fi
  prev="$arg"
done
prompt="${!#}"
[[ "$prompt" == *'End with exactly one machine-readable line: VERDICT: PASS'* ]] || exit 96
bundle_path="$(printf '%s\n' "$prompt" | sed -n 's/^Precomputed review bundle: //p')"
[[ -n "$bundle_path" && -f "$bundle_path" ]] || exit 98
call_no="$(($(wc -l < "$CODEX_LOG") + 1))"
cp "$bundle_path" "$BUNDLE_CAPTURE/codex-$call_no.txt"
[[ -z "${MUTATE_FILE:-}" ]] || chmod 400 "$MUTATE_FILE"
printf 'CALL\tcwd=%q' "$PWD" >> "$CODEX_LOG"
printf '\t%q' "$@" >> "$CODEX_LOG"
printf '\n' >> "$CODEX_LOG"
if [[ -n "${HANG_CODEX:-}" ]]; then
  printf '%s' "$$" > "$CODEX_HANG_MARKER"
  sleep 600
  exit 0
fi
if [[ "$seen_resume" -eq 1 && -n "${FAIL_RESUME_MARKER:-}" && ! -e "$FAIL_RESUME_MARKER" ]]; then
  : > "$FAIL_RESUME_MARKER"
  exit 1
fi
if [[ -n "${NO_LAST_MESSAGE:-}" ]]; then
  out=""
fi
if [[ -n "$out" ]]; then
  printf 'fake codex review\n' > "$out"
  if [[ -n "${SKIP_VERDICT:-}" ]]; then
    printf 'VERDICT: SKIPPED\n' >> "$out"
  elif [[ -n "${NEEDS_CODEX:-}" ]]; then
    printf 'VERDICT: NEEDS REVISION\n' >> "$out"
  elif [[ -z "${UNRECOGNIZED_VERDICT:-}" ]]; then
    printf 'VERDICT: PASS\n' >> "$out"
  fi
  [[ -z "${TRAILING_CODEX:-}" ]] || printf 'trailing Codex text\n' >> "$out"
fi
if [[ "$seen_resume" -eq 0 ]]; then
  if [[ -n "${BAD_THREAD_EVENT:-}" ]]; then
    printf '{"type":"turn.started"}\n'
  else
    count_file="$CODEX_LOG.counter"
    n=0
    [[ -e "$count_file" ]] && n="$(cat "$count_file")"
    n=$((n + 1))
    printf '%s' "$n" > "$count_file"
    printf '{"type":"thread.started","thread_id":"00000000-0000-4000-8000-%012d"}\n' "$n"
  fi
fi
EOF
chmod +x "$tmp/bin/codex"

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
    CODEX_LOG="$tmp/codex.log" BUNDLE_CAPTURE="$tmp/bundles"
  )
  runner_args=("$mode" --focus test)
  if (($# > 1)); then
    runner_args+=("${@:2}")
  fi
  if [[ -n "$task_key" ]]; then
    env -u CODEX_REVIEW_SESSION_KEY -u CLAUDE_CODE_SESSION_ID \
      "${review_env[@]}" \
      "$runner" "${runner_args[@]}" --session-key "$task_key" >"$tmp/review.stdout" 2>>"$tmp/review.stderr"
  else
    env -u CODEX_REVIEW_SESSION_KEY -u CLAUDE_CODE_SESSION_ID \
      "${review_env[@]}" \
      "$runner" "${runner_args[@]}" >"$tmp/review.stdout" 2>>"$tmp/review.stderr"
  fi
}

thread_id() {
  printf '00000000-0000-4000-8000-%012d' "$1"
}

codex_line() {
  sed -n "${1}p" "$tmp/codex.log"
}

resume_id_from() {
  codex_line "$1" | tr '\t' '\n' | awk 'prev == "resume" { print; exit } { prev = $0 }'
}

is_new_session_call() {
  local line
  line="$(codex_line "$1")"
  [[ "$line" == CALL*exec* ]] || return 1
  ! printf '%s' "$line" | tr '\t' '\n' | grep -qx resume
}

cwd_of_call() {
  codex_line "$1" | sed -n 's/^CALL\tcwd=\([^\t]*\).*/\1/p'
}

state_dir_of() {
  printf '%s/codex-review-sessions' "$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)"
}

state_content() {
  local repo="$1" key="$2"
  local root hash
  root="$(git -C "$repo" rev-parse --show-toplevel)"
  hash="$(printf '%s\0%s' "$root" "$key" | git -C "$repo" hash-object --stdin)"
  [[ -f "$(state_dir_of "$repo")/$hash" ]] && cat "$(state_dir_of "$repo")/$hash"
}

session_hash_for() {
  local root
  root="$(cd "$1" && pwd -P)"
  printf '%s\0%s' "$root" "$2" | git -C "$1" hash-object --stdin
}

last_bundle() {
  local count
  count="$(awk 'END { print NR }' "$tmp/codex.log")"
  printf '%s/bundles/codex-%s.txt\n' "$tmp" "$count"
}

repo_a="$tmp/repo-a"
repo_b="$tmp/repo-b"
repo_c="$tmp/repo-c"
make_repo "$repo_a"
make_repo "$repo_b"
make_repo "$repo_c"
: > "$tmp/codex.log"
if (cd "$repo_a" && run_review retired-kimi-risk --kimi-risk concurrency); then
  fail 'retired --kimi-risk was accepted'
fi
[[ ! -s "$tmp/codex.log" ]] || fail 'retired --kimi-risk started Codex'

# Keyed persistence, resume, and the isolated invocation contract.
(cd "$repo_a" && run_review task-a)
(cd "$repo_a" && run_review task-a)
id1="$(thread_id 1)"
[[ "$(state_content "$repo_a" task-a)" == "$id1" ]] || fail 'first task review did not persist the session'
[[ "$(resume_id_from 2)" == "$id1" ]] || fail 'second task review did not resume the session'
for call_no in 1 2; do
  line="$(codex_line "$call_no")"
  for flag in --ignore-user-config --ignore-rules --skip-git-repo-check --json mcp_servers; do
    [[ "$line" == *"$flag"* ]] || fail "reviewer call $call_no omitted $flag"
  done
  [[ "$line" == *--sandbox*read-only* ]] || fail "reviewer call $call_no omitted the read-only sandbox"
  [[ "$line" == *--disable*hooks* && "$line" == *--disable*plugins* && "$line" == *--disable*apps* ]] ||
    fail "reviewer call $call_no did not disable hooks, plugins, and apps"
  [[ "$line" != *--ephemeral* ]] || fail 'persistent review unexpectedly ran ephemeral'
  call_cwd="$(cwd_of_call "$call_no")"
  [[ -n "$call_cwd" && "$call_cwd" != "$repo_a"* ]] || fail 'reviewer ran from inside the reviewed repository'
done
# A stale session falls back to a fresh full-scope session and re-persists.
FAIL_RESUME_MARKER="$tmp/failed-resume"; export FAIL_RESUME_MARKER
(cd "$repo_a" && run_review task-a)
unset FAIL_RESUME_MARKER
id2="$(thread_id 2)"
[[ "$(resume_id_from 3)" == "$id1" ]] || fail 'stale-session check did not try resume first'
is_new_session_call 4 || fail 'stale session was not replaced with a new session'
[[ "$(state_content "$repo_a" task-a)" == "$id2" ]] || fail 'replacement session was not saved'
(cd "$repo_a" && run_review task-a)
[[ "$(resume_id_from 5)" == "$id2" ]] || fail 'replacement session was not resumed'

(cd "$repo_a" && run_review task-b)
id3="$(thread_id 3)"
[[ "$(state_content "$repo_a" task-b)" == "$id3" && "$id3" != "$id2" ]] || fail 'different tasks shared a session'

(cd "$repo_b" && run_review task-a)
id4="$(thread_id 4)"
[[ "$(state_content "$repo_b" task-a)" == "$id4" && "$id4" != "$id2" ]] || fail 'different repositories shared a session'

# Session keys are hashed into the state directory and kept private.
(cd "$repo_a" && run_review '../../outside')
expected_state="$(session_hash_for "$repo_a" '../../outside')"
[[ -f "$(state_dir_of "$repo_a")/$expected_state" ]] || fail 'session key was not hashed'
[[ "$(LC_ALL=C ls -l "$(state_dir_of "$repo_a")/$expected_state")" == -rw-------* ]] || fail 'session state is not mode 0600'
[[ ! -e "$tmp/outside" ]] || fail 'session key escaped the state directory'

# Keyless reviews stay ephemeral and stateless.
(cd "$repo_a" && run_review '')
last_line="$(tail -n 1 "$tmp/codex.log")"
[[ "$last_line" == *--ephemeral* ]] || fail 'no-key review did not run ephemeral'
[[ "$last_line" != *resume* ]] || fail 'no-key review unexpectedly resumed a session'

# Environment key resolution: --session-key beats the env key; the Claude
# session id is the final fallback.
(cd "$repo_a" && env -u CLAUDE_CODE_SESSION_ID CODEX_REVIEW_SESSION_KEY=env-loser \
  HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  CODEX_LOG="$tmp/codex.log" BUNDLE_CAPTURE="$tmp/bundles" \
  "$runner" adversarial --focus test --session-key arg-winner >/dev/null 2>>"$tmp/review.stderr")
[[ -n "$(state_content "$repo_a" arg-winner)" ]] || fail '--session-key did not create its own session state'
[[ -z "$(state_content "$repo_a" env-loser)" ]] || fail '--session-key did not override CODEX_REVIEW_SESSION_KEY'

(cd "$repo_a" && env -u CODEX_REVIEW_SESSION_KEY CLAUDE_CODE_SESSION_ID=claude-fallback \
  HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  CODEX_LOG="$tmp/codex.log" BUNDLE_CAPTURE="$tmp/bundles" \
  "$runner" adversarial --focus test >/dev/null 2>>"$tmp/review.stderr")
[[ -n "$(state_content "$repo_a" claude-fallback)" ]] || fail 'CLAUDE_CODE_SESSION_ID fallback did not persist a session'

# The per-key lock fails a concurrent round loudly and is never auto-removed.
lock_hash="$(session_hash_for "$repo_a" task-a)"
lock_path="$(state_dir_of "$repo_a")/$lock_hash.lock"
mkdir "$lock_path"
calls_before="$(wc -l < "$tmp/codex.log")"
if (cd "$repo_a" && run_review task-a); then
  fail 'held lock did not fail the invocation'
fi
[[ -d "$lock_path" ]] || fail 'failed invocation removed a foreign lock'
[[ "$(wc -l < "$tmp/codex.log")" -eq "$calls_before" ]] || fail 'locked invocation still started a reviewer'
rmdir "$lock_path"
(cd "$repo_a" && run_review task-a) || fail 'lock was not released for the next round'
[[ ! -e "$lock_path" ]] || fail 'successful run left its lock behind'

# Session-state write failures fail the keyed gate.
readonly_state_dir="$(state_dir_of "$repo_c")"
mkdir -p "$readonly_state_dir"
chmod 500 "$readonly_state_dir"
if (cd "$repo_c" && run_review cannot-save); then
  chmod 700 "$readonly_state_dir"
  fail 'session-state write failure did not fail the gate'
fi
chmod 700 "$readonly_state_dir"

# Piped stdin must not reach the reviewer.
(cd "$repo_a" && (sleep 5) | run_review stdin-detach) \
  || fail 'review with piped stdin did not detach stdin'

# Output contract failures fail the gate.
if (cd "$repo_a" && NO_LAST_MESSAGE=1 run_review no-report); then
  fail 'empty Codex report did not fail the gate'
fi
if (cd "$repo_a" && UNRECOGNIZED_VERDICT=1 run_review no-verdict); then
  fail 'missing verdict did not fail the gate'
fi
if (cd "$repo_a" && SKIP_VERDICT=1 run_review skipped-verdict); then
  fail 'SKIPPED-only verdict did not fail the gate'
fi
if (cd "$repo_a" && NEEDS_CODEX=1 run_review needs-revision); then
  fail 'Codex NEEDS REVISION did not block the gate'
fi
if (cd "$repo_a" && TRAILING_CODEX=1 run_review trailing-verdict); then
  fail 'Codex PASS followed by trailing text did not block the gate'
fi

# A keyed round that cannot capture the thread id must fail, not degrade.
if (cd "$repo_a" && BAD_THREAD_EVENT=1 run_review no-capture); then
  fail 'uncaptured session id did not fail the keyed gate'
fi
[[ -z "$(state_content "$repo_a" no-capture)" ]] || fail 'failed id capture still persisted session state'

# Reviewer-side mutation of the repository fails the gate.
mut_target="$repo_a/untracked-mode.txt"
printf 'x\n' > "$mut_target"
if (cd "$repo_a" && MUTATE_FILE="$mut_target" run_review mode-mutation); then
  fail 'mode-only mutation of an untracked file did not fail the gate'
fi
rm -f "$mut_target"

# An interrupted wrapper terminates the reviewer process group before it
# releases the per-key lock, so no orphan can share the persistent session
# with the next round.
rm -f "$tmp/codex.hang"
(
  cd "$repo_a" && exec env -u CODEX_REVIEW_SESSION_KEY -u CLAUDE_CODE_SESSION_ID \
    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    CODEX_LOG="$tmp/codex.log" BUNDLE_CAPTURE="$tmp/bundles" \
    HANG_CODEX=1 CODEX_HANG_MARKER="$tmp/codex.hang" \
    "$runner" adversarial --focus test --session-key interrupt-task
) >/dev/null 2>>"$tmp/review.stderr" &
runner_pid=$!
for _ in {1..100}; do
  [[ -s "$tmp/codex.hang" ]] && break
  sleep 0.1
done
[[ -s "$tmp/codex.hang" ]] || fail 'interruption scenario never reached the reviewer'
kill -TERM "$runner_pid"
if wait "$runner_pid"; then
  fail 'interrupted runner exited zero'
fi
hung_pid="$(cat "$tmp/codex.hang")"
for _ in {1..50}; do
  kill -0 "$hung_pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$hung_pid" 2>/dev/null; then
  fail 'interrupted runner left the reviewer process running'
fi
interrupt_lock="$(state_dir_of "$repo_a")/$(session_hash_for "$repo_a" interrupt-task).lock"
[[ ! -e "$interrupt_lock" ]] || fail 'interrupted runner left the per-key lock held'
(cd "$repo_a" && run_review interrupt-task) || fail 'round after interruption failed'

# Incremental checkpoints: full first round, delta-only later rounds.
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

codex_incremental="$(last_bundle)"
grep -Fq 'NEW_PATCH_BODY' "$codex_incremental" || fail 'Codex incremental bundle omitted the new commit body'
! grep -Fq 'OLD_PATCH_BODY' "$codex_incremental" || fail 'Codex incremental bundle repeated an old patch body'
grep -Fq '## Full task summary' "$codex_incremental" || fail 'Codex incremental bundle omitted the full-task summary'

incremental_hash="$(session_hash_for "$repo_incremental" incremental-task)"
incremental_state="$(state_dir_of "$repo_incremental")/$incremental_hash.adversarial.reviewed"
incremental_session="$(state_content "$repo_incremental" incremental-task)"
[[ "$(cat "$incremental_state")" == "$task_base $(git -C "$repo_incremental" rev-parse HEAD) $incremental_session" ]] \
  || fail 'checkpoint did not record base, head, and session id'

# Fail-closed incremental preconditions start no reviewer.
review_calls_before="$(wc -l < "$tmp/codex.log")"
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
review_calls_after="$(wc -l < "$tmp/codex.log")"
[[ "$review_calls_after" -eq "$review_calls_before" ]] || fail 'invalid incremental input started a reviewer'

# A checkpoint bound to a different session forces a full review.
incremental_session_file="$(state_dir_of "$repo_incremental")/$incremental_hash"
saved_session="$(cat "$incremental_session_file")"
printf '%s\n' 'ffffffff-ffff-4fff-8fff-ffffffffffff' > "$incremental_session_file"
(cd "$repo_incremental" && run_review incremental-task \
  --base "$task_base" --since "$previous_review_head")
grep -Fq 'OLD_PATCH_BODY' "$(last_bundle)" \
  || fail 'session-mismatched checkpoint did not force a full review'
printf '%s\n' "$saved_session" > "$incremental_session_file"

# A malformed (two-field) checkpoint is ignored, forcing a full review.
head_now="$(git -C "$repo_incremental" rev-parse HEAD)"
printf '%s %s\n' "$task_base" "$head_now" > "$incremental_state"
(cd "$repo_incremental" && run_review incremental-task \
  --base "$task_base" --since "$previous_review_head")
grep -Fq 'OLD_PATCH_BODY' "$(last_bundle)" \
  || fail 'malformed checkpoint did not force a full review'

# A failed resume during a --since round falls back to the full task.
resume_fallback_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'FALLBACK_BODY\n' > "$repo_incremental/fallback.txt"
git -C "$repo_incremental" add fallback.txt
git -C "$repo_incremental" commit -qm 'add fallback fixture'
FAIL_RESUME_MARKER="$tmp/incremental-failed-resume"; export FAIL_RESUME_MARKER
(cd "$repo_incremental" && run_review incremental-task \
  --base "$task_base" --since "$resume_fallback_previous")
unset FAIL_RESUME_MARKER
grep -Fq 'OLD_PATCH_BODY' "$(last_bundle)" \
  || fail 'fresh fallback session did not receive the full task'
fallback_session="$(state_content "$repo_incremental" incremental-task)"
[[ "$(cat "$incremental_state")" == *" $fallback_session" ]] \
  || fail 'checkpoint did not rebind to the fallback session'

printf 'codex review session checks passed\n'
