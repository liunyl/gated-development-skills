#!/usr/bin/env bash
set -euo pipefail

runner="$(cd "$(dirname "$0")" && pwd)/claude-review.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-review-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.kimi-code/bin" "$tmp/relative-bin"

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
[[ -z "${MUTATE_FILE:-}" ]] || chmod 400 "$MUTATE_FILE"
: > "$CLAUDE_STARTED"
for _ in {1..100}; do
  [[ -e "$KIMI_STARTED" ]] && break
  sleep 0.02
done
[[ -e "$KIMI_STARTED" ]] || exit 8
printf 'CALL' >> "$CLAUDE_LOG"
shift
printf '\t%q' "$@" >> "$CLAUDE_LOG"
printf '\n' >> "$CLAUDE_LOG"
if [[ -n "${FAIL_RESUME_MARKER:-}" && ! -e "$FAIL_RESUME_MARKER" ]]; then
  for arg in "$@"; do
    if [[ "$arg" == "--resume" ]]; then
      : > "$FAIL_RESUME_MARKER"
      exit 1
    fi
  done
fi
[[ -n "${NO_LAST_MESSAGE:-}" ]] || printf 'fake claude verdict\n'
EOF
chmod +x "$tmp/bin/claude"

cat > "$tmp/home/.kimi-code/bin/kimi" <<'EOF'
#!/usr/bin/env bash
if [[ -t 0 || -p /dev/stdin ]]; then
  printf 'fake kimi: stdin must be pinned to /dev/null\n' >&2
  exit 97
fi
: > "$KIMI_STARTED"
for _ in {1..100}; do
  [[ -e "$CLAUDE_STARTED" ]] && break
  sleep 0.02
done
[[ -e "$CLAUDE_STARTED" ]] || exit 8
[[ -f "$PWD/repo/tracked.txt" && -f "$PWD/review-scope.txt" ]] || exit 7
if grep -Fq -- "$LIVE_REPO" "$PWD/review-scope.txt"; then
  exit 12
fi
if ! grep -Fqx -- "Repository: $PWD/repo" "$PWD/review-scope.txt"; then
  exit 13
fi
if [[ -n "${EXPECT_SNAPSHOT_TYPES:-}" ]]; then
  [[ -f "$PWD/repo/external-link" && ! -L "$PWD/repo/external-link" ]] || exit 19
  grep -Fqx -- 'symlink' "$PWD/repo/external-link" || exit 20
  if grep -Fq -- 'external secret content' "$PWD/repo/external-link"; then
    exit 21
  fi
  [[ -f "$PWD/repo/submodule/.gitlink" ]] || exit 22
  [[ ! -e "$PWD/repo/submodule/inside.txt" ]] || exit 23
fi
if [[ -n "${PROBE_SANDBOX:-}" ]]; then
  sandbox_failed=0
  /bin/cat "$LIVE_IGNORED" >/dev/null 2>&1 && sandbox_failed=1
  /bin/cat "$LIVE_GIT_FILE" >/dev/null 2>&1 && sandbox_failed=1
  /usr/bin/touch "$LIVE_WRITE" >/dev/null 2>&1 && sandbox_failed=1
  /usr/bin/touch "$LIVE_GIT_WRITE" >/dev/null 2>&1 && sandbox_failed=1
  [[ -z "${OLDPWD:-}${GIT_DIR:-}${GIT_WORK_TREE:-}" ]] || sandbox_failed=1
  [[ "$sandbox_failed" -eq 0 ]] || exit 14
fi
for arg in "$@"; do
  [[ "$arg" != *"$LIVE_REPO"* ]] || exit 10
done
[[ "$*" == *"$PWD/repo"* ]] || exit 11
printf 'CALL\tcwd=%q' "$PWD" >> "$KIMI_LOG"
printf '\t%q' "$@" >> "$KIMI_LOG"
printf '\n' >> "$KIMI_LOG"
[[ -z "${FAIL_KIMI:-}" ]] || exit 9
[[ -n "${NO_KIMI_LAST_MESSAGE:-}" ]] || printf 'fake kimi verdict\n'
EOF
chmod +x "$tmp/home/.kimi-code/bin/kimi"

cat > "$tmp/relative-bin/kimi" <<'EOF'
#!/usr/bin/env bash
: > "$RELATIVE_KIMI_MARKER"
exec "$HOME/.kimi-code/bin/kimi" "$@"
EOF
chmod +x "$tmp/relative-bin/kimi"

