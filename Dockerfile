# syntax=docker/dockerfile:1

# Declared before the first FROM so it can be interpolated INTO a FROM line
# (Docker requires this specific placement for that). Default "current"
# preserves prior behavior (tracks newest Node release line, not just LTS);
# override with --build-arg NODE_VERSION=22.11.0 (or "22", "lts", etc.) for a
# reproducible pin instead.
ARG NODE_VERSION=current

##############################################################################
# Orca remote server — headless `orca serve` in a container
#
# Verified directly against the real v1.4.x Linux AppImage (downloaded and
# extracted it, inspected AppRun and the CLI launcher, ran ldd on the actual
# binary) rather than only against the docs — see the two corrections below.
#
# CORRECTIONS vs. Stably's published headless-Linux-server guide
# (https://github.com/stablyai/orca/blob/main/docs/reference/headless-linux-server.md):
#   1. The guide's troubleshooting section says `ldd squashfs-root/orca`.
#      The real executable inside the current build is named `orca-ide`
#      (confirmed by AppRun's own `BIN="$APPDIR/orca-ide"` and by the CLI
#      launcher's comment: "Linux executableName is orca-ide (avoids Ubuntu
#      GNOME Orca conflict)"). `squashfs-root/orca` does not exist. This
#      Dockerfile uses AppRun as the entrypoint either way, so it never
#      depended on that name being right — but if you ever invoke the binary
#      directly, use orca-ide.
#   2. AppRun already probes sandbox availability itself (`unshare -Ur true`)
#      and silently adds --no-sandbox when user namespaces aren't usable —
#      you may not need --cap-add=SYS_ADMIN at all. See entrypoint.sh.
#
# Key idea: the AppImage is extracted at BUILD time with --appimage-extract,
# so the running container never needs FUSE / /dev/fuse — just a plain
# unprivileged rootfs. Xvfb is installed so Orca can auto-start its own
# virtual display when no $DISPLAY is set (current Orca builds do this
# automatically).
#
# Base: debian:bookworm-slim. Electron/Chromium binaries are glibc-only, so
# Debian/Ubuntu are the safe options; Alpine's musl libc is not supported.
# The package list below is NOT copied from a generic "Electron on Docker"
# recipe — it's `ldd`'d directly against the real orca-ide binary and cross-
# checked package-by-package against packages.debian.org for bookworm
# specifically (a few common guesses, e.g. libxss1/libxtst6/libappindicator3-1,
# turned out NOT to be linked by this binary and were deliberately left out).
# Multi-stage (3 stages): "fetch" downloads+extracts the AppImage (its curl
# is build-time only); "node" is the official Node.js image, used purely as
# a copy source; the final runtime stage assembles OS packages + orca +
# Node.js together. curl IS also installed in the runtime stage separately
# (for debugging/health-checks/agent-CLI use) — that's a deliberate install,
# not a leftover from the fetch stage.
#
# Multi-arch: this one Dockerfile targets both amd64 and arm64 via Docker's
# built-in TARGETARCH build arg (see the fetch stage below) — confirmed
# directly (HTTP checks against both real asset URLs) that Orca ships
# separate real AppImage builds per architecture, not a fat/universal
# binary. Build with `docker buildx build --platform linux/amd64,linux/arm64
# ...` to produce both from this one file.
##############################################################################

# --- Stage 1: fetch + extract (curl lives and dies here) --------------------
FROM debian:bookworm-slim AS fetch

# Pin a real release tag for reproducibility, e.g. --build-arg ORCA_VERSION=v1.4.199
# "latest" works too but drifts under you on every rebuild.
ARG ORCA_VERSION=latest

