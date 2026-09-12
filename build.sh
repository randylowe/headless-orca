#!/bin/bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Versioning & tags
#
# This image wraps a specific Orca release, so tags follow the distro
# packaging convention <upstream>-<revision>:
#
#     v1.4.200-1    Orca v1.4.200, first build of this image on it
#     v1.4.200-2    image-only change (Dockerfile/entrypoint), same Orca
#     v1.4.201-1    Orca bumped, revision resets
#
# `latest` floats alongside and always points at the newest build.
#
# ORCA_VERSION resolves automatically from the electron-builder manifest
# (latest-linux.yml) — the same artifact the Dockerfile verifies the AppImage
# checksum against — so there is one source of truth and no GitHub API rate
# limit in play. WRAPPER_REV auto-increments from the highest matching tag
# already on Docker Hub, so it needs no manual bump and never reuses a tag.
# Override either by exporting it first:
#
#     WRAPPER_REV=7 ./build.sh
# ---------------------------------------------------------------------------
MANIFEST_URL="https://github.com/stablyai/orca/releases/latest/download/latest-linux.yml"
TAGS_URL="https://hub.docker.com/v2/repositories/randylowe/headless-orca/tags?page_size=100&name="

ORCA_VERSION="v$(curl -fsSL "$MANIFEST_URL" | awk '$1 == "version:" {print $2; exit}')"
if [ -z "${ORCA_VERSION#v}" ]; then
  echo "ERROR: could not resolve the Orca version from $MANIFEST_URL — refusing to build" >&2
  exit 1
fi

if [ -z "${WRAPPER_REV:-}" ]; then
  # Highest published revision for this Orca version, +1. An empty result
  # means no such tags exist yet → revision 1 is safe (nothing to collide
  # with). A FAILED LOOKUP ABORTS (curl -f + pipefail) rather than defaulting:
  # silently rebuilding as -1 could overwrite an already-published tag on push.
  # page_size=100 returns newest-first — ample for one release's revisions.
  hub_tags="$(curl -fsSL "${TAGS_URL}${ORCA_VERSION}-")"
  WRAPPER_REV="$(printf '%s' "$hub_tags" \
    | grep -o "\"name\": *\"${ORCA_VERSION}-[0-9]*\"" \
    | sed 's/.*-//' \
    | sort -n \
    | tail -1 || true)"
  WRAPPER_REV="${WRAPPER_REV:-1}"
fi

IMAGE_TAG="${ORCA_VERSION}-${WRAPPER_REV}"
echo "Building randylowe/headless-orca:${IMAGE_TAG} (latest will float alongside)"

docker buildx create --use --name multiarch 2>/dev/null || docker buildx use multiarch
docker buildx inspect --bootstrap

# Build+load a single-arch image first and scan it for known-CVE OS/app
# packages before anything gets published — build.sh previously pushed
# straight to Docker Hub with no scan step at all. `--load` only works for a
# single platform, hence building amd64 here separately from the multi-arch
# push below.
#
# ORCA_VERSION is pinned (not "latest") so the scanned image and the pushed
# multi-arch images are the same bits — with "latest", each build re-resolves
# independently, and a release landing mid-script means publishing code that
# was never scanned.
docker buildx build --platform linux/amd64 \
  --build-arg ORCA_VERSION="$ORCA_VERSION" \
  --build-arg WRAPPER_REV="$WRAPPER_REV" \
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
  --build-arg ORCA_VERSION="$ORCA_VERSION" \
  --build-arg WRAPPER_REV="$WRAPPER_REV" \
  -t "randylowe/headless-orca:${IMAGE_TAG}" \
  -t randylowe/headless-orca:latest \
  --push .
