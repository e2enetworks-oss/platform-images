#!/usr/bin/env bats
# Unit tests for immutable and moving image-tag decisions.

setup() {
  export REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export SCRIPT="$REPO_ROOT/scripts/build-matrix.sh"
  export WORKFLOW="$REPO_ROOT/.github/workflows/build.yml"
}

# Catches: Rust publishing a hash-only tag that hides its compiler version.
@test "should prefix a bare image immutable tag with its version" {
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/rust "" e6f4b3d 1.98.0
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ghcr.io/e2enetworks-oss/rust:1.98.0-e6f4b3d" ]
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
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/rust "" e6f4b3d 1.98
  [ "$status" -ne 0 ]
  [[ "$output" == *"version must use x.y.z format"* ]]
}

@test "should read one strict version line" {
  printf '1.98.0\n' > "$BATS_TEST_TMPDIR/VERSION"
  run "$SCRIPT" version "$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -eq 0 ]
  [ "$output" = "1.98.0" ]
}

@test "should reject a version file with carriage returns" {
  printf '1.98.0\r\n' > "$BATS_TEST_TMPDIR/VERSION"
  run "$SCRIPT" version "$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -ne 0 ]
  [[ "$output" == *"one x.y.z line with a Unix newline"* ]]
}

@test "should reject a version file with extra lines" {
  printf '1.98.0\n2.0.0\n' > "$BATS_TEST_TMPDIR/VERSION"
  run "$SCRIPT" version "$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -ne 0 ]
  [[ "$output" == *"one x.y.z line with a Unix newline"* ]]
}

@test "should reject a malformed version file" {
  printf '1.98\n' > "$BATS_TEST_TMPDIR/VERSION"
  run "$SCRIPT" version "$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -ne 0 ]
  [[ "$output" == *"version must use x.y.z format"* ]]
}

@test "should reject a version combined with a directory variant" {
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/rust 1.98 e6f4b3d 1.98.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot both set the tag prefix"* ]]
}

@test "should reject a commit hash with the wrong shape" {
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/rust "" not-a-sha 1.98.0
  [ "$status" -ne 0 ]
  [[ "$output" == *"seven lowercase hexadecimal characters"* ]]
}

@test "should allow the local development tag outside a Git checkout" {
  run "$SCRIPT" tags ghcr.io/e2enetworks-oss/rust "" dev 1.98.0
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "ghcr.io/e2enetworks-oss/rust:1.98.0-dev" ]
  [ "${lines[1]}" = "ghcr.io/e2enetworks-oss/rust:latest" ]
}

@test "should require the Rust version file" {
  run "$SCRIPT" image-version rust "$BATS_TEST_TMPDIR/missing-version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Rust requires a VERSION file"* ]]
}

@test "should allow an unversioned bare image without a version file" {
  run "$SCRIPT" image-version helm-vector "$BATS_TEST_TMPDIR/missing-version"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "should require the Rust build version as an external build argument" {
  run grep -Fx "ARG RUST_VERSION" "$REPO_ROOT/rust/Dockerfile"
  [ "$status" -eq 0 ]
}

@test "should use the Rust build version in each base image" {
  run grep -Fc 'FROM mirror.gcr.io/library/rust:${RUST_VERSION}-slim-trixie' \
    "$REPO_ROOT/rust/Dockerfile"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

@test "should resolve the Rust Docker build argument" {
  run "$SCRIPT" build-arg rust 1.98.0
  [ "$status" -eq 0 ]
  [ "$output" = "RUST_VERSION=1.98.0" ]
}

@test "should require a resolved Rust Docker build version" {
  run "$SCRIPT" build-arg rust ""
  [ "$status" -ne 0 ]
  [[ "$output" == *"Rust requires a resolved build version"* ]]
}

@test "should reject a malformed Rust Docker build version" {
  run "$SCRIPT" build-arg rust 1.98
  [ "$status" -ne 0 ]
  [[ "$output" == *"version must use x.y.z format"* ]]
}

@test "should omit Docker build arguments for other images" {
  run "$SCRIPT" build-arg helm-vector ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
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
  printf '1.98\n' > "$BATS_TEST_TMPDIR/VERSION"
  run make -C "$REPO_ROOT" --no-print-directory build \
    IMAGE=rust DOCKER=true VERSION_FILE="$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -ne 0 ]
  [[ "$output" == *"version must use x.y.z format"* ]]
}

@test "should stop a Make build when the Rust version file is missing" {
  run make -C "$REPO_ROOT" --no-print-directory build \
    IMAGE=rust DOCKER=true VERSION_FILE="$BATS_TEST_TMPDIR/missing-version"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Rust requires a VERSION file"* ]]
}

@test "should pass the Rust version file value to Docker" {
  printf '1.98.0\n' > "$BATS_TEST_TMPDIR/VERSION"
  run make -C "$REPO_ROOT" --no-print-directory build \
    IMAGE=rust DOCKER=echo VERSION_FILE="$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--build-arg RUST_VERSION=1.98.0"* ]]
  [[ "$output" == *"rust:1.98.0-"* ]]
}

@test "should pass the Rust version file value to a multi-architecture push" {
  printf '1.98.0\n' > "$BATS_TEST_TMPDIR/VERSION"
  run make -C "$REPO_ROOT" --no-print-directory push \
    IMAGE=rust DOCKER=echo GH=true PLATFORMS=linux/amd64 \
    VERSION_FILE="$BATS_TEST_TMPDIR/VERSION"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--build-arg RUST_VERSION=1.98.0"* ]]
  [[ "$output" == *"rust:1.98.0-"* ]]
  [[ "$output" == *"--platform linux/amd64"* ]]
  [[ "$output" == *"--push"* ]]
}

@test "should pass the resolved Rust version into GitHub Actions builds" {
  block=$(sed -n '/name: Resolve build output and cache refs/,/name: Report Critical vulnerabilities/p' "$WORKFLOW")
  [[ "$block" == *'DIR: ${{ matrix.image.dir }}'* ]]
  [[ "$block" == *'version=$(scripts/build-matrix.sh image-version "$DIR")'* ]]
  [[ "$block" == *'build_args=$(scripts/build-matrix.sh build-arg "$DIR" "$version")'* ]]
  [[ "$block" == *'echo "build_args=${build_args}"'* ]]
  [[ "$block" == *'build-args: ${{ steps.out.outputs.build_args }}'* ]]
}

@test "should require the image version before publishing manifest tags" {
  block=$(sed -n '/name: Create and push the multi-arch manifest/,$p' "$WORKFLOW")
  [[ "$block" == *'DIR: ${{ matrix.image.dir }}'* ]]
  [[ "$block" == *'version=$(scripts/build-matrix.sh image-version "$DIR")'* ]]
  [[ "$block" != *'if [ -f "${DIR}/VERSION" ]'* ]]
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

@test "should scan the repository for secrets with redacted Gitleaks output" {
  block=$(sed -n '/^  gitleaks:/,/^  build:/p' "$WORKFLOW")
  [[ "$block" == *"zricethezav/gitleaks:v8.24.2@sha256:b5918eb91b8d2473cec722f066abb4352e4ffdc4ec9f4283ec143aba9ec9ebc4"* ]]
  [[ "$block" == *"dir . --redact --exit-code 1 --no-banner"* ]]
}

@test "should require Gitleaks before building or publishing images" {
  [[ $(grep -c '^    needs: \[changes, gitleaks\]$' "$WORKFLOW") -eq 1 ]]
  [[ $(grep -c '^    needs: \[changes, gitleaks, build\]$' "$WORKFLOW") -eq 1 ]]
  [[ $(grep -c "needs.gitleaks.result == 'success'" "$WORKFLOW") -eq 1 ]]
}
