#!/usr/bin/env bash
set -euo pipefail
# Everything this wrapper writes (session state, review bundle, reviewer
# reports) is private to the user; children inherit the restrictive mask.
umask 077

usage() {
  cat <<'EOF'
Usage:
  claude-review.sh adversarial [--base REF] [--since REF] [--focus TEXT] [--session-key KEY]
  claude-review.sh code [--base REF] [--since REF] [--focus TEXT] [--session-key KEY]

Without --base, review staged, unstaged, and untracked working-tree changes.
With --base, review REF...HEAD plus current working-tree changes.
With --base and --since, review only committed changes since REF when the same
review mode has a verified persistent checkpoint; otherwise review the full
task. Incremental review requires a clean working tree.

Session continuity: with --session-key (or CLAUDE_REVIEW_SESSION_KEY, or
CODEX_THREAD_ID), one persistent Claude session and one persistent Kimi
workspace per (repository, key) are reused across review rounds. Without any
key the review runs non-persistently.
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
claude_bin="$(command -v claude 2>/dev/null)" || die_usage "claude CLI is not installed"
kimi_bin="$(command -v kimi 2>/dev/null || true)"
[[ -n "$kimi_bin" ]] || kimi_bin="${HOME:-}/.kimi-code/bin/kimi"
if [[ "$kimi_bin" != /* ]]; then
  kimi_bin="$(cd "$(dirname "$kimi_bin")" && pwd -P)/$(basename "$kimi_bin")"
fi
[[ -x "$kimi_bin" ]] || die_usage "kimi CLI is not installed"
sandbox_bin="/usr/bin/sandbox-exec"
if [[ ! -x "$sandbox_bin" ]]; then
  sandbox_bin="$(command -v sandbox-exec 2>/dev/null || true)"
  if [[ -n "$sandbox_bin" && "$sandbox_bin" != /* ]]; then
    sandbox_bin="$(cd "$(dirname "$sandbox_bin")" && pwd -P)/$(basename "$sandbox_bin")"
  fi
fi
[[ -x "$sandbox_bin" ]] || die_usage "native sandbox-exec is required for Kimi review"
if [[ "$claude_bin" == /* ]]; then
  export PATH="$(dirname "$claude_bin"):$PATH"
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die_usage "run inside a git repository"
repo_root="$(cd "$repo_root" && pwd -P)"
git_common_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-common-dir)"
git_common_dir="$(cd "$git_common_dir" && pwd -P)"
git_dir="$(git -C "$repo_root" rev-parse --path-format=absolute --git-dir)"
git_dir="$(cd "$git_dir" && pwd -P)"
status="$(git -C "$repo_root" status --porcelain=v1 --untracked-files=all)"
base_oid=""
since_oid=""
head_oid="$(git -C "$repo_root" rev-parse HEAD)"

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

review_tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-review.XXXXXX")" || die_usage "cannot create temporary review directory"
trap 'rm -rf "$review_tmp"' EXIT
full_review_bundle="$review_tmp/full-review-scope.txt"
incremental_review_bundle="$review_tmp/incremental-review-scope.txt"
review_bundle="$full_review_bundle"
sandbox_profile="$review_tmp/kimi.sb"
kimi_skills_dir="$review_tmp/kimi-skills"
mkdir -p "$kimi_skills_dir"

session_key="${session_key_arg:-${CLAUDE_REVIEW_SESSION_KEY:-${CODEX_THREAD_ID:-}}}"
session_file=""
session_id=""
reviewed_state_file=""
reviewed_base=""
reviewed_head=""
kimi_workspace="$review_tmp/kimi-workspace"
kimi_state_file=""
kimi_session_id=""
if [[ -n "$session_key" ]]; then
  session_dir="$git_common_dir/claude-review-sessions"
  mkdir -p "$session_dir"
  session_hash="$(printf '%s\0%s' "$repo_root" "$session_key" | git hash-object --stdin)"
  session_file="$session_dir/$session_hash"
  reviewed_state_file="$session_file.$mode.reviewed"
  if [[ -s "$session_file" ]]; then
    IFS= read -r session_id < "$session_file" || true
  fi
  if [[ -s "$reviewed_state_file" ]]; then
    read -r reviewed_base reviewed_head < "$reviewed_state_file" || true
    if ! git -C "$repo_root" rev-parse --verify "${reviewed_head}^{commit}" >/dev/null 2>&1; then
      reviewed_base=""
      reviewed_head=""
    fi
  fi

  kimi_workspace_dir="${XDG_CACHE_HOME:-${HOME:-}/.cache}/claude-gated-development/kimi-review-workspaces"
  mkdir -p "$kimi_workspace_dir"
  kimi_workspace="$kimi_workspace_dir/$session_hash"
  mkdir -p "$kimi_workspace"
  kimi_workspace="$(cd "$kimi_workspace" && pwd -P)"
  kimi_state_file="$kimi_workspace/.successful-review"
  if [[ -s "$kimi_state_file" ]]; then
    IFS= read -r kimi_session_id < "$kimi_state_file" || true
    [[ "$kimi_session_id" =~ ^session_[A-Za-z0-9_-]+$ ]] || kimi_session_id=""
  fi
fi

incremental_active=0
if [[ -n "$since" ]]; then
  if [[ -n "$session_id" && -n "$kimi_session_id" &&
        "$reviewed_base" == "$base_oid" ]] &&
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

sandbox_path() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die_usage "repository path cannot contain newlines"
  value="${value//\\/\\\\}"
  printf '%s' "${value//\"/\\\"}"
}

sandbox_repo="$(sandbox_path "$repo_root")"
sandbox_common="$(sandbox_path "$git_common_dir")"
sandbox_git="$(sandbox_path "$git_dir")"
{
  printf '(version 1)\n'
  printf '(allow default)\n'
  printf '(deny file-read* file-write* (subpath "%s"))\n' "$sandbox_repo"
  printf '(deny file-read* file-write* (subpath "%s"))\n' "$sandbox_common"
  printf '(deny file-read* file-write* (subpath "%s"))\n' "$sandbox_git"
} > "$sandbox_profile"

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

if [[ "$incremental_active" -eq 1 ]]; then
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
  review_bundle="$incremental_review_bundle"
fi

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

build_claude_prompt() {
  local bundle="$1" scope_contract="$2"
  cat <<EOF
You are the independent external reviewer in a gated development workflow. This is review-only: do not edit, write, delete, commit, or otherwise mutate repository files or state. You may use Claude subagents and non-gate skills when useful, but do not invoke codex-gated-development.

Repository: $repo_root
Review mode: $mode
Scope contract: $scope_contract
Precomputed review bundle: $bundle
Review focus: $focus
Review lens: $lens

Read the precomputed review bundle first, then inspect applicable CLAUDE.md and AGENTS.md guidance and the named repository files with Read, Glob, and Grep. You do not have Bash or file-edit tools. Verify that the review scope is non-empty and contains the artifact's actual substance; do not rely on a prompt summary when the code or document is available.

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

full_prompt="$(build_claude_prompt "$full_review_bundle" "$full_scope")"
prompt="$full_prompt"
if [[ "$incremental_active" -eq 1 ]]; then
  prompt="$(build_claude_prompt "$review_bundle" "$scope")"
fi

cd "$repo_root"
before_fingerprint="$(repo_fingerprint)"

claude_args=(
  --print
  --permission-mode dontAsk
  --effort max
  --output-format text
  --add-dir "$review_tmp"
  --tools 'Read,Glob,Grep,Skill,Agent'
  --allowedTools 'Read,Glob,Grep,Skill,Agent'
  --strict-mcp-config
  --mcp-config '{"mcpServers":{}}'
  --settings '{"disableAllHooks":true,"disableSkillShellExecution":true}'
  --disallowedTools 'Skill(codex-gated-development)' 'Bash' 'Write' 'Edit' 'NotebookEdit' 'EnterPlanMode' 'ExitPlanMode'
)

# stdin is pinned to /dev/null: claude --print appends piped stdin to the prompt
# and blocks forever when stdin is an open pipe (e.g. under background runners).
run_claude() {
  local review_prompt="$1"
  shift
  "$claude_bin" "$review_prompt" "${claude_args[@]}" "$@" < /dev/null
}

prepare_kimi_workspace() {
  local line kimi_repo
  mkdir -p "$kimi_workspace"
  kimi_workspace="$(cd "$kimi_workspace" && pwd -P)"
  kimi_repo="$kimi_workspace/repo"
  rm -rf "$kimi_workspace/repo"
  mkdir -p "$kimi_workspace/repo"
  while IFS= read -r -d '' path; do
    [[ -e "$repo_root/$path" || -L "$repo_root/$path" ]] || continue
    mkdir -p "$kimi_workspace/repo/$(dirname "$path")"
    if [[ -L "$repo_root/$path" ]]; then
      printf 'symlink\n' > "$kimi_workspace/repo/$path"
    elif [[ -d "$repo_root/$path" ]]; then
      mkdir -p "$kimi_workspace/repo/$path"
      printf 'gitlink\n' > "$kimi_workspace/repo/$path/.gitlink"
    else
      cp -p -- "$repo_root/$path" "$kimi_workspace/repo/$path"
    fi
  done < <(git -C "$repo_root" ls-files --cached --others --exclude-standard -z)
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "${line//$repo_root/$kimi_repo}"
  done < "$review_bundle" > "$kimi_workspace/review-scope.txt"
}

run_claude_review() {
  local claude_status
  if [[ -z "$session_file" ]]; then
    run_claude "$prompt" --no-session-persistence
    return $?
  fi

  if [[ -n "$session_id" ]]; then
    run_claude "$prompt" --resume "$session_id"
    claude_status=$?
  else
    claude_status=1
  fi

  if [[ "$claude_status" -ne 0 ]]; then
    [[ -z "$session_id" ]] || printf 'Warning: Claude session %s could not be resumed; starting a new session\n' "$session_id" >&2
    session_seed="$(printf '%s\0%s' "$session_hash" "$review_tmp" | git hash-object --stdin)"
    session_id="${session_seed:0:8}-${session_seed:8:4}-4${session_seed:13:3}-8${session_seed:17:3}-${session_seed:20:12}"
    # A fresh conversation cannot safely interpret an incremental patch alone.
    run_claude "$full_prompt" --session-id "$session_id"
    claude_status=$?
    if [[ "$claude_status" -eq 0 ]]; then
      # ponytail: direct write is enough because a corrupt ID self-heals via the retry above and same-reviewer rounds are serial by contract; add locking if that changes.
      if ! printf '%s\n' "$session_id" > "$session_file"; then
        printf 'Error: could not save Claude session state at %s\n' "$session_file" >&2
        claude_status=5
      fi
    fi
  fi

  return "$claude_status"
}

run_kimi_review() {
  local -a kimi_args=(--skills-dir "$kimi_skills_dir" -p "$kimi_prompt")
  local -a kimi_env=(env -u OLDPWD)
  local name parsed_session_id kimi_status
  local kimi_resuming=0
  local kimi_raw_report="$review_tmp/kimi-raw-report.txt"
  if [[ -n "$kimi_session_id" ]]; then
    kimi_args=(--session "$kimi_session_id" "${kimi_args[@]}")
    kimi_resuming=1
  fi
  while IFS= read -r name; do
    [[ "$name" == GIT_* ]] && kimi_env+=(-u "$name")
  done < <(compgen -e)
  if (
    cd "$kimi_workspace"
    # stdin is pinned to /dev/null: kimi -p, like other CLIs, can block on an
    # open stdin pipe (e.g. under background runners).
    "${kimi_env[@]}" "$sandbox_bin" -f "$sandbox_profile" "$kimi_bin" "${kimi_args[@]}" < /dev/null
  ) > "$kimi_raw_report" 2>&1; then
    kimi_status=0
  else
    kimi_status=$?
  fi
  cat "$kimi_raw_report"

  if [[ "$kimi_status" -ne 0 && "$kimi_resuming" -eq 1 ]]; then
    if ! : > "$kimi_state_file"; then
      printf 'Error: could not clear stale Kimi session state at %s\n' "$kimi_state_file" >&2
      return 5
    fi
  fi
  if [[ "$kimi_status" -eq 0 ]]; then
    parsed_session_id="$(sed -n 's/^To resume this session: kimi -r \(session_[A-Za-z0-9_-][A-Za-z0-9_-]*\)$/\1/p' "$kimi_raw_report" | tail -n 1)"
    if [[ -z "$parsed_session_id" ]]; then
      if [[ "$kimi_resuming" -eq 1 ]] && ! : > "$kimi_state_file"; then
        printf 'Error: could not clear unusable Kimi session state at %s\n' "$kimi_state_file" >&2
        return 5
      fi
      printf 'Error: Kimi produced no valid resume hint; gate failed\n' >&2
      return 6
    fi
    if [[ -n "$kimi_state_file" ]] && ! printf '%s\n' "$parsed_session_id" > "$kimi_state_file"; then
      printf 'Error: could not save Kimi session state at %s\n' "$kimi_state_file" >&2
      return 5
    fi
  fi
  return "$kimi_status"
}

prepare_kimi_workspace
kimi_repo="$kimi_workspace/repo"
kimi_scope="${scope//$repo_root/$kimi_repo}"
kimi_focus="${focus//$repo_root/$kimi_repo}"
IFS= read -r -d '' kimi_prompt <<EOF || true
You are the independent external reviewer in a gated development workflow. This is review-only: do not edit, write, delete, commit, or otherwise mutate repository files or state. You may use built-in Kimi subagents, but do not invoke kimi-gated-development.

Repository snapshot: $kimi_repo
Review mode: $mode
Scope contract: $kimi_scope
Precomputed review bundle: $kimi_workspace/review-scope.txt
Review focus: $kimi_focus
Review lens: $lens

Read the precomputed review bundle first, then inspect applicable CLAUDE.md and AGENTS.md guidance and the named repository snapshot files. Verify that the review scope is non-empty and contains the artifact's actual substance; do not rely on a prompt summary when the code or document is available.

Return:
1. Scope examined: exact refs, diffs, and files reviewed.
2. Blocking findings: only valid correctness, security, look-ahead, sizing, spec-violation, or other material defects. Give priority, file:line, evidence, impact, and the smallest sound remedy.
3. Residual findings: optional style, alternative designs, or speculative hardening, clearly separated.
4. Verdict: PASS only when there is no valid unaddressed blocking finding; otherwise NEEDS REVISION.

End with exactly one machine-readable line: VERDICT: PASS, VERDICT: NEEDS REVISION, or VERDICT: SKIPPED.

If the target is empty or you cannot inspect the required scope, return SKIPPED rather than PASS.

This conversation may include earlier review gates from the same task. Use that context for continuity, but treat this invocation's review bundle and repository snapshot files as authoritative.
EOF
claude_report="$review_tmp/claude-report.txt"
kimi_report="$review_tmp/kimi-report.txt"

set +e
run_claude_review > "$claude_report" 2>&1 &
claude_pid=$!
run_kimi_review > "$kimi_report" 2>&1 &
kimi_pid=$!
wait "$claude_pid"
claude_status=$?
wait "$kimi_pid"
kimi_status=$?
set -e

printf '=== Claude review ===\n'
cat "$claude_report"
printf '=== Kimi review ===\n'
cat "$kimi_report"

after_fingerprint="$(repo_fingerprint)"
if [[ "$before_fingerprint" != "$after_fingerprint" ]]; then
  printf 'Error: repository state changed during reviewer execution; gate failed\n' >&2
  exit 4
fi

if [[ "$claude_status" -eq 0 ]] && ! grep -q '[^[:space:]]' "$claude_report"; then
  printf 'Error: Claude produced no review output; gate failed\n' >&2
  claude_status=6
fi
if [[ "$kimi_status" -eq 0 ]] && ! grep -q '[^[:space:]]' "$kimi_report"; then
  printf 'Error: Kimi produced no review output; gate failed\n' >&2
  kimi_status=6
fi

# A successful process is not a successful review when the reviewer skipped
# the scope or ignored the output contract. NEEDS REVISION is valid here: it
# records the state that produced findings so the next round can be incremental.
has_review_verdict() {
  tr -d '\r*' < "$1" |
    grep -Eq '^[[:space:]]*VERDICT:[[:space:]]*(PASS|NEEDS REVISION)[[:space:]]*$'
}
if [[ "$claude_status" -eq 0 ]] && ! has_review_verdict "$claude_report"; then
  printf 'Error: Claude produced no valid PASS or NEEDS REVISION verdict; gate failed\n' >&2
  claude_status=6
fi
if [[ "$kimi_status" -eq 0 ]] && ! has_review_verdict "$kimi_report"; then
  printf 'Error: Kimi produced no valid PASS or NEEDS REVISION verdict; gate failed\n' >&2
  kimi_status=6
fi

if [[ "$claude_status" -ne 0 ]]; then
  exit "$claude_status"
fi
if [[ "$kimi_status" -ne 0 ]]; then
  exit "$kimi_status"
fi

if [[ -n "$reviewed_state_file" && -n "$base_oid" && -z "$status" ]]; then
  state_tmp="$reviewed_state_file.tmp.$$"
  if [[ -d "$reviewed_state_file" ]] ||
     ! printf '%s %s\n' "$base_oid" "$head_oid" > "$state_tmp" ||
     ! mv -- "$state_tmp" "$reviewed_state_file"; then
    printf 'Error: could not save reviewed checkpoint at %s\n' "$reviewed_state_file" >&2
    exit 5
  fi
fi
