#!/usr/bin/env bash
set -euo pipefail
umask 077

usage() {
  cat <<'EOF'
Usage:
  kimi-review.sh --repo PATH --mode adversarial|code --full-bundle FILE \
    [--base OID --head OID] [--since OID --incremental-bundle FILE] \
    --focus TEXT --risk RISK... [--session-key KEY]

Run one selected Kimi review against a detached repository snapshot. Progress
is written to stderr, the final report to stdout, and exit status is zero only
for VERDICT: PASS. --head is required whenever --base or --since is used.
EOF
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit "${2:-2}"
}

repo=""
mode=""
full_bundle=""
incremental_bundle=""
base_oid=""
since_oid=""
head_oid=""
focus=""
session_key=""
risks=()

while (($#)); do
  case "$1" in
    --repo|--mode|--full-bundle|--incremental-bundle|--base|--since|--head|--focus|--risk|--session-key)
      (($# >= 2)) || die "$1 requires a value"
      case "$1" in
        --repo) repo="$2" ;;
        --mode) mode="$2" ;;
        --full-bundle) full_bundle="$2" ;;
        --incremental-bundle) incremental_bundle="$2" ;;
        --base) base_oid="$2" ;;
        --since) since_oid="$2" ;;
        --head) head_oid="$2" ;;
        --focus) focus="$2" ;;
        --risk) risks+=("$2") ;;
        --session-key) session_key="$2" ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

command -v git >/dev/null 2>&1 || die "git is not installed"
[[ -n "$repo" ]] || die "--repo is required"
[[ -n "$full_bundle" && -f "$full_bundle" ]] || die "--full-bundle must name a readable file"
case "$mode" in
  adversarial|code) ;;
  *) die "--mode must be adversarial or code" ;;
esac
if [[ -n "$since_oid" ]]; then
  [[ -n "$base_oid" && -n "$head_oid" ]] || die "--since requires --base and --head"
  [[ -n "$incremental_bundle" && -f "$incremental_bundle" ]] ||
    die "--since requires --incremental-bundle"
fi
[[ -z "$base_oid" || -n "$head_oid" ]] || die "--base requires --head"
((${#risks[@]})) || die "at least one --risk is required"
for risk in "${risks[@]}"; do
  case "$risk" in
    concurrency|idempotency|database-transactions|tenant-isolation|distributed-state) ;;
    *) die "unsupported Kimi risk: $risk" ;;
  esac
done

repo_root="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)" || die "--repo is not a Git worktree"
repo_root="$(cd "$repo_root" && pwd -P)"
git_common_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir)"
git_common_dir="$(cd "$git_common_dir" && pwd -P)"
git_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-dir)"
git_dir="$(cd "$git_dir" && pwd -P)"

