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
#
# Usage:
#     ./build.sh            resolve version → scan gate → multi-arch push to
#                           Docker Hub (+ git tag on a clean tree)
#     ./build.sh --local    same pipeline, stops after the scan: no Hub
#                           lookup, no push, no git tag — for testing image
#                           changes on the Docker host before publishing
# ---------------------------------------------------------------------------
LOCAL=0
case "${1:-}" in
  "") ;;
  --local) LOCAL=1 ;;
  *) echo "usage: build.sh [--local]" >&2; exit 1 ;;
esac

MANIFEST_URL="https://github.com/stablyai/orca/releases/latest/download/latest-linux.yml"
TAGS_URL="https://hub.docker.com/v2/repositories/randylowe/headless-orca/tags?page_size=100&name="

ORCA_VERSION="v$(curl -fsSL "$MANIFEST_URL" | awk '$1 == "version:" {print $2; exit}')"
if [ -z "${ORCA_VERSION#v}" ]; then
  echo "ERROR: could not resolve the Orca version from $MANIFEST_URL — refusing to build" >&2
  exit 1
fi

if [ -z "${WRAPPER_REV:-}" ]; then
  if [ "$LOCAL" = 1 ]; then
    # Local-only build: nothing is pushed, so there is no tag to collide with
    # and no reason to require Hub reachability — default to revision 1. The
    # value only feeds the OCI label on the local image; a real publish always
    # resolves and stamps its own.
    WRAPPER_REV=1
  else
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
fi

IMAGE_TAG="${ORCA_VERSION}-${WRAPPER_REV}"
if [ "$LOCAL" = 1 ]; then
  echo "Local build of ${ORCA_VERSION} (rev ${WRAPPER_REV} is local-only — Docker Hub untouched)"
else
  echo "Building randylowe/headless-orca:${IMAGE_TAG} (latest will float alongside)"
fi

# Reuse the multiarch builder if it exists, create it if not. Deliberately NO
# stderr suppression here: this used to be `create ... 2>/dev/null || use ...`,
# which hid create's real failure and fell through to `use`, aborting with a
# baffling `failed to find instance "multiarch"` that named everything except
# the cause. A genuine failure (permissions on ~/.docker, disk, buildx broken)
# should abort loudly here with its actual message.
if ! docker buildx inspect multiarch >/dev/null 2>&1; then
  docker buildx create --name multiarch
fi
docker buildx use multiarch
docker buildx inspect --bootstrap multiarch

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
# --pull refreshes the base image (debian:bookworm-slim is a moving security
# target — the tag is rebuilt by Debian as point releases land). Without it
# the builder silently reuses whatever base layers are cached locally. Cheap
# when unchanged: just a manifest check; layers only re-pull when Debian
# actually shipped something.
docker buildx build --pull --platform linux/amd64 \
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

# --local stops here: the exact scanned bits are loaded locally and nothing
# has touched Docker Hub. Run them via compose with a retag + --no-build —
# compose uses the default builder, so it can't reuse this buildx cache and
# a plain `up --build` would rebuild from scratch instead of running what
# was just scanned.
if [ "$LOCAL" = 1 ]; then
  echo "Scan passed — local build ready, NOT published."
  echo "Run the scanned bits:"
  echo "  docker tag headless-orca:scan headless-orca"
  echo "  docker compose up -d --no-build"
  echo "Publish later with: ./build.sh"
  exit 0
fi

docker buildx build --pull --platform linux/amd64,linux/arm64 \
  --build-arg ORCA_VERSION="$ORCA_VERSION" \
  --build-arg WRAPPER_REV="$WRAPPER_REV" \
  -t "randylowe/headless-orca:${IMAGE_TAG}" \
  -t randylowe/headless-orca:latest \
  --push .

# ---------------------------------------------------------------------------
# Mirror the published image tag as a git tag, so git tag = Docker tag =
# changelog heading (see CHANGELOG.md "Versioning note" and AGENTS.md).
# Only on a clean tree — tagging a dirty working tree would mislabel the
# published bits. -f on the tag: a republish of the same <version>-<rev>
# moves the tag to the commit that actually produced the pushed bits; a
# stale tag pointing at the wrong commit is worse than a moved one.
# ---------------------------------------------------------------------------
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git diff-index --quiet HEAD --; then
    git tag -f "$IMAGE_TAG"
    git push -f origin "refs/tags/${IMAGE_TAG}" 2>/dev/null \
      || echo "NOTE: git tag ${IMAGE_TAG} created locally but not pushed (no remote configured yet?) — push it once the GitHub repo exists."
    echo "Git tag: ${IMAGE_TAG}"
  else
    echo "WARNING: working tree is dirty — git tag ${IMAGE_TAG} skipped (it would point at a commit that isn't what was published)."
  fi
else
  echo "NOTE: not a git repo — skipping git tag ${IMAGE_TAG}."
fi
