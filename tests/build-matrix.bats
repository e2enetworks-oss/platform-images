#!/usr/bin/env bats
#
# Unit tests for scripts/build-matrix.sh — the decisions the Build & Publish
# workflow makes about what gets built. Each test names the bug it catches.

setup() {
  export REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/build-matrix.sh"
  # The real image set, so the tests move when make/build.mk moves. Exported:
  # the `run bash -c` subshells below cannot see a plain shell variable, and an
  # empty IMAGES would make every "should reject" test pass for the wrong reason.
  IMAGES="$(make -C "$REPO_ROOT" --no-print-directory list-dirs)"
  export IMAGES
  [ -n "$IMAGES" ] || { echo "image set is empty — the fixture is broken"; return 1; }
}

# ── key transform and filter generation ──────────────────────────────────

# Catches: a key transform that drops the dot, so python/3.14 and python/314
# collapse to the same filter and one of them silently never builds.
@test "should collapse dots and slashes to underscores when deriving a key" {
  run bash -c "printf 'python/3.14\n' | '$SCRIPT' keys"
  [ "$status" -eq 0 ]
  [ "$output" = '["python_3_14"]' ]
}

# Catches: a transform that also rewrites hyphens, breaking helm-vector.
@test "should leave hyphens untouched when deriving a key" {
  run bash -c "printf 'helm-vector\n' | '$SCRIPT' keys"
  [ "$status" -eq 0 ]
  [ "$output" = '["helm-vector"]' ]
}

# Catches: an unquoted or mis-globbed filter that matches sibling directories —
# python/3.1 changes would rebuild python/3.14.
@test "should emit one quoted recursive glob per directory when generating filters" {
  run bash -c "printf 'python/3.14\nrust\n' | '$SCRIPT' filters"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "python_3_14: 'python/3.14/**'" ]
  [ "${lines[1]}" = "rust: 'rust/**'" ]
}

# Catches: a map that stores the transformed key as the value, losing the real
# path, so the build job checks out a directory that does not exist.
@test "should preserve the original directory as the map value" {
  run bash -c "printf 'python/3.14\n' | '$SCRIPT' map"
  [ "$status" -eq 0 ]
  [ "$output" = '{"python_3_14":"python/3.14"}' ]
}

# ── matrix construction ──────────────────────────────────────────────────

# Catches: name/variant split that puts the whole path in name, producing the
# tag ghcr.io/.../python/3.14:latest instead of python:3.14-latest.
@test "should split name and variant when the directory has a variant segment" {
  map='{"python_3_14":"python/3.14"}'
  run bash -c "printf '[\"python_3_14\"]' | '$SCRIPT' matrix '$map'"
  [ "$status" -eq 0 ]
  [ "$output" = '[{"key":"python_3_14","dir":"python/3.14","name":"python","variant":"3.14"}]' ]
}

# Catches: a null variant leaking into the tag as "null-latest" for bare dirs.
@test "should set variant to empty string when the directory is bare" {
  map='{"rust":"rust"}'
  run bash -c "printf '[\"rust\"]' | '$SCRIPT' matrix '$map'"
  [ "$status" -eq 0 ]
  [ "$output" = '[{"key":"rust","dir":"rust","name":"rust","variant":""}]' ]
}

# Catches: nothing changed being treated as something changed, rebuilding and
# republishing every image on an unrelated commit.
@test "should produce an empty matrix when no keys changed" {
  map='{"rust":"rust"}'
  run bash -c "printf '[]' | '$SCRIPT' matrix '$map'"
  [ "$status" -eq 0 ]
  [ "$output" = '[]' ]
}

# Catches: workflow filters and make/build.mk drifting apart. Silently skipping
# the unknown key would mean an image quietly stops being published.
@test "should reject a filter key with no directory in the map" {
  map='{"rust":"rust"}'
  run bash -c "printf '[\"ghost\"]' | '$SCRIPT' matrix '$map'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown filter key: ghost"* ]]
}

