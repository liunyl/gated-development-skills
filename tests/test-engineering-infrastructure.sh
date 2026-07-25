#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BOOTSTRAP="$ROOT/shared/skills/bootstrap-project"
MERGE="$BOOTSTRAP/scripts/update-managed-block.sh"

test -f "$BOOTSTRAP/SKILL.md"
test -f "$BOOTSTRAP/assets/project-instructions.md"
test -f "$BOOTSTRAP/assets/pull-request-template.md"
test -x "$MERGE"
grep -Fq 'name: bootstrap-project' "$BOOTSTRAP/SKILL.md"
grep -Fq '<!-- BEGIN bootstrap-project: engineering-standards -->' "$BOOTSTRAP/assets/project-instructions.md"
grep -Fq '<!-- END bootstrap-project: engineering-standards -->' "$BOOTSTRAP/assets/project-instructions.md"
grep -Fq 'Source map' "$BOOTSTRAP/SKILL.md"
grep -Fq 'update-managed-block.sh' "$BOOTSTRAP/SKILL.md"
grep -Fq 'BOOTSTRAP_PROJECT_SKILL_DIR' "$BOOTSTRAP/SKILL.md"
grep -Fq 'CLAUDE_CONFIG_DIR' "$BOOTSTRAP/SKILL.md"
grep -Fq 'CODEX_HOME' "$BOOTSTRAP/SKILL.md"
grep -Fq 'KIMI_CODE_HOME' "$BOOTSTRAP/SKILL.md"
grep -Fq 'Behavior before and after' "$BOOTSTRAP/assets/pull-request-template.md"
grep -Fq 'Read `docs/README.md` when present, then read the repository' "$BOOTSTRAP/SKILL.md"
grep -Fq 'existing documentation entry point, architecture index, and relevant current-architecture documents' "$BOOTSTRAP/SKILL.md"
grep -Fq 'root README' "$BOOTSTRAP/SKILL.md"
grep -Fq 'manifests, source and test roots, build/test entry points, runtime entry points, persistence, and external integrations' "$BOOTSTRAP/SKILL.md"
grep -Fq 'Scan the source tree and sample implementation and tests around apparent boundaries' "$BOOTSTRAP/SKILL.md"
grep -Fq 'excluding vendored, generated, cache, and worktree directories' "$BOOTSTRAP/SKILL.md"
grep -Fq 'evidence-backed module map' "$BOOTSTRAP/SKILL.md"
grep -Fq 'before drafting architecture prose' "$BOOTSTRAP/SKILL.md"
grep -Fq 'independent responsibility plus a meaningful interface, data flow, or lifecycle' "$BOOTSTRAP/SKILL.md"
grep -Fq 'capture its responsibility, evidence paths, and architecture-document destination' "$BOOTSTRAP/SKILL.md"
grep -Fq 'Use the module map to choose the documentation taxonomy' "$BOOTSTRAP/SKILL.md"
grep -Fq 'Reconcile taxonomy from the module map; preserve equivalent existing content' "$BOOTSTRAP/SKILL.md"
grep -Fq 'at most one durable module may keep readable architecture detail in one overview' "$BOOTSTRAP/SKILL.md"
grep -Fq 'multiple durable modules emerge or the detail needs independent navigation' "$BOOTSTRAP/SKILL.md"
grep -Fq 'two or more independent durable modules' "$BOOTSTRAP/SKILL.md"
grep -Fq 'subagents are available' "$BOOTSTRAP/SKILL.md"
grep -Fq 'one bounded module investigation and draft per subagent' "$BOOTSTRAP/SKILL.md"
grep -Fq 'The parent owns taxonomy, cross-cutting behavior, integration, source-map validation, and conflict resolution' "$BOOTSTRAP/SKILL.md"
grep -Fq 'Work locally when the project is smaller or subagents are unavailable' "$BOOTSTRAP/SKILL.md"
grep -Fq 'Empty repositories' "$BOOTSTRAP/SKILL.md"
grep -Fq 'minimal truthful docs entry point, architecture index, and overview' "$BOOTSTRAP/SKILL.md"
grep -Fq 'do not invent module documents' "$BOOTSTRAP/SKILL.md"
grep -Fq 'focused numbered subsystem documents' "$BOOTSTRAP/SKILL.md"
grep -Fq 'historical change context' "$BOOTSTRAP/SKILL.md"
grep -Fq '`docs/plans/` and `docs/superpowers/` are reserved for historical change context and are never current architecture authority' "$BOOTSTRAP/SKILL.md"
grep -Fq 'only when the documentation guide and repository evidence establish that role; do not infer authority from path names alone' "$BOOTSTRAP/SKILL.md"
grep -Fq 'Current architecture authority lives in `docs/architecture/` by default, or in the repository' "$BOOTSTRAP/SKILL.md"
grep -Fq 'existing equivalent current-architecture hierarchy' "$BOOTSTRAP/SKILL.md"
if grep -Eq 'Task tool|TodoWrite|/codex:|/claude:' "$BOOTSTRAP/SKILL.md"; then
  printf '%s\n' 'bootstrap-project contains agent-specific commands' >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
