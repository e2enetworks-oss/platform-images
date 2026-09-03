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
#   version <file>              —                  → validated x.y.z version
#   image-version <dir> [file]  —                  → required/optional image version
#   build-arg <dir> [version]   —                  → image-specific Docker build argument
#   tags <repo> <variant> <sha7> [version]          → immutable and moving tags
#   build-output <publish> <event> <repo> <key> <arch> <sha7>

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
  # "rust,bun/1.4" would resolve to "rust" alone.
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

valid_version() {
  [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

# VERSION files are deliberately strict. Hidden carriage returns or extra
# lines can create a different registry tag locally than in GitHub Actions.
cmd_version() {
  local file=${1:?version requires a file path}
  local version

  if [ ! -f "$file" ]; then
    echo "::error::version file '$file' does not exist" >&2
    return 1
  fi
  IFS= read -r version < "$file" || true
  if [[ "$version" == *$'\r'* ]]; then
    echo "::error::version file must contain one x.y.z line with a Unix newline" >&2
    return 1
  fi
  if ! valid_version "$version"; then
    echo "::error::version must use x.y.z format, got '$version'" >&2
    return 1
  fi
  if ! cmp -s "$file" <(printf '%s\n' "$version"); then
    echo "::error::version file must contain one x.y.z line with a Unix newline" >&2
    return 1
  fi
  printf '%s\n' "$version"
}

# Rust uses VERSION for both its base image and published tag. Other images may
# omit the file and keep their directory-derived or hash-only tag scheme.
cmd_image_version() {
  local dir=${1:?image-version requires an image directory}
  local file=${2:-${dir}/VERSION}

  if [ -f "$file" ]; then
    cmd_version "$file"
    return
  fi
  if [ "$dir" = "rust" ]; then
    echo "::error::Rust requires a VERSION file at '$file'" >&2
    return 1
  fi
}

# Keep image-specific build inputs beside version resolution so local Make and
# GitHub Actions cannot choose different Rust base images.
cmd_build_arg() {
  local dir=${1:?build-arg requires an image directory}
  local version=${2-}

  if [ "$dir" != "rust" ]; then
    return
  fi
  if [ -z "$version" ]; then
    echo "::error::Rust requires a resolved build version" >&2
    return 1
  fi
  if ! valid_version "$version"; then
    echo "::error::version must use x.y.z format, got '$version'" >&2
    return 1
  fi
  printf 'RUST_VERSION=%s\n' "$version"
}

# A VERSION file gives a bare image a readable immutable tag while preserving
# its unqualified latest tag. Variant directories keep their existing tags.
cmd_tags() {
  local repo=${1:?tags requires the image repository}
  local variant=${2-}
  local sha=${3:?tags requires a seven-character commit hash}
  local version=${4-}
  local immutable_prefix moving_prefix

  if [[ "$repo" =~ [[:space:]] ]]; then
    echo "::error::image repository must not contain whitespace" >&2
    return 1
  fi
  if [ "$sha" != "dev" ] && [[ ! "$sha" =~ ^[0-9a-f]{7}$ ]]; then
    echo "::error::commit hash must be seven lowercase hexadecimal characters or 'dev'" >&2
    return 1
  fi
  if [ -n "$version" ] && ! valid_version "$version"; then
    echo "::error::version must use x.y.z format, got '$version'" >&2
    return 1
  fi
  if [ -n "$version" ] && [ -n "$variant" ]; then
    echo "::error::version and directory variant cannot both set the tag prefix" >&2
    return 1
  fi

  immutable_prefix=${version:-$variant}
  moving_prefix=$variant
  printf '%s:%s%s\n' "$repo" "${immutable_prefix:+${immutable_prefix}-}" "$sha"
  printf '%s:%slatest\n' "$repo" "${moving_prefix:+${moving_prefix}-}"
}

# Pull requests need a local image for Trivy. Published builds keep pushing by
# digest so the merge job can join the native architecture results safely.
cmd_build_output() {
  local publish=${1:?build-output requires true or false}
  local event=${2:?build-output requires an event name}
  local repo=${3:?build-output requires the image repository}
  local key=${4:?build-output requires the image key}
  local arch=${5:?build-output requires the architecture}
  local sha=${6:?build-output requires a seven-character commit hash}
  local image_ref

  if [ "$publish" != "true" ] && [ "$publish" != "false" ]; then
    echo "::error::publish must be true or false" >&2
    return 1
  fi
  if [[ "$repo" =~ [[:space:]] ]] || [[ ! "$key" =~ ^[a-zA-Z0-9_.-]+$ ]] \
    || [[ ! "$arch" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
    echo "::error::repository, key, and architecture must be safe image identifiers" >&2
    return 1
  fi
  if [[ ! "$sha" =~ ^[0-9a-f]{7}$ ]]; then
    echo "::error::commit hash must be seven lowercase hexadecimal characters" >&2
    return 1
  fi

  if [ "$publish" = "true" ]; then
    printf 'spec=type=image,name=%s,push-by-digest=true,name-canonical=true,push=true\n' "$repo"
    printf 'image_ref=\n'
  elif [ "$event" = "pull_request" ]; then
    image_ref="${repo}:scan-${key}-${arch}-${sha}"
    printf 'spec=type=docker,name=%s\n' "$image_ref"
    printf 'image_ref=%s\n' "$image_ref"
  else
    printf 'spec=type=cacheonly\n'
    printf 'image_ref=\n'
  fi
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
    version)       cmd_version "$@" ;;
    image-version) cmd_image_version "$@" ;;
    build-arg)     cmd_build_arg "$@" ;;
    tags)          cmd_tags "$@" ;;
    build-output)  cmd_build_output "$@" ;;
    -h|--help)     usage ;;
    *)
      echo "unknown command: '${command}'" >&2
      usage >&2
      return 2
      ;;
  esac
}

main "$@"