@test "should reject matrix invoked without a map argument" {
  run bash -c "printf '[]' | '$SCRIPT' matrix"
  [ "$status" -ne 0 ]
}

@test "should reject matrix when the keys input is not valid JSON" {
  map='{"rust":"rust"}'
  run bash -c "printf 'not-json' | '$SCRIPT' matrix '$map'"
  [ "$status" -ne 0 ]
}

# ── workflow_dispatch input resolution ───────────────────────────────────

@test "should return every known directory when requested is all" {
  run bash -c "printf '%s\n' \"\$IMAGES\" | '$SCRIPT' resolve-dirs all"
  [ "$status" -eq 0 ]
  [ "$output" = "$IMAGES" ]
}

@test "should return only the requested subset when given a comma-separated list" {
  run bash -c "printf '%s\n' \"\$IMAGES\" | '$SCRIPT' resolve-dirs 'rust,bun/1.4'"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "rust" ]
  [ "${lines[1]}" = "bun/1.4" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "should tolerate whitespace around comma-separated entries" {
  run bash -c "printf '%s\n' \"\$IMAGES\" | '$SCRIPT' resolve-dirs ' rust , bun/1.4 '"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
}

# Catches: a typo in the dispatch input silently building nothing, so the
# operator believes they republished an image they did not.
@test "should reject an unknown image directory" {
  run bash -c "printf '%s\n' \"\$IMAGES\" | '$SCRIPT' resolve-dirs 'rus'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown image directory 'rus'"* ]]
}

# Catches: substring matching, where 'python/3.1' would be accepted and then
# resolve to a directory that does not exist.
@test "should reject a directory name that is only a prefix of a known one" {
  run bash -c "printf '%s\n' \"\$IMAGES\" | '$SCRIPT' resolve-dirs 'python/3.1'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown image directory"* ]]
}

@test "should reject a directory that differs only by case" {
  run bash -c "printf '%s\n' \"\$IMAGES\" | '$SCRIPT' resolve-dirs 'Rust'"
  [ "$status" -ne 0 ]
}

@test "should reject a requested list containing only separators" {
  run bash -c "printf '%s\n' \"\$IMAGES\" | '$SCRIPT' resolve-dirs ',,,'"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no image directories requested"* ]]
}

@test "should reject resolve-dirs invoked without an argument" {
  run bash -c "printf '%s\n' \"\$IMAGES\" | '$SCRIPT' resolve-dirs"
  [ "$status" -ne 0 ]
}

# ── digest guard for the manifest merge ──────────────────────────────────

