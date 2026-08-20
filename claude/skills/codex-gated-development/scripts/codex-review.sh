#!/usr/bin/env bash
set -euo pipefail
# Everything this wrapper writes (session state, review bundle, reviewer
# reports) is private to the user; children inherit the restrictive mask.
umask 077

usage() {
  cat <<'EOF'
Usage:
  codex-review.sh adversarial [--base REF] [--since REF] [--focus TEXT] [--session-key KEY]
  codex-review.sh code [--base REF] [--since REF] [--focus TEXT] [--session-key KEY]

Without --base, review staged, unstaged, and untracked working-tree changes.
With --base, review REF...HEAD plus current working-tree changes.
With --base and --since, review only committed changes since REF when the same
review mode has a verified persistent checkpoint produced by the same Codex
session; otherwise review the full task. Incremental review requires a clean
working tree.

Session continuity: with --session-key (or CODEX_REVIEW_SESSION_KEY, or
CLAUDE_CODE_SESSION_ID), one persistent Codex session per (repository, key) is
reused across review rounds; distinct tasks must use distinct keys. Without
any key the review runs without reusable continuity.
EOF
}

die_usage() {
  printf 'Error: %s\n' "$1" >&2
  usage >&2
  exit 2
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

mode="${1:-}"
case "$mode" in
  adversarial|code) shift ;;
  "") die_usage "review mode is required" ;;
  *) die_usage "unknown review mode: $mode" ;;
esac