BLOCK="$BOOTSTRAP/assets/project-instructions.md"

grep -Fq 'introduces, removes, splits, or merges a durable module' "$BLOCK"
grep -Fq 'Keep the overview focused on system context' "$BLOCK"
grep -Fq 'docs/architecture/README.md' "$BLOCK"
grep -Fq 'by default, or its existing equivalent' "$BLOCK"
grep -Fq 'at most one durable module may keep readable architecture detail in its overview' "$BLOCK"
grep -Fq 'When multiple durable modules emerge or detail needs independent navigation' "$BLOCK"
grep -Fq 'Treat `docs/plans/` and `docs/superpowers/` as historical change context, not authoritative descriptions of the current code.' "$BLOCK"

test_action() {
  expected=$1
  shift
  target=$1
  if actual=$("$MERGE" "$@" 2>&1); then
    helper_status=0
  else
    helper_status=$?
  fi
  if test "$helper_status" -ne 0 || test "$actual" != "$expected"; then
    printf '%s\n' \
      "test_action target: $target" \
      "test_action expected: $expected" \
      "test_action actual: $actual" >&2
    exit 1
  fi
}

file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

assert_rejected() {
  label=$1
  expected_status=$2
  expected_stderr=$3
  shift 3
  rejected_stdout="$TMP/rejected.out"
  rejected_stderr="$TMP/rejected.err"

  if "$@" >"$rejected_stdout" 2>"$rejected_stderr"; then
    actual_status=0
  else
    actual_status=$?
  fi

  if test "$actual_status" -eq "$expected_status" &&
    test ! -s "$rejected_stdout" &&
    grep -Fq "$expected_stderr" "$rejected_stderr"
  then
    return
  fi

  {
    printf '%s\n' \
      "rejection case: $label" \
      "expected status: $expected_status" \
      "actual status: $actual_status" \
      "expected stderr substring: $expected_stderr" \
      'stdout:'
    cat "$rejected_stdout"
    printf '%s\n' 'stderr:'
    cat "$rejected_stderr"
  } >&2
  exit 1
}

# A missing target is created from the complete block.
test_action created "$TMP/new.md" "$BLOCK"
cmp "$TMP/new.md" "$BLOCK"

# Existing unmanaged content is preserved when the block is appended.
printf '%s\n' '# Local rules' '' 'Keep this line.' >"$TMP/unmanaged.md"
{
  printf '%s\n' '# Local rules' '' 'Keep this line.' ''
  sed -n 'p' "$BLOCK"
} >"$TMP/unmanaged.expected"
test_action appended "$TMP/unmanaged.md" "$BLOCK"
cmp "$TMP/unmanaged.md" "$TMP/unmanaged.expected"

# One existing block is replaced, while other managed IDs remain untouched.
cat >"$TMP/replace.md" <<'EOF'
Local prefix.
<!-- BEGIN bootstrap-project: other -->
Other managed content.
<!-- END bootstrap-project: other -->
<!-- BEGIN bootstrap-project: engineering-standards -->
Old content.
<!-- END bootstrap-project: engineering-standards -->
Local suffix.
EOF
{
  printf '%s\n' 'Local prefix.' '<!-- BEGIN bootstrap-project: other -->' 'Other managed content.' '<!-- END bootstrap-project: other -->'
  sed -n 'p' "$BLOCK"
  printf '%s\n' 'Local suffix.'
} >"$TMP/replace.expected"
cp "$TMP/replace.md" "$TMP/read-only.md"
chmod 0444 "$TMP/read-only.md"
test_action replaced "$TMP/replace.md" "$BLOCK"
cmp "$TMP/replace.md" "$TMP/replace.expected"
test "$(grep -Fc '<!-- BEGIN bootstrap-project: engineering-standards -->' "$TMP/replace.md")" -eq 1
test "$(grep -Fc '<!-- END bootstrap-project: engineering-standards -->' "$TMP/replace.md")" -eq 1

