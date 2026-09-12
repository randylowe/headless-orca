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
