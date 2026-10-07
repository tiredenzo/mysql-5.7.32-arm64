#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
fail() { echo "Build: $*" >&2; exit 1; }
# The retained builder image must be visible to BuildKit in this same daemon.
# Use a Docker context so every command can be pinned without global changes.
[[ -z "${DOCKER_HOST:-}" ]] || fail 'Unset DOCKER_HOST and select a local ARM64 Docker context with DOCKER_CONTEXT before running this script.'
builder_details=$(docker buildx inspect) || fail 'Cannot inspect the selected Buildx builder. Select a local Docker builder with BUILDX_BUILDER.'
builder=$(awk '/^Name:/ {print $2; exit}' <<< "$builder_details")
driver=$(awk '/^Driver:/ {print $2; exit}' <<< "$builder_details")
builder_context=$(awk '/^Endpoint:/ {print $2}' <<< "$builder_details")
[[ "$driver" == docker && -n "$builder" && -n "$builder_context" && "$builder_context" != *$'\n'* ]] || \
  fail 'Select a local docker-driver builder with BUILDX_BUILDER (for Docker Desktop, BUILDX_BUILDER=desktop-linux). Remote and docker-container builders are unsupported.'
endpoint=$(docker context inspect "$builder_context" --format '{{.Endpoints.docker.Host}}') || \
  fail "Builder '$builder' must use a local Docker context."
[[ "$endpoint" == unix://* ]] || fail "Builder '$builder' uses a nonlocal endpoint. Select a local Unix-socket Docker context and its docker-driver builder."
docker_cmd=(docker --context "$builder_context")
engine_arch=$("${docker_cmd[@]}" info --format '{{.Architecture}}') || fail "Cannot reach Docker context '$builder_context'."
case "$engine_arch" in
  aarch64|arm64) ;;
  *) fail "Builder '$builder' requires a native ARM64 Docker engine; context '$builder_context' reports '$engine_arch'." ;;
esac
echo "Using native ARM64 local Docker builder '$builder' (context '$builder_context')."
jobs=${BUILD_JOBS:-6}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo 'BUILD_JOBS must be positive.' >&2; exit 1; }
mkdir -p artifacts
started=$(date +%s)
"${docker_cmd[@]}" buildx build --builder "$builder" --platform linux/arm64 --build-arg "BUILD_JOBS=$jobs" \
  --target builder --load --progress plain -t mysql-5.7.32-arm64-builder:local . \
  2>&1 | tee artifacts/build-compile.log
# Assemble directly from the retained builder image. This also avoids repeated
# compilation when a Docker engine does not retain intermediate build cache.
"${docker_cmd[@]}" image inspect mysql-5.7.32-arm64-builder:local --format '{{.Id}}' > artifacts/builder-image-id.txt
python3 - <<'PY'
from pathlib import Path
source = Path('Dockerfile').read_text()
base = source[:source.index('FROM runtime-base AS build-dependencies')]
runtime = source[source.index('FROM runtime-base AS final'):]
Path('artifacts/Dockerfile.runtime').write_text(
    'FROM mysql-5.7.32-arm64-builder:local AS builder\n' + base + '\n' + runtime
)
PY
"${docker_cmd[@]}" buildx build --builder "$builder" --platform linux/arm64 --build-arg "BUILD_JOBS=$jobs" \
  --load --progress plain -f artifacts/Dockerfile.runtime \
  -t "${IMAGE:-mysql:5.7.32-arm64-local}" . 2>&1 | tee artifacts/build.log
ended=$(date +%s)
printf '%s\n' "$((ended-started))" > artifacts/build-duration-seconds.txt
"${docker_cmd[@]}" image inspect "${IMAGE:-mysql:5.7.32-arm64-local}" > artifacts/image-inspect.json
container=$("${docker_cmd[@]}" create --platform linux/arm64 --entrypoint true "${IMAGE:-mysql:5.7.32-arm64-local}")
trap '"${docker_cmd[@]}" rm -v "$container" >/dev/null' EXIT
"${docker_cmd[@]}" cp "$container:/usr/share/mysql/arm64-build" artifacts/
echo "Build completed in $((ended-started)) seconds."