# Read-only existing targets remain replaceable and retain their mode.
test_action replaced "$TMP/read-only.md" "$BLOCK"
cmp "$TMP/read-only.md" "$TMP/replace.expected"
test "$(file_mode "$TMP/read-only.md")" = 444

# Whitespace accepted around BLOCK markers is accepted around TARGET markers too.
printf '%s\n' \
  'Local prefix.' \
  '  <!-- BEGIN bootstrap-project: engineering-standards -->   ' \
  'Old content.' \
  '  <!-- END bootstrap-project: engineering-standards -->   ' \
  'Local suffix.' >"$TMP/whitespace.md"
{
  printf '%s\n' 'Local prefix.'
  sed -n 'p' "$BLOCK"
  printf '%s\n' 'Local suffix.'
} >"$TMP/whitespace.expected"
whitespace_action=$($MERGE "$TMP/whitespace.md" "$BLOCK")
if test "$whitespace_action" != replaced; then
  printf 'whitespace-marker target: expected replaced, got %s\n' "$whitespace_action" >&2
  exit 1
fi
cmp "$TMP/whitespace.md" "$TMP/whitespace.expected"
test "$(grep -Ec '^[[:space:]]*<!-- BEGIN bootstrap-project: engineering-standards -->[[:space:]]*$' "$TMP/whitespace.md")" -eq 1
test "$(grep -Ec '^[[:space:]]*<!-- END bootstrap-project: engineering-standards -->[[:space:]]*$' "$TMP/whitespace.md")" -eq 1

# Malformed and duplicate matching markers fail without changing the target.
MALFORMED_TARGET_ERROR='update-managed-block: invalid TARGET: malformed or duplicate markers for engineering-standards'
cat >"$TMP/malformed.md" <<'EOF'
Keep me.
<!-- BEGIN bootstrap-project: engineering-standards -->
Incomplete block.
EOF
cp "$TMP/malformed.md" "$TMP/malformed.before"
assert_rejected missing-end-marker 2 "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/malformed.md" "$BLOCK"
cmp "$TMP/malformed.md" "$TMP/malformed.before"

cat >"$TMP/trailing-marker-text.md" <<'EOF'
Keep me too.
<!-- BEGIN bootstrap-project: engineering-standards --> invalid
Untrusted content.
<!-- END bootstrap-project: engineering-standards --> invalid
EOF
cp "$TMP/trailing-marker-text.md" "$TMP/trailing-marker-text.before"
assert_rejected trailing-marker-text 2 "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/trailing-marker-text.md" "$BLOCK"
cmp "$TMP/trailing-marker-text.md" "$TMP/trailing-marker-text.before"

cat >"$TMP/leading-marker-text.md" <<'EOF'
Keep leading text unchanged.
invalid <!-- BEGIN bootstrap-project: engineering-standards -->
Untrusted content.
invalid <!-- END bootstrap-project: engineering-standards -->
EOF
cp "$TMP/leading-marker-text.md" "$TMP/leading-marker-text.before"
assert_rejected leading-marker-text 2 "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/leading-marker-text.md" "$BLOCK"
cmp "$TMP/leading-marker-text.md" "$TMP/leading-marker-text.before"

cat >"$TMP/internal-marker-whitespace.md" <<'EOF'
Keep internal whitespace unchanged.
<!-- BEGIN bootstrap-project: engineering-standards  -->
Untrusted content.
<!-- END bootstrap-project: engineering-standards  -->
EOF
cp "$TMP/internal-marker-whitespace.md" "$TMP/internal-marker-whitespace.before"
assert_rejected internal-marker-whitespace 2 \
  "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/internal-marker-whitespace.md" "$BLOCK"
cmp "$TMP/internal-marker-whitespace.md" "$TMP/internal-marker-whitespace.before"

cat >"$TMP/missing-marker-terminator.md" <<'EOF'
Keep missing terminators unchanged.
<!-- BEGIN bootstrap-project: engineering-standards
Untrusted content.
<!-- END bootstrap-project: engineering-standards
EOF
cp "$TMP/missing-marker-terminator.md" "$TMP/missing-marker-terminator.before"
assert_rejected missing-marker-terminator 2 \
  "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/missing-marker-terminator.md" "$BLOCK"
cmp "$TMP/missing-marker-terminator.md" "$TMP/missing-marker-terminator.before"

printf '%b\n' \
  'Keep ID-leading whitespace unchanged.' \
  '<!-- BEGIN bootstrap-project:  engineering-standards -->' \
  'Untrusted content.' \
  '<!-- END bootstrap-project:\tengineering-standards -->' \
  >"$TMP/id-leading-whitespace.md"