make_repo() {
  local path="$1"
  git init -q "$path"
  git -C "$path" config user.name Test
  git -C "$path" config user.email test@example.com
  printf '.ignored-secret\n.sandbox-write\n' > "$path/.gitignore"
  printf 'ignored live secret\n' > "$path/.ignored-secret"
  printf 'before\n' > "$path/tracked.txt"
  git -C "$path" add .gitignore tracked.txt
  git -C "$path" commit -qm baseline
  printf 'after\n' >> "$path/tracked.txt"
}

run_review() {
  local repo="$1" task_key="$2" probe="${3:-}"
  local live_repo live_git review_path
  local -a review_env
  live_repo="$(git -C "$repo" rev-parse --show-toplevel)"
  live_git="$(git -C "$repo" rev-parse --path-format=absolute --git-dir)"
  review_path="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  [[ "$probe" == "relative-path" ]] && review_path="$tmp/bin:../relative-bin:/usr/bin:/bin:/usr/sbin:/sbin"
  review_env=(
    HOME="$tmp/home" PATH="$review_path"
    CLAUDE_LOG="$tmp/claude.log" KIMI_LOG="$tmp/kimi.log"
    RELATIVE_KIMI_MARKER="$tmp/relative-kimi.started"
    LIVE_REPO="$live_repo"
    CLAUDE_STARTED="$tmp/claude.started" KIMI_STARTED="$tmp/kimi.started"
  )
  if [[ -L "$repo/external-link" && -d "$repo/submodule" ]]; then
    review_env+=(EXPECT_SNAPSHOT_TYPES=1)
  fi
  if [[ "$probe" == "sandbox" ]]; then
    review_env+=(
      PROBE_SANDBOX=1
      LIVE_IGNORED="$live_repo/.ignored-secret"
      LIVE_GIT_FILE="$live_git/HEAD"
      LIVE_WRITE="$live_repo/.sandbox-write"
      LIVE_GIT_WRITE="$live_git/sandbox-write"
      OLDPWD="$live_repo"
      GIT_DIR="$live_git"
      GIT_WORK_TREE="$live_repo"
    )
  fi
  rm -f "$tmp/claude.started" "$tmp/kimi.started"
  if [[ -n "$task_key" ]]; then
    env -u CLAUDE_REVIEW_SESSION_KEY CODEX_THREAD_ID="$task_key" \
      "${review_env[@]}" \
      "$runner" adversarial --focus test >/dev/null 2>>"$tmp/review.stderr"
  else
    env -u CODEX_THREAD_ID -u CLAUDE_REVIEW_SESSION_KEY \
      "${review_env[@]}" \
      "$runner" adversarial --focus test >/dev/null 2>>"$tmp/review.stderr"
  fi
}

session_id_from() {
  sed -n "${1}s/.*--session-id[[:space:]]\([^[:space:]]*\).*/\1/p" "$tmp/claude.log"
}

resume_id_from() {
  sed -n "${1}s/.*--resume[[:space:]]\([^[:space:]]*\).*/\1/p" "$tmp/claude.log"
}

repo_a="$tmp/repo-a"
repo_b="$tmp/repo-b"
repo_c="$tmp/repo-c"
make_repo "$repo_a"
make_repo "$repo_b"
make_repo "$repo_c"
external_secret="$tmp/external-secret.txt"
printf 'external secret content\n' > "$external_secret"
ln -s "$external_secret" "$repo_a/external-link"
submodule_source="$tmp/submodule-source"
git init -q "$submodule_source"
git -C "$submodule_source" config user.name Test
git -C "$submodule_source" config user.email test@example.com
printf 'submodule content\n' > "$submodule_source/inside.txt"
git -C "$submodule_source" add inside.txt
git -C "$submodule_source" commit -qm baseline
git -C "$repo_a" -c protocol.file.allow=always submodule add -q "$submodule_source" submodule
git -C "$repo_a" config -f .gitmodules submodule.submodule.url ../submodule-source
git -C "$repo_a" add .gitmodules external-link submodule
git -C "$repo_a" commit -qm 'add snapshot type fixtures'
: > "$tmp/claude.log"
: > "$tmp/kimi.log"

