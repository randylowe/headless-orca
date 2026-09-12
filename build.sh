#!/bin/bash
set -euo pipefail

docker buildx create --use --name multiarch 2>/dev/null || docker buildx use multiarch
docker buildx inspect --bootstrap

# Build+load a single-arch image first and scan it for known-CVE OS/app
# packages before anything gets published — build.sh previously pushed
# straight to Docker Hub with no scan step at all. `--load` only works for a
# single platform, hence building amd64 here separately from the multi-arch
# push below.
docker buildx build --platform linux/amd64 \
  --build-arg ORCA_VERSION=latest \
  -t headless-orca:scan \
  --load .

# --ignore-unfixed: debian:bookworm-slim always carries some HIGH/CRITICAL
# CVEs with no upstream fix yet (won't-fix or affected-no-patch) — those
# aren't actionable by rebuilding here, so failing on them would block every
# publish forever. --ignorefile carries one documented, expiring exception
# for an issue bundled inside Orca's own AppImage (see .trivyignore).
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.trivyignore:/.trivyignore:ro" \
  aquasec/trivy:latest image --severity HIGH,CRITICAL --ignore-unfixed \
    --ignorefile /.trivyignore --exit-code 1 headless-orca:scan

docker buildx build --platform linux/amd64,linux/arm64 \
  --build-arg ORCA_VERSION=latest \
  -t randylowe/headless-orca:latest \
  --push .