cp "$TMP/id-leading-whitespace.md" "$TMP/id-leading-whitespace.before"
assert_rejected id-leading-whitespace 2 "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/id-leading-whitespace.md" "$BLOCK"
cmp "$TMP/id-leading-whitespace.md" "$TMP/id-leading-whitespace.before"

printf '%b\n' \
  'Keep keyword whitespace unchanged.' \
  '<!-- BEGIN  bootstrap-project: engineering-standards -->' \
  'Untrusted content.' \
  '<!-- END\tbootstrap-project: engineering-standards -->' \
  >"$TMP/keyword-whitespace.md"
cp "$TMP/keyword-whitespace.md" "$TMP/keyword-whitespace.before"
assert_rejected keyword-whitespace 2 "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/keyword-whitespace.md" "$BLOCK"
cmp "$TMP/keyword-whitespace.md" "$TMP/keyword-whitespace.before"

printf '%b\n' \
  'Keep comment whitespace unchanged.' \
  '<!--  BEGIN bootstrap-project: engineering-standards -->' \
  'Untrusted content.' \
  '<!--\tEND bootstrap-project: engineering-standards -->' \
  >"$TMP/comment-whitespace.md"
cp "$TMP/comment-whitespace.md" "$TMP/comment-whitespace.before"
assert_rejected comment-whitespace 2 "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/comment-whitespace.md" "$BLOCK"
cmp "$TMP/comment-whitespace.md" "$TMP/comment-whitespace.before"

cat >"$TMP/missing-structural-whitespace.md" <<'EOF'
Keep missing structural whitespace unchanged.
<!--BEGINbootstrap-project:engineering-standards -->
Untrusted content.
<!--ENDbootstrap-project:engineering-standards -->
EOF
cp "$TMP/missing-structural-whitespace.md" "$TMP/missing-structural-whitespace.before"
assert_rejected missing-structural-whitespace 2 "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/missing-structural-whitespace.md" "$BLOCK"
cmp "$TMP/missing-structural-whitespace.md" "$TMP/missing-structural-whitespace.before"

cat >"$TMP/missing-colon-whitespace.md" <<'EOF'
Keep missing colon whitespace unchanged.
<!-- BEGIN bootstrap-project:engineering-standards -->
Untrusted content.
<!-- END bootstrap-project:engineering-standards -->
EOF
cp "$TMP/missing-colon-whitespace.md" "$TMP/missing-colon-whitespace.before"
assert_rejected missing-colon-whitespace 2 "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/missing-colon-whitespace.md" "$BLOCK"
cmp "$TMP/missing-colon-whitespace.md" "$TMP/missing-colon-whitespace.before"

printf '%b\n' \
  'Keep pre-colon whitespace unchanged.' \
  '<!-- BEGIN bootstrap-project : engineering-standards -->' \
  'Untrusted content.' \
  '<!-- END bootstrap-project\t: engineering-standards -->' \
  >"$TMP/pre-colon-whitespace.md"
cp "$TMP/pre-colon-whitespace.md" "$TMP/pre-colon-whitespace.before"
assert_rejected pre-colon-whitespace 2 "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/pre-colon-whitespace.md" "$BLOCK"
cmp "$TMP/pre-colon-whitespace.md" "$TMP/pre-colon-whitespace.before"

cat >"$TMP/repeated-colon.md" <<'EOF'
Keep repeated colons unchanged.
<!-- BEGIN bootstrap-project :: engineering-standards -->
Untrusted content.
<!-- END bootstrap-project :: engineering-standards -->
EOF
cp "$TMP/repeated-colon.md" "$TMP/repeated-colon.before"
assert_rejected repeated-colon 2 "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/repeated-colon.md" "$BLOCK"
cmp "$TMP/repeated-colon.md" "$TMP/repeated-colon.before"

cat >"$TMP/duplicate.md" <<'EOF'
<!-- BEGIN bootstrap-project: engineering-standards -->
First.
<!-- END bootstrap-project: engineering-standards -->
<!-- BEGIN bootstrap-project: engineering-standards -->
Second.
<!-- END bootstrap-project: engineering-standards -->
EOF
cp "$TMP/duplicate.md" "$TMP/duplicate.before"
assert_rejected duplicate-markers 2 "$MALFORMED_TARGET_ERROR" \
  "$MERGE" "$TMP/duplicate.md" "$BLOCK"
cmp "$TMP/duplicate.md" "$TMP/duplicate.before"