@test "should report the digest count when it matches the architecture count" {
  mkdir -p "$BATS_TEST_TMPDIR/d" && touch "$BATS_TEST_TMPDIR/d/aaa" "$BATS_TEST_TMPDIR/d/bbb"
  run "$SCRIPT" check-digests 2 "$BATS_TEST_TMPDIR/d"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

# Catches THE bug this guard exists for: one architecture's build failed, and
# the merge publishes an amd64-only image under a tag read as multi-arch.
@test "should refuse to publish when fewer digests than architectures" {
  mkdir -p "$BATS_TEST_TMPDIR/d" && touch "$BATS_TEST_TMPDIR/d/only-one"
  run "$SCRIPT" check-digests 2 "$BATS_TEST_TMPDIR/d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"found 1"* ]]
  [[ "$output" == *"refusing to publish a partial manifest"* ]]
}

# Catches: stale artifacts from a previous attempt being merged in alongside
# the current ones, producing a manifest with duplicate architectures.
@test "should refuse to publish when more digests than architectures" {
  mkdir -p "$BATS_TEST_TMPDIR/d" && touch "$BATS_TEST_TMPDIR/d/a" "$BATS_TEST_TMPDIR/d/b" "$BATS_TEST_TMPDIR/d/c"
  run "$SCRIPT" check-digests 2 "$BATS_TEST_TMPDIR/d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"found 3"* ]]
}

# Catches: an artifact download that silently produced nothing, which without
# this check would reach `imagetools create` with no sources at all.
@test "should refuse to publish when the digest directory is empty" {
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  run "$SCRIPT" check-digests 2 "$BATS_TEST_TMPDIR/empty"
  [ "$status" -ne 0 ]
  [[ "$output" == *"found 0"* ]]
}

@test "should fail when the digest directory does not exist" {
  run "$SCRIPT" check-digests 2 "$BATS_TEST_TMPDIR/absent"
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist"* ]]
}

# Catches: `[ n -ne abc ]` exits 2, which `if` reads as false — so a garbage
# expected count would fall straight through the guard and publish anything.
@test "should reject a non-numeric expected architecture count" {
  mkdir -p "$BATS_TEST_TMPDIR/d" && touch "$BATS_TEST_TMPDIR/d/a"
  run "$SCRIPT" check-digests "two" "$BATS_TEST_TMPDIR/d"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must be a positive integer"* ]]
}

@test "should reject check-digests invoked without a directory argument" {
  run "$SCRIPT" check-digests 2
  [ "$status" -ne 0 ]
}

# ── input hygiene and command surface ────────────────────────────────────

# Catches: a trailing newline in `make list-dirs` becoming a phantom empty
# image directory in the matrix.
@test "should ignore blank lines and trailing newlines in the image list" {
  run bash -c "printf 'rust\n\n\nbun/1.4\n\n' | '$SCRIPT' keys"
  [ "$status" -eq 0 ]
  [ "$output" = '["rust","bun_1_4"]' ]
}

@test "should handle a single directory" {
  run bash -c "printf 'rust\n' | '$SCRIPT' filters"
  [ "$status" -eq 0 ]
  [ "$output" = "rust: 'rust/**'" ]
}

@test "should exit non-zero on an unknown command" {
  run "$SCRIPT" not-a-command
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown command"* ]]
}

@test "should exit non-zero when invoked with no command" {
  run "$SCRIPT"
  [ "$status" -eq 2 ]
}

# ── regression: pin the generated output against the real image set ──────

# Golden. The workflow used to carry a hand-written filter list; this pins the
# generated equivalent. A diff here means the image set or the key transform
# changed — explain why before re-blessing.
@test "should generate filters matching the pinned golden file" {
  run bash -c "printf '%s\n' \"\$IMAGES\" | '$SCRIPT' filters"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$REPO_ROOT/tests/golden/filters.txt")" ]
}

@test "should generate a map matching the pinned golden file" {
  run bash -c "printf '%s\n' \"\$IMAGES\" | '$SCRIPT' map"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$REPO_ROOT/tests/golden/map.json")" ]
}

# Every key the filters generate must resolve through the map. This is the
# invariant that the two generated artifacts stay consistent with each other.
@test "should resolve every generated key through the generated map" {
  keys=$(printf '%s\n' "$IMAGES" | "$SCRIPT" keys)
  map=$(printf '%s\n' "$IMAGES" | "$SCRIPT" map)
  run bash -c "printf '%s' '$keys' | '$SCRIPT' matrix '$map'"
  [ "$status" -eq 0 ]
  count=$(printf '%s' "$output" | jq 'length')
  [ "$count" -eq "$(printf '%s\n' "$IMAGES" | wc -l | tr -d ' ')" ]
}

# ── make targets changed in this diff ────────────────────────────────────

@test "should print every image directory one per line from make list-dirs" {
  run make -C "$REPO_ROOT" --no-print-directory list-dirs
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 7 ]
  [[ "$output" == *"python/3.11"* ]]
  [[ "$output" == *"python/3.12"* ]]
  [[ "$output" == *"bun/1.4"* ]]
}

# Catches the bug the new default arm fixes: an image added to IMAGES with no
# smoke-test case ran `sh -c ""` and reported success.
@test "should fail make test when the image has no smoke-test case" {
  run make -C "$REPO_ROOT" --no-print-directory test IMAGE=ghost IMAGES=ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"no smoke test defined"* ]]
}

@test "should reject make test for an image outside the image set" {
  run make -C "$REPO_ROOT" --no-print-directory test IMAGE=nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown IMAGE"* ]]
}
