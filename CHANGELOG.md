# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and entries are grouped under `## [Unreleased]` until a versioned release.
Per repo convention (**see AGENTS.md → "Changelog discipline"**), every completed
feature — and notable bug fix — gets an entry here **just before the git
commit**, in the same changeset.

**Versioning note:** this project has no independent version — the published
Docker image tag (`v<orca-version>-<rev>`, e.g. `v1.4.200-1`) *is* the version.
When `build.sh` publishes a tag, the `[Unreleased]` section folds into
`## [<image-tag>] - <date>`, and the same string is applied as a git tag, so
changelog heading, git tag, and Docker tag are one identifier.

## [Unreleased]

### Added

- Repo instructions for AI agents: `AGENTS.md` as the canonical working
  conventions (verify-don't-guess packaging policy, no-secrets rule, minimal-
  abstraction principle, changelog discipline), with `CLAUDE.md` importing it
  as a thin pointer so every agent reads the same rules.
- `CHANGELOG.md` — this file. All future features and notable fixes get an
  entry here just before their git commit.
- Versioned image tags in distro-packaging style (`v<orca-version>-<rev>`, e.g.
  `v1.4.200-1`) alongside the floating `latest` tag, plus an
  `org.opencontainers.image.version` OCI label on every image so `docker
  inspect` reveals the bundled Orca release without pulling.
- `build.sh` publishing pipeline: auto-resolves the Orca release from the
  upstream electron-builder manifest, auto-increments the wrapper revision
  from already-published Docker Hub tags, gates the push on a Trivy
  HIGH/CRITICAL scan of the exact bits to be published (`--ignore-unfixed`,
  documented exceptions in `.trivyignore`), then pushes multi-arch
  (amd64/arm64).
- Initial headless Orca server: 3-stage multi-arch Dockerfile (amd64/arm64) that
  fetches the Orca Linux AppImage, verifies it against the release sha512
  manifest, and extracts it at build time — no FUSE needed at runtime.
- `entrypoint.sh` wrapper around `AppRun serve` that requires
  `ORCA_PAIRING_ADDRESS` (or an explicit `ORCA_ALLOW_AUTO_ADDRESS=1` opt-out)
  so remote clients always get a reachable pairing URL.
- `docker-compose.yml` as the single build/run path, with the `orca-data` named
  volume persisting `/home/orca` (repos, agent-CLI credentials, Orca settings).
- Runtime UID/GID override via compose `user:` (`1001:1001`) matching the host's
  Syncthing-synced projects folder, plus the `/mnt/projects` bind-mount and
  `~/.ssh` mount points (commented, set per deployment).
- Runtime-facing `README.md`: quick start (published image or build from
  source), pairing guide, Tailscale sidecar setup, agent-CLI and skill
  installation, upgrade/backup procedures, health check, and troubleshooting.
- Release convention: the published Docker tag is the project's only version —
  changelog sections are cut as `## [v<orca-version>-<rev>] - <date>` and
  `build.sh` mirrors each published tag as a git tag on the built commit
  (clean-tree guard), so changelog, git, and Docker Hub share one identifier.
- Passwordless `sudo` for the `orca` user: `sudo -i` from a paired client
  gives a root shell inside the container (ad-hoc OS package installs, etc.).
  `NOPASSWD` is the only workable mode — the account ships with no password at
  all — and adds no new exposure, since pairing already grants a shell as this
  user. OS packages installed this way are wiped on container recreate;
  durable ones belong in the Dockerfile. See README → "Root inside the
  container (`sudo`)".
- `build.sh --local`: runs the publish pipeline up to the Trivy scan gate and
  stops there — no Docker Hub tag lookup, no push, no git tag — so image
  changes can be tested on the Docker host with the exact scanned bits
  (`docker tag headless-orca:scan headless-orca && docker compose up -d
  --no-build`) before publishing. Local builds never affect revision
  numbering; the rev counter is still derived from published tags only.
  See README → "Publishing".
- `build.sh --push`: publishes the bits from a previous `--local` run without
  rebuilding them. Re-scans the existing local image (the gate still runs),
  reads the Orca version from that image's OCI label instead of re-resolving
  upstream — so a release landing between test and push can't swap in
  unscanned bits — then does the multi-arch push + git tag. amd64 is all
  cache hits; only arm64 compiles. See README → "Publishing".

### Fixed

- `build.sh` no longer swallows the `docker buildx create` error for its
  `multiarch` builder: a create failure used to fall through to
  `docker buildx use`, which aborted with a baffling
  `failed to find instance "multiarch"` that hid the real cause. The builder
  is now found-or-created explicitly with errors visible.

### Changed

- The Trivy security scan now runs on the exact bits that get published: the
  Orca release is resolved once and pinned into both the scanned build and
  the pushed multi-arch build, instead of each build independently
  re-resolving `latest` — previously a release landing mid-publish could
  ship code that was never scanned.
- Base image and packages now refresh on every build: `build.sh` passes
  `--pull` and the Dockerfile runs `apt-get upgrade`, so Debian security
  updates reach published images instead of failing the scan gate (first
  case: two HIGH libpcre2-8-0 CVEs, fixed in `10.42-1+deb12u1`, which the
  base image alone did not carry).