# Auto-populated by `docker buildx build --platform ...` — no need to pass
# this yourself. Confirmed directly (HTTP HEAD against both real URLs, not
# guessed): Orca's Linux "Universal AppImage" is universal across distros,
# NOT across CPU architectures — amd64 and arm64 are two separate asset
# files. This ARG picks the right one at build time so one Dockerfile
# handles both; nothing else in this file needs to change per-arch.
ARG TARGETARCH

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/orca
# Verifies the downloaded AppImage against the sha512 electron-builder publishes
# alongside every release (latest-linux.yml / latest-linux-arm64.yml, the same
# manifest its own auto-updater trusts) — confirmed these exist and match per-
# release, not just for the "latest" tag, by checking two real releases
# directly. Without this, a compromised or corrupted release asset would be
# extracted and shipped with no detection.
RUN set -eux; \
    case "$TARGETARCH" in \
        amd64) ORCA_ASSET="orca-linux.AppImage"; MANIFEST="latest-linux.yml" ;; \
        arm64) ORCA_ASSET="orca-linux-arm64.AppImage"; MANIFEST="latest-linux-arm64.yml" ;; \
        *) echo "Unsupported TARGETARCH: $TARGETARCH (Orca publishes amd64 and arm64 Linux AppImages only)" >&2; exit 1 ;; \
    esac; \
    if [ "$ORCA_VERSION" = "latest" ]; then \
        BASE_URL="https://github.com/stablyai/orca/releases/latest/download"; \
    else \
        BASE_URL="https://github.com/stablyai/orca/releases/download/${ORCA_VERSION}"; \
    fi; \
    curl -fL "${BASE_URL}/${ORCA_ASSET}" -o orca.AppImage; \
    curl -fL "${BASE_URL}/${MANIFEST}" -o manifest.yml; \
    EXPECTED_SHA512=$(awk -v asset="$ORCA_ASSET" '$0 ~ ("url: " asset) {getline; print $2; exit}' manifest.yml); \
    if [ -z "$EXPECTED_SHA512" ]; then \
        echo "ERROR: could not find a sha512 entry for ${ORCA_ASSET} in ${MANIFEST} — refusing to trust an unverifiable download" >&2; \
        exit 1; \
    fi; \
    ACTUAL_SHA512=$(openssl dgst -sha512 -binary orca.AppImage | openssl base64 -A); \
    if [ "$ACTUAL_SHA512" != "$EXPECTED_SHA512" ]; then \
        echo "ERROR: checksum mismatch for ${ORCA_ASSET}" >&2; \
        echo "  expected: ${EXPECTED_SHA512}" >&2; \
        echo "  actual:   ${ACTUAL_SHA512}" >&2; \
        exit 1; \
    fi; \
    chmod +x orca.AppImage; \
    ./orca.AppImage --appimage-extract; \
    rm orca.AppImage manifest.yml; \
    echo "${ORCA_VERSION} (${TARGETARCH})" > /opt/orca/VERSION

# --- Stage 2: Node.js (official image, same base OS so glibc matches) -------
# Version comes from NODE_VERSION (declared above, before the first FROM).
FROM node:${NODE_VERSION}-bookworm-slim AS node

# --- Stage 3: runtime ---------------------------------------------------------
FROM debian:bookworm-slim

# Image versioning: tags follow <upstream>-<revision> (v1.4.200-1, distro
# packaging style). ORCA_VERSION is the pinned Orca release (build.sh resolves
# it from the upstream release manifest — "latest" only when building by
# hand); WRAPPER_REV counts image-only rebuilds on top of that release
# (build.sh auto-increments it from published Docker Hub tags). Both are
# passed in so this label and the pushed tag can never disagree. See build.sh.
ARG ORCA_VERSION
ARG WRAPPER_REV=1
LABEL org.opencontainers.image.version="${ORCA_VERSION}-${WRAPPER_REV}" \
      org.opencontainers.image.base.name="debian:bookworm-slim"

ENV DEBIAN_FRONTEND=noninteractive \
    LIBGL_ALWAYS_SOFTWARE=1 \
    ORCA_HOME=/home/orca \
    NPM_CONFIG_PREFIX=/home/orca/.npm-global \
    PATH="/home/orca/.npm-global/bin:/opt/orca/squashfs-root/resources/bin:${PATH}"

# NPM_CONFIG_PREFIX points inside $HOME (the persistent volume, see the
# VOLUME line below) instead of /usr/local. That means `npm install -g
# @anthropic-ai/claude-code opencode-ai` run later, inside the running
# container, writes into the volume — it survives container recreation
# (docker compose up -d --build, docker rm + recreate) without needing to
# rebuild the image or touch this Dockerfile at all. Install once, keep it
# forever, add more agent CLIs the same way whenever you like.

