#!/usr/bin/env bash
set -euo pipefail

runner="$(cd "$(dirname "$0")" && pwd)/codex-review.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/codex-review-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

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
printf 'CALL' >> "$CODEX_LOG"
printf '\t%q' "$@" >> "$CODEX_LOG"
printf '\n' >> "$CODEX_LOG"
[[ -z "${MUTATE_FILE:-}" ]] || chmod 400 "$MUTATE_FILE"
seen_resume=0
out=""
prev=""
for arg in "$@"; do
  if [[ "$arg" == "resume" ]]; then
    seen_resume=1
  fi
  if [[ "$seen_resume" -eq 1 && "$arg" == "--sandbox" ]]; then
    printf "error: unexpected argument '--sandbox' found\n" >&2
    exit 2
  fi
  if [[ "$prev" == "--output-last-message" ]]; then
    out="$arg"
  fi
  prev="$arg"
done
if [[ "$seen_resume" -eq 1 && -n "${FAIL_RESUME_MARKER:-}" && ! -e "$FAIL_RESUME_MARKER" ]]; then
  : > "$FAIL_RESUME_MARKER"
  exit 1
fi
if [[ -n "${NO_LAST_MESSAGE:-}" ]]; then
  out=""
fi
[[ -z "$out" ]] || printf 'fake review verdict\n' > "$out"
if [[ "${1:-}" == "exec" && "$seen_resume" -eq 0 ]]; then
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
  local repo="$1" task_key="$2"
  if [[ -n "$task_key" ]]; then
    env -u CODEX_REVIEW_SESSION_KEY -u CODEX_THREAD_ID \
      PATH="$tmp/bin:$PATH" CODEX_LOG="$tmp/codex.log" \
      "$runner" adversarial --focus test --session-key "$task_key" >/dev/null 2>>"$tmp/review.stderr"
  else
    env -u CODEX_REVIEW_SESSION_KEY -u CODEX_THREAD_ID \
      PATH="$tmp/bin:$PATH" CODEX_LOG="$tmp/codex.log" \
      "$runner" adversarial --focus test >/dev/null 2>>"$tmp/review.stderr"
  fi
}

thread_id() {
  printf '00000000-0000-4000-8000-%012d' "$1"
}

resume_id_from() {
  sed -n "${1}p" "$tmp/codex.log" | tr '\t' '\n' | awk 'prev == "resume" { print; exit } { prev = $0 }'
}

is_new_session_call() {
  local line
  line="$(sed -n "${1}p" "$tmp/codex.log")"
  [[ "$line" == CALL*exec* ]] || return 1
  ! printf '%s' "$line" | tr '\t' '\n' | grep -qx resume
}

state_content() {
  local repo="$1" key="$2"
  local root state_dir hash
  root="$(git -C "$repo" rev-parse --show-toplevel)"
  state_dir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir)/codex-review-sessions"
  hash="$(printf '%s\0%s' "$root" "$key" | git -C "$repo" hash-object --stdin)"
  [[ -f "$state_dir/$hash" ]] && cat "$state_dir/$hash"
}

repo_a="$tmp/repo-a"
repo_b="$tmp/repo-b"
repo_c="$tmp/repo-c"
make_repo "$repo_a"
make_repo "$repo_b"
make_repo "$repo_c"
: > "$tmp/codex.log"

(cd "$repo_a" && run_review "$repo_a" task-a)
(cd "$repo_a" && run_review "$repo_a" task-a)
id1="$(thread_id 1)"
[[ "$(state_content "$repo_a" task-a)" == "$id1" ]] || fail 'first task review did not persist the session'
[[ "$(resume_id_from 2)" == "$id1" ]] || fail 'second task review did not resume the session'
line2="$(sed -n '2p' "$tmp/codex.log")"
[[ "$line2" == *--sandbox*read-only* ]] || fail 'resume omitted the read-only sandbox'
[[ "$line2" == *--json* ]] || fail 'resume omitted json events'
[[ "$line2" == *mcp_servers* ]] || fail 'resume omitted MCP lockdown'
[[ "$line2" != *--ephemeral* ]] || fail 'persistent review unexpectedly ran ephemeral'

FAIL_RESUME_MARKER="$tmp/failed-resume"; export FAIL_RESUME_MARKER
(cd "$repo_a" && run_review "$repo_a" task-a)
unset FAIL_RESUME_MARKER
id2="$(thread_id 2)"
[[ "$(resume_id_from 3)" == "$id1" ]] || fail 'stale-session check did not try resume first'
is_new_session_call 4 || fail 'stale session was not replaced with a new session'
[[ "$(state_content "$repo_a" task-a)" == "$id2" ]] || fail 'replacement session was not saved'
(cd "$repo_a" && run_review "$repo_a" task-a)
[[ "$(resume_id_from 5)" == "$id2" ]] || fail 'replacement session was not resumed'

