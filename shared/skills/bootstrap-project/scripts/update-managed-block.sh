#!/bin/sh
set -eu

fail() {
  printf '%s\n' "update-managed-block: $1" >&2
  exit 2
}

test "$#" -eq 2 || fail 'usage: update-managed-block.sh TARGET BLOCK'

target=$1
block=$2

test -f "$block" && test -r "$block" || fail "invalid BLOCK: $block is not a readable regular file"
test ! -L "$target" || fail "symbolic-link TARGET is not allowed: $target"

begin_lines=$(grep -Ec '^[[:space:]]*<!-- BEGIN bootstrap-project: [A-Za-z0-9][A-Za-z0-9._-]* -->[[:space:]]*$' "$block" || true)
end_lines=$(grep -Ec '^[[:space:]]*<!-- END bootstrap-project: [A-Za-z0-9][A-Za-z0-9._-]* -->[[:space:]]*$' "$block" || true)
all_begins=$(grep -Fc '<!-- BEGIN bootstrap-project:' "$block" || true)
all_ends=$(grep -Fc '<!-- END bootstrap-project:' "$block" || true)
test "$begin_lines" -eq 1 && test "$end_lines" -eq 1 &&
  test "$all_begins" -eq 1 && test "$all_ends" -eq 1 ||
  fail 'invalid BLOCK: expected exactly one BEGIN marker and one END marker'

begin=$(grep -E '^[[:space:]]*<!-- BEGIN bootstrap-project: [A-Za-z0-9][A-Za-z0-9._-]* -->[[:space:]]*$' "$block")
end=$(grep -E '^[[:space:]]*<!-- END bootstrap-project: [A-Za-z0-9][A-Za-z0-9._-]* -->[[:space:]]*$' "$block")
begin_id=${begin#*'<!-- BEGIN bootstrap-project: '}
begin_id=${begin_id%%' -->'*}
end_id=${end#*'<!-- END bootstrap-project: '}
end_id=${end_id%%' -->'*}
test "$begin_id" = "$end_id" || fail "invalid BLOCK: marker IDs do not match ($begin_id and $end_id)"

begin="<!-- BEGIN bootstrap-project: $begin_id -->"
end="<!-- END bootstrap-project: $begin_id -->"
awk -v begin="$begin" -v end="$end" '
  { marker = $0; sub(/^[[:space:]]*/, "", marker); sub(/[[:space:]]*$/, "", marker) }
  marker == begin { if (seen_begin || seen_end) exit 1; seen_begin = 1 }
  marker == end { if (!seen_begin || seen_end) exit 1; seen_end = 1 }
  END { if (!seen_begin || !seen_end) exit 1 }
' "$block" || fail 'invalid BLOCK: markers must form one ordered pair'

action=created
mode=
if test -e "$target"; then
  test -f "$target" || fail "invalid TARGET: $target is not a regular file"
  mode=$(stat -c '%a' "$target" 2>/dev/null || stat -f '%Lp' "$target") ||
    fail "invalid TARGET: cannot read mode for $target"
  # A matching-ID marker with extra text is ambiguous; fail closed rather than append beside it.
  counts=$(awk -v begin="$begin" -v end="$end" '
    { marker = $0; sub(/^[[:space:]]*/, "", marker); sub(/[[:space:]]*$/, "", marker) }
    index($0, begin) { raw_begins++ }
    index($0, end) { raw_ends++ }
    marker == begin { begins++; if (ends) reversed = 1 }
    marker == end { ends++; if (!begins) reversed = 1 }
    END { print begins + 0, ends + 0, reversed + 0, raw_begins + 0, raw_ends + 0 }
  ' "$target")
  set -- $counts
  if test "$4" -ne "$1" || test "$5" -ne "$2"; then
    fail "invalid TARGET: malformed or duplicate markers for $begin_id"
  elif test "$1" -eq 0 && test "$2" -eq 0; then
    action=appended
  elif test "$1" -eq 1 && test "$2" -eq 1 && test "$3" -eq 0; then
    action=replaced
  else
    fail "invalid TARGET: malformed or duplicate markers for $begin_id"
  fi
fi

dir=$(dirname "$target")
# Render beside the target, then restore its mode before atomic replacement so failures leave it intact.
tmp=$(mktemp "$dir/.bootstrap-project.XXXXXX")
trap 'rm -f "$tmp"' EXIT HUP INT TERM

case $action in
  created)
    cat "$block" >"$tmp"
    ;;
  appended)
    {
      cat "$target"
      printf '\n'
      cat "$block"
    } >"$tmp"
    ;;
  replaced)
    awk -v begin="$begin" -v end="$end" -v block="$block" '
      { marker = $0; sub(/^[[:space:]]*/, "", marker); sub(/[[:space:]]*$/, "", marker) }
      marker == begin {
        while ((getline line < block) > 0) print line
        close(block)
        replacing = 1
        next
      }
      replacing && marker == end { replacing = 0; next }
      !replacing { print }
    ' "$target" >"$tmp"
    ;;
esac

if test "$action" = created; then
  chmod 0644 "$tmp"
else
  chmod "$mode" "$tmp"
fi

mv "$tmp" "$target"
trap - EXIT HUP INT TERM
printf '%s\n' "$action"