# A longer marker ID is unrelated and must not be treated as a malformed match.
cat >"$TMP/suffix-id.md" <<'EOF'
<!-- BEGIN bootstrap-project: engineering-standards-extra -->
Other managed content.
<!-- END bootstrap-project: engineering-standards-extra -->
EOF
test_action appended "$TMP/suffix-id.md" "$BLOCK"
test "$(grep -Fc '<!-- BEGIN bootstrap-project: engineering-standards-extra -->' "$TMP/suffix-id.md")" -eq 1
test "$(grep -Fc '<!-- BEGIN bootstrap-project: engineering-standards -->' "$TMP/suffix-id.md")" -eq 1

# Relative option-like TARGET and BLOCK names are files, not utility options.
mkdir "$TMP/option-like-paths"
cp "$BLOCK" "$TMP/option-like-paths/-block.md"
(
  cd "$TMP/option-like-paths"
  test_action created -AGENTS.md -block.md
  cmp ./-AGENTS.md ./-block.md
)

# Operational command failures are distinct from input validation failures.
mkdir "$TMP/fail-stat" "$TMP/fail-awk" "$TMP/counting-awk"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$TMP/fail-stat/stat"
printf '%s\n' '#!/bin/sh' 'exit 1' >"$TMP/fail-awk/awk"
cat >"$TMP/counting-awk/awk" <<'EOF'
#!/bin/sh
count=0
if test -f "$AWK_COUNT_FILE"; then
  IFS= read -r count <"$AWK_COUNT_FILE"
fi
count=$((count + 1))
printf '%s\n' "$count" >"$AWK_COUNT_FILE"
if test "$count" -eq "${AWK_FAIL_ON:-0}"; then
  printf 'forced awk failure on invocation %s\n' "$count" >&2
  exit 9
fi
if test "$count" -eq "${AWK_REMOVE_ON:-0}"; then
  rm -f "$AWK_REMOVE_FILE"
fi
exec "$REAL_AWK" "$@"
EOF
chmod +x "$TMP/fail-stat/stat" "$TMP/fail-awk/awk" "$TMP/counting-awk/awk"
cp "$TMP/replace.md" "$TMP/stat-failure.before"
assert_rejected stat-command-failure 3 \
  'update-managed-block: cannot read mode for TARGET:' \
  env PATH="$TMP/fail-stat:$PATH" \
  "$MERGE" "$TMP/replace.md" "$BLOCK"
cmp "$TMP/replace.md" "$TMP/stat-failure.before"
assert_rejected block-scanner-failure 3 \
  'update-managed-block: cannot inspect BLOCK:' \
  env PATH="$TMP/fail-awk:$PATH" \
  "$MERGE" "$TMP/awk-failure.md" "$BLOCK"
test ! -e "$TMP/awk-failure.md"

REAL_AWK=$(command -v awk)
printf '%s\n' 0 >"$TMP/awk-count"
cp "$TMP/replace.md" "$TMP/target-scan-failure.md"
cp "$TMP/target-scan-failure.md" "$TMP/target-scan-failure.before"
assert_rejected target-scanner-failure 3 \
  'update-managed-block: cannot inspect TARGET:' \
  env PATH="$TMP/counting-awk:$PATH" \
  REAL_AWK="$REAL_AWK" AWK_COUNT_FILE="$TMP/awk-count" AWK_FAIL_ON=2 \
  "$MERGE" "$TMP/target-scan-failure.md" "$BLOCK"
cmp "$TMP/target-scan-failure.md" "$TMP/target-scan-failure.before"

# Losing BLOCK during replacement must fail before chmod/mv and clean the temporary render.
printf '%s\n' 0 >"$TMP/awk-count"
cp "$BLOCK" "$TMP/render-failure-block.md"
cp "$TMP/replace.md" "$TMP/render-failure.md"
cp "$TMP/render-failure.md" "$TMP/render-failure.before"
assert_rejected replacement-block-read-failure 3 \
  'update-managed-block: cannot render TARGET from BLOCK:' \
  env PATH="$TMP/counting-awk:$PATH" \
  REAL_AWK="$REAL_AWK" AWK_COUNT_FILE="$TMP/awk-count" AWK_REMOVE_ON=3 \
  AWK_REMOVE_FILE="$TMP/render-failure-block.md" \
  "$MERGE" "$TMP/render-failure.md" "$TMP/render-failure-block.md"
cmp "$TMP/render-failure.md" "$TMP/render-failure.before"
test -z "$(find "$TMP" -name '.bootstrap-project.*' -print)"

# Execute the documented resolver so relative overrides cannot select helpers
# from the repository being bootstrapped.
RESOLVER="$TMP/resolve-bootstrap-project.sh"
awk '
  /^```sh$/ && !found { found = 1; capture = 1; next }
  capture && /^```$/ { exit }
  capture { print }
