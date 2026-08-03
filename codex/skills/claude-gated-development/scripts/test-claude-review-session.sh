#!/usr/bin/env bash
set -euo pipefail

runner="$(cd "$(dirname "$0")" && pwd)/claude-review.sh"
shared_runner="$(cd "$(dirname "$runner")/../../../.." && pwd -P)/shared/scripts/kimi-review.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-review-test.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home/.kimi-code/bin" "$tmp/relative-bin"
kimi_source_home="$(cd "$tmp/home/.kimi-code" && pwd -P)"
kimi_source_hash="$(printf '%s' "$kimi_source_home" | git hash-object --stdin)"
kimi_test_runtime="$tmp/home/.cache/gated-development-skills/kimi-review-runtime/$kimi_source_hash"
mkdir -p "$kimi_test_runtime/bundles"
ln -s "$kimi_test_runtime/bundles" "$tmp/bundles"
: > "$kimi_test_runtime/kimi.log"
ln -s "$kimi_test_runtime/kimi.log" "$tmp/kimi.log"
for marker in kimi.started kimi.hang kimi.leak relative-kimi.started; do
  ln -s "$kimi_test_runtime/$marker" "$tmp/$marker"
done
mkdir -p "$tmp/home/.codex/skills/claude-gated-development"
mkdir -p "$tmp/home/.cache/gated-development-skills/kimi-review-state"
printf 'protected gate\n' > "$tmp/home/.codex/skills/claude-gated-development/protected"
printf 'protected state\n' > "$tmp/home/.cache/gated-development-skills/kimi-review-state/protected"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cat > "$tmp/bin/mkdir" <<'EOF'
#!/usr/bin/env bash
for arg in "$@"; do
  if [[ -n "${FAIL_KIMI_SETUP:-}" && "$arg" == */kimi-review-workspaces* ]]; then
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
if [[ -n "${COMMIT_DURING_KIMI:-}" ]]; then
  printf 'concurrent change\n' > "$LIVE_REPO/concurrent-review-change.txt"
  git -C "$LIVE_REPO" add concurrent-review-change.txt
  git -C "$LIVE_REPO" commit -qm 'concurrent review mutation'
  : > "$CONCURRENT_COMMIT_DONE"
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
  elif [[ -n "${NEEDS_CLAUDE:-}" ]]; then
    printf 'VERDICT: NEEDS REVISION\n'
  elif [[ -z "${UNRECOGNIZED_CLAUDE_VERDICT:-}" ]]; then
    printf 'VERDICT: PASS\n'
  fi
  [[ -z "${TRAILING_CLAUDE:-}" ]] || printf 'trailing Claude text\n'
fi
EOF
chmod +x "$tmp/bin/claude"

cat > "$tmp/home/.kimi-code/bin/kimi" <<'EOF'
#!/usr/bin/env bash
if [[ -t 0 || -p /dev/stdin ]]; then
  printf 'fake kimi: stdin must be pinned to /dev/null\n' >&2
  exit 97
fi
[[ "$HOME" == "$KIMI_CODE_HOME/home" ]] || exit 98
: > /dev/null || exit 99
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
  /bin/cat "$PROTECTED_STATE_FILE" >/dev/null 2>&1 && sandbox_failed=1
  /bin/cat "/proc/1/root$PROTECTED_STATE_FILE" >/dev/null 2>&1 && sandbox_failed=1
  /usr/bin/touch "$PROTECTED_STATE_WRITE" >/dev/null 2>&1 && sandbox_failed=1
  /usr/bin/touch "$PROTECTED_GATE_WRITE" >/dev/null 2>&1 && sandbox_failed=1
  /usr/bin/touch "$UNRELATED_WRITE" >/dev/null 2>&1 && sandbox_failed=1
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
if [[ -n "${COMMIT_DURING_KIMI:-}" ]]; then
  for _ in {1..100}; do
    [[ -e "$CONCURRENT_COMMIT_DONE" ]] && break
    sleep 0.02
  done
  [[ -e "$CONCURRENT_COMMIT_DONE" ]] || exit 35
fi
if [[ -n "${LEAK_KIMI_STDERR:-}" ]]; then
  sleep 600 >&2 &
  printf '%s' "$!" > "$KIMI_LEAK_MARKER"
