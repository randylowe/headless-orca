# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and entries are grouped under `## [Unreleased]` until a versioned release.
Per repo convention (**see AGENTS.md → "Changelog discipline"**), every completed
feature — and notable bug fix — gets an entry here **just before the git
commit**, in the same changeset.

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
- Versioned image tags on Docker Hub: `v<orca-version>-<rev>` (e.g.
  `v1.4.200-1`) alongside the floating `latest`, so a tag tells you which
  Orca release an image wraps and deployments can pin or roll back to an
  exact image. The wrapper revision auto-increments from already-published
  tags, so re-running the build never overwrites an existing version.
- Images carry an `org.opencontainers.image.version` OCI label
  (`v<orca-version>-<rev>`), so `docker inspect` shows what's bundled
  without pulling anything.

### Changed

- The Trivy security scan now runs on the exact bits that get published: the
  Orca release is resolved once and pinned into both the scanned build and
  the pushed multi-arch build, instead of each build independently
  re-resolving `latest` — previously a release landing mid-publish could
  ship code that was never scanned.
