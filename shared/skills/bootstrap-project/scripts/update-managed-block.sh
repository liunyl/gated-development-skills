#!/bin/sh
set -eu

fail() {
  printf '%s\n' "update-managed-block: $1" >&2
  exit 2
}

operational_error() {
  printf '%s\n' "update-managed-block: $1" >&2
  exit 3
}

test "$#" -eq 2 || fail 'usage: update-managed-block.sh TARGET BLOCK'

target=$1
block=$2

case $target in
  -*) target=./$target ;;
esac
case $block in
  -*) block=./$block ;;
esac

test -f "$block" && test -r "$block" || fail "invalid BLOCK: $block is not a readable regular file"
test ! -L "$target" || fail "symbolic-link TARGET is not allowed: $target"

if block_markers=$(awk '
  BEGIN { begin_id = "_"; end_id = "_" }
  {
    marker = $0
    sub(/^[[:space:]]*/, "", marker)
    sub(/[[:space:]]*$/, "", marker)
    if (index($0, "<!-- BEGIN bootstrap-project:")) all_begins++
    if (index($0, "<!-- END bootstrap-project:")) all_ends++
    if (marker ~ /^<!-- BEGIN bootstrap-project: [A-Za-z0-9][A-Za-z0-9._-]* -->$/) {
      begins++
      begin_id = marker
      sub(/^<!-- BEGIN bootstrap-project: /, "", begin_id)
      sub(/ -->$/, "", begin_id)
      if (seen_begin || seen_end) invalid_order = 1
      seen_begin = 1
    }
    if (marker ~ /^<!-- END bootstrap-project: [A-Za-z0-9][A-Za-z0-9._-]* -->$/) {
      ends++
      end_id = marker
      sub(/^<!-- END bootstrap-project: /, "", end_id)
      sub(/ -->$/, "", end_id)
      if (!seen_begin || seen_end) invalid_order = 1
      seen_end = 1
    }
  }
  END {
    if (!seen_begin || !seen_end) invalid_order = 1
    print begins + 0, ends + 0, all_begins + 0, all_ends + 0,
      invalid_order + 0, begin_id, end_id
  }
' "$block"); then
  :
else
  operational_error "cannot inspect BLOCK: $block"
fi
set -- $block_markers
begin_lines=$1
end_lines=$2
all_begins=$3
all_ends=$4
test "$begin_lines" -eq 1 && test "$end_lines" -eq 1 &&
  test "$all_begins" -eq 1 && test "$all_ends" -eq 1 ||
  fail 'invalid BLOCK: expected exactly one BEGIN marker and one END marker'

test "$5" -eq 0 || fail 'invalid BLOCK: markers must form one ordered pair'
begin_id=$6
end_id=$7
test "$begin_id" = "$end_id" || fail "invalid BLOCK: marker IDs do not match ($begin_id and $end_id)"

begin="<!-- BEGIN bootstrap-project: $begin_id -->"
end="<!-- END bootstrap-project: $begin_id -->"

action=created
mode=
if test -e "$target"; then
  test -f "$target" || fail "invalid TARGET: $target is not a regular file"
  if mode=$(stat -c '%a' "$target" 2>/dev/null); then
    :
  elif mode=$(stat -f '%Lp' "$target" 2>/dev/null); then
    :
  else
    operational_error "cannot read mode for TARGET: $target"
  fi
  # A matching-ID marker with extra text is ambiguous; fail closed rather than append beside it.
  if counts=$(awk -v begin="$begin" -v end="$end" -v id="$begin_id" '
    function matches_id(marker, keyword, id, offset, relative, start, rest, first, opener, project) {
      opener = "<!--"
      project = "bootstrap-project:"
      offset = 1
      while ((relative = index(substr(marker, offset), opener))) {
        start = offset + relative - 1
        rest = substr(marker, start + length(opener))
        sub(/^[[:space:]]*/, "", rest)
        if (substr(rest, 1, length(keyword)) != keyword) {
          offset = start + length(opener)
          continue
        }
        rest = substr(rest, length(keyword) + 1)
        sub(/^[[:space:]]*/, "", rest)
        if (substr(rest, 1, length(project)) != project) {
          offset = start + length(opener)
          continue
        }
        rest = substr(rest, length(project) + 1)
        sub(/^[[:space:]]*/, "", rest)
        if (substr(rest, 1, length(id)) != id) {
          offset = start + length(opener)
          continue
        }
        rest = substr(rest, length(id) + 1)
        if (rest == "") return 1
        first = substr(rest, 1, 1)
        if (first !~ /[A-Za-z0-9._-]/) return 1
        offset = start + length(opener)
      }
      return 0
    }
    { marker = $0; sub(/^[[:space:]]*/, "", marker); sub(/[[:space:]]*$/, "", marker) }
    matches_id(marker, "BEGIN", id) { raw_begins++ }
    matches_id(marker, "END", id) { raw_ends++ }
    marker == begin { begins++; if (ends) reversed = 1 }
    marker == end { ends++; if (!begins) reversed = 1 }
    END { print begins + 0, ends + 0, reversed + 0, raw_begins + 0, raw_ends + 0 }
  ' "$target"); then
    :
  else
    operational_error "cannot inspect TARGET: $target"
  fi
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
    cat "$block" >"$tmp" || operational_error "cannot render TARGET from BLOCK: $block"
    ;;
  appended)
    {
      cat "$target" &&
      printf '\n' &&
      cat "$block"
    } >"$tmp" || operational_error "cannot render TARGET from BLOCK: $block"
    ;;
  replaced)
    if awk -v begin="$begin" -v end="$end" -v block="$block" '
      { marker = $0; sub(/^[[:space:]]*/, "", marker); sub(/[[:space:]]*$/, "", marker) }
      marker == begin {
        while ((read_status = getline line < block) > 0) print line
        if (read_status < 0) exit 2
        close(block)
        replacing = 1
        next
      }
      replacing && marker == end { replacing = 0; next }
      !replacing { print }
    ' "$target" >"$tmp"; then
      :
    else
      operational_error "cannot render TARGET from BLOCK: $block"
    fi
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