(cd "$repo_a" && run_review "$repo_a" task-a)
(cd "$repo_a" && run_review "$repo_a" task-a)
first_id="$(session_id_from 1)"
[[ -n "$first_id" ]] || fail 'first task review did not create a session'
[[ "$(resume_id_from 2)" == "$first_id" ]] || fail 'second task review did not resume the session'
[[ "$(sed -n '1p' "$tmp/claude.log")" != *--no-session-persistence* ]] || fail 'persistent review disabled session persistence'
[[ "$(sed -n '2p' "$tmp/claude.log")" == *--allowedTools* ]] || fail 'resume omitted allowed tools'
[[ "$(sed -n '2p' "$tmp/claude.log")" == *--disallowedTools* ]] || fail 'resume omitted denied tools'
[[ "$(sed -n '2p' "$tmp/claude.log")" == *--strict-mcp-config* ]] || fail 'resume omitted strict MCP config'
[[ "$(sed -n '2p' "$tmp/claude.log")" == *disableAllHooks* ]] || fail 'resume omitted hook lockdown'
[[ "$(sed -n '1p' "$tmp/kimi.log")" != *--continue* ]] || fail 'first Kimi review unexpectedly resumed a session'
[[ "$(sed -n '2p' "$tmp/kimi.log")" == *--continue* ]] || fail 'second Kimi review did not resume the session'
kimi_task_a_cwd="$(sed -n '1s/^CALL\tcwd=\([^[:space:]]*\).*/\1/p' "$tmp/kimi.log")"
[[ -n "$kimi_task_a_cwd" && "$(sed -n '2p' "$tmp/kimi.log")" == *"cwd=$kimi_task_a_cwd"* ]] || fail 'same task did not reuse Kimi workspace'
[[ "$kimi_task_a_cwd" != "$repo_a" ]] || fail 'Kimi reviewed the live worktree'

FAIL_RESUME_MARKER="$tmp/failed-resume"; export FAIL_RESUME_MARKER
(cd "$repo_a" && run_review "$repo_a" task-a)
unset FAIL_RESUME_MARKER
replacement_id="$(session_id_from 4)"
[[ "$(resume_id_from 3)" == "$first_id" ]] || fail 'stale-session check did not try resume first'
[[ -n "$replacement_id" && "$replacement_id" != "$first_id" ]] || fail 'stale session was not replaced'
(cd "$repo_a" && run_review "$repo_a" task-a)
[[ "$(resume_id_from 5)" == "$replacement_id" ]] || fail 'replacement session was not saved'

(cd "$repo_a" && run_review "$repo_a" task-b)
task_b_id="$(session_id_from 6)"
[[ -n "$task_b_id" && "$task_b_id" != "$replacement_id" ]] || fail 'different tasks shared a session'
[[ "$(sed -n '5p' "$tmp/kimi.log")" != *"cwd=$kimi_task_a_cwd"* ]] || fail 'different tasks shared a Kimi workspace'

(cd "$repo_b" && run_review "$repo_b" task-a)
repo_b_id="$(session_id_from 7)"
[[ -n "$repo_b_id" && "$repo_b_id" != "$replacement_id" ]] || fail 'different repositories shared a session'
[[ "$(sed -n '6p' "$tmp/kimi.log")" != *"cwd=$kimi_task_a_cwd"* ]] || fail 'different repositories shared a Kimi workspace'

(cd "$repo_a" && run_review "$repo_a" '../../outside')
state_dir="$(git -C "$repo_a" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions"
repo_a_root="$(git -C "$repo_a" rev-parse --show-toplevel)"
expected_state="$(printf '%s\0%s' "$repo_a_root" '../../outside' | git -C "$repo_a" hash-object --stdin)"
[[ -f "$state_dir/$expected_state" ]] || fail 'session key was not hashed'
[[ "$(LC_ALL=C ls -l "$state_dir/$expected_state")" == -rw-------* ]] || fail 'session state is not mode 0600'
[[ ! -e "$tmp/outside" ]] || fail 'session key escaped the state directory'

(cd "$repo_a" && run_review "$repo_a" '')
last_line="$(tail -n 1 "$tmp/claude.log")"
[[ "$last_line" == *--no-session-persistence* ]] || fail 'no-task review did not stay non-persistent'
[[ "$last_line" != *--session-id* && "$last_line" != *--resume* ]] || fail 'no-task review unexpectedly reused a session'
[[ "$(sed -n '8p' "$tmp/kimi.log")" != *--continue* ]] || fail 'no-task Kimi review unexpectedly reused a session'