' "$BOOTSTRAP/SKILL.md" >"$RESOLVER"
printf '%s\n' 'printf '\''%s\n'\'' "$BOOTSTRAP_PROJECT_SKILL_DIR"' >>"$RESOLVER"

resolved=$(BOOTSTRAP_PROJECT_SKILL_DIR="$BOOTSTRAP" sh "$RESOLVER")
test "$resolved" = "$BOOTSTRAP"

TARGET_REPO="$TMP/target-repo"
RELATIVE_ROOT=target-config
RELATIVE_SKILL="$TARGET_REPO/$RELATIVE_ROOT/skills/bootstrap-project"
mkdir -p "$RELATIVE_SKILL/scripts"
printf '%s\n' '#!/bin/sh' >"$RELATIVE_SKILL/scripts/update-managed-block.sh"
mkdir -p "$TARGET_REPO/$RELATIVE_ROOT/.claude/skills/bootstrap-project/scripts"
printf '%s\n' '#!/bin/sh' >"$TARGET_REPO/$RELATIVE_ROOT/.claude/skills/bootstrap-project/scripts/update-managed-block.sh"

# An absolute helper remains safe to use with paths relative to the target repo.
(
  cd "$TARGET_REPO"
  test_action created AGENTS.md "$BLOCK"
  cmp AGENTS.md "$BLOCK"
  test_action replaced AGENTS.md "$BLOCK"
  cmp AGENTS.md "$BLOCK"
)

assert_relative_resolution_rejected() {
  label=$1
  expected_stderr=$2
  shift 2
  assert_rejected "$label-relative-resolution" 2 "$expected_stderr" \
    run_resolver_in_target "$@"
}

run_resolver_in_target() {
  (cd "$TARGET_REPO" && env "$@" sh "$RESOLVER")
}

assert_relative_resolution_rejected BOOTSTRAP_PROJECT_SKILL_DIR \
  'bootstrap-project: trusted skill directory must be absolute' \
  BOOTSTRAP_PROJECT_SKILL_DIR="$RELATIVE_ROOT/skills/bootstrap-project" \
  HOME="$TMP/home"
assert_relative_resolution_rejected CLAUDE_CONFIG_DIR \
  'bootstrap-project: trusted skill roots must be absolute' \
  BOOTSTRAP_PROJECT_SKILL_DIR= \
  CLAUDE_CONFIG_DIR="$RELATIVE_ROOT" \
  CODEX_HOME="$TMP/missing-codex" \
  KIMI_CODE_HOME="$TMP/missing-kimi" \
  HOME="$TMP/home"
assert_relative_resolution_rejected CODEX_HOME \
  'bootstrap-project: trusted skill roots must be absolute' \
  BOOTSTRAP_PROJECT_SKILL_DIR= \
  CLAUDE_CONFIG_DIR="$TMP/missing-claude" \
  CODEX_HOME="$RELATIVE_ROOT" \
  KIMI_CODE_HOME="$TMP/missing-kimi" \
  HOME="$TMP/home"
assert_relative_resolution_rejected KIMI_CODE_HOME \
  'bootstrap-project: trusted skill roots must be absolute' \
  BOOTSTRAP_PROJECT_SKILL_DIR= \
  CLAUDE_CONFIG_DIR="$TMP/missing-claude" \
  CODEX_HOME="$TMP/missing-codex" \
  KIMI_CODE_HOME="$RELATIVE_ROOT" \
  HOME="$TMP/home"
assert_relative_resolution_rejected HOME-defaults \
  'bootstrap-project: trusted skill roots must be absolute' \
  BOOTSTRAP_PROJECT_SKILL_DIR= \
  CLAUDE_CONFIG_DIR= \
  CODEX_HOME= \
  KIMI_CODE_HOME= \
  HOME="$RELATIVE_ROOT"

# A symbolic-link target fails without changing the link or its destination.
printf '%s\n' 'Destination content.' >"$TMP/destination.md"
cp "$TMP/destination.md" "$TMP/destination.before"
ln -s destination.md "$TMP/link.md"
link_before=$(readlink "$TMP/link.md")
assert_rejected symbolic-link-target 2 \
  'update-managed-block: symbolic-link TARGET is not allowed:' \
  "$MERGE" "$TMP/link.md" "$BLOCK"
test -L "$TMP/link.md"
test "$(readlink "$TMP/link.md")" = "$link_before"
cmp "$TMP/destination.md" "$TMP/destination.before"