kimi_bin="$(command -v kimi 2>/dev/null || true)"
[[ -n "$kimi_bin" ]] || kimi_bin="${HOME:-}/.kimi-code/bin/kimi"
if [[ "$kimi_bin" != /* ]]; then
  kimi_bin="$(cd "$(dirname "$kimi_bin")" && pwd -P)/$(basename "$kimi_bin")"
fi
[[ -x "$kimi_bin" ]] || die "selected Kimi review cannot run: kimi CLI is not installed" 12

sandbox_kind=""
sandbox_bin=""
case "$(uname -s 2>/dev/null || true)" in
  Darwin) sandbox_kind="sandbox-exec" ;;
  Linux) sandbox_kind="bwrap" ;;
  *) die "selected Kimi review cannot run: unsupported platform" 12 ;;
esac
sandbox_bin="/usr/bin/$sandbox_kind"
if [[ ! -x "$sandbox_bin" ]]; then
  sandbox_bin="$(command -v "$sandbox_kind" 2>/dev/null || true)"
  if [[ -n "$sandbox_bin" && "$sandbox_bin" != /* ]]; then
    sandbox_bin="$(cd "$(dirname "$sandbox_bin")" && pwd -P)/$(basename "$sandbox_bin")"
  fi
fi
[[ -x "$sandbox_bin" ]] || die "selected Kimi review cannot run: native $sandbox_kind is missing" 12

timeout_seconds="${KIMI_REVIEW_TIMEOUT_SECONDS:-${KIMI_REVIEW_GRACE_SECONDS:-1800}}"
heartbeat_seconds="${KIMI_REVIEW_HEARTBEAT_SECONDS:-30}"
[[ "$timeout_seconds" =~ ^[1-9][0-9]*$ ]] || die "KIMI_REVIEW_TIMEOUT_SECONDS must be a positive integer"
[[ "$heartbeat_seconds" =~ ^[1-9][0-9]*$ ]] || die "KIMI_REVIEW_HEARTBEAT_SECONDS must be a positive integer"

review_tmp="$(mktemp -d "${TMPDIR:-/tmp}/kimi-review.XXXXXX")" || die "cannot create temporary directory"
kimi_pid=""
stderr_pid=""
lock_dir=""
kimi_repo=""
skills_dir=""
review_scope_file=""
cleanup() {
  if [[ -n "$kimi_pid" ]] && kill -0 -- "-$kimi_pid" 2>/dev/null; then
    kill -TERM -- "-$kimi_pid" 2>/dev/null || true
    sleep 1
    kill -KILL -- "-$kimi_pid" 2>/dev/null || true
  fi
  [[ -z "$stderr_pid" ]] || kill "$stderr_pid" 2>/dev/null || true
  [[ -z "$kimi_repo" ]] || rm -rf "$kimi_repo" "$skills_dir"
  [[ -z "$review_scope_file" ]] || rm -f "$review_scope_file"
  rm -rf "$review_tmp"
  [[ -z "$lock_dir" ]] || rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

session_file=""
reviewed_state_file=""
kimi_session_id=""
reviewed_base=""
reviewed_head=""
reviewed_session=""
cache_root="${XDG_CACHE_HOME:-${HOME:-}/.cache}/gated-development-skills"
workspace_parent="$cache_root/kimi-review-workspaces"
state_parent="$cache_root/kimi-review-state"
source_kimi_home="${KIMI_CODE_HOME:-${HOME:-}/.kimi-code}"
[[ -d "$source_kimi_home" ]] || die "Kimi data root is missing at $source_kimi_home" 12
source_kimi_home="$(cd "$source_kimi_home" && pwd -P)"
source_kimi_hash="$(printf '%s' "$source_kimi_home" | git hash-object --stdin)"
kimi_runtime="$cache_root/kimi-review-runtime/$source_kimi_hash"
mkdir -p "$state_parent" "$kimi_runtime" || die "cannot create Kimi state or runtime root" 5
state_parent="$(cd "$state_parent" && pwd -P)"
kimi_runtime="$(cd "$kimi_runtime" && pwd -P)"
chmod 700 "$kimi_runtime" || die "cannot protect Kimi runtime root at $kimi_runtime" 5

# KIMI_CODE_HOME gives the reviewer an isolated writable data root. Copy only
# authentication/config inputs; sessions, logs, and caches are reviewer-owned.
for config_file in config.toml device_id; do
  if [[ ! -e "$kimi_runtime/$config_file" && -f "$source_kimi_home/$config_file" ]]; then
    cp -p "$source_kimi_home/$config_file" "$kimi_runtime/$config_file" ||
      die "cannot initialize Kimi runtime $config_file" 5
  fi
done
for config_dir in credentials oauth; do
  if [[ ! -e "$kimi_runtime/$config_dir" && -d "$source_kimi_home/$config_dir" ]]; then
    mkdir -p "$kimi_runtime/$config_dir"
    cp -pR "$source_kimi_home/$config_dir/." "$kimi_runtime/$config_dir" ||
      die "cannot initialize Kimi runtime $config_dir" 5
  fi
done
mkdir -p "$kimi_runtime/home" "$kimi_runtime/tmp"
if [[ -n "$session_key" ]]; then
  mkdir -p "$workspace_parent" || die "cannot create Kimi workspace root at $workspace_parent" 5
  workspace_parent="$(cd "$workspace_parent" && pwd -P)"
  session_hash="$(printf '%s\0%s\0%s' "$repo_root" "$session_key" "$source_kimi_home" | git hash-object --stdin)"
  workspace="$workspace_parent/$session_hash"
  state_dir="$state_parent/$session_hash"
  pending_lock="$state_dir.lock"
  if ! mkdir "$pending_lock" 2>/dev/null; then
    die "another Kimi review round holds $pending_lock; remove it manually only if no round is running" 7
  fi
  lock_dir="$pending_lock"
  mkdir -p "$workspace" "$state_dir" || die "cannot create Kimi workspace or state directory" 5
  session_file="$state_dir/.session-id"
  reviewed_state_file="$state_dir/.$mode.reviewed"
  if [[ -s "$session_file" ]]; then
    IFS= read -r kimi_session_id < "$session_file" || true
    [[ "$kimi_session_id" =~ ^session_[A-Za-z0-9_-]+$ ]] || kimi_session_id=""
  fi
  if [[ -s "$reviewed_state_file" ]]; then
    read -r reviewed_base reviewed_head reviewed_session < "$reviewed_state_file" || true
    if [[ -z "$reviewed_session" ]] ||
       ! git -C "$repo_root" rev-parse --verify "${reviewed_head}^{commit}" >/dev/null 2>&1; then
      reviewed_base=""
      reviewed_head=""
      reviewed_session=""
    fi
  fi
else
  workspace="$review_tmp/workspace"
  mkdir -p "$workspace"
fi
workspace="$(cd "$workspace" && pwd -P)"
for protected_path in "$repo_root" "$git_common_dir" "$git_dir"; do
  if [[ "$workspace" == "$protected_path" || "$workspace" == "$protected_path/"* ]]; then
    die "Kimi workspace must be outside the live repository and Git directories"
  fi
done

incremental_active=0
if [[ -n "$since_oid" ]]; then
  if [[ -n "$kimi_session_id" && "$reviewed_base" == "$base_oid" &&
        "$reviewed_session" == "$kimi_session_id" ]] &&
     git -C "$repo_root" merge-base --is-ancestor "$since_oid" "$reviewed_head" &&
     git -C "$repo_root" merge-base --is-ancestor "$reviewed_head" "$head_oid"; then
    incremental_active=1
  else
    printf '[Kimi] checkpoint unavailable or mismatched; reviewing the full task\n' >&2
  fi
fi

review_bundle="$full_bundle"
scope_kind="full"
if [[ "$incremental_active" -eq 1 ]]; then
  review_bundle="$incremental_bundle"
  scope_kind="incremental"
fi

sandbox_profile="$review_tmp/kimi.sb"
sandbox_args=()
read_masks=()
add_read_mask() {
  local candidate="$1" mask
  candidate="$(cd "$candidate" && pwd -P)"
  for mask in "${read_masks[@]+"${read_masks[@]}"}"; do
    if [[ "$candidate" == "$mask" || "$candidate" == "$mask/"* ]]; then
      return
    fi
  done
  read_masks+=("$candidate")
}
add_read_mask "$repo_root"
add_read_mask "$git_common_dir"
add_read_mask "$git_dir"
add_read_mask "$state_parent"
write_allows=("$workspace" "$kimi_runtime")
sandbox_path() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || return 1
  value="${value//\\/\\\\}"
  printf '%s' "${value//\"/\\\"}"
}
prepare_sandbox() {
  local mask probe_file="$kimi_runtime/tmp/sandbox-probe.$$" sandbox_error sandbox_mask
  if [[ "$sandbox_kind" == "sandbox-exec" ]]; then
    : > "$sandbox_profile" || return 1
    printf '(version 1)\n(allow default)\n(deny file-write*)\n' >> "$sandbox_profile" || return 1
    printf '(allow file-write* (literal "/dev/null") (literal "/dev/zero") (literal "/dev/tty") (subpath "/dev/fd"))\n' >> "$sandbox_profile" || return 1
    for mask in "${write_allows[@]}"; do
      sandbox_mask="$(sandbox_path "$mask")" || return 1
      printf '(allow file-write* (subpath "%s"))\n' "$sandbox_mask" >> "$sandbox_profile" || return 1
    done
    for mask in "${read_masks[@]}"; do
      sandbox_mask="$(sandbox_path "$mask")" || return 1
      printf '(deny file-read* (subpath "%s"))\n' "$sandbox_mask" >> "$sandbox_profile" || return 1
    done
    sandbox_args=(-f "$sandbox_profile")
  else
    # The host is read-only; only disposable review data and Kimi's isolated
    # runtime are writable. Live repository and gate state are hidden as well.
    sandbox_args=(--die-with-parent --new-session --unshare-pid --ro-bind / / --dev /dev --proc /proc)
    for mask in "${read_masks[@]}"; do
      sandbox_args+=(--tmpfs "$mask" --remount-ro "$mask")
    done
    for mask in "${write_allows[@]}"; do
      sandbox_args+=(--bind "$mask" "$mask")
    done
    sandbox_args+=(--)
  fi
  if ! sandbox_error="$(HOME="$kimi_runtime/home" TMPDIR="$kimi_runtime/tmp" \
    "$sandbox_bin" "${sandbox_args[@]}" /bin/sh -c \
    ': > /dev/null && : > "$1" && rm -f "$1"' sh "$probe_file" 2>&1 >/dev/null)"; then
    printf 'Error: selected Kimi sandbox probe failed: %s\n' "$sandbox_error" >&2
    return 1
  fi
}
prepare_sandbox || exit 12

repo_fingerprint() {
  local file_mode path
  {
    git -C "$repo_root" rev-parse HEAD 2>/dev/null || printf 'unborn HEAD\n'
    git -C "$repo_root" status --porcelain=v1 -z --untracked-files=all
    git -C "$repo_root" diff --binary
    git -C "$repo_root" diff --cached --binary
    while IFS= read -r -d '' path; do
      printf 'untracked:%s\0' "$path"
      git -C "$repo_root" hash-object -- "$path" || true
      file_mode="$(stat -c '%a' "$repo_root/$path" 2>/dev/null || stat -f '%Lp' "$repo_root/$path" 2>/dev/null || true)"
      printf 'mode:%s\0' "$file_mode"
    done < <(git -C "$repo_root" ls-files --others --exclude-standard -z)
  } | git hash-object --stdin
}

if [[ -n "$head_oid" ]]; then
  current_head="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"
  [[ "$current_head" == "$head_oid" ]] || die "repository HEAD no longer matches --head" 9
fi
start_fingerprint="$(repo_fingerprint)"
printf '[Kimi] PREPARING snapshot\n' >&2

kimi_repo="$workspace/repo"
skills_dir="$workspace/skills"
review_scope_file="$workspace/review-scope.txt"
snapshot_paths="$review_tmp/snapshot-paths"
rm -rf "$kimi_repo" "$skills_dir"
mkdir -p "$kimi_repo" "$skills_dir"
git -C "$repo_root" ls-files --cached --others --exclude-standard -z > "$snapshot_paths"
while IFS= read -r -d '' path; do
  [[ -e "$repo_root/$path" || -L "$repo_root/$path" ]] || continue
  mkdir -p "$kimi_repo/$(dirname "$path")"
  if [[ -L "$repo_root/$path" ]]; then
    printf 'symlink\n' > "$kimi_repo/$path"
  elif [[ -d "$repo_root/$path" ]]; then
    mkdir -p "$kimi_repo/$path"
    printf 'gitlink\n' > "$kimi_repo/$path/.gitlink"
  else
    cp -p -- "$repo_root/$path" "$kimi_repo/$path"
  fi
done < "$snapshot_paths"
while IFS= read -r line || [[ -n "$line" ]]; do
  printf '%s\n' "${line//$repo_root/$kimi_repo}"
done < "$review_bundle" > "$review_scope_file"
[[ "$(repo_fingerprint)" == "$start_fingerprint" ]] ||
  die "repository changed while the Kimi snapshot was prepared" 9

printf -v risk_list '%s, ' "${risks[@]}"
risk_list="${risk_list%, }"
if [[ "$mode" == "adversarial" ]]; then
  lens="Question the approach itself, not only line-level defects. Check whether the artifact solves the right problem, fits repository constraints, covers failure modes, and avoids unjustified complexity."
else
  lens="Review the code as a strict defect finder. Prioritize reproducible correctness, security, data-loss, concurrency, and material performance problems. Exclude pure style and optional refactors."
fi
if [[ "$incremental_active" -eq 1 ]]; then
  scope="Review the committed delta ${since_oid}...${head_oid} as the primary patch. Use prior-session findings for continuity and inspect affected final files, callers, and tests when needed. The complete task ${base_oid}...${head_oid} is included only as a stat and name-status summary."
elif [[ -n "$base_oid" ]]; then
  scope="Review the complete task state: git diff ${base_oid}...${head_oid}, the staged diff, the unstaged diff, and every relevant untracked file. Do not review only the last commit or current hunk."
else
  scope="Review the complete working tree: status, staged diff, unstaged diff, and every relevant untracked file."
fi
kimi_scope="${scope//$repo_root/$kimi_repo}"
kimi_focus="${focus//$repo_root/$kimi_repo}"
IFS= read -r -d '' prompt <<EOF || true
You are a selected specialist reviewer in a gated development workflow. This is review-only: do not edit, write, delete, commit, or otherwise mutate repository files or state. You may use built-in Agent and AgentSwarm subagents. Do not invoke external reviewers or review-gate workflows, including Claude Code, Codex, CodeSearch, external model CLIs, or gate skills.

Repository snapshot: $kimi_repo
Review mode: $mode
Scope contract: $kimi_scope
Precomputed review bundle: $review_scope_file
Kimi risk classes: $risk_list
Review focus: $kimi_focus
Review lens: $lens

Read the precomputed review bundle first, then inspect applicable CLAUDE.md and AGENTS.md guidance and the named repository snapshot files. Verify that the review scope is non-empty and contains the artifact's actual substance; do not rely on a prompt summary when the code or document is available.

Return:
1. Scope examined: exact refs, diffs, and files reviewed.
2. Blocking findings: only reproducible material defects within the requested Kimi risk classes. Give priority, file:line, evidence, impact, and the smallest sound remedy.
3. Residual findings: optional style, alternative designs, or speculative hardening, clearly separated.
4. Verdict: PASS only when there is no valid unaddressed blocking finding; otherwise NEEDS REVISION.

End with exactly one machine-readable line: VERDICT: PASS, VERDICT: NEEDS REVISION, or VERDICT: SKIPPED.

If the target is empty or you cannot inspect the required scope, return SKIPPED rather than PASS.

This conversation may include earlier review rounds from the same task. Use that context for continuity, but treat this invocation's review bundle and repository snapshot files as authoritative.
EOF

report_file="$review_tmp/report.txt"
events_file="$review_tmp/events.txt"
last_activity_file="$review_tmp/last-activity"
stderr_pipe="$review_tmp/stderr.pipe"
: > "$events_file"
mkfifo "$stderr_pipe"
start_time="$(date +%s)"
printf '%s\n' "$start_time" > "$last_activity_file"
forward_stderr() {
  local line now
  while IFS= read -r line || [[ -n "$line" ]]; do
    now="$(date +%s)"
    printf '%s\n' "$now" > "$last_activity_file"
    printf '%s\n' "$line" >> "$events_file"
    printf '[Kimi] ACTIVE %s\n' "$line" >&2
  done
}
forward_stderr < "$stderr_pipe" &
stderr_pid=$!

kimi_args=(--skills-dir "$skills_dir" --output-format text -p "$prompt")
if [[ -n "$kimi_session_id" ]]; then
  kimi_args=(--session "$kimi_session_id" "${kimi_args[@]}")
fi
kimi_env=(env -u OLDPWD)
while IFS= read -r name; do
  [[ "$name" == GIT_* ]] && kimi_env+=(-u "$name")
done < <(compgen -e)
kimi_env+=(
  HOME="$kimi_runtime/home"
  KIMI_CODE_HOME="$kimi_runtime"
  KIMI_DISABLE_TELEMETRY=1
  TMPDIR="$kimi_runtime/tmp"
  XDG_CACHE_HOME="$kimi_runtime/xdg-cache"
  XDG_CONFIG_HOME="$kimi_runtime/xdg-config"
  XDG_DATA_HOME="$kimi_runtime/xdg-data"
  XDG_STATE_HOME="$kimi_runtime/xdg-state"
)

printf '[Kimi] STARTED mode=%s scope=%s timeout=%ss\n' "$mode" "$scope_kind" "$timeout_seconds" >&2
set +e
set -m
(
  cd "$workspace"
  "${kimi_env[@]}" "$sandbox_bin" "${sandbox_args[@]}" "$kimi_bin" "${kimi_args[@]}" < /dev/null
) > "$report_file" 2> "$stderr_pipe" &
kimi_pid=$!
set +m
timed_out=0
next_heartbeat=$((start_time + heartbeat_seconds))
while kill -0 -- "-$kimi_pid" 2>/dev/null; do
  now="$(date +%s)"
  if ((now >= next_heartbeat)); then
    last_activity="$(cat "$last_activity_file" 2>/dev/null || printf '%s' "$start_time")"
    idle_for=$((now - last_activity))
    state="ACTIVE"
    ((idle_for < heartbeat_seconds)) || state="IDLE"
    printf '[Kimi] %s elapsed=%ss last_activity=%ss process=alive\n' \
      "$state" "$((now - start_time))" "$idle_for" >&2
    next_heartbeat=$((now + heartbeat_seconds))
  fi
  if ((now - start_time >= timeout_seconds)); then
    timed_out=1
    kill -TERM -- "-$kimi_pid" 2>/dev/null
    sleep 2
    kill -KILL -- "-$kimi_pid" 2>/dev/null
    break
  fi
  sleep 1
done
wait "$kimi_pid"
kimi_status=$?
kimi_pid=""
for _ in {1..50}; do
  kill -0 "$stderr_pid" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$stderr_pid" 2>/dev/null; then
  kill "$stderr_pid" 2>/dev/null
fi
wait "$stderr_pid" 2>/dev/null
stderr_pid=""
set -e
cat "$report_file"

if [[ "$timed_out" -eq 1 ]]; then
  if [[ -n "$kimi_session_id" && -n "$session_file" ]]; then
    : > "$session_file" || die "could not clear timed-out Kimi session state" 5
  fi
  printf '[Kimi] TIMED_OUT after %ss\n' "$timeout_seconds" >&2
  exit 124
fi
if [[ "$kimi_status" -ne 0 ]]; then
  if [[ -n "$kimi_session_id" && -n "$session_file" ]]; then
    : > "$session_file" || die "could not clear stale Kimi session state" 5
  fi
  printf '[Kimi] FAILED process_exit=%s\n' "$kimi_status" >&2
  exit "$kimi_status"
fi
if ! grep -q '[^[:space:]]' "$report_file"; then
  printf '[Kimi] FAILED empty report\n' >&2
  exit 6
fi

last_verdict="$({
  LC_ALL=C sed $'s/\033\\[[0-9;]*[[:alpha:]]//g' "$report_file" |
    tr -d '\r*`' |
    awk 'NF { line=$0 } END { print line }'
} || true)"
verdict=""
if printf '%s\n' "$last_verdict" | LC_ALL=C grep -Eq \
  '^[^[:alnum:]]*VERDICT[[:space:]]*:[[:space:]]*PASS[^[:alnum:]]*$'; then
  verdict="PASS"
elif printf '%s\n' "$last_verdict" | LC_ALL=C grep -Eq \
  '^[^[:alnum:]]*VERDICT[[:space:]]*:[[:space:]]*NEEDS REVISION[^[:alnum:]]*$'; then
  verdict="NEEDS REVISION"
else
  printf '[Kimi] FAILED final nonempty line is not a valid verdict\n' >&2
  exit 6
fi

if [[ "$(repo_fingerprint)" != "$start_fingerprint" ]]; then
  printf '[Kimi] FAILED repository changed during review; session and checkpoint were not advanced\n' >&2
  exit 9
fi

if [[ -n "$session_file" ]]; then
  parsed_session_id="$(
    sed -n 's/^[[:space:]]*To resume this session: kimi -r \(session_[A-Za-z0-9_-][A-Za-z0-9_-]*\)[[:space:]]*$/\1/p' \
      "$events_file" | tail -n 1
  )"
  if [[ -z "$parsed_session_id" ]]; then
    if [[ -n "$kimi_session_id" ]]; then
      parsed_session_id="$kimi_session_id"
    else
      printf '[Kimi] FAILED no valid resume hint\n' >&2
      exit 6
    fi
  fi
  state_tmp="$session_file.tmp.$$"
  if [[ -d "$session_file" ]] ||
     ! printf '%s\n' "$parsed_session_id" > "$state_tmp" ||
     ! mv -- "$state_tmp" "$session_file"; then
    die "could not save Kimi session state at $session_file" 5
  fi
  kimi_session_id="$parsed_session_id"
fi

status="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
if [[ -n "$reviewed_state_file" && -n "$base_oid" && -n "$head_oid" && -z "$status" ]]; then
  state_tmp="$reviewed_state_file.tmp.$$"
  if [[ -d "$reviewed_state_file" ]] ||
     ! printf '%s %s %s\n' "$base_oid" "$head_oid" "$kimi_session_id" > "$state_tmp" ||
     ! mv -- "$state_tmp" "$reviewed_state_file"; then
    die "could not save Kimi checkpoint at $reviewed_state_file" 5
  fi
fi

elapsed="$(($(date +%s) - start_time))"
printf '[Kimi] COMPLETED elapsed=%ss verdict=%s\n' "$elapsed" "$verdict" >&2
[[ "$verdict" == "PASS" ]] || exit 8