(cd "$repo_a" && run_review "$repo_a" sandbox-probe sandbox)
[[ ! -e "$repo_a/.sandbox-write" ]] || fail 'Kimi wrote an ignored live-worktree file'
[[ ! -e "$repo_a/.git/sandbox-write" ]] || fail 'Kimi wrote live Git state'

marker_key="marker-write-failure"
marker_repo="$(git -C "$repo_a" rev-parse --show-toplevel)"
marker_hash="$(printf '%s\0%s' "$marker_repo" "$marker_key" | git -C "$repo_a" hash-object --stdin)"
marker_path="$tmp/home/.cache/claude-gated-development/kimi-review-workspaces/$marker_hash/.successful-review"
mkdir -p "$marker_path"
if (cd "$repo_a" && run_review "$repo_a" "$marker_key"); then
  fail 'Kimi marker write failure did not fail the gate'
fi
rm -rf "$marker_path"

rm -f "$tmp/relative-kimi.started"
(cd "$repo_a" && run_review "$repo_a" relative-path relative-path)
[[ -e "$tmp/relative-kimi.started" ]] || fail 'relative PATH Kimi was not invoked'

FAIL_KIMI=1; export FAIL_KIMI
if (cd "$repo_a" && run_review "$repo_a" task-a); then
  unset FAIL_KIMI
  fail 'Kimi failure did not fail the gate'
fi
unset FAIL_KIMI

readonly_state_dir="$(git -C "$repo_c" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions"
mkdir -p "$readonly_state_dir"
chmod 500 "$readonly_state_dir"
if (cd "$repo_c" && run_review "$repo_c" cannot-save); then
  chmod 700 "$readonly_state_dir"
  fail 'session-state write failure did not fail the gate'
fi
chmod 700 "$readonly_state_dir"

rm -f "$tmp/claude.started" "$tmp/kimi.started"
(cd "$repo_a" && env -u CODEX_THREAD_ID CLAUDE_REVIEW_SESSION_KEY=env-loser \
  HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  CLAUDE_LOG="$tmp/claude.log" KIMI_LOG="$tmp/kimi.log" \
  RELATIVE_KIMI_MARKER="$tmp/relative-kimi.started" \
  LIVE_REPO="$(git -C "$repo_a" rev-parse --show-toplevel)" \
  CLAUDE_STARTED="$tmp/claude.started" KIMI_STARTED="$tmp/kimi.started" \
  "$runner" adversarial --focus test --session-key arg-winner >/dev/null 2>>"$tmp/review.stderr")
arg_state="$(printf '%s\0%s' "$repo_a_root" 'arg-winner' | git -C "$repo_a" hash-object --stdin)"
env_state="$(printf '%s\0%s' "$repo_a_root" 'env-loser' | git -C "$repo_a" hash-object --stdin)"
[[ -f "$state_dir/$arg_state" ]] || fail '--session-key did not create its own session state'
[[ ! -e "$state_dir/$env_state" ]] || fail '--session-key did not override CLAUDE_REVIEW_SESSION_KEY'

(cd "$repo_a" && (sleep 5) | run_review "$repo_a" stdin-detach) \
  || fail 'review with piped stdin did not detach stdin'

if (cd "$repo_a" && NO_LAST_MESSAGE=1 run_review "$repo_a" no-claude-report); then
  unset NO_LAST_MESSAGE
  fail 'empty Claude report did not fail the gate'
fi
unset NO_LAST_MESSAGE

if (cd "$repo_a" && NO_KIMI_LAST_MESSAGE=1 run_review "$repo_a" no-kimi-report); then
  unset NO_KIMI_LAST_MESSAGE
  fail 'empty Kimi report did not fail the gate'
fi
unset NO_KIMI_LAST_MESSAGE

mut_target="$repo_a/untracked-mode.txt"
printf 'x\n' > "$mut_target"
if (cd "$repo_a" && MUTATE_FILE="$mut_target" run_review "$repo_a" mode-mutation); then
  unset MUTATE_FILE
  fail 'mode-only mutation of an untracked file did not fail the gate'
fi
unset MUTATE_FILE

printf 'parallel Claude and Kimi review checks passed\n'
