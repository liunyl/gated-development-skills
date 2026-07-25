#!/usr/bin/env bash
set -euo pipefail

runner="$(cd "$(dirname "$0")" && pwd)/claude-review.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-review-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.kimi-code/bin" "$tmp/relative-bin" "$tmp/bundles"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cat > "$tmp/bin/mkdir" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ -n "${FAIL_KIMI_SETUP:-}" && "$arg" == */kimi-workspace* ]]; then
    exit 42
  fi
done
exec /bin/mkdir "$@"
EOF
chmod +x "$tmp/bin/mkdir"

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
: > "$CLAUDE_STARTED"
if [[ -n "${EXPECT_KIMI:-}" ]]; then
  for _ in {1..100}; do
    [[ -e "$KIMI_STARTED" ]] && break
    sleep 0.02
  done
  [[ -e "$KIMI_STARTED" ]] || exit 8
fi
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
  elif [[ -z "${UNRECOGNIZED_CLAUDE_VERDICT:-}" ]]; then
    printf 'VERDICT: PASS\n'
  fi
fi
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
[[ -d "$PWD/repo" && -f "$PWD/review-scope.txt" ]] || exit 7
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
  /bin/cat "/proc/1/root$LIVE_IGNORED" >/dev/null 2>&1 && sandbox_failed=1
  /usr/bin/touch "$LIVE_WRITE" >/dev/null 2>&1 && sandbox_failed=1
  /usr/bin/touch "$LIVE_GIT_WRITE" >/dev/null 2>&1 && sandbox_failed=1
  [[ -z "${OLDPWD:-}${GIT_DIR:-}${GIT_WORK_TREE:-}" ]] || sandbox_failed=1
  [[ "$sandbox_failed" -eq 0 ]] || exit 14
fi
for arg in "$@"; do
  [[ "$arg" != *"$LIVE_REPO"* ]] || exit 10
done
[[ "$*" == *"$PWD/repo"* ]] || exit 11
skills_dir=""
review_prompt=""
previous=""
for arg in "$@"; do
  [[ "$previous" != "--skills-dir" ]] || skills_dir="$arg"
  [[ "$previous" != "-p" ]] || review_prompt="$arg"
  previous="$arg"
done
[[ -d "$skills_dir" ]] || exit 24
[[ -z "$(find "$skills_dir" -mindepth 1 -print -quit)" ]] || exit 25
[[ "$review_prompt" == *'End with exactly one machine-readable line: VERDICT: PASS'* ]] || exit 26
[[ "$review_prompt" == *'You may use built-in Agent and AgentSwarm subagents.'* ]] || exit 27
[[ "$review_prompt" == *'Do not invoke external reviewers or review-gate workflows'* ]] || exit 34
[[ "$review_prompt" == *'concurrency, idempotency, database-transactions'* ]] || exit 28
call_no="$(($(wc -l < "$KIMI_LOG") + 1))"
cp "$PWD/review-scope.txt" "$BUNDLE_CAPTURE/kimi-$call_no.txt"
printf 'CALL\tcwd=%q' "$PWD" >> "$KIMI_LOG"
printf '\t%q' "$@" >> "$KIMI_LOG"
printf '\n' >> "$KIMI_LOG"
if [[ -n "${HANG_KIMI:-}" ]]; then
  : > "$KIMI_HANG_MARKER"
  sleep 600
  exit 0
fi
if [[ -n "${FAIL_KIMI_RESUME:-}" && "$*" == *--session* ]]; then
  exit 9
fi
[[ -z "${FAIL_KIMI:-}" ]] || exit 9
if [[ -z "${NO_KIMI_LAST_MESSAGE:-}" ]]; then
  printf 'fake kimi review\n'
  if [[ -n "${SKIP_KIMI:-}" ]]; then
    [[ -z "${EARLY_KIMI_PASS:-}" ]] || printf 'VERDICT: PASS\n'
    printf 'VERDICT: SKIPPED\n'
  else
    printf '\033[32m  VERDICT: PASS\033[0m\n'
  fi
  printf 'To resume this session: kimi -r session_fake_review_id\n'
