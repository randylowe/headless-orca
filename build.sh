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
# ORCA_UID/ORCA_GID work the same way (default 1000:1000). Set them when the
# runtime runs under a different UID — compose `user:` overrides — so the
# baked-in passwd entry matches and sudo works (see README → "Root inside the
# container"). Use the SAME values for a --local run and its later --push:
#
#     ORCA_UID=3000 ORCA_GID=3000 ./build.sh --local
#
# Usage:
#     ./build.sh            resolve version → scan gate → multi-arch push to
#                           Docker Hub (+ git tag on a clean tree)
#     ./build.sh --local    same pipeline, stops after the scan: no Hub
#                           lookup, no push, no git tag — for testing image
#                           changes on the Docker host before publishing.
#                           Tags the result headless-orca:latest in the
#                           local store, so compose can run it directly
#     ./build.sh --push     second half of a --local run: re-scans the
#                           existing local image (no rebuild), re-resolves the
#                           revision, multi-arch push + git tag
# ---------------------------------------------------------------------------
LOCAL=0
PUSH=0
case "${1:-}" in
  "") ;;
  --local) LOCAL=1 ;;
  --push) PUSH=1 ;;
  *) echo "usage: build.sh [--local|--push]" >&2; exit 1 ;;
esac

MANIFEST_URL="https://github.com/stablyai/orca/releases/latest/download/latest-linux.yml"
TAGS_URL="https://hub.docker.com/v2/repositories/randylowe/headless-orca/tags?page_size=100&name="

if [ "$PUSH" = 1 ]; then
  # Second half of a --local run: publish the exact bits that were already
  # built and scanned locally. The version comes from the local image's own
  # OCI label — NOT re-resolved from upstream — so an Orca release landing
  # between the local run and this push can't swap in unscanned bits.
  if ! docker image inspect headless-orca:latest >/dev/null 2>&1; then
    echo "ERROR: no local image headless-orca:latest — run ./build.sh --local first" >&2
    exit 1
  fi
  LABEL_VERSION="$(docker image inspect headless-orca:latest \
    --format '{{index .Config.Labels "org.opencontainers.image.version"}}')"
  ORCA_VERSION="${LABEL_VERSION%-*}"
  if [ -z "$ORCA_VERSION" ] || [ "$ORCA_VERSION" = "$LABEL_VERSION" ]; then
    echo "ERROR: could not read the Orca version from headless-orca:latest's" \
         "org.opencontainers.image.version label (got: '${LABEL_VERSION:-<empty>}')" >&2
    echo "Rebuild it with ./build.sh --local" >&2
    exit 1
  fi
else
  ORCA_VERSION="v$(curl -fsSL "$MANIFEST_URL" | awk '$1 == "version:" {print $2; exit}')"
  if [ -z "${ORCA_VERSION#v}" ]; then
    echo "ERROR: could not resolve the Orca version from $MANIFEST_URL — refusing to build" >&2
    exit 1
  fi
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
if [ "$PUSH" = 1 ]; then
  echo "Pushing scanned ${ORCA_VERSION} bits as randylowe/headless-orca:${IMAGE_TAG} (latest will float alongside)"
elif [ "$LOCAL" = 1 ]; then
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
#
# Skipped entirely in --push mode: headless-orca:latest already exists (it's
# the whole input to that mode) and rebuilding it could produce bits that
# differ from what the scan gate is about to see.
if [ "$PUSH" = 0 ]; then
  # One tag, local store only: headless-orca:latest (the Hub one is
  # randylowe/headless-orca:latest, pushed only by the runs below). The same
  # image is scanned in place by Trivy next, and --push reads its OCI label —
  # so a compose file pointing at this name runs the exact scanned bits with
  # no retag step.
  docker buildx build --pull --platform linux/amd64 \
    --build-arg ORCA_VERSION="$ORCA_VERSION" \
    --build-arg WRAPPER_REV="$WRAPPER_REV" \
    --build-arg ORCA_UID="${ORCA_UID:-1000}" \
    --build-arg ORCA_GID="${ORCA_GID:-1000}" \
    -t headless-orca:latest \
    --load .
fi

# --ignore-unfixed: debian:bookworm-slim always carries some HIGH/CRITICAL
# CVEs with no upstream fix yet (won't-fix or affected-no-patch) — those
# aren't actionable by rebuilding here, so failing on them would block every
# publish forever. --ignorefile carries one documented, expiring exception
# for an issue bundled inside Orca's own AppImage (see .trivyignore).
# In --push mode this re-scans the existing headless-orca:latest unchanged, so
# the gate still runs on the exact bits about to be pushed.
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD/.trivyignore:/.trivyignore:ro" \
  aquasec/trivy:latest image --severity HIGH,CRITICAL --ignore-unfixed \
    --ignorefile /.trivyignore --exit-code 1 headless-orca:latest

# --local stops here: the exact scanned bits are loaded locally and nothing
# has touched Docker Hub. They're tagged headless-orca:latest, so a compose
# file pointing at that name runs them directly with --no-build — a plain
# `up --build` would rebuild via the default builder (separate cache) instead
# of running what was just scanned.
if [ "$LOCAL" = 1 ]; then
  echo "Scan passed — local build ready, NOT published."
  echo "Scanned bits are tagged locally as headless-orca:latest:"
  echo "  image: headless-orca:latest     # in docker-compose.yml"
  echo "  docker compose up -d --no-build"
  echo "Publish later with: ./build.sh --push (or ./build.sh for the full pipeline)"
  exit 0
fi

# --push deliberately omits --pull here: the cached base layers ARE the ones
# the scan saw, and pulling a fresher bookworm-slim at this point could ship
# base bits the gate never ran against. Full mode keeps --pull — it rescans
# in the same run anyway. Same rule for ORCA_UID/ORCA_GID: keep the
# environment consistent with the --local run, or the useradd layer rebuilds
# and the pushed bits differ from the scanned ones.
if [ "$PUSH" = 1 ]; then PULL_FLAG=""; else PULL_FLAG="--pull"; fi
docker buildx build ${PULL_FLAG:+"$PULL_FLAG"} --platform linux/amd64,linux/arm64 \
  --build-arg ORCA_VERSION="$ORCA_VERSION" \
  --build-arg WRAPPER_REV="$WRAPPER_REV" \
  --build-arg ORCA_UID="${ORCA_UID:-1000}" \
  --build-arg ORCA_GID="${ORCA_GID:-1000}" \
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
