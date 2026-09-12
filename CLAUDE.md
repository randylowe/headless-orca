# CLAUDE.md

This repo builds and runs a Docker container that serves [Orca](https://www.onorca.dev/)
headlessly (`orca serve`) via the Linux AppImage, for remote pairing from Orca desktop/mobile
clients. See README.md for usage.

## Files

- `Dockerfile` — 3-stage build (fetch/extract AppImage → copy Node.js → assemble runtime image).
- `entrypoint.sh` — the container's ENTRYPOINT; wraps `AppRun serve`.
- `docker-compose.yml` — the only intended way to build/run this locally.

## Working in this repo

- The package list in `Dockerfile` was derived by running `ldd` against the real extracted
  `orca-ide` binary, not copied from a generic Electron-on-Docker recipe. If Orca is upgraded and
  startup fails with a missing `.so`, re-verify with `ldd` on the actual binary rather than
  guessing — several commonly-recommended packages (`libxss1`, `libxtst6`, `libappindicator3-1`)
  were deliberately left out because they aren't in this binary's `NEEDED` list.
- Don't hardcode secrets or credentials into the Dockerfile, entrypoint.sh, or
  docker-compose.yml. Provider-CLI credentials (`~/.claude`, `~/.codex`, SSH keys) belong in the
  persisted `/home/orca` volume or a bind mount, never baked into the image.
- `ORCA_PAIRING_ADDRESS` in docker-compose.yml is a real LAN IP for this deployment — treat it as
  environment-specific config, not something to genericize away without asking.
- Keep the corrections-vs-upstream-docs comment block at the top of the Dockerfile up to date if
  you discover further discrepancies with Stably's published guide — it's there so future changes
  don't quietly regress a fix that was already verified once.
- This is a small, self-contained infra repo — prefer minimal, direct changes over adding
  abstraction (templating, multiple compose profiles, etc.) unless actually needed.