fi
if [[ -z "${NO_KIMI_LAST_MESSAGE:-}" ]]; then
  printf 'fake kimi review\n'
  [[ -z "${QUOTE_FALSE_SESSION:-}" ]] ||
    printf 'evidence: kimi -r session_report_injection\n'
  if [[ -n "${SKIP_KIMI:-}" ]]; then
    [[ -z "${EARLY_KIMI_PASS:-}" ]] || printf 'VERDICT: PASS\n'
    printf 'VERDICT: SKIPPED\n'
  elif [[ -n "${NEEDS_KIMI:-}" ]]; then
    printf 'VERDICT: NEEDS REVISION\n'
  else
    printf '\033[32m  VERDICT: PASS\033[0m\n'
  fi
  [[ -z "${TRAILING_KIMI:-}" ]] || printf 'trailing Kimi text\n'
  [[ -n "${NO_KIMI_RESUME_HINT:-}" ]] ||
    printf 'To resume this session: kimi -r session_fake_review_id\n' >&2
fi
EOF
chmod +x "$tmp/home/.kimi-code/bin/kimi"

cat > "$tmp/relative-bin/kimi" <<'EOF'
#!/usr/bin/env bash
: > "$RELATIVE_KIMI_MARKER"
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
exec "$script_dir/../home/.kimi-code/bin/kimi" "$@"
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
    CLAUDE_LOG="$tmp/claude.log" KIMI_LOG="$kimi_test_runtime/kimi.log"
    BUNDLE_CAPTURE="$kimi_test_runtime/bundles"
    RELATIVE_KIMI_MARKER="$kimi_test_runtime/relative-kimi.started"
    LIVE_REPO="$live_repo"
    CLAUDE_STARTED="$tmp/claude.started" KIMI_STARTED="$kimi_test_runtime/kimi.started"
    KIMI_HANG_MARKER="$kimi_test_runtime/kimi.hang" KIMI_LEAK_MARKER="$kimi_test_runtime/kimi.leak"
    CONCURRENT_COMMIT_DONE="$tmp/concurrent-commit.done"
  )
  [[ -z "${GATED_KIMI_REVIEW_RUNNER:-}" ]] ||
    review_env+=(GATED_KIMI_REVIEW_RUNNER="$GATED_KIMI_REVIEW_RUNNER")
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
      PROTECTED_STATE_FILE="$tmp/home/.cache/gated-development-skills/kimi-review-state/protected"
      PROTECTED_STATE_WRITE="$tmp/home/.cache/gated-development-skills/kimi-review-state/write-probe"
      PROTECTED_GATE_WRITE="$tmp/home/.codex/skills/claude-gated-development/write-probe"
      UNRELATED_WRITE="$tmp/unrelated-write"
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
  rm -f "$tmp/claude.started" "$kimi_test_runtime/kimi.started"
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