(cd "$repo_a" && run_review "$repo_a" task-b)
id3="$(thread_id 3)"
[[ "$(state_content "$repo_a" task-b)" == "$id3" && "$id3" != "$id2" ]] || fail 'different tasks shared a session'

(cd "$repo_b" && run_review "$repo_b" task-a)
id4="$(thread_id 4)"
[[ "$(state_content "$repo_b" task-a)" == "$id4" && "$id4" != "$id2" ]] || fail 'different repositories shared a session'

(cd "$repo_a" && run_review "$repo_a" '../../outside')
state_dir_a="$(git -C "$repo_a" rev-parse --path-format=absolute --git-common-dir)/codex-review-sessions"
repo_a_root="$(git -C "$repo_a" rev-parse --show-toplevel)"
expected_state="$(printf '%s\0%s' "$repo_a_root" '../../outside' | git -C "$repo_a" hash-object --stdin)"
[[ -f "$state_dir_a/$expected_state" ]] || fail 'session key was not hashed'
[[ "$(LC_ALL=C ls -l "$state_dir_a/$expected_state")" == -rw-------* ]] || fail 'session state is not mode 0600'
[[ ! -e "$tmp/outside" ]] || fail 'session key escaped the state directory'

(cd "$repo_a" && run_review "$repo_a" '')
last_line="$(tail -n 1 "$tmp/codex.log")"
[[ "$last_line" == *--ephemeral* ]] || fail 'no-key review did not run ephemeral'
[[ "$last_line" != *resume* ]] || fail 'no-key review unexpectedly resumed a session'

readonly_state_dir="$(git -C "$repo_c" rev-parse --path-format=absolute --git-common-dir)/codex-review-sessions"
mkdir -p "$readonly_state_dir"
chmod 500 "$readonly_state_dir"
if (cd "$repo_c" && run_review "$repo_c" cannot-save); then
  chmod 700 "$readonly_state_dir"
  fail 'session-state write failure did not fail the gate'
fi
chmod 700 "$readonly_state_dir"

(cd "$repo_a" && env -u CODEX_THREAD_ID PATH="$tmp/bin:$PATH" CODEX_LOG="$tmp/codex.log" CODEX_REVIEW_SESSION_KEY=env-loser \
  "$runner" adversarial --focus test --session-key arg-winner >/dev/null 2>>"$tmp/review.stderr")
[[ -n "$(state_content "$repo_a" arg-winner)" ]] || fail '--session-key did not create its own session state'
[[ -z "$(state_content "$repo_a" env-loser)" ]] || fail '--session-key did not override CODEX_REVIEW_SESSION_KEY'

(cd "$repo_a" && env -u CODEX_REVIEW_SESSION_KEY CODEX_THREAD_ID=thread-fallback \
  PATH="$tmp/bin:$PATH" CODEX_LOG="$tmp/codex.log" \
  "$runner" adversarial --focus test >/dev/null 2>>"$tmp/review.stderr")
[[ -n "$(state_content "$repo_a" thread-fallback)" ]] || fail 'CODEX_THREAD_ID fallback did not persist a session'

(cd "$repo_a" && (sleep 5) | env -u CODEX_REVIEW_SESSION_KEY -u CODEX_THREAD_ID \
  PATH="$tmp/bin:$PATH" CODEX_LOG="$tmp/codex.log" \
  "$runner" adversarial --focus test >/dev/null 2>>"$tmp/review.stderr") \
  || fail 'review with piped stdin did not detach stdin'

if (cd "$repo_a" && env -u CODEX_THREAD_ID NO_LAST_MESSAGE=1 PATH="$tmp/bin:$PATH" CODEX_LOG="$tmp/codex.log" \
  "$runner" adversarial --focus test >/dev/null 2>>"$tmp/review.stderr"); then
  fail 'empty final message did not fail the gate'
fi

if (cd "$repo_a" && env -u CODEX_THREAD_ID BAD_THREAD_EVENT=1 PATH="$tmp/bin:$PATH" CODEX_LOG="$tmp/codex.log" \
  "$runner" adversarial --focus test --session-key no-capture >/dev/null 2>>"$tmp/review.stderr"); then
  fail 'uncaptured session id did not fail the keyed gate'
fi
[[ -z "$(state_content "$repo_a" no-capture)" ]] || fail 'failed id capture still persisted session state'

mut_target="$repo_a/untracked-mode.txt"
printf 'x\n' > "$mut_target"
if (cd "$repo_a" && env -u CODEX_THREAD_ID MUTATE_FILE="$mut_target" PATH="$tmp/bin:$PATH" CODEX_LOG="$tmp/codex.log" \
  "$runner" adversarial --focus test >/dev/null 2>>"$tmp/review.stderr"); then
  fail 'mode-only mutation of an untracked file did not fail the gate'
fi

printf 'codex review session checks passed\n'
