#!/usr/bin/env bash
# Pure decisions for the Build & Publish workflow.
#
# Every branch that decides *what* gets built lives here rather than in a YAML
# `run:` block, so it can be unit tested (tests/build-matrix.bats). The workflow
# is only the GitHub input/output around these commands.
#
# The image directory list is read from stdin, one per line: `make list-dirs`
# in the workflow, a fixture in the tests. Nothing here touches the network,
# the registry, or the filesystem except where a command names a directory.
#
# Commands:
#   filters                     stdin: dirs        → paths-filter YAML
#   map                         stdin: dirs        → JSON object, key → dir
#   keys                        stdin: dirs        → JSON array of keys
#   matrix <map-json>           stdin: keys JSON   → JSON array of matrix entries
#   resolve-dirs <requested>    stdin: known dirs  → validated dirs, one per line
#   check-digests <n> <dir>     —                  → exits non-zero unless dir holds n files

set -euo pipefail

usage() {
  sed -n '/^# Commands:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

# Filter keys must be plain identifiers, so "." and "/" collapse to "_":
#   python/3.14 → python_3_14 · helm-vector → helm-vector
# The transform is deliberately lossy. Nothing reverses it — `map` carries the
# original directory forward instead.
key_for() {
  printf '%s' "$1" | tr './' '__'
}

# Drop blank lines so a trailing newline in the input is not a phantom entry.
read_dirs() {
  grep -v '^[[:space:]]*$' || true
}

cmd_filters() {
  local dir
  while read -r dir; do
    printf "%s: '%s/**'\n" "$(key_for "$dir")" "$dir"
  done < <(read_dirs)
}

cmd_map() {
  read_dirs | jq -Rsc '
    split("\n") | map(select(length > 0))
    | map({key: gsub("[./]"; "_"), value: .}) | from_entries'
}

cmd_keys() {
  read_dirs | jq -Rsc 'split("\n") | map(select(length > 0) | gsub("[./]"; "_"))'
}

# A key with no entry in the map means the workflow and the image list have
# drifted apart. That is a bug, not an empty build — fail rather than skip.
cmd_matrix() {
  local map=${1:?matrix requires the map JSON as an argument}
  jq -c --argjson map "$map" '
    map(
      ($map[.] // error("unknown filter key: \(.)")) as $dir
      | {
          key: .,
          dir: $dir,
          name: ($dir | split("/")[0]),
          variant: ($dir | split("/")[1] // ""),
        }
    )'
}

cmd_resolve_dirs() {
  local requested=${1:?resolve-dirs requires "all" or a comma-separated list}
  local known dir
  known=$(read_dirs)

  if [ "$requested" = "all" ]; then
    printf '%s\n' "$known"
    return 0
  fi

  local -a wanted=()
  # printf with the trailing newline, not '%s': `read` returns non-zero on a
  # final line with no delimiter, which silently drops the last entry — so
  # "rust,bun/1" would resolve to "rust" alone.
  while read -r dir; do
    [ -n "$dir" ] || continue
    if ! printf '%s\n' "$known" | grep -qxF "$dir"; then
      echo "::error::unknown image directory '$dir'. Known: $(printf '%s' "$known" | tr '\n' ' ')" >&2
      return 1
    fi
    wanted+=("$dir")
  done < <(printf '%s\n' "$requested" | tr ',' '\n' | tr -d '[:blank:]')

  if [ ${#wanted[@]} -eq 0 ]; then
    echo "::error::no image directories requested" >&2
    return 1
  fi
  printf '%s\n' "${wanted[@]}"
}

# Guards the manifest merge. Publishing with fewer digests than architectures
# would put a single-arch image behind a tag consumers read as multi-arch.
cmd_check_digests() {
  local expected=${1:?check-digests requires the expected count}
  local dir=${2:?check-digests requires the digest directory}
  local found

  # Without this, a non-numeric count makes `[ n -ne abc ]` exit 2, which the
  # `if` below reads as false — the guard would pass and publish anything.
  case "$expected" in
    ''|*[!0-9]*)
      echo "::error::expected count must be a positive integer, got '$expected'" >&2
      return 1
      ;;
  esac

  if [ ! -d "$dir" ]; then
    echo "::error::digest directory '$dir' does not exist" >&2
    return 1
  fi

  found=$(find "$dir" -type f | wc -l | tr -d '[:space:]')
  if [ "$found" -ne "$expected" ]; then
    echo "::error::expected $expected per-arch digests, found $found — refusing to publish a partial manifest" >&2
    return 1
  fi
  printf '%s\n' "$found"
}

main() {
  local command=${1:-}
  [ $# -gt 0 ] && shift
  case "$command" in
    filters)       cmd_filters "$@" ;;
    map)           cmd_map "$@" ;;
    keys)          cmd_keys "$@" ;;
    matrix)        cmd_matrix "$@" ;;
    resolve-dirs)  cmd_resolve_dirs "$@" ;;
    check-digests) cmd_check_digests "$@" ;;
    -h|--help)     usage ;;
    *)
      echo "unknown command: '${command}'" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