kimi_session_hash_for() {
  local repo_root source_home task_key="$2"
  repo_root="$(cd "$1" && pwd -P)"
  source_home="$(cd "$tmp/home/.kimi-code" && pwd -P)"
  printf '%s\0%s\0%s' "$repo_root" "$task_key" "$source_home" |
    git -C "$1" hash-object --stdin
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
if (cd "$repo_a" && EXPECT_KIMI_START=0 run_review "$repo_a" kimi-setup-failure); then
  unset FAIL_KIMI_SETUP
  fail 'selected Kimi setup failure did not block the gate'
fi
unset FAIL_KIMI_SETUP
[[ "$(wc -l < "$tmp/claude.log")" -eq 1 ]] || fail 'Claude did not run concurrently with the failing Kimi setup'
[[ ! -s "$tmp/kimi.log" ]] || fail 'Kimi started after its snapshot setup failed'
: > "$tmp/claude.log"
: > "$tmp/kimi.log"

if [[ "$(uname -s)" == "Linux" ]]; then
  if (cd "$repo_a" && EXPECT_KIMI_START=0 run_review "$repo_a" bwrap-probe-failure failing-bwrap); then
    fail 'selected Kimi sandbox failure did not block the gate'
  fi
  [[ "$(wc -l < "$tmp/claude.log")" -eq 1 ]] || fail 'Claude did not run concurrently with the Bubblewrap failure'
  [[ ! -s "$tmp/kimi.log" ]] || fail 'Kimi started after Bubblewrap probe failure'
  grep -Fq 'selected Kimi sandbox probe failed' "$tmp/review.stderr" || fail 'Bubblewrap probe failure was omitted'
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
[[ "$(sed -n '2p' "$tmp/kimi.log")" == *--session*session_fake_review_id* ]] || fail 'second Kimi review did not resume its session'
[[ "$(sed -n '2p' "$tmp/kimi.log")" != *--continue* ]] || fail 'Kimi review used unsafe implicit continuation'
[[ "$(sed -n '1p' "$tmp/claude.log")" == *--allowedTools*Agent* ]] || fail 'Claude reviewer lost its own subagent tool'
[[ "$(sed -n '1p' "$tmp/claude.log")" == *codex-gated-development* ]] || fail 'Claude reviewer gate skill was not denied'
kimi_task_a_cwd="$(sed -n '1s/^CALL\tcwd=\([^[:space:]]*\).*/\1/p' "$tmp/kimi.log")"
[[ -n "$kimi_task_a_cwd" && "$(sed -n '2p' "$tmp/kimi.log")" == *"cwd=$kimi_task_a_cwd"* ]] || fail 'Kimi session did not reuse its stable snapshot workspace'
[[ "$kimi_task_a_cwd" != "$repo_a" ]] || fail 'Kimi reviewed the live worktree'
[[ ! -e "$kimi_task_a_cwd/repo" && ! -e "$kimi_task_a_cwd/review-scope.txt" ]] || fail 'persistent Kimi workspace retained a repository snapshot'
grep -Fq '[Kimi] STARTED' "$tmp/review.stderr" || fail 'Kimi start status was omitted'
grep -Fq '[Kimi] ACTIVE' "$tmp/review.stderr" || fail 'Kimi native progress was not forwarded'
grep -Fq '[Kimi] COMPLETED' "$tmp/review.stderr" || fail 'Kimi completion status was omitted'

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
[[ ! -e "$tmp/unrelated-write" ]] || fail 'Kimi wrote an unrelated host file'
sandbox_calls_before="$(wc -l < "$tmp/kimi.log")"
(cd "$repo_external_git" && run_review "$repo_external_git" external-git-sandbox-probe sandbox)
[[ "$(wc -l < "$tmp/kimi.log")" -eq "$((sandbox_calls_before + 1))" ]] || fail 'Kimi separate-Git-dir sandbox probe did not complete'
[[ ! -e "$repo_external_git/.sandbox-write" ]] || fail 'Kimi wrote a separate-Git-dir worktree file'
[[ ! -e "$external_git/sandbox-write" ]] || fail 'Kimi wrote separate Git state'

rm -f "$kimi_test_runtime/relative-kimi.started"
(cd "$repo_a" && run_review "$repo_a" relative-path relative-path)
[[ -e "$tmp/relative-kimi.started" ]] || fail 'relative PATH Kimi was not invoked'

FAIL_KIMI=1; export FAIL_KIMI
if (cd "$repo_a" && run_review "$repo_a" task-a); then
  unset FAIL_KIMI
  fail 'selected Kimi failure did not block the gate'
fi
unset FAIL_KIMI

# A selected Kimi is bounded by the shared runner and timeout is a gate failure.
rm -f "$kimi_test_runtime/kimi.hang"
task_a_kimi_hash="$(kimi_session_hash_for "$repo_a" task-a)"
task_a_kimi_session="$tmp/home/.cache/gated-development-skills/kimi-review-state/$task_a_kimi_hash/.session-id"
hang_start="$(date +%s)"
if (cd "$repo_a" && HANG_KIMI=1 KIMI_REVIEW_TIMEOUT_SECONDS=2 \
  KIMI_REVIEW_HEARTBEAT_SECONDS=1 run_review "$repo_a" task-a); then
  fail 'timed-out selected Kimi did not block the gate'
fi
hang_elapsed="$(( $(date +%s) - hang_start ))"
[[ -e "$tmp/kimi.hang" ]] || fail 'hang scenario never reached the fake Kimi'
[[ "$hang_elapsed" -lt 60 ]] || fail 'hung Kimi was not terminated within the timeout'
grep -Fq '[Kimi] IDLE' "$tmp/review.stderr" || fail 'Kimi heartbeat was omitted'
grep -Fq '[Kimi] TIMED_OUT' "$tmp/review.stderr" || fail 'Kimi timeout status was omitted'
[[ ! -s "$task_a_kimi_session" ]] || fail 'timed-out Kimi retained its stale session id'
(cd "$repo_a" && run_review "$repo_a" task-a) || fail 'round after Kimi timeout failed'
[[ "$(tail -n 1 "$tmp/kimi.log")" != *--session* ]] || fail 'round after Kimi timeout resumed the stale session'

# An interrupted wrapper terminates the reviewer process group instead of
# leaving an orphan running against the persistent session.
rm -f "$tmp/claude.hang"
(
  cd "$repo_a" && exec env -u CODEX_THREAD_ID -u CLAUDE_REVIEW_SESSION_KEY \
    HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    CLAUDE_LOG="$tmp/claude.log" KIMI_LOG="$kimi_test_runtime/kimi.log" \
    BUNDLE_CAPTURE="$kimi_test_runtime/bundles" \
    RELATIVE_KIMI_MARKER="$kimi_test_runtime/relative-kimi.started" \
    LIVE_REPO="$(git -C "$repo_a" rev-parse --show-toplevel)" \
    CLAUDE_STARTED="$tmp/claude.started" KIMI_STARTED="$kimi_test_runtime/kimi.started" \
    KIMI_HANG_MARKER="$kimi_test_runtime/kimi.hang" \
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

rm -f "$tmp/claude.started" "$kimi_test_runtime/kimi.started"
(cd "$repo_a" && env -u CODEX_THREAD_ID CLAUDE_REVIEW_SESSION_KEY=env-loser \
  HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  CLAUDE_LOG="$tmp/claude.log" KIMI_LOG="$kimi_test_runtime/kimi.log" \
  BUNDLE_CAPTURE="$kimi_test_runtime/bundles" \
  RELATIVE_KIMI_MARKER="$kimi_test_runtime/relative-kimi.started" \
  LIVE_REPO="$(git -C "$repo_a" rev-parse --show-toplevel)" \
  CLAUDE_STARTED="$tmp/claude.started" KIMI_STARTED="$kimi_test_runtime/kimi.started" \
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

NEEDS_CLAUDE=1; export NEEDS_CLAUDE
if (cd "$repo_a" && run_review "$repo_a" needs-claude-revision); then
  unset NEEDS_CLAUDE
  fail 'Claude NEEDS REVISION did not block the gate'
fi
unset NEEDS_CLAUDE

NEEDS_KIMI=1; export NEEDS_KIMI
if (cd "$repo_a" && run_review "$repo_a" needs-kimi-revision); then
  unset NEEDS_KIMI
  fail 'selected Kimi NEEDS REVISION did not block the gate'
fi
unset NEEDS_KIMI

if (cd "$repo_a" && TRAILING_CLAUDE=1 run_review "$repo_a" trailing-claude); then
  fail 'Claude PASS followed by trailing text did not block the gate'
fi
if (cd "$repo_a" && TRAILING_KIMI=1 run_review "$repo_a" trailing-kimi); then
  fail 'selected Kimi PASS followed by trailing text did not block the gate'
fi

if (cd "$repo_a" && NO_KIMI_LAST_MESSAGE=1 run_review "$repo_a" no-kimi-report); then
  unset NO_KIMI_LAST_MESSAGE
  fail 'empty selected Kimi report did not block the gate'
fi
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
grep -Fq 'NEW_PATCH_BODY' "$kimi_incremental" || fail 'Kimi incremental bundle omitted the new commit body'
! grep -Fq 'OLD_PATCH_BODY' "$kimi_incremental" || fail 'Kimi incremental bundle repeated an old patch body'
grep -Fq '## Full task summary' "$kimi_incremental" || fail 'Kimi incremental bundle omitted the full-task summary'

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

kimi_resume_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'KIMI_RESUME_FAILURE_BODY\n' > "$repo_incremental/kimi-resume-failure.txt"
git -C "$repo_incremental" add kimi-resume-failure.txt
git -C "$repo_incremental" commit -qm 'add Kimi resume failure fixture'
kimi_resume_hash="$(kimi_session_hash_for "$repo_incremental" incremental-task)"
kimi_resume_state="$tmp/home/.cache/gated-development-skills/kimi-review-state/$kimi_resume_hash"
kimi_checkpoint_before_resume_failure="$(cat "$kimi_resume_state/.adversarial.reviewed")"
FAIL_KIMI_RESUME=1; export FAIL_KIMI_RESUME
if (cd "$repo_incremental" && run_review "$repo_incremental" incremental-task "" \
  --base "$changed_base" --since "$kimi_resume_previous"); then
  unset FAIL_KIMI_RESUME
  fail 'failed Kimi resume did not block the gate'
fi
unset FAIL_KIMI_RESUME
[[ ! -s "$kimi_resume_state/.session-id" ]] || fail 'failed Kimi resume retained the stale session id'
[[ "$(cat "$kimi_resume_state/.adversarial.reviewed")" == "$kimi_checkpoint_before_resume_failure" ]] ||
  fail 'failed Kimi resume advanced its checkpoint'
(cd "$repo_incremental" && run_review "$repo_incremental" incremental-task "" \
  --base "$changed_base" --since "$kimi_resume_previous")
grep -Fq 'NEW_PATCH_BODY' "$(last_bundle kimi "$tmp/kimi.log")" ||
  fail 'round after failed Kimi resume did not fall back to the full task'

claude_fallback_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'CLAUDE_FALLBACK_BODY\n' > "$repo_incremental/claude-fallback.txt"
git -C "$repo_incremental" add claude-fallback.txt
git -C "$repo_incremental" commit -qm 'add Claude fallback fixture'
FAIL_RESUME_MARKER="$tmp/incremental-failed-resume"; export FAIL_RESUME_MARKER
(cd "$repo_incremental" && run_review "$repo_incremental" incremental-task "" \
  --base "$changed_base" --since "$claude_fallback_previous")
unset FAIL_RESUME_MARKER
grep -Fq 'NEW_PATCH_BODY' "$(last_bundle claude "$tmp/claude.log")" || fail 'fresh Claude fallback did not receive the full task'
grep -Fq 'CLAUDE_FALLBACK_BODY' "$(last_bundle kimi "$tmp/kimi.log")" || fail 'Kimi incremental review omitted the latest patch'
! grep -Fq 'NEW_PATCH_BODY' "$(last_bundle kimi "$tmp/kimi.log")" || fail 'independent Kimi session unnecessarily fell back to the full task'

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
if (cd "$repo_incremental" && run_review "$repo_incremental" "$skipped_key" "" \
  --base "$changed_base" --since "$skipped_previous"); then
  unset SKIP_KIMI EARLY_KIMI_PASS
  fail 'SKIPPED selected Kimi verdict did not block the gate'
fi
unset SKIP_KIMI EARLY_KIMI_PASS
[[ "$(cat "$skipped_checkpoint")" != "$checkpoint_before_skipped" ]] || fail 'Claude checkpoint did not record its completed review before Kimi failed'
! grep -Fq "ambiguous argument 'HEAD'" "$tmp/review.stderr" || fail 'unborn working-tree review emitted a raw HEAD error'

(cd "$repo_a" && run_review "$repo_a" resume-hint-optional)
(cd "$repo_a" && NO_KIMI_RESUME_HINT=1 run_review "$repo_a" resume-hint-optional) ||
  fail 'resumed Kimi session required a redundant resume hint'

concurrent_key='concurrent-mutation'
(cd "$repo_incremental" && run_review "$repo_incremental" "$concurrent_key" "" --base "$task_base")
concurrent_hash="$(kimi_session_hash_for "$repo_incremental" "$concurrent_key")"
kimi_state="$tmp/home/.cache/gated-development-skills/kimi-review-state/$concurrent_hash"
kimi_checkpoint="$kimi_state/.adversarial.reviewed"
kimi_session="$kimi_state/.session-id"
checkpoint_before_mutation="$(cat "$kimi_checkpoint")"
session_before_mutation="$(cat "$kimi_session")"
concurrent_previous="$(git -C "$repo_incremental" rev-parse HEAD)"
printf 'intended delta\n' > "$repo_incremental/intended-delta.txt"
git -C "$repo_incremental" add intended-delta.txt
git -C "$repo_incremental" commit -qm 'add intended delta'
rm -f "$tmp/concurrent-commit.done"
COMMIT_DURING_KIMI=1; export COMMIT_DURING_KIMI
if (cd "$repo_incremental" && run_review "$repo_incremental" "$concurrent_key" "" \
  --base "$task_base" --since "$concurrent_previous"); then
  unset COMMIT_DURING_KIMI
  fail 'repository mutation during Kimi review did not block the gate'
fi
unset COMMIT_DURING_KIMI
[[ "$(cat "$kimi_checkpoint")" == "$checkpoint_before_mutation" ]] ||
  fail 'Kimi checkpoint advanced after repository mutation'
[[ "$(cat "$kimi_session")" == "$session_before_mutation" ]] ||
  fail 'Kimi session advanced after repository mutation'

missing_hint_key='missing-first-resume-hint'
missing_hint_hash="$(kimi_session_hash_for "$repo_incremental" "$missing_hint_key")"
missing_hint_state="$tmp/home/.cache/gated-development-skills/kimi-review-state/$missing_hint_hash"
if (cd "$repo_incremental" && NO_KIMI_RESUME_HINT=1 \
  run_review "$repo_incremental" "$missing_hint_key" "" --base "$task_base"); then
  fail 'first Kimi session without a resume hint did not block the gate'
fi
[[ ! -e "$missing_hint_state/.session-id" ]] || fail 'missing resume hint persisted a Kimi session'
[[ ! -e "$missing_hint_state/.adversarial.reviewed" ]] || fail 'missing resume hint persisted a Kimi checkpoint'

quoted_session_key='quoted-session-evidence'
quoted_session_hash="$(kimi_session_hash_for "$repo_incremental" "$quoted_session_key")"
quoted_session_state="$tmp/home/.cache/gated-development-skills/kimi-review-state/$quoted_session_hash/.session-id"
(cd "$repo_incremental" && QUOTE_FALSE_SESSION=1 \
  run_review "$repo_incremental" "$quoted_session_key" "" --base "$task_base")
[[ "$(cat "$quoted_session_state")" == 'session_fake_review_id' ]] ||
  fail 'model-authored report text replaced the CLI resume session id'

session_dir_key='session-state-directory'
session_dir_hash="$(kimi_session_hash_for "$repo_incremental" "$session_dir_key")"
session_dir_state="$tmp/home/.cache/gated-development-skills/kimi-review-state/$session_dir_hash"
mkdir -p "$session_dir_state/.session-id"
if (cd "$repo_incremental" && run_review "$repo_incremental" "$session_dir_key" "" --base "$task_base"); then
  fail 'Kimi session-state directory collision did not fail the gate'
fi

checkpoint_dir_key='checkpoint-state-directory'
checkpoint_dir_hash="$(kimi_session_hash_for "$repo_incremental" "$checkpoint_dir_key")"
checkpoint_dir_state="$tmp/home/.cache/gated-development-skills/kimi-review-state/$checkpoint_dir_hash"
mkdir -p "$checkpoint_dir_state/.adversarial.reviewed"
if (cd "$repo_incremental" && run_review "$repo_incremental" "$checkpoint_dir_key" "" --base "$task_base"); then
  fail 'Kimi checkpoint directory collision did not fail the gate'
fi

rm -f "$kimi_test_runtime/kimi.hang"
set -m
(cd "$repo_a" && HANG_KIMI=1 KIMI_REVIEW_TIMEOUT_SECONDS=30 \
  run_review "$repo_a" shared-lock) &
locking_runner_pid=$!
set +m
for _ in {1..100}; do
  [[ -e "$tmp/kimi.hang" ]] && break
  sleep 0.05
done
[[ -e "$tmp/kimi.hang" ]] || fail 'shared-lock fixture never reached Kimi'
shared_lock_hash="$(kimi_session_hash_for "$repo_a" shared-lock)"
shared_lock_path="$tmp/home/.cache/gated-development-skills/kimi-review-state/$shared_lock_hash.lock"
if env HOME="$tmp/home" PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$shared_runner" --repo "$repo_a" --mode adversarial \
  --full-bundle "$(last_bundle claude "$tmp/claude.log")" --focus test \
  --risk concurrency --session-key shared-lock >/dev/null 2>>"$tmp/review.stderr"; then
  fail 'overlapping selected Kimi review acquired the same session lock'
fi
[[ -d "$shared_lock_path" ]] || fail 'overlapping Kimi review removed the active lock'
kill -TERM -- "-$locking_runner_pid" 2>/dev/null || true
if wait "$locking_runner_pid" 2>/dev/null; then
  fail 'interrupted shared-lock fixture unexpectedly passed'
fi
for _ in {1..50}; do
  [[ ! -e "$shared_lock_path" ]] && break
  sleep 0.1
done
[[ ! -e "$shared_lock_path" ]] || fail 'completed Kimi review left its session lock behind'

rm -f "$kimi_test_runtime/kimi.leak"
if (cd "$repo_a" && LEAK_KIMI_STDERR=1 KIMI_REVIEW_TIMEOUT_SECONDS=2 \
  run_review "$repo_a" leaked-kimi-child); then
  fail 'Kimi descendant holding stderr open did not block the gate'
fi
[[ -s "$tmp/kimi.leak" ]] || fail 'Kimi descendant fixture did not start'
! kill -0 "$(cat "$tmp/kimi.leak")" 2>/dev/null || fail 'Kimi descendant survived process-group timeout'

alt_kimi_home="$tmp/alt-kimi-home"
mkdir -p "$alt_kimi_home"
alt_kimi_home="$(cd "$alt_kimi_home" && pwd -P)"
alt_kimi_source_hash="$(printf '%s' "$alt_kimi_home" | git hash-object --stdin)"
alt_kimi_runtime="$tmp/home/.cache/gated-development-skills/kimi-review-runtime/$alt_kimi_source_hash"
mkdir -p "$alt_kimi_runtime/bundles"
: > "$alt_kimi_runtime/kimi.log"
: > "$tmp/claude.started"
env HOME="$tmp/home" KIMI_CODE_HOME="$alt_kimi_home" \
  PATH="$tmp/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  KIMI_LOG="$alt_kimi_runtime/kimi.log" BUNDLE_CAPTURE="$alt_kimi_runtime/bundles" \
  LIVE_REPO="$(cd "$repo_a" && pwd -P)" CLAUDE_STARTED="$tmp/claude.started" \
  KIMI_STARTED="$alt_kimi_runtime/kimi.started" \
  "$shared_runner" --repo "$repo_a" --mode adversarial \
  --full-bundle "$(last_bundle claude "$tmp/claude.log")" --focus test \
  --risk concurrency --risk idempotency --risk database-transactions \
  --session-key profile-isolation >/dev/null 2>>"$tmp/review.stderr"
alt_profile_state="$(printf '%s\0%s\0%s' "$(cd "$repo_a" && pwd -P)" profile-isolation "$alt_kimi_home" |
  git -C "$repo_a" hash-object --stdin)"
default_profile_state="$(kimi_session_hash_for "$repo_a" profile-isolation)"
[[ -s "$tmp/home/.cache/gated-development-skills/kimi-review-state/$alt_profile_state/.session-id" ]] ||
  fail 'alternate KIMI_CODE_HOME did not receive independent Kimi state'
[[ ! -e "$tmp/home/.cache/gated-development-skills/kimi-review-state/$default_profile_state" ]] ||
  fail 'alternate KIMI_CODE_HOME reused the default profile state'

copied_wrapper="$tmp/fake-home/.codex/skills/claude-gated-development/scripts/claude-review.sh"
mkdir -p "$(dirname "$copied_wrapper")"
cp "$runner" "$copied_wrapper"
chmod +x "$copied_wrapper"
original_runner="$runner"
runner="$copied_wrapper"
(cd "$repo_a" && GATED_KIMI_REVIEW_RUNNER="$shared_runner" \
  run_review "$repo_a" override-runner) || fail 'GATED_KIMI_REVIEW_RUNNER override was not executable outside the source tree'
installed_data="$tmp/xdg-data/gated-development-skills"
mkdir -p "$installed_data" "$tmp/fake-home/shared/scripts"
cp "$shared_runner" "$installed_data/kimi-review.sh"
cp /usr/bin/false "$tmp/fake-home/shared/scripts/kimi-review.sh"
chmod +x "$installed_data/kimi-review.sh" "$tmp/fake-home/shared/scripts/kimi-review.sh"
(cd "$repo_a" && XDG_DATA_HOME="$tmp/xdg-data" \
  run_review "$repo_a" installed-runner) || fail 'installed shared Kimi runner was not found outside the source tree'
runner="$original_runner"

printf 'mandatory Claude and conditionally mandatory Kimi review checks passed\n'
