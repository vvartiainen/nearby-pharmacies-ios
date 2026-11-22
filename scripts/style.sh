#!/bin/bash
# Check or apply swift-format style to Swift sources.
#
# Usage:
#   scripts/style.sh check [--all | FILE...]   Report violations, change nothing.
#   scripts/style.sh format [--all | FILE...]  Rewrite files in place.
#
# Without file arguments, both commands cover changed Swift files: staged, unstaged
# and untracked, excluding deleted and ignored files. --all covers every tracked
# and untracked, non-ignored Swift file. Set SWIFT_FORMAT to use another binary.

set -uo pipefail

usage() {
  echo "usage: scripts/style.sh check|format [--all | FILE...]" >&2
  exit 64
}

[ $# -ge 1 ] || usage
mode=$1
shift
case "$mode" in
  check | format) ;;
  *) usage ;;
esac

root=$(cd "$(dirname "$0")/.." && pwd -P) || exit 1
cd "$root" || exit 1
scratch=$(mktemp -d "${TMPDIR:-/tmp}/nearby-pharmacies-style.XXXXXX") || exit 1
trap 'rm -f "$scratch/candidates" "$scratch/formatted"; rmdir "$scratch"' EXIT

find_swift_format() {
  if [ -n "${SWIFT_FORMAT:-}" ]; then
    printf '%s\n' "$SWIFT_FORMAT"
    return 0
  fi
  local developer_dir candidate
  if developer_dir=$(xcode-select -p 2>/dev/null); then
    candidate="$developer_dir/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-format"
    if [ -x "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  if candidate=$(xcrun --find swift-format 2>/dev/null) && [ -x "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  command -v swift-format
}

# Prints NUL-separated candidate paths relative to the repository root.
list_candidates() {
  if [ "${1:-}" = "--all" ]; then
    git ls-files -z --cached --others --exclude-standard -- '*.swift'
  else
    git diff --cached --name-only -z --diff-filter=d -- '*.swift' &&
    git diff --name-only -z --diff-filter=d -- '*.swift' &&
    git ls-files -z --others --exclude-standard -- '*.swift'
  fi
}

files=()
add_file() {
  local file=$1
  # Skip deleted, non-regular and ignored paths, including tracked files that
  # now match an ignore rule.
  [ -f "$file" ] && [ ! -L "$file" ] || return 0
  git check-ignore -q --no-index -- "$file" && return 0
  files+=("./$file")
}

if [ $# -eq 0 ] || [ "$1" = "--all" ]; then
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "style.sh: $root is not a Git work tree; pass files explicitly." >&2
    exit 1
  fi
  if ! list_candidates "${1:-}" | sort -zu >"$scratch/candidates"; then
    echo 'style.sh: unable to list Swift files through Git.' >&2
    exit 1
  fi
  while IFS= read -r -d '' file; do
    add_file "$file"
  done <"$scratch/candidates"
else
  for file in "$@"; do
    case "$file" in
      *.swift) ;;
      *) continue ;;
    esac
    directory=$(cd -- "$(dirname -- "$file")" && pwd -P) || exit 1
    file="$directory/${file##*/}"
    case "$file" in
      "$root"/*) add_file "${file#"$root"/}" ;;
      *) printf 'style.sh: path is outside the repository: %s\n' "$file" >&2; exit 1 ;;
    esac
  done
fi

if [ ${#files[@]} -eq 0 ]; then
  echo "style.sh: no Swift files to $mode."
  exit 0
fi

if ! swift_format=$(find_swift_format) || [ -z "$swift_format" ]; then
  echo "style.sh: swift-format not found. Install Xcode 16 or later, or set SWIFT_FORMAT." >&2
  exit 69
fi

config="$root/.swift-format"

if [ "$mode" = "format" ]; then
  # Write through the shell instead of --in-place: swift-format's atomic save
  # needs a temporary directory that agent sandboxes may deny. This also keeps
  # each file's permissions.
  formatted="$scratch/formatted"
  status=0
  changed=0
  for file in "${files[@]}"; do
    if ! "$swift_format" format --configuration "$config" -- "$file" >"$formatted"; then
      status=1
      continue
    fi
    if ! cmp -s "$formatted" "$file"; then
      cat "$formatted" >"$file" || status=1
      changed=$((changed + 1))
      echo "formatted $file"
    fi
  done
  echo "style.sh: $changed of ${#files[@]} Swift file(s) changed. Run scripts/style.sh check for rules formatting cannot fix."
  exit $status
fi

output=$("$swift_format" lint --strict --configuration "$config" -- "${files[@]}" 2>&1)
status=$?
if [ $status -eq 0 ]; then
  echo "style.sh: ${#files[@]} Swift file(s) pass swift-format."
  exit 0
fi

{
  printf '%s\n' "$output"
  echo
  echo "style.sh: swift-format found style violations in the files above."
  echo "Fix formatting with: scripts/style.sh format${1:+ $*}"
  echo "Then rerun: scripts/style.sh check${1:+ $*}"
  echo "Rules that formatting cannot fix, such as naming, need a manual edit."
} >&2
exit 1