base=""
since=""
focus=""
session_key_arg=""
while (($#)); do
  case "$1" in
    --base)
      (($# >= 2)) || die_usage "--base requires a ref"
      [[ -n "$2" ]] || die_usage "--base requires a non-empty ref"
      base="$2"
      shift 2
      ;;
    --focus)
      (($# >= 2)) || die_usage "--focus requires text"
      focus="$2"
      shift 2
      ;;
    --since)
      (($# >= 2)) || die_usage "--since requires a ref"
      [[ -n "$2" ]] || die_usage "--since requires a non-empty ref"
      since="$2"
      shift 2
      ;;
    --session-key)
      (($# >= 2)) || die_usage "--session-key requires a value"
      [[ -n "$2" ]] || die_usage "--session-key requires a non-empty value"
      session_key_arg="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

command -v git >/dev/null 2>&1 || die_usage "git is not installed"
codex_bin="$(command -v codex 2>/dev/null)" || die_usage "codex CLI is not installed"
if [[ "$codex_bin" == /* ]]; then
  export PATH="$(dirname "$codex_bin"):$PATH"
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die_usage "run inside a git repository"
repo_root="$(cd "$repo_root" && pwd -P)"
git_common_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir)"
git_common_dir="$(cd "$git_common_dir" && pwd -P)"
status="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
base_oid=""
since_oid=""
# Working-tree-only review remains valid in a newly initialized repository;
# commit-based paths below already require and validate an actual HEAD.
head_oid="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null || true)"

if [[ -n "$base" ]]; then
  git -C "$repo_root" rev-parse --verify "${base}^{commit}" >/dev/null 2>&1 || die_usage "invalid base ref: $base"
  base_oid="$(git -C "$repo_root" rev-parse "${base}^{commit}")"
  branch_changed=0
  if ! git -C "$repo_root" diff --quiet "$base"...HEAD --; then
    branch_changed=1
  fi
  if [[ "$branch_changed" -eq 0 && -z "$status" ]]; then
    printf 'Error: empty review target for base %s\n' "$base" >&2
    exit 3
  fi
else
  if [[ -z "$status" ]]; then
    printf 'Error: empty working-tree review target\n' >&2
    exit 3
  fi
fi

if [[ -n "$since" ]]; then
  [[ -n "$base" ]] || die_usage "--since requires --base"
  [[ -z "$status" ]] || die_usage "--since requires no staged, unstaged, or untracked changes; commit review fixes first"
  git -C "$repo_root" rev-parse --verify "${since}^{commit}" >/dev/null 2>&1 || die_usage "invalid since ref: $since"
  since_oid="$(git -C "$repo_root" rev-parse "${since}^{commit}")"
  git -C "$repo_root" merge-base --is-ancestor "$base_oid" "$since_oid" || die_usage "base must be an ancestor of since"
  git -C "$repo_root" merge-base --is-ancestor "$since_oid" "$head_oid" || die_usage "since must be an ancestor of HEAD; run a full review after history changes"
  # Three-dot diffing is exact here because the ancestry check fixes SINCE as
  # the merge base; relaxing that check would change the scope semantics.
  if git -C "$repo_root" diff --quiet "$since_oid"..."$head_oid" --; then
    printf 'Error: empty incremental review target for since %s\n' "$since" >&2
    exit 3
  fi
fi

if [[ -z "$focus" ]]; then
  if [[ "$mode" == "adversarial" ]]; then
    focus="Challenge whether the chosen approach, design, assumptions, and tradeoffs are correct for this repository."
  else
    focus="Find material correctness, security, performance, and specification defects in the implementation."
  fi
fi

review_tmp="$(mktemp -d "${TMPDIR:-/tmp}/codex-review.XXXXXX")" || die_usage "cannot create temporary review directory"
lock_dir=""
codex_pid=""
# The reviewer process group dies before the lock is released or its tmpdir is
# removed: an interrupted wrapper must not leave an orphan sharing the
# persistent session with the next round.
cleanup() {
  if [[ -n "$codex_pid" ]] && kill -0 "$codex_pid" 2>/dev/null; then
    kill -TERM -- "-$codex_pid" 2>/dev/null || true
    sleep 2
    kill -KILL -- "-$codex_pid" 2>/dev/null || true
    wait 2>/dev/null || true
  fi
  rm -rf "$review_tmp"
  [[ -z "$lock_dir" ]] || rmdir "$lock_dir" 2>/dev/null || true
}
trap cleanup EXIT
# Signal deaths must route through the EXIT trap; bash skips it otherwise.
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
full_review_bundle="$review_tmp/full-review-scope.txt"
incremental_review_bundle="$review_tmp/incremental-review-scope.txt"
review_bundle="$full_review_bundle"
# The reviewer never executes from inside the reviewed repository: a neutral
# working root prevents the repository's own project-layer Codex configuration
# (.codex/config.toml) from configuring its reviewer, whatever its trust state.
neutral_root="$review_tmp/neutral"
mkdir -p "$neutral_root"

session_key="${session_key_arg:-${CODEX_REVIEW_SESSION_KEY:-${CLAUDE_CODE_SESSION_ID:-}}}"
session_file=""
session_id=""
reviewed_state_file=""
reviewed_base=""
reviewed_head=""
reviewed_session=""
if [[ -n "$session_key" ]]; then
  session_dir="$git_common_dir/codex-review-sessions"
  mkdir -p "$session_dir"
  session_hash="$(printf '%s\0%s' "$repo_root" "$session_key" | git hash-object --stdin)"
  session_file="$session_dir/$session_hash"
  # Rounds sharing a key are serial by contract; the lock turns an accidental
  # overlap into a loud failure instead of interleaved reviewer turns or torn
  # session/checkpoint state. A stale lock is never removed silently.
  if ! mkdir "$session_file.lock" 2>/dev/null; then
    printf 'Error: another review round holds %s; if no round is running, remove it manually\n' "$session_file.lock" >&2
    exit 7
  fi
  lock_dir="$session_file.lock"
  reviewed_state_file="$session_file.$mode.reviewed"
  if [[ -s "$session_file" ]]; then
    IFS= read -r session_id < "$session_file" || true
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
fi

incremental_active=0
if [[ -n "$since" ]]; then
  # The checkpoint is honored only when the session that will be resumed is
  # the session that produced it: that session reviewed base..reviewed_head
  # in-context, so the reviewed union stays complete even if a key is reused.
  if [[ -n "$session_id" && "$reviewed_base" == "$base_oid" && "$reviewed_session" == "$session_id" ]] &&
     git -C "$repo_root" merge-base --is-ancestor "$since_oid" "$reviewed_head" &&
     git -C "$repo_root" merge-base --is-ancestor "$reviewed_head" "$head_oid"; then
    incremental_active=1
  else
    printf 'Warning: reviewer checkpoint is incomplete or mismatched; running a full review\n' >&2
  fi
fi

if [[ -n "$base" ]]; then
  full_scope="Review the complete task state: git diff ${base_oid}...${head_oid}, the staged diff, the unstaged diff, and every relevant untracked file. Do not review only the last commit or current hunk."
else
  full_scope="Review the complete working tree: git status --short --untracked-files=all, git diff --cached, git diff, and every relevant untracked file."
fi
if [[ "$incremental_active" -eq 1 ]]; then
  scope="Review the committed delta ${since_oid}...${head_oid} as the primary patch. Use prior-session findings for continuity and inspect affected final files, callers, and tests when needed. The complete task ${base_oid}...${head_oid} is included only as a stat and name-status summary."
else
  scope="$full_scope"
fi

{
  printf 'Repository: %s\n' "$repo_root"
  printf 'Review mode: %s\n' "$mode"
  if [[ -n "$base" ]]; then
    printf 'Base ref: %s\n' "$base_oid"
    printf 'HEAD: %s\n' "$head_oid"
    printf '\n## Branch diff: %s...%s\n' "$base_oid" "$head_oid"
    git -C "$repo_root" diff --binary "$base_oid"..."$head_oid" --
  else
    printf 'Base ref: working tree only\n'
  fi
  printf '\n## Status\n'
  git -C "$repo_root" status --short --untracked-files=all
  printf '\n## Staged diff\n'
  git -C "$repo_root" diff --cached --binary
  printf '\n## Unstaged diff\n'
  git -C "$repo_root" diff --binary --
  printf '\n## Untracked files\n'
  git -C "$repo_root" ls-files --others --exclude-standard
} > "$full_review_bundle"

if [[ -n "$since_oid" ]]; then
  {
    printf 'Repository: %s\n' "$repo_root"
    printf 'Review mode: %s\n' "$mode"
    printf 'Base ref: %s\n' "$base_oid"
    printf 'Since ref: %s\n' "$since_oid"
    printf 'HEAD: %s\n' "$head_oid"
    printf '\n## Commits since prior review\n'
    git -C "$repo_root" log --oneline --no-decorate "$since_oid".."$head_oid"
    printf '\n## Incremental changed files\n'
    git -C "$repo_root" diff --name-status "$since_oid"..."$head_oid" --
    printf '\n## Incremental patch\n'
    git -C "$repo_root" diff --binary "$since_oid"..."$head_oid" --
    printf '\n## Full task summary\n'
    git -C "$repo_root" diff --stat "$base_oid"..."$head_oid" --
    git -C "$repo_root" diff --name-status "$base_oid"..."$head_oid" --
  } > "$incremental_review_bundle"
fi
if [[ "$incremental_active" -eq 1 ]]; then
  review_bundle="$incremental_review_bundle"
fi

if [[ "$mode" == "adversarial" ]]; then
  lens="Question the approach itself, not only line-level defects. Check whether the artifact solves the right problem, fits repository constraints, covers failure modes, and avoids unjustified complexity."
else
  lens="Review the code as a strict defect finder. Prioritize reproducible correctness, security, data-loss, concurrency, and material performance problems. Exclude pure style and optional refactors."
fi

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

build_codex_prompt() {
  local bundle="$1" scope_contract="$2"
  cat <<EOF
You are the independent external reviewer in a gated development workflow. This is review-only: do not edit, write, delete, commit, or otherwise mutate repository files or state. Your shell runs in a read-only sandbox from a neutral working directory outside the repository; use it only for read commands such as git -C $repo_root status, git -C $repo_root diff, grep, and cat. Do not invoke any gated-development skill (such as codex-gated-development or claude-gated-development), the review wrapper scripts, or another external agent CLI such as claude; you are the reviewer, not a delegator.

Repository: $repo_root
Review mode: $mode
Scope contract: $scope_contract
Precomputed review bundle: $bundle
Review focus: $focus
Review lens: $lens

Read the precomputed review bundle first, then inspect applicable CLAUDE.md and AGENTS.md guidance and the named repository files under $repo_root. Verify that the review scope is non-empty and contains the artifact's actual substance; do not rely on a prompt summary when the code or document is available.

Return:
1. Scope examined: exact refs, diffs, and files reviewed.
2. Blocking findings: only valid correctness, security, look-ahead, sizing, spec-violation, or other material defects. Give priority, file:line, evidence, impact, and the smallest sound remedy.
3. Residual findings: optional style, alternative designs, or speculative hardening, clearly separated.
4. Verdict: PASS only when there is no valid unaddressed blocking finding; otherwise NEEDS REVISION.

End with exactly one machine-readable line: VERDICT: PASS, VERDICT: NEEDS REVISION, or VERDICT: SKIPPED.

If the target is empty or you cannot inspect the required scope, return SKIPPED rather than PASS.

This conversation may include earlier review gates from the same task. Use that context for continuity. For an incremental review, the new patch and full-task summary are authoritative; inspect final task files when compaction or interaction risks require more context.
EOF
}

full_prompt="$(build_codex_prompt "$full_review_bundle" "$full_scope")"
prompt="$full_prompt"
if [[ "$incremental_active" -eq 1 ]]; then
  prompt="$(build_codex_prompt "$review_bundle" "$scope")"
fi

cd "$repo_root"
before_fingerprint="$(repo_fingerprint)"

events_file="$review_tmp/codex-events.jsonl"
codex_last_message="$review_tmp/codex-last-message.txt"

# The reviewer runs with the user, rules, hooks, plugins, apps, and MCP
# surfaces removed: reviewed content must never gain tools inside its own
# reviewer, and a hook or MCP process could mutate state the repository
# fingerprint cannot see. mcp_servers={} alone is insufficient (TOML table
# overrides merge per key) and is kept only as redundancy.
codex_common_args=(
  --ignore-user-config
  --ignore-rules
  --disable hooks
  --disable plugins
  --disable apps
  -c 'mcp_servers={}'
  --skip-git-repo-check
  --json
  --sandbox read-only
  --output-last-message "$codex_last_message"
)

# stdin is pinned to /dev/null: codex exec appends piped stdin to the prompt
# and blocks forever when stdin is an open pipe (e.g. under background
# runners). The last-message file is truncated per attempt so a stale report
# from a failed attempt can never be printed as this round's verdict.
run_codex_new() {
  : > "$codex_last_message"
  (cd "$neutral_root" && "$codex_bin" exec "${codex_common_args[@]}" "$@") < /dev/null
}

# Parent options must precede the resume subcommand: codex exec resume
# rejects parent-only flags such as --sandbox placed after it.
run_codex_resume() {
  local resume_id="$1"
  shift
  : > "$codex_last_message"
  (cd "$neutral_root" && "$codex_bin" exec "${codex_common_args[@]}" resume "$resume_id" "$@") < /dev/null
}

extract_thread_id() {
  grep '"thread.started"' "$1" | head -n 1 | sed -n 's/.*"thread_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true
}

run_codex_review() {
  local codex_status
  if [[ -z "$session_file" ]]; then
    run_codex_new --ephemeral "$prompt" > "$events_file"
    return $?
  fi

  if [[ -n "$session_id" ]]; then
    run_codex_resume "$session_id" "$prompt" > "$events_file"
    codex_status=$?
  else
    codex_status=1
  fi

  if [[ "$codex_status" -ne 0 ]]; then
    [[ -z "$session_id" ]] || printf 'Warning: Codex session %s could not be resumed; starting a new session\n' "$session_id" >&2
    # A fresh conversation cannot safely interpret an incremental patch alone.
    run_codex_new "$full_prompt" > "$events_file"
    codex_status=$?
    if [[ "$codex_status" -eq 0 ]]; then
      session_id="$(extract_thread_id "$events_file")"
      if [[ -z "$session_id" ]]; then
        printf 'Error: could not capture Codex session id; keyed review requires session persistence\n' >&2
        codex_status=5
      elif ! printf '%s\n' "$session_id" > "$session_file"; then
        printf 'Error: could not save Codex session state at %s\n' "$session_file" >&2
        codex_status=5
      fi
    fi
  fi

  return "$codex_status"
}

codex_report="$review_tmp/codex-report.txt"

set +e
# Job control gives the reviewer its own process group for interruption cleanup.
set -m
run_codex_review > "$codex_report" 2>&1 &
codex_pid=$!
set +m
wait "$codex_pid"
codex_status=$?
codex_pid=""
# The review runs in a background subshell, so a fallback-created session id
# only exists in the session file; re-read it or the checkpoint below would
# bind to a stale id and silently disable every later incremental round.
if [[ -n "$session_file" && -s "$session_file" ]]; then
  IFS= read -r session_id < "$session_file" || true
fi
set -e

printf '=== Codex review ===\n'
if [[ -s "$codex_last_message" ]]; then
  cat "$codex_last_message"
else
  cat "$codex_report"
fi

after_fingerprint="$(repo_fingerprint)"
if [[ "$before_fingerprint" != "$after_fingerprint" ]]; then
  printf 'Error: repository state changed during reviewer execution; gate failed\n' >&2
  exit 4
fi

if [[ "$codex_status" -eq 0 ]] && ! grep -q '[^[:space:]]' "$codex_last_message" 2>/dev/null; then
  printf 'Error: Codex produced no final review message; gate failed\n' >&2
  codex_status=6
fi
# NEEDS REVISION is valid checkpoint evidence, but only PASS clears the gate.
# Enforce the prompt contract against the final nonempty line so trailing text
# cannot accidentally turn an incomplete response into a successful review.
review_verdict() {
  local last_line
  last_line="$(
    LC_ALL=C sed $'s/\033\\[[0-9;]*[[:alpha:]]//g' "$1" |
      tr -d '\r*`' |
      awk 'NF { line=$0 } END { print line }'
  )"
  if printf '%s\n' "$last_line" | LC_ALL=C grep -Eq \
    '^[^[:alnum:]]*VERDICT[[:space:]]*:[[:space:]]*PASS[^[:alnum:]]*$'; then
    printf 'PASS\n'
  elif printf '%s\n' "$last_line" | LC_ALL=C grep -Eq \
    '^[^[:alnum:]]*VERDICT[[:space:]]*:[[:space:]]*NEEDS REVISION[^[:alnum:]]*$'; then
    printf 'NEEDS REVISION\n'
  else
    return 1
  fi
}
codex_verdict=""
if [[ "$codex_status" -eq 0 ]]; then
  if ! codex_verdict="$(review_verdict "$codex_last_message")"; then
    printf 'Error: Codex final nonempty line is not a valid PASS or NEEDS REVISION verdict; gate failed\n' >&2
    codex_status=6
  fi
fi
if [[ "$codex_status" -ne 0 ]]; then
  exit "$codex_status"
fi

if [[ -n "$reviewed_state_file" && -n "$base_oid" && -z "$status" ]]; then
  state_tmp="$reviewed_state_file.tmp.$$"
  if [[ -d "$reviewed_state_file" ]] ||
     ! printf '%s %s %s\n' "$base_oid" "$head_oid" "$session_id" > "$state_tmp" ||
     ! mv -- "$state_tmp" "$reviewed_state_file"; then
    printf 'Error: could not save reviewed checkpoint at %s\n' "$reviewed_state_file" >&2
    exit 5
  fi
fi

[[ "$codex_verdict" == "PASS" ]] || exit 8