fi
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
  if (($# > 1)); then
    git init -q --separate-git-dir "$2" "$path"
  else
    git init -q "$path"
  fi
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
  local mode="${REVIEW_MODE:-adversarial}"
  local -a review_env runner_args sandbox_prefix=()
  live_repo="$(git -C "$repo" rev-parse --show-toplevel)"
  live_git="$(git -C "$repo" rev-parse --path-format=absolute --git-dir)"
  review_path="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  [[ "$probe" == "relative-path" ]] && review_path="$tmp/bin:../relative-bin:/usr/bin:/bin:/usr/sbin:/sbin"
  review_env=(
    HOME="$tmp/home" PATH="$review_path"
    CLAUDE_LOG="$tmp/claude.log" KIMI_LOG="$tmp/kimi.log"
    BUNDLE_CAPTURE="$tmp/bundles"
    RELATIVE_KIMI_MARKER="$tmp/relative-kimi.started"
    LIVE_REPO="$live_repo"
    CLAUDE_STARTED="$tmp/claude.started" KIMI_STARTED="$tmp/kimi.started"
    KIMI_HANG_MARKER="$tmp/kimi.hang"
  )
  if [[ "${INCLUDE_KIMI:-1}" -eq 1 && "${EXPECT_KIMI_START:-1}" -eq 1 ]]; then
    review_env+=(EXPECT_KIMI=1)
  fi
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
  elif [[ "$probe" == "failing-bwrap" ]]; then
    sandbox_prefix=(
      /usr/bin/bwrap --die-with-parent --new-session --bind / / --dev /dev
      --ro-bind /usr/bin/env /usr/bin/bwrap --
    )
  fi
  rm -f "$tmp/claude.started" "$tmp/kimi.started"
  runner_args=("$mode" --focus test)
  if [[ "${INCLUDE_KIMI:-1}" -eq 1 ]]; then
    if [[ "${INVALID_KIMI_RISK:-0}" -eq 1 ]]; then
      runner_args+=(--kimi-risk security)
    else
      runner_args+=(
        --kimi-risk concurrency
        --kimi-risk idempotency
        --kimi-risk database-transactions
      )
    fi
  fi
  if (($# > 3)); then
    runner_args+=("${@:4}")
  fi
  # ${arr[@]+...} keeps the empty-array expansion legal under macOS bash 3.2
  # with set -u, where a bare "${arr[@]}" aborts as unbound.
  if [[ -n "$task_key" ]]; then
    ${sandbox_prefix[@]+"${sandbox_prefix[@]}"} env -u CLAUDE_REVIEW_SESSION_KEY CODEX_THREAD_ID="$task_key" \
      "${review_env[@]}" \
      "$runner" "${runner_args[@]}" >/dev/null 2>>"$tmp/review.stderr"
  else
    ${sandbox_prefix[@]+"${sandbox_prefix[@]}"} env -u CODEX_THREAD_ID -u CLAUDE_REVIEW_SESSION_KEY \
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
  local reviewer="$1" log="$2" count
  count="$(awk 'END { print NR }' "$log")"
  printf '%s/bundles/%s-%s.txt\n' "$tmp" "$reviewer" "$count"
}

session_hash_for() {
  local repo_root task_key="$2"
  repo_root="$(cd "$1" && pwd -P)"
  printf '%s\0%s' "$repo_root" "$task_key" | git -C "$1" hash-object --stdin
}

repo_a="$tmp/repo-a"
repo_b="$tmp/repo-b"
repo_c="$tmp/repo-c"
repo_external_git="$tmp/repo-external-git"
external_git="$tmp/external.git"
repo_unborn="$tmp/repo-unborn"
make_repo "$repo_a"
make_repo "$repo_b"
make_repo "$repo_c"
make_repo "$repo_external_git" "$external_git"
git init -q "$repo_unborn"
printf 'uncommitted plan\n' > "$repo_unborn/plan.md"
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

mv "$tmp/home/.kimi-code/bin/kimi" "$tmp/home/.kimi-code/bin/kimi.off"
if ! (cd "$repo_a" && INCLUDE_KIMI=0 run_review "$repo_a" claude-only); then
  mv "$tmp/home/.kimi-code/bin/kimi.off" "$tmp/home/.kimi-code/bin/kimi"
  fail 'Claude-only default required Kimi'
fi
mv "$tmp/home/.kimi-code/bin/kimi.off" "$tmp/home/.kimi-code/bin/kimi"
[[ ! -s "$tmp/kimi.log" ]] || fail 'Claude-only default invoked Kimi'
: > "$tmp/claude.log"
: > "$tmp/kimi.log"

if (cd "$repo_a" && INVALID_KIMI_RISK=1 run_review "$repo_a" invalid-kimi-risk); then
  fail 'unsupported Kimi risk was accepted'
fi
[[ ! -s "$tmp/claude.log" && ! -s "$tmp/kimi.log" ]] || fail 'unsupported Kimi risk started a reviewer'

FAIL_KIMI_SETUP=1; export FAIL_KIMI_SETUP
if ! (cd "$repo_a" && EXPECT_KIMI_START=0 run_review "$repo_a" kimi-setup-failure); then
  unset FAIL_KIMI_SETUP
  fail 'optional Kimi setup failure blocked Claude'
fi
unset FAIL_KIMI_SETUP
[[ "$(wc -l < "$tmp/claude.log")" -eq 1 ]] || fail 'Claude did not run after optional Kimi setup failure'
[[ ! -s "$tmp/kimi.log" ]] || fail 'Kimi started after its snapshot setup failed'
grep -Fq 'optional Kimi snapshot setup failed' "$tmp/review.stderr" || fail 'Kimi setup failure warning was omitted'
: > "$tmp/claude.log"
: > "$tmp/kimi.log"

if [[ "$(uname -s)" == "Linux" ]]; then
  (cd "$repo_a" && EXPECT_KIMI_START=0 run_review "$repo_a" bwrap-probe-failure failing-bwrap)
  [[ "$(wc -l < "$tmp/claude.log")" -eq 1 ]] || fail 'Claude did not run after Bubblewrap probe failure'
  [[ ! -s "$tmp/kimi.log" ]] || fail 'Kimi started after Bubblewrap probe failure'
  grep -Fq 'optional Kimi sandbox setup failed' "$tmp/review.stderr" || fail 'Bubblewrap probe failure warning was omitted'
  grep -Fq 'unrecognized option' "$tmp/review.stderr" || fail 'Bubblewrap probe failure detail was omitted'
  : > "$tmp/claude.log"
  : > "$tmp/kimi.log"
fi

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
[[ "$(sed -n '1p' "$tmp/kimi.log")" != *--session* ]] || fail 'first Kimi review unexpectedly resumed a session'
[[ "$(sed -n '2p' "$tmp/kimi.log")" != *--session* ]] || fail 'second Kimi review reused a session'
[[ "$(sed -n '2p' "$tmp/kimi.log")" != *--continue* ]] || fail 'Kimi review used unsafe implicit continuation'
[[ "$(sed -n '1p' "$tmp/claude.log")" == *--allowedTools*Agent* ]] || fail 'Claude reviewer lost its own subagent tool'
[[ "$(sed -n '1p' "$tmp/claude.log")" == *codex-gated-development* ]] || fail 'Claude reviewer gate skill was not denied'
kimi_task_a_cwd="$(sed -n '1s/^CALL\tcwd=\([^[:space:]]*\).*/\1/p' "$tmp/kimi.log")"
[[ -n "$kimi_task_a_cwd" && "$(sed -n '2p' "$tmp/kimi.log")" != *"cwd=$kimi_task_a_cwd"* ]] || fail 'optional Kimi review reused a workspace'
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
[[ "$(sed -n '8p' "$tmp/kimi.log")" != *--session* ]] || fail 'no-task Kimi review unexpectedly reused a session'

sandbox_calls_before="$(wc -l < "$tmp/kimi.log")"
(cd "$repo_a" && run_review "$repo_a" sandbox-probe sandbox)
[[ "$(wc -l < "$tmp/kimi.log")" -eq "$((sandbox_calls_before + 1))" ]] || fail 'Kimi live-repository sandbox probe did not complete'
[[ ! -e "$repo_a/.sandbox-write" ]] || fail 'Kimi wrote an ignored live-worktree file'
[[ ! -e "$repo_a/.git/sandbox-write" ]] || fail 'Kimi wrote live Git state'
sandbox_calls_before="$(wc -l < "$tmp/kimi.log")"
(cd "$repo_external_git" && run_review "$repo_external_git" external-git-sandbox-probe sandbox)
[[ "$(wc -l < "$tmp/kimi.log")" -eq "$((sandbox_calls_before + 1))" ]] || fail 'Kimi separate-Git-dir sandbox probe did not complete'
[[ ! -e "$repo_external_git/.sandbox-write" ]] || fail 'Kimi wrote a separate-Git-dir worktree file'
[[ ! -e "$external_git/sandbox-write" ]] || fail 'Kimi wrote separate Git state'

rm -f "$tmp/relative-kimi.started"
(cd "$repo_a" && run_review "$repo_a" relative-path relative-path)
[[ -e "$tmp/relative-kimi.started" ]] || fail 'relative PATH Kimi was not invoked'

FAIL_KIMI=1; export FAIL_KIMI
(cd "$repo_a" && run_review "$repo_a" task-a) || {
  unset FAIL_KIMI
  fail 'optional Kimi failure blocked Claude'
}
unset FAIL_KIMI

# A hung optional Kimi is terminated after the bounded grace and never
# blocks the mandatory Claude verdict.
rm -f "$tmp/kimi.hang"
hang_start="$(date +%s)"
(cd "$repo_a" && HANG_KIMI=1 KIMI_REVIEW_GRACE_SECONDS=1 run_review "$repo_a" task-a) \
  || fail 'hung optional Kimi failed the Claude gate'
hang_elapsed="$(( $(date +%s) - hang_start ))"
[[ -e "$tmp/kimi.hang" ]] || fail 'hang scenario never reached the fake Kimi'
[[ "$hang_elapsed" -lt 60 ]] || fail 'hung Kimi was not terminated within the grace window'
grep -Fq 'optional Kimi review timed out' "$tmp/review.stderr" || fail 'Kimi timeout warning was omitted'
(cd "$repo_a" && run_review "$repo_a" task-a) || fail 'round after Kimi timeout failed'

# An interrupted wrapper terminates the reviewer process group instead of
# leaving an orphan running against the persistent session.
rm -f "$tmp/claude.hang"
(
  cd "$repo_a" && exec env -u CODEX_THREAD_ID -u CLAUDE_REVIEW_SESSION_KEY \
    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    CLAUDE_LOG="$tmp/claude.log" KIMI_LOG="$tmp/kimi.log" \
    BUNDLE_CAPTURE="$tmp/bundles" \
    RELATIVE_KIMI_MARKER="$tmp/relative-kimi.started" \
    LIVE_REPO="$(git -C "$repo_a" rev-parse --show-toplevel)" \
    CLAUDE_STARTED="$tmp/claude.started" KIMI_STARTED="$tmp/kimi.started" \
    KIMI_HANG_MARKER="$tmp/kimi.hang" \
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
(cd "$repo_a" && run_review "$repo_a" interrupt-task) || fail 'round after interruption failed'

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
  BUNDLE_CAPTURE="$tmp/bundles" \
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

(cd "$repo_unborn" && run_review "$repo_unborn" unborn-working-tree)

if (cd "$repo_a" && NO_LAST_MESSAGE=1 run_review "$repo_a" no-claude-report); then
  unset NO_LAST_MESSAGE
  fail 'empty Claude report did not fail the gate'
fi
unset NO_LAST_MESSAGE

UNRECOGNIZED_CLAUDE_VERDICT=1; export UNRECOGNIZED_CLAUDE_VERDICT
if (cd "$repo_a" && run_review "$repo_a" unrecognized-claude-verdict); then
  unset UNRECOGNIZED_CLAUDE_VERDICT
  fail 'unrecognized Claude verdict did not fail the gate'
fi
unset UNRECOGNIZED_CLAUDE_VERDICT

(cd "$repo_a" && NO_KIMI_LAST_MESSAGE=1 run_review "$repo_a" no-kimi-report) || {
  unset NO_KIMI_LAST_MESSAGE
  fail 'empty optional Kimi report blocked Claude'
}
unset NO_KIMI_LAST_MESSAGE

mut_target="$repo_a/untracked-mode.txt"
printf 'x\n' > "$mut_target"
if (cd "$repo_a" && MUTATE_FILE="$mut_target" run_review "$repo_a" mode-mutation); then
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

(cd "$repo_incremental" && run_review "$repo_incremental" incremental-task "" --base "$task_base")
printf 'NEW_PATCH_BODY\n' > "$repo_incremental/new.txt"
git -C "$repo_incremental" add new.txt
git -C "$repo_incremental" commit -qm 'add review fix'
(cd "$repo_incremental" && run_review "$repo_incremental" incremental-task "" \
  --base "$task_base" --since "$previous_review_head")

claude_incremental="$tmp/bundles/claude-$(awk 'END { print NR }' "$tmp/claude.log").txt"
kimi_incremental="$tmp/bundles/kimi-$(awk 'END { print NR }' "$tmp/kimi.log").txt"
grep -Fq 'NEW_PATCH_BODY' "$claude_incremental" || fail 'Claude incremental bundle omitted the new commit body'
! grep -Fq 'OLD_PATCH_BODY' "$claude_incremental" || fail 'Claude incremental bundle repeated an old patch body'
grep -Fq '## Full task summary' "$claude_incremental" || fail 'Claude incremental bundle omitted the full-task summary'
grep -Fq 'NEW_PATCH_BODY' "$kimi_incremental" || fail 'Kimi full bundle omitted the new commit body'
grep -Fq 'OLD_PATCH_BODY' "$kimi_incremental" || fail 'Kimi did not receive the full task'

incremental_hash="$(session_hash_for "$repo_incremental" incremental-task)"
incremental_state="$(git -C "$repo_incremental" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions/$incremental_hash.adversarial.reviewed"
[[ "$(cat "$incremental_state")" == "$task_base $(git -C "$repo_incremental" rev-parse HEAD)" ]] || fail 'Claude review checkpoint was not recorded'

review_calls_before="$(($(wc -l < "$tmp/claude.log") + $(wc -l < "$tmp/kimi.log")))"
if (cd "$repo_incremental" && run_review "$repo_incremental" invalid-no-base "" --since "$previous_review_head"); then
  fail '--since without --base did not fail'
fi
if (cd "$repo_incremental" && run_review "$repo_incremental" invalid-empty "" --base "$task_base" --since HEAD); then
  fail 'empty incremental range did not fail'
fi
unrelated_commit="$(git -C "$repo_incremental" commit-tree "$(git -C "$repo_incremental" write-tree)" -m unrelated)"
if (cd "$repo_incremental" && run_review "$repo_incremental" invalid-history "" --base "$task_base" --since "$unrelated_commit"); then
  fail 'unrelated incremental history did not fail'
fi
printf 'dirty\n' > "$repo_incremental/dirty.txt"
if (cd "$repo_incremental" && run_review "$repo_incremental" invalid-dirty "" --base "$task_base" --since "$previous_review_head"); then
  fail 'dirty incremental review did not fail'
fi
rm -f "$repo_incremental/dirty.txt"
review_calls_after="$(($(wc -l < "$tmp/claude.log") + $(wc -l < "$tmp/kimi.log")))"
[[ "$review_calls_after" -eq "$review_calls_before" ]] || fail 'invalid incremental input started a reviewer'

(cd "$repo_incremental" && run_review "$repo_incremental" fresh-incremental "" \
  --base "$task_base" --since "$previous_review_head")
grep -Fq 'OLD_PATCH_BODY' "$(last_bundle claude "$tmp/claude.log")" || fail 'fresh Claude session did not receive the full task'
grep -Fq 'OLD_PATCH_BODY' "$(last_bundle kimi "$tmp/kimi.log")" || fail 'fresh Kimi session did not receive the full task'

code_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'CODE_FIRST_BODY\n' > "$repo_incremental/code.txt"
git -C "$repo_incremental" add code.txt
git -C "$repo_incremental" commit -qm 'add code gate change'
(cd "$repo_incremental" && REVIEW_MODE=code run_review "$repo_incremental" incremental-task "" \
  --base "$task_base" --since "$code_previous")
grep -Fq 'OLD_PATCH_BODY' "$(last_bundle kimi "$tmp/kimi.log")" || fail 'first code-mode review was not full'

unsafe_since="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'UNSAFE_CHECKPOINT_BODY\n' > "$repo_incremental/unsafe.txt"
git -C "$repo_incremental" add unsafe.txt
git -C "$repo_incremental" commit -qm 'add unsafe checkpoint fixture'
(cd "$repo_incremental" && run_review "$repo_incremental" incremental-task "" \
  --base "$task_base" --since "$unsafe_since")
grep -Fq 'OLD_PATCH_BODY' "$(last_bundle claude "$tmp/claude.log")" || fail 'checkpoint ahead of reviewed HEAD did not force a full review'

changed_base="$previous_review_head"
changed_base_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'CHANGED_BASE_BODY\n' > "$repo_incremental/changed-base.txt"
git -C "$repo_incremental" add changed-base.txt
git -C "$repo_incremental" commit -qm 'add changed base fixture'
(cd "$repo_incremental" && run_review "$repo_incremental" incremental-task "" \
  --base "$changed_base" --since "$changed_base_previous")
grep -Fq 'NEW_PATCH_BODY' "$(last_bundle kimi "$tmp/kimi.log")" || fail 'changed task base did not force a full review'

claude_fallback_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'CLAUDE_FALLBACK_BODY\n' > "$repo_incremental/claude-fallback.txt"
git -C "$repo_incremental" add claude-fallback.txt
git -C "$repo_incremental" commit -qm 'add Claude fallback fixture'
FAIL_RESUME_MARKER="$tmp/incremental-failed-resume"; export FAIL_RESUME_MARKER
(cd "$repo_incremental" && run_review "$repo_incremental" incremental-task "" \
  --base "$changed_base" --since "$claude_fallback_previous")
unset FAIL_RESUME_MARKER
grep -Fq 'NEW_PATCH_BODY' "$(last_bundle claude "$tmp/claude.log")" || fail 'fresh Claude fallback did not receive the full task'
grep -Fq 'NEW_PATCH_BODY' "$(last_bundle kimi "$tmp/kimi.log")" || fail 'fresh Kimi review did not receive the full task'

escaped_key='../../incremental-outside'
(cd "$repo_incremental" && run_review "$repo_incremental" "$escaped_key" "" --base "$changed_base")
escaped_hash="$(session_hash_for "$repo_incremental" "$escaped_key")"
escaped_checkpoint="$(git -C "$repo_incremental" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions/$escaped_hash.adversarial.reviewed"
[[ -f "$escaped_checkpoint" ]] || fail 'hashed incremental checkpoint was not written'
[[ ! -e "$tmp/incremental-outside" ]] || fail 'incremental checkpoint key escaped its state directory'

checkpoint_failure_key='checkpoint-write-failure'
checkpoint_failure_hash="$(session_hash_for "$repo_incremental" "$checkpoint_failure_key")"
checkpoint_failure_path="$(git -C "$repo_incremental" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions/$checkpoint_failure_hash.adversarial.reviewed"
mkdir -p "$checkpoint_failure_path"
if (cd "$repo_incremental" && run_review "$repo_incremental" "$checkpoint_failure_key" "" --base "$changed_base"); then
  fail 'checkpoint write failure did not fail the gate'
fi
rm -rf "$checkpoint_failure_path"

skipped_key='skipped-checkpoint'
(cd "$repo_incremental" && run_review "$repo_incremental" "$skipped_key" "" --base "$changed_base")
skipped_hash="$(session_hash_for "$repo_incremental" "$skipped_key")"
skipped_checkpoint="$(git -C "$repo_incremental" rev-parse --path-format=absolute --git-common-dir)/claude-review-sessions/$skipped_hash.adversarial.reviewed"
skipped_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
checkpoint_before_skipped="$(cat "$skipped_checkpoint")"
printf 'SKIPPED_REVIEW_BODY\n' > "$repo_incremental/skipped.txt"
git -C "$repo_incremental" add skipped.txt
git -C "$repo_incremental" commit -qm 'add skipped review fixture'
SKIP_KIMI=1; EARLY_KIMI_PASS=1; export SKIP_KIMI EARLY_KIMI_PASS
(cd "$repo_incremental" && run_review "$repo_incremental" "$skipped_key" "" \
  --base "$changed_base" --since "$skipped_previous") || {
  unset SKIP_KIMI EARLY_KIMI_PASS
  fail 'SKIPPED optional Kimi verdict blocked Claude'
}
unset SKIP_KIMI EARLY_KIMI_PASS
[[ "$(cat "$skipped_checkpoint")" != "$checkpoint_before_skipped" ]] || fail 'Claude checkpoint did not advance after optional Kimi SKIPPED'
! grep -Fq "ambiguous argument 'HEAD'" "$tmp/review.stderr" || fail 'unborn working-tree review emitted a raw HEAD error'

printf 'mandatory Claude and optional targeted Kimi review checks passed\n'