FINISH="$ROOT/shared/skills/finish-pr"
CODEX_GATE="$ROOT/codex/skills/claude-gated-development/SKILL.md"
CODEX_GATE_RUNNER="$ROOT/codex/skills/claude-gated-development/scripts/claude-review.sh"
CLAUDE_GATE="$ROOT/claude/skills/codex-gated-development/SKILL.md"
CLAUDE_GATE_RUNNER="$ROOT/claude/skills/codex-gated-development/scripts/codex-review.sh"
test -f "$FINISH/SKILL.md"
grep -Fq 'name: finish-pr' "$FINISH/SKILL.md"
grep -Fq 'type(scope): imperative summary' "$FINISH/SKILL.md"
grep -Fq 'blocks the PR' "$FINISH/SKILL.md"
grep -Fq 'finishing-a-development-branch' "$FINISH/SKILL.md"
grep -Fq 'stops after drafting' "$FINISH/SKILL.md"
grep -Fq 'does not push, merge, synchronize, delete branches, or delete worktrees' "$FINISH/SKILL.md"
grep -Fq 'Finish: use `finish-pr`, then `/finishing-a-development-branch`' \
  "$CLAUDE_GATE"
grep -Fq 'Finish: use `finish-pr`, then `superpowers:finishing-a-development-branch`' \
  "$CODEX_GATE"
grep -Eq '^\| Finish handoff \| After the final code gate clears \| Use `finish-pr`.*before.*branch-finishing workflow\. \|$' \
  "$ROOT/kimi/skills/kimi-gated-development/SKILL.md"
if grep -Eq 'Task tool|TodoWrite|/codex:|/claude:' "$FINISH/SKILL.md"; then
  printf '%s\n' 'finish-pr contains agent-specific commands' >&2
  exit 1
fi

AGENTS="$ROOT/AGENTS.md"
CLAUDE="$ROOT/CLAUDE.md"
PR_TEMPLATE="$ROOT/.github/pull_request_template.md"
DOCS_INDEX="$ROOT/docs/README.md"
ARCHITECTURE_INDEX="$ROOT/docs/architecture/README.md"
OVERVIEW="$ROOT/docs/architecture/01-overview.md"

grep -Fq 'architecture index' "$DOCS_INDEX"
grep -Fq '`docs/architecture/` tracks the current code' "$DOCS_INDEX"
grep -Fq 'docs/plans/' "$DOCS_INDEX"
grep -Fq 'docs/superpowers/' "$DOCS_INDEX"
grep -Fq 'historical design and implementation plans' "$DOCS_INDEX"
grep -Fq 'not authoritative for the current code' "$DOCS_INDEX"
grep -Fq 'evidence-backed module map' "$OVERVIEW"
grep -Fq 'Architecture overviews stay focused on system context' "$OVERVIEW"
grep -Fq 'focused numbered subsystem documents' "$OVERVIEW"
grep -Fq 'at most one durable module may keep readable detail' "$OVERVIEW"
grep -Fq 'existing equivalent current-architecture hierarchy retains authority' "$OVERVIEW"

for file in \
  "$AGENTS" \
  "$CLAUDE" \
  "$PR_TEMPLATE" \
  "$DOCS_INDEX" \
  "$ARCHITECTURE_INDEX" \
  "$OVERVIEW"
do
  test -f "$file"
done

extract_managed_block() {
  source=$1
  destination=$2
  test "$(grep -Fc '<!-- BEGIN bootstrap-project: engineering-standards -->' "$source")" -eq 1
  test "$(grep -Fc '<!-- END bootstrap-project: engineering-standards -->' "$source")" -eq 1
  sed -n \
    '/^<!-- BEGIN bootstrap-project: engineering-standards -->$/,/^<!-- END bootstrap-project: engineering-standards -->$/p' \
    "$source" >"$destination"
}

extract_managed_block "$AGENTS" "$TMP/agents-managed.md"
extract_managed_block "$CLAUDE" "$TMP/claude-managed.md"
cmp "$TMP/agents-managed.md" "$BLOCK"
cmp "$TMP/claude-managed.md" "$BLOCK"
grep -Fq 'sh tests/test-engineering-infrastructure.sh' "$AGENTS"
grep -Fq 'sh tests/test-engineering-infrastructure.sh' "$CLAUDE"

grep -Fq 'sole mandatory external gate' "$CODEX_GATE"
grep -Fq 'Kimi availability, quota, transport failure, a hang, or a missing verdict never blocks the Claude gate' \
  "$CODEX_GATE"
