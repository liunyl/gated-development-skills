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
if grep -Eq 'Task tool|TodoWrite|/codex:|/claude:' "$BOOTSTRAP/SKILL.md"; then
  printf '%s\n' 'bootstrap-project contains agent-specific commands' >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
BLOCK="$BOOTSTRAP/assets/project-instructions.md"

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
cat >"$TMP/malformed.md" <<'EOF'
Keep me.
<!-- BEGIN bootstrap-project: engineering-standards -->
Incomplete block.
EOF
cp "$TMP/malformed.md" "$TMP/malformed.before"
if "$MERGE" "$TMP/malformed.md" "$BLOCK" >"$TMP/out" 2>"$TMP/err"; then
  exit 1
else
  test "$?" -eq 2
fi
cmp "$TMP/malformed.md" "$TMP/malformed.before"
test -s "$TMP/err"

cat >"$TMP/trailing-marker-text.md" <<'EOF'
Keep me too.
<!-- BEGIN bootstrap-project: engineering-standards --> invalid
Untrusted content.
<!-- END bootstrap-project: engineering-standards --> invalid
EOF
cp "$TMP/trailing-marker-text.md" "$TMP/trailing-marker-text.before"
if "$MERGE" "$TMP/trailing-marker-text.md" "$BLOCK" >"$TMP/out" 2>"$TMP/err"; then
  exit 1
else
  test "$?" -eq 2
fi
cmp "$TMP/trailing-marker-text.md" "$TMP/trailing-marker-text.before"
test -s "$TMP/err"

cat >"$TMP/duplicate.md" <<'EOF'
<!-- BEGIN bootstrap-project: engineering-standards -->
First.
<!-- END bootstrap-project: engineering-standards -->
<!-- BEGIN bootstrap-project: engineering-standards -->
Second.
<!-- END bootstrap-project: engineering-standards -->
EOF
cp "$TMP/duplicate.md" "$TMP/duplicate.before"
if "$MERGE" "$TMP/duplicate.md" "$BLOCK" >"$TMP/out" 2>"$TMP/err"; then
  exit 1
else
  test "$?" -eq 2
fi
cmp "$TMP/duplicate.md" "$TMP/duplicate.before"
test -s "$TMP/err"

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
  shift
  if (cd "$TARGET_REPO" && env "$@" sh "$RESOLVER" >"$TMP/out" 2>"$TMP/err"); then
    printf '%s\n' "$label: relative path selected a target-repository helper" >&2
    exit 1
  else
    test "$?" -eq 2
  fi
  test -s "$TMP/err"
}

assert_relative_resolution_rejected BOOTSTRAP_PROJECT_SKILL_DIR \
  BOOTSTRAP_PROJECT_SKILL_DIR="$RELATIVE_ROOT/skills/bootstrap-project" \
  HOME="$TMP/home"
assert_relative_resolution_rejected CLAUDE_CONFIG_DIR \
  BOOTSTRAP_PROJECT_SKILL_DIR= \
  CLAUDE_CONFIG_DIR="$RELATIVE_ROOT" \
  CODEX_HOME="$TMP/missing-codex" \
  KIMI_CODE_HOME="$TMP/missing-kimi" \
  HOME="$TMP/home"
assert_relative_resolution_rejected CODEX_HOME \
  BOOTSTRAP_PROJECT_SKILL_DIR= \
  CLAUDE_CONFIG_DIR="$TMP/missing-claude" \
  CODEX_HOME="$RELATIVE_ROOT" \
  KIMI_CODE_HOME="$TMP/missing-kimi" \
  HOME="$TMP/home"
assert_relative_resolution_rejected KIMI_CODE_HOME \
  BOOTSTRAP_PROJECT_SKILL_DIR= \
  CLAUDE_CONFIG_DIR="$TMP/missing-claude" \
  CODEX_HOME="$TMP/missing-codex" \
  KIMI_CODE_HOME="$RELATIVE_ROOT" \
  HOME="$TMP/home"
assert_relative_resolution_rejected HOME-defaults \
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
if "$MERGE" "$TMP/link.md" "$BLOCK" >"$TMP/out" 2>"$TMP/err"; then
  exit 1
else
  test "$?" -eq 2
fi
test -L "$TMP/link.md"
test "$(readlink "$TMP/link.md")" = "$link_before"
cmp "$TMP/destination.md" "$TMP/destination.before"
test -s "$TMP/err"

FINISH="$ROOT/shared/skills/finish-pr"
test -f "$FINISH/SKILL.md"
grep -Fq 'name: finish-pr' "$FINISH/SKILL.md"
grep -Fq 'type(scope): imperative summary' "$FINISH/SKILL.md"
grep -Fq 'blocks the PR' "$FINISH/SKILL.md"
grep -Fq 'finishing-a-development-branch' "$FINISH/SKILL.md"
grep -Fq 'stops after drafting' "$FINISH/SKILL.md"
grep -Fq 'does not push, merge, synchronize, delete branches, or delete worktrees' "$FINISH/SKILL.md"
grep -Eq '^\| 9\. Finish \|.*`finish-pr`.*then.*/finishing-a-development-branch.*\|$' \
  "$ROOT/claude/skills/codex-gated-development/SKILL.md"
grep -Eq '^\| 7\. Finish \|.*`finish-pr`.*then.*`superpowers:finishing-a-development-branch`.*\|$' \
  "$ROOT/codex/skills/claude-gated-development/SKILL.md"
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