# --- OS packages --------------------------------------------------------------
# Confirmed by running `ldd` on the actual orca-ide binary. Packages below map
# 1:1 to real NEEDED entries; deep transitive libs (krb5/gnutls/avahi/systemd/
# harfbuzz/freetype's own sub-deps, etc.) are intentionally omitted — apt
# pulls those in automatically as dependencies of the packages listed here.
#   xvfb           -> virtual display Orca starts itself when $DISPLAY is unset
#   libgl1/mesa-dri -> software rendering; paired with LIBGL_ALWAYS_SOFTWARE
#                      (kept per Stably's own systemd unit, even though the
#                      app also bundles its own SwiftShader/ANGLE libs)
#   git/openssh     -> for any agent CLI you register later to work with repos
#   curl            -> not needed by orca-ide itself; added for debugging /
#                      health checks / agent CLIs that shell out to it
#   sudo            -> not needed by orca-ide either; added so the paired user
#                      can administer the container (ad-hoc apt installs etc.).
#                      Passwordless, on purpose — see the sudoers step below.
#   libatomic1      -> not needed by orca-ide itself either. Added for Pi
#                      (pi.dev) — its curl-installed build (Bun-compiled) hits
#                      "libatomic.so.1: cannot open shared object file"
#                      without it, a known Bun-on-minimal-Debian issue. If you
#                      install Pi via npm instead (`npm install -g
#                      --ignore-scripts @earendil-works/pi-coding-agent`) this
#                      package isn't actually exercised — confirmed directly:
#                      its one native addon (a clipboard binding) resolves
#                      cleanly against the libs already listed here.
# Deliberately NOT installed: libfuse2 (we extract, never mount — no FUSE
# needed), libxss1/libxtst6/libnotify4/libsecret-1-0/libxcursor1 (not in the
# binary's actual NEEDED list), libappindicator3-1 (doesn't exist as a real
# package in bookworm — it's a virtual name provided by
# libayatana-appindicator3-1 — and is tray-icon-only anyway, irrelevant headless).
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        openssh-client \
        sudo \
        xvfb \
        libgl1-mesa-dri \
        libgl1 \
        libglib2.0-0 \
        libnspr4 \
        libnss3 \
        libatk1.0-0 \
        libatk-bridge2.0-0 \
        libatspi2.0-0 \
        libatomic1 \
        libcups2 \
        libdbus-1-3 \
        libdrm2 \
        libexpat1 \
        libfontconfig1 \
        libfreetype6 \
        libgbm1 \
        libx11-6 \
        libxext6 \
        libxi6 \
        libxrender1 \
        libxcb1 \
        libxkbcommon0 \
        libxcomposite1 \
        libxdamage1 \
        libxfixes3 \
        libxrandr2 \
        libasound2 \
        libpango-1.0-0 \
        libcairo2 \
        libgtk-3-0 \
        fonts-liberation \
        xdg-utils \
    && rm -rf /var/lib/apt/lists/*

COPY --from=fetch /opt/orca /opt/orca

# Full Node.js + npm/npx install, copied wholesale from the official image so
# no symlinks inside /usr/local get missed. This is what most agent CLIs
# (Claude Code, Codex, etc. — all npm packages) actually need at runtime;
# Orca's own bundled CLI launcher does NOT need this, it runs its own
# Electron binary in Node mode instead.
COPY --from=node /usr/local /usr/local

# --- Unprivileged service user ------------------------------------------------
# The upstream systemd guide specifically runs as a non-root user so
# Chromium's own sandbox stays usable — root disables/breaks it. Also owns
# /usr/local (fallback for anything that ignores NPM_CONFIG_PREFIX above).
#
# UID/GID are build args, not hardcoded — matters if you ever bind-mount a
# real host directory into /home/orca instead of the named volume (e.g. repos
# that already live on a NAS): matching your host user's UID/GID here means
# files created from either side show up with sane ownership on both.
# Default 1000:1000 matches most single-user Linux/macOS hosts already.
ARG ORCA_UID=1000
ARG ORCA_GID=1000
RUN groupadd --gid "${ORCA_GID}" orca \
    && useradd --create-home --home-dir "${ORCA_HOME}" --shell /usr/sbin/nologin \
       --uid "${ORCA_UID}" --gid "${ORCA_GID}" orca \
    && chown -R orca:orca /opt/orca /usr/local

# Passwordless sudo for orca. The account above is created with NO password
# (locked in shadow), so password-prompted sudo could never succeed — and a
# prompt would add nothing security-wise: anyone who can pair to this server
# already has an interactive shell as this exact user. NOPASSWD just makes
# that shell able to administer the container (apt installs, etc.). Scoped to
# the container: no docker socket is mounted and the default capability set
# applies, so this is not host root. visudo -c fails the build on a malformed
# rule instead of shipping a sudo that can't start.
RUN echo 'orca ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/orca \
    && chmod 0440 /etc/sudoers.d/orca \
    && visudo -c

COPY --chmod=755 entrypoint.sh /opt/orca/entrypoint.sh
RUN chown orca:orca /opt/orca/entrypoint.sh

USER orca
WORKDIR ${ORCA_HOME}

# Repos, worktrees, provider-CLI credentials (~/.claude, ~/.codex, etc.) and
# Orca's own settings all live under $HOME — persist this.
VOLUME ["/home/orca"]

EXPOSE 6768

# orca serve exposes no HTTP endpoint to poll, only a stdout log line
# HEALTHCHECK can't read — this only confirms the listener is bound, not
# that pairing/E2EE setup succeeded (see README's "Health check" section).
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD bash -c 'exec 3<>"/dev/tcp/127.0.0.1/${ORCA_PORT:-6768}"' || exit 1

ENTRYPOINT ["/opt/orca/entrypoint.sh"]