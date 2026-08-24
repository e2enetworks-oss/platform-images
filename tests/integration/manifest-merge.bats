#!/usr/bin/env bats
#
# Integration tests for the publish path: per-architecture push-by-digest, then
# `docker buildx imagetools create` joining those digests into one multi-arch
# manifest.
#
# Why these exist: in the workflow that sequence only runs on a push to main.
# A pull request never reaches it, so without these tests the first execution
# of the merge would be against real tags in the real registry.
#
# Real docker, real buildx, real registry (registry:2 on localhost). Nothing is
# mocked — a mocked registry would not reproduce manifest-list semantics, which
# is the entire thing under test.
#
# Run with: make test-integration

REGISTRY_CTR=pi-it-registry
REGISTRY_PORT=5555
REGISTRY_HOST="localhost:${REGISTRY_PORT}"
BUILDER=pi-it-builder
REPO="${REGISTRY_HOST}/probe"

setup_file() {
  command -v docker >/dev/null 2>&1 || skip "docker is required for integration tests"
  export BATS_FILE_TMPDIR="${BATS_FILE_TMPDIR:-$(mktemp -d)}"

  docker rm -f "$REGISTRY_CTR" >/dev/null 2>&1 || true
  docker run -d --name "$REGISTRY_CTR" -p "${REGISTRY_PORT}:5000" \
    mirror.gcr.io/library/registry:2 >/dev/null

  # Wait for the registry rather than sleeping a guessed interval.
  local i
  for i in $(seq 1 30); do
    curl -sf "http://${REGISTRY_HOST}/v2/" >/dev/null && break
    [ "$i" -eq 30 ] && { echo "registry never became ready" >&2; return 1; }
    sleep 1
  done

  # network=host so the builder container can reach a registry published on the
  # host. Without it localhost inside the builder is the builder itself.
  docker buildx rm "$BUILDER" >/dev/null 2>&1 || true
  docker buildx create --name "$BUILDER" --driver docker-container \
    --driver-opt network=host --bootstrap >/dev/null 2>&1

  printf 'FROM mirror.gcr.io/library/alpine:3.21\nRUN echo integration > /marker\n' \
    > "$BATS_FILE_TMPDIR/Dockerfile"

  # One build per architecture, exactly as the build job does it: single
  # platform, no tag, pushed by digest.
  local arch
  for arch in arm64 amd64; do
    docker buildx --builder "$BUILDER" build "$BATS_FILE_TMPDIR" \
      -f "$BATS_FILE_TMPDIR/Dockerfile" \
      --platform "linux/${arch}" \
      --provenance=false \
      --output "type=image,name=${REPO},push-by-digest=true,name-canonical=true,push=true" \
      --metadata-file "$BATS_FILE_TMPDIR/${arch}.json" >/dev/null 2>&1
  done

  DIGEST_ARM64=$(jq -r '."containerimage.digest"' "$BATS_FILE_TMPDIR/arm64.json")
  DIGEST_AMD64=$(jq -r '."containerimage.digest"' "$BATS_FILE_TMPDIR/amd64.json")
  export DIGEST_ARM64 DIGEST_AMD64 REPO BUILDER REGISTRY_HOST
}

teardown_file() {
  docker buildx rm "$BUILDER" >/dev/null 2>&1 || true
  docker rm -f "$REGISTRY_CTR" >/dev/null 2>&1 || true
}

setup() {
  export SCRIPT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/scripts/build-matrix.sh"
}

# ── T1: real-dependency wiring ───────────────────────────────────────────

@test "should push each architecture to the registry by digest" {
  [ -n "$DIGEST_ARM64" ]
  [ -n "$DIGEST_AMD64" ]
  [[ "$DIGEST_ARM64" == sha256:* ]]
  [[ "$DIGEST_AMD64" == sha256:* ]]
}

# Catches: a build that ignores --platform and pushes the same image for both
# jobs. The digests would be identical, and the "multi-arch" manifest that
# follows would carry one architecture listed twice.
@test "should produce a different digest for each architecture" {
  [ "$DIGEST_ARM64" != "$DIGEST_AMD64" ]
}

# ── T3: state assertions on the published artifact ───────────────────────

@test "should produce an OCI image index when merging two per-arch digests" {
  docker buildx imagetools create --tag "${REPO}:merged" \
    "${REPO}@${DIGEST_ARM64}" "${REPO}@${DIGEST_AMD64}" >/dev/null 2>&1
  run docker buildx imagetools inspect --raw "${REPO}:merged"
  [ "$status" -eq 0 ]
  media=$(printf '%s' "$output" | jq -r '.mediaType')
  [ "$media" = "application/vnd.oci.image.index.v1+json" ]
}

# The assertion the whole design rests on: consumers pulling this tag on either
# architecture must get a matching image.
@test "should list exactly the two built architectures in the merged manifest" {
  docker buildx imagetools create --tag "${REPO}:platforms" \
    "${REPO}@${DIGEST_ARM64}" "${REPO}@${DIGEST_AMD64}" >/dev/null 2>&1
  run docker buildx imagetools inspect --raw "${REPO}:platforms"
  [ "$status" -eq 0 ]
  platforms=$(printf '%s' "$output" | jq -r '[.manifests[] | "\(.platform.os)/\(.platform.architecture)"] | sort | join(",")')
  [ "$platforms" = "linux/amd64,linux/arm64" ]
}

# Catches: provenance re-enabling and re-introducing the unknown/unknown
# attestation entries the workflow sets provenance:false to avoid.
@test "should carry no unknown platform entries when provenance is disabled" {
  docker buildx imagetools create --tag "${REPO}:noprov" \
    "${REPO}@${DIGEST_ARM64}" "${REPO}@${DIGEST_AMD64}" >/dev/null 2>&1
  run docker buildx imagetools inspect --raw "${REPO}:noprov"
  [ "$status" -eq 0 ]
  unknowns=$(printf '%s' "$output" | jq '[.manifests[] | select(.platform.architecture == "unknown")] | length')
  [ "$unknowns" -eq 0 ]
  total=$(printf '%s' "$output" | jq '.manifests | length')
  [ "$total" -eq 2 ]
}

# The workflow applies both generated tags in one imagetools call. Both must
# land on the same index, or latest and the immutable tag would diverge.
@test "should point the versioned immutable and latest tags at the same manifest" {
  tags=$("$SCRIPT" tags "$REPO" "" abc1234 1.98.0)
  immutable=$(printf '%s\n' "$tags" | sed -n '1p')
  moving=$(printf '%s\n' "$tags" | sed -n '2p')
  docker buildx imagetools create \
    --tag "$immutable" --tag "$moving" \
    "${REPO}@${DIGEST_ARM64}" "${REPO}@${DIGEST_AMD64}" >/dev/null 2>&1
  [ "$immutable" = "${REPO}:1.98.0-abc1234" ]
  [ "$moving" = "${REPO}:latest" ]
  a=$(docker buildx imagetools inspect --raw "$immutable" | shasum -a 256 | cut -d' ' -f1)
  b=$(docker buildx imagetools inspect --raw "$moving" | shasum -a 256 | cut -d' ' -f1)
  [ "$a" = "$b" ]
}

# ── T4: the failure the digest guard exists to prevent ───────────────────

# This is the load-bearing test. `imagetools create` does NOT reject a single
# source: it publishes a one-platform manifest under the tag, with no error.
# An arm64 build failing would silently ship an amd64-only "multi-arch" image.
# The only thing standing between that and a publish is check-digests.
@test "should silently publish a single-platform manifest when given one digest" {
  docker buildx imagetools create --tag "${REPO}:partial" \
    "${REPO}@${DIGEST_ARM64}" >/dev/null 2>&1
  run docker buildx imagetools inspect --raw "${REPO}:partial"
  [ "$status" -eq 0 ]
  count=$(printf '%s' "$output" | jq '(.manifests // []) | length')
  [ "$count" -eq 1 ]
}

# Ties the guard to that reality: given the artifact directory a half-failed
# build would produce, check-digests must refuse before imagetools is reached.
@test "should refuse the merge when only one architecture produced a digest" {
  dir="$BATS_TEST_TMPDIR/one-arch"
  mkdir -p "$dir" && touch "$dir/${DIGEST_ARM64#sha256:}"
  run "$SCRIPT" check-digests 2 "$dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"refusing to publish a partial manifest"* ]]
}

@test "should allow the merge when both architectures produced a digest" {
  dir="$BATS_TEST_TMPDIR/two-arch"
  mkdir -p "$dir"
  touch "$dir/${DIGEST_ARM64#sha256:}" "$dir/${DIGEST_AMD64#sha256:}"
  run "$SCRIPT" check-digests 2 "$dir"
  [ "$status" -eq 0 ]
}

# Catches: a digest filename mangled in the artifact round-trip, which would
# otherwise surface as an opaque registry error during publish.
@test "should fail to merge a digest that is not present in the registry" {
  absent="sha256:$(printf '0%.0s' $(seq 1 64))"
  run docker buildx imagetools create --tag "${REPO}:absent" "${REPO}@${absent}"
  [ "$status" -ne 0 ]
}

# ── T5: both architecture jobs push to one repository at the same time ───

# The two build jobs run concurrently and push blobs to the same repository.
# Catches a registry-level race leaving one architecture's blobs incomplete.
@test "should land both digests when architectures push concurrently" {
  printf 'FROM mirror.gcr.io/library/alpine:3.21\nRUN echo concurrent > /c\n' \
    > "$BATS_TEST_TMPDIR/Dockerfile"
  for arch in arm64 amd64; do
    docker buildx --builder "$BUILDER" build "$BATS_TEST_TMPDIR" \
      -f "$BATS_TEST_TMPDIR/Dockerfile" \
      --platform "linux/${arch}" --provenance=false \
      --output "type=image,name=${REPO}-conc,push-by-digest=true,name-canonical=true,push=true" \
      --metadata-file "$BATS_TEST_TMPDIR/c-${arch}.json" >/dev/null 2>&1 &
  done
  wait

  ca=$(jq -r '."containerimage.digest"' "$BATS_TEST_TMPDIR/c-arm64.json")
  cb=$(jq -r '."containerimage.digest"' "$BATS_TEST_TMPDIR/c-amd64.json")
  [ -n "$ca" ] && [ -n "$cb" ] && [ "$ca" != "$cb" ]

  docker buildx imagetools create --tag "${REPO}-conc:merged" \
    "${REPO}-conc@${ca}" "${REPO}-conc@${cb}" >/dev/null 2>&1
  run docker buildx imagetools inspect --raw "${REPO}-conc:merged"
  [ "$status" -eq 0 ]
  platforms=$(printf '%s' "$output" | jq '.manifests | length')
  [ "$platforms" -eq 2 ]
}
