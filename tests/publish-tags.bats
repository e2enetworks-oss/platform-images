#!/usr/bin/env bats
# Unit tests for immutable and moving image-tag decisions.

setup() {
  export REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/build-matrix.sh"
  export WORKFLOW="$REPO_ROOT/.github/workflows/build.yml"
}

# Catches: Rust publishing a hash-only tag that hides its compiler version.
@test "should prefix a bare image immutable tag with its version" {
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/rust "" e6f4b3d 1.97.1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ghcr.io/e2enetworks-oss/rust:1.97.1-e6f4b3d" ]
  [ "${lines[1]}" = "ghcr.io/e2enetworks-oss/rust:latest" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "should preserve variant tags for versioned image families" {
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/python 3.14 e6f4b3d
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ghcr.io/e2enetworks-oss/python:3.14-e6f4b3d" ]
  [ "${lines[1]}" = "ghcr.io/e2enetworks-oss/python:3.14-latest" ]
}

@test "should preserve hash-only tags for bare images without a version" {
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/helm-vector "" e6f4b3d
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ghcr.io/e2enetworks-oss/helm-vector:e6f4b3d" ]
  [ "${lines[1]}" = "ghcr.io/e2enetworks-oss/helm-vector:latest" ]
}

@test "should reject a malformed image version" {
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/rust "" e6f4b3d 1.97
  [ "$status" -ne 0 ]
  [[ "$output" == *"version must use x.y.z format"* ]]
}

@test "should read one strict version line" {
  printf '1.97.1\n' > "$BATS_TEST_TMPDIR/VERSION"
  run "$SCRIPT" version "$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -eq 0 ]
  [ "$output" = "1.97.1" ]
}

@test "should reject a version file with carriage returns" {
  printf '1.97.1\r\n' > "$BATS_TEST_TMPDIR/VERSION"
  run "$SCRIPT" version "$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -ne 0 ]
  [[ "$output" == *"one x.y.z line with a Unix newline"* ]]
}

@test "should reject a version file with extra lines" {
  printf '1.97.1\n2.0.0\n' > "$BATS_TEST_TMPDIR/VERSION"
  run "$SCRIPT" version "$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -ne 0 ]
  [[ "$output" == *"one x.y.z line with a Unix newline"* ]]
}

@test "should reject a malformed version file" {
  printf '1.97\n' > "$BATS_TEST_TMPDIR/VERSION"
  run "$SCRIPT" version "$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -ne 0 ]
  [[ "$output" == *"version must use x.y.z format"* ]]
}

@test "should reject a version combined with a directory variant" {
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/rust 1.97 e6f4b3d 1.97.1
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot both set the tag prefix"* ]]
}

@test "should reject a commit hash with the wrong shape" {
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/rust "" not-a-sha 1.97.1
  [ "$status" -ne 0 ]
  [[ "$output" == *"seven lowercase hexadecimal characters"* ]]
}

@test "should allow the local development tag outside a Git checkout" {
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/rust "" dev 1.97.1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ghcr.io/e2enetworks-oss/rust:1.97.1-dev" ]
  [ "${lines[1]}" = "ghcr.io/e2enetworks-oss/rust:latest" ]
}

@test "should keep the Rust version file aligned with the Dockerfile" {
  version=$("$SCRIPT" version "$REPO_ROOT/rust/VERSION")
  run grep -Fx "ARG RUST_VERSION=$version" "$REPO_ROOT/rust/Dockerfile"
  [ "$status" -eq 0 ]
}

@test "should list a versioned immutable Rust tag and unqualified latest tag" {
  sha=$(git -C "$REPO_ROOT" rev-parse HEAD | cut -c1-7)
  version=$("$SCRIPT" version "$REPO_ROOT/rust/VERSION")
  run make -C "$REPO_ROOT" --no-print-directory list
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghcr.io/e2enetworks-oss/rust:${version}-${sha}"* ]]
  [[ "$output" == *"ghcr.io/e2enetworks-oss/rust:latest"* ]]
  [[ "$output" != *"ghcr.io/e2enetworks-oss/rust:${sha}"* ]]
}

@test "should stop a Make build when the version file is invalid" {
  printf '1.97\n' > "$BATS_TEST_TMPDIR/VERSION"
  run make -C "$REPO_ROOT" --no-print-directory build \
    IMAGE=rust DOCKER=true VERSION_FILE="$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -ne 0 ]
  [[ "$output" == *"version must use x.y.z format"* ]]
}

@test "should use a local Docker image output for pull request scans" {
  run "$SCRIPT" build-output false pull_request \
    ghcr.io/e2enetworks-oss/rust rust arm64 e6f4b3d
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "spec=type=docker,name=ghcr.io/e2enetworks-oss/rust:scan-rust-arm64-e6f4b3d" ]
  [ "${lines[1]}" = "image_ref=ghcr.io/e2enetworks-oss/rust:scan-rust-arm64-e6f4b3d" ]
}

@test "should keep digest output for published builds" {
  run "$SCRIPT" build-output true push \
    ghcr.io/e2enetworks-oss/rust rust amd64 e6f4b3d
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "spec=type=image,name=ghcr.io/e2enetworks-oss/rust,push-by-digest=true,name-canonical=true,push=true" ]
  [ "${lines[1]}" = "image_ref=" ]
}

@test "should keep cache-only output for manual branch builds" {
  run "$SCRIPT" build-output false workflow_dispatch \
    ghcr.io/e2enetworks-oss/rust rust amd64 e6f4b3d
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "spec=type=cacheonly" ]
  [ "${lines[1]}" = "image_ref=" ]
}

@test "should reject an invalid publish decision" {
  run "$SCRIPT" build-output maybe pull_request \
    ghcr.io/e2enetworks-oss/rust rust amd64 e6f4b3d
  [ "$status" -ne 0 ]
  [[ "$output" == *"publish must be true or false"* ]]
}

@test "should report every Critical finding without failing the report step" {
  block=$(sed -n '/name: Report Critical vulnerabilities/,/name: Block fixable Critical vulnerabilities/p' "$WORKFLOW")
  [[ "$block" == *"aquasecurity/trivy-action@ed142fd0673e97e23eac54620cfb913e5ce36c25"* ]]
  [[ "$block" == *"ignore-unfixed: false"* ]]
  [[ "$block" == *"exit-code: 0"* ]]
}

@test "should fail pull requests only for fixable Critical findings" {
  block=$(sed -n '/name: Block fixable Critical vulnerabilities/,/name: Export digest/p' "$WORKFLOW")
  [[ "$block" == *"if: github.event_name == 'pull_request'"* ]]
  [[ "$block" == *"ignore-unfixed: true"* ]]
  [[ "$block" == *"exit-code: 1"* ]]
}
