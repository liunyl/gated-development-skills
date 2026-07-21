#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
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
  actual=$($MERGE "$@")
  test "$actual" = "$expected"
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
test_action replaced "$TMP/replace.md" "$BLOCK"
cmp "$TMP/replace.md" "$TMP/replace.expected"
test "$(grep -Fc '<!-- BEGIN bootstrap-project: engineering-standards -->' "$TMP/replace.md")" -eq 1
test "$(grep -Fc '<!-- END bootstrap-project: engineering-standards -->' "$TMP/replace.md")" -eq 1

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
grep -Fq 'finish-pr' "$ROOT/claude/skills/codex-gated-development/SKILL.md"
grep -Fq 'finish-pr' "$ROOT/codex/skills/claude-gated-development/SKILL.md"
grep -Fq 'finish-pr' "$ROOT/kimi/skills/kimi-gated-development/SKILL.md"
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
