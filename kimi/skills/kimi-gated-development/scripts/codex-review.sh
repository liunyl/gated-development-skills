#!/usr/bin/env bash
set -euo pipefail
# Everything this wrapper writes (session state, review bundle, captured
# output) is private to the user; children inherit the restrictive mask.
umask 077

usage() {
  cat <<'EOF'
Usage:
  codex-review.sh adversarial [--base REF] [--focus TEXT] [--session-key KEY]
  codex-review.sh code [--base REF] [--focus TEXT] [--session-key KEY]

Without --base, review staged, unstaged, and untracked working-tree changes.
With --base, review REF...HEAD plus current working-tree changes.

Session continuity: with --session-key (or CODEX_REVIEW_SESSION_KEY), one
persistent Codex session per (repository, key) is reused across review rounds.
Without a key the review runs --ephemeral and nothing is persisted.
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
status="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"

if [[ -n "$base" ]]; then
  git -C "$repo_root" rev-parse --verify "${base}^{commit}" >/dev/null 2>&1 || die_usage "invalid base ref: $base"
  branch_changed=0
  if ! git -C "$repo_root" diff --quiet "$base"...HEAD --; then
    branch_changed=1
  fi
  if [[ "$branch_changed" -eq 0 && -z "$status" ]]; then
    printf 'Error: empty review target for base %s\n' "$base" >&2
    exit 3
  fi
  scope="Review the complete task state: git diff ${base}...HEAD, the staged diff, the unstaged diff, and every relevant untracked file. Do not review only the last commit or current hunk."
else
  if [[ -z "$status" ]]; then
    printf 'Error: empty working-tree review target\n' >&2
    exit 3
  fi
  scope="Review the complete working tree: git status --short --untracked-files=all, git diff --cached, git diff, and every relevant untracked file."
fi

if [[ -z "$focus" ]]; then
  if [[ "$mode" == "adversarial" ]]; then
    focus="Challenge whether the chosen approach, design, assumptions, and tradeoffs are correct for this repository."
  else
    focus="Find material correctness, security, performance, and specification defects in the implementation."
  fi
fi

review_tmp="$(mktemp -d "${TMPDIR:-/tmp}/codex-review.XXXXXX")" || die_usage "cannot create temporary review directory"
trap 'rm -rf "$review_tmp"' EXIT
review_bundle="$review_tmp/review-scope.txt"

{
  printf 'Repository: %s\n' "$repo_root"
  printf 'Review mode: %s\n' "$mode"
  if [[ -n "$base" ]]; then
    printf 'Base ref: %s\n' "$base"
    printf '\n## Branch diff: %s...HEAD\n' "$base"
    git -C "$repo_root" diff --binary "$base"...HEAD --
  else
    printf 'Base ref: working tree only\n'
  fi
  printf '\n## Status\n'
  git -C "$repo_root" status --short --untracked-files=all
  printf '\n## Staged diff\n'
  git -C "$repo_root" diff --cached --binary --
  printf '\n## Unstaged diff\n'
  git -C "$repo_root" diff --binary --
  printf '\n## Untracked files\n'
  git -C "$repo_root" ls-files --others --exclude-standard
} > "$review_bundle"

if [[ "$mode" == "adversarial" ]]; then
  lens="Question the approach itself, not only line-level defects. Check whether the artifact solves the right problem, fits repository constraints, covers failure modes, and avoids unjustified complexity."
else
  lens="Review the code as a strict defect finder. Prioritize reproducible correctness, security, data-loss, concurrency, and material performance problems. Exclude pure style and optional refactors."
fi

repo_fingerprint() {
  {
    git -C "$repo_root" rev-parse HEAD
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

prompt=""
IFS= read -r -d '' prompt <<EOF || true
You are the independent external reviewer in a gated development workflow. This is review-only: do not edit, write, delete, commit, or otherwise mutate repository files or state. Your shell runs in a read-only sandbox; use it only for read commands such as git status, git diff, grep, and cat. Do not invoke any gated-development skill (such as claude-gated-development) or the review wrapper scripts; you are the reviewer, not a delegator.

Repository: $repo_root
Review mode: $mode
Scope contract: $scope
Precomputed review bundle: $review_bundle
Review focus: $focus
Review lens: $lens

Read the precomputed review bundle first, then inspect applicable CLAUDE.md and AGENTS.md guidance and the named repository files. Verify that the review scope is non-empty and contains the artifact's actual substance; do not rely on a prompt summary when the code or document is available.

Return:
1. Scope examined: exact refs, diffs, and files reviewed.
2. Blocking findings: only valid correctness, security, look-ahead, sizing, spec-violation, or other material defects. Give priority, file:line, evidence, impact, and the smallest sound remedy.
3. Residual findings: optional style, alternative designs, or speculative hardening, clearly separated.
4. Verdict: PASS only when there is no valid unaddressed blocking finding; otherwise NEEDS REVISION.

If the target is empty or you cannot inspect the required scope, return SKIPPED rather than PASS.

This conversation may include earlier review gates from the same task. Use that context for continuity, but treat this invocation's review bundle and repository files as authoritative.
EOF

cd "$repo_root"
before_fingerprint="$(repo_fingerprint)"

events_file="$review_tmp/events.jsonl"
last_message_file="$review_tmp/last-message.txt"

codex_common_args=(
  --json
  --sandbox read-only
  --output-last-message "$last_message_file"
  -c 'mcp_servers={}'
)

# stdin is pinned to /dev/null: codex exec appends piped stdin to the prompt
# and blocks forever when stdin is an open pipe (e.g. under background runners).
# The last-message file is truncated per attempt so a stale report from a
# failed attempt can never be printed as this round's verdict.
run_codex_new() {
  : > "$last_message_file"
  "$codex_bin" exec "${codex_common_args[@]}" "$@" < /dev/null
}

# Parent options must precede the resume subcommand: codex exec resume
# rejects parent-only flags such as --sandbox placed after it.
run_codex_resume() {
  local resume_id="$1"
  shift
  : > "$last_message_file"
  "$codex_bin" exec "${codex_common_args[@]}" resume "$resume_id" "$prompt" "$@" < /dev/null
}

session_key="${session_key_arg:-${CODEX_REVIEW_SESSION_KEY:-${CODEX_THREAD_ID:-}}}"
session_file=""
session_id=""
if [[ -n "$session_key" ]]; then
  git_common_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir)"
  session_dir="$git_common_dir/codex-review-sessions"
  mkdir -p "$session_dir"
  session_hash="$(printf '%s\0%s' "$repo_root" "$session_key" | git hash-object --stdin)"
  session_file="$session_dir/$session_hash"
  if [[ -s "$session_file" ]]; then
    IFS= read -r session_id < "$session_file" || true
  fi
fi

extract_thread_id() {
  grep '"thread.started"' "$1" | head -n 1 | sed -n 's/.*"thread_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' || true
}

codex_status=0
new_session_id=""
set +e
if [[ -z "$session_file" ]]; then
  run_codex_new --ephemeral "$prompt" > "$events_file"
  codex_status=$?
else
  if [[ -n "$session_id" ]]; then
    run_codex_resume "$session_id" > "$events_file"
    codex_status=$?
  else
    codex_status=1
  fi

  if [[ "$codex_status" -ne 0 ]]; then
    [[ -z "$session_id" ]] || printf 'Warning: Codex session %s could not be resumed; starting a new session\n' "$session_id" >&2
    run_codex_new "$prompt" > "$events_file"
    codex_status=$?
    if [[ "$codex_status" -eq 0 ]]; then
      new_session_id="$(extract_thread_id "$events_file")"
      if [[ -z "$new_session_id" ]]; then
        printf 'Error: could not capture Codex session id; keyed review requires session persistence\n' >&2
        codex_status=5
      elif ! printf '%s\n' "$new_session_id" > "$session_file"; then
        printf 'Error: could not save Codex session state at %s\n' "$session_file" >&2
        codex_status=5
      fi
    fi
  fi
fi
set -e

after_fingerprint="$(repo_fingerprint)"
if [[ "$before_fingerprint" != "$after_fingerprint" ]]; then
  printf 'Error: repository state changed during Codex review; gate failed\n' >&2
  exit 4
fi

if [[ "$codex_status" -eq 0 ]]; then
  if [[ -s "$last_message_file" ]] && grep -q '[^[:space:]]' "$last_message_file"; then
    cat "$last_message_file"
  else
    printf 'Error: Codex produced no final review message; gate failed\n' >&2
    codex_status=6
  fi
fi

exit "$codex_status"