grep -Fq 'KIMI_REVIEW_GRACE_SECONDS' "$CODEX_GATE_RUNNER"
grep -Fq -- '--kimi-risk concurrency' "$CODEX_GATE"
grep -Fq -- '--since <previous-reviewed-head>' "$CODEX_GATE"
grep -Fq 'For incremental reruns, save the reviewed commit, commit the fixes' "$CODEX_GATE"
grep -Fq 'You may use built-in Agent and AgentSwarm subagents.' "$CODEX_GATE_RUNNER"
grep -Fq 'Do not invoke external reviewers or review-gate workflows' "$CODEX_GATE_RUNNER"

grep -Fq 'sole mandatory external gate' "$CLAUDE_GATE"
grep -Fq 'Kimi availability, quota, transport failure, a hang, or a missing verdict never blocks the Codex' \
  "$CLAUDE_GATE"
grep -Fq -- '--kimi-risk concurrency' "$CLAUDE_GATE"
grep -Fq -- '--since <previous-reviewed-head>' "$CLAUDE_GATE"
grep -Fq 'For incremental reruns, save the reviewed commit, commit the fixes' "$CLAUDE_GATE"
grep -Fq 'Risk triggers override artifact type' "$CLAUDE_GATE"
grep -Fq 'Route by concrete risk, not diff size' "$CLAUDE_GATE"
test -x "$CLAUDE_GATE_RUNNER"
test -x "$ROOT/claude/skills/codex-gated-development/scripts/test-codex-review-session.sh"
grep -Fq 'Your tools are restricted to Read, Grep, and Glob.' "$CLAUDE_GATE_RUNNER"
grep -Fq 'Do not invoke external reviewers or review-gate workflows' "$CLAUDE_GATE_RUNNER"
grep -Fq 'KIMI_CODE_EXPERIMENTAL_FLAG=1' "$CLAUDE_GATE_RUNNER"
grep -Fq -- '--ignore-user-config' "$CLAUDE_GATE_RUNNER"
grep -Fq 'End with exactly one machine-readable line: VERDICT: PASS' "$CLAUDE_GATE_RUNNER"

test "$(grep -Fc '<!-- BEGIN bootstrap-project: pull-request-template -->' "$PR_TEMPLATE")" -eq 1
test "$(grep -Fc '<!-- END bootstrap-project: pull-request-template -->' "$PR_TEMPLATE")" -eq 1
previous_line=0
for section in \
  '<!-- BEGIN bootstrap-project: pull-request-template -->' \
  '## Context' \
  '## Behavior before and after' \
  '## Implementation' \
  '## Design decisions and alternatives' \
  '## Documentation and comments' \
  '## Test plan' \
  '## Risk assessment' \
  '## Rollback plan' \
  '## Reviewer guide' \
  '## Follow-up work' \
  '<!-- END bootstrap-project: pull-request-template -->'
do
  test "$(grep -Fxc "$section" "$PR_TEMPLATE")" -eq 1
  line=$(grep -nFx "$section" "$PR_TEMPLATE" | cut -d: -f1)
  test "$line" -gt "$previous_line"
  previous_line=$line
done

grep -Fq 'Source map' "$OVERVIEW"
grep -Fq 'Source map' "$ARCHITECTURE_INDEX"
grep -Fq 'incremental-review-scope.txt' "$OVERVIEW"
grep -Fq -- '--since <previous-reviewed-head>' "$ROOT/README.md"
grep -Fq 'sole mandatory external gate' "$ROOT/README.md"
grep -Fq 'Optional Kimi' "$ROOT/README.md"
if grep -Ern 'POSIX helper|POSIX shell script|POSIX-compatible shell checks' \
  "$ROOT/docs" "$BOOTSTRAP/SKILL.md" >"$TMP/posix-claims"; then
  cat "$TMP/posix-claims" >&2
  exit 1
fi
grep -Fq 'standard macOS/Linux `mktemp`' "$BOOTSTRAP/SKILL.md"
for source_path in \
  'claude/skills/codex-gated-development/' \
  'codex/skills/claude-gated-development/' \
  'kimi/skills/kimi-gated-development/' \
  'shared/skills/bootstrap-project/' \
  'shared/skills/finish-pr/' \
  'tests/test-engineering-infrastructure.sh'
do
  grep -Fq "$source_path" "$OVERVIEW"
done

grep -Fq 'bootstrap-project' "$ROOT/README.md"
grep -Fq 'finish-pr' "$ROOT/README.md"
grep -Fq '.claude/skills' "$ROOT/README.md"
grep -Fq '.codex/skills' "$ROOT/README.md"
grep -Fq '.kimi-code/skills' "$ROOT/README.md"

printf '%s\n' 'engineering infrastructure checks passed'
