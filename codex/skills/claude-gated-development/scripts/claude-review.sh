#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  claude-review.sh adversarial [--base REF] [--focus TEXT]
  claude-review.sh code [--base REF] [--focus TEXT]

Without --base, review staged, unstaged, and untracked working-tree changes.
With --base, review REF...HEAD plus current working-tree changes.
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
    -h|--help)
      usage
      exit 0
      ;;
    *) die_usage "unknown argument: $1" ;;
  esac
done

command -v git >/dev/null 2>&1 || die_usage "git is not installed"
claude_bin="$(command -v claude 2>/dev/null)" || die_usage "claude CLI is not installed"
if [[ "$claude_bin" == /* ]]; then
  export PATH="$(dirname "$claude_bin"):$PATH"
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

review_tmp="$(mktemp -d "${TMPDIR:-/tmp}/claude-review.XXXXXX")" || die_usage "cannot create temporary review directory"
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
      git -C "$repo_root" hash-object -- "$path"
    done < <(git -C "$repo_root" ls-files --others --exclude-standard -z)
  } | git hash-object --stdin
}

prompt=""
IFS= read -r -d '' prompt <<EOF || true
You are the independent external reviewer in a gated development workflow. This is review-only: do not edit, write, delete, commit, or otherwise mutate repository files or state. You may use other Claude skills and subagents when useful.

Repository: $repo_root
Review mode: $mode
Scope contract: $scope
Precomputed review bundle: $review_bundle
Review focus: $focus
Review lens: $lens

Read the precomputed review bundle first, then inspect applicable CLAUDE.md and AGENTS.md guidance and the named repository files with Read, Glob, and Grep. You do not have Bash or file-edit tools. Verify that the review scope is non-empty and contains the artifact's actual substance; do not rely on a prompt summary when the code or document is available.

Return:
1. Scope examined: exact refs, diffs, and files reviewed.
2. Blocking findings: only valid correctness, security, look-ahead, sizing, spec-violation, or other material defects. Give priority, file:line, evidence, impact, and the smallest sound remedy.
3. Residual findings: optional style, alternative designs, or speculative hardening, clearly separated.
4. Verdict: PASS only when there is no valid unaddressed blocking finding; otherwise NEEDS REVISION.

If the target is empty or you cannot inspect the required scope, return SKIPPED rather than PASS.
EOF

cd "$repo_root"
before_fingerprint="$(repo_fingerprint)"

set +e
"$claude_bin" "$prompt" \
  --print \
  --permission-mode dontAsk \
  --effort max \
  --no-session-persistence \
  --output-format text \
  --add-dir "$review_tmp" \
  --tools 'Read,Glob,Grep,Skill,Agent' \
  --allowedTools 'Read,Glob,Grep,Skill,Agent' \
  --strict-mcp-config \
  --mcp-config '{"mcpServers":{}}' \
  --settings '{"disableAllHooks":true,"disableSkillShellExecution":true}' \
  --disallowedTools 'Skill(codex-gated-development)' 'Bash' 'Write' 'Edit' 'NotebookEdit' 'EnterPlanMode' 'ExitPlanMode'
claude_status=$?
set -e

after_fingerprint="$(repo_fingerprint)"
if [[ "$before_fingerprint" != "$after_fingerprint" ]]; then
  printf 'Error: repository state changed during Claude review; gate failed\n' >&2
  exit 4
fi

exit "$claude_status"
