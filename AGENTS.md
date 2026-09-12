# AGENTS.md

Instructions for AI agents (and humans) working in this repo. This file is the
canonical copy — `CLAUDE.md` only imports it, so **edit this file, never
duplicate it elsewhere**.

## What this repo is

A small infra repo that builds and runs a Docker container serving
[Orca](https://www.onorca.dev/) headlessly (`orca serve` via the Linux AppImage),
for remote pairing from Orca desktop/mobile clients. `README.md` is the
user-facing doc and the source of truth for how the container behaves.

## Files

- `Dockerfile` — 3-stage, multi-arch build (fetch/extract AppImage → copy Node.js → assemble runtime image).
- `entrypoint.sh` — the container's ENTRYPOINT; wraps `AppRun serve`.
- `docker-compose.yml` — the only intended way to build/run this locally.
- `build.sh` — the only publishing path (resolve Orca version → scan → multi-arch push to Docker Hub).
- `DOCKERHUB.md` — the Docker Hub README (short user-facing overview; details live in `README.md`).
- `.trivyignore` — documented, expiring Trivy exceptions. Keep entries dated and justified.
- `README.md` — user-facing documentation.
- `CHANGELOG.md` — required on every feature (see below).

## Changelog discipline (required)

**Every new feature must get a `CHANGELOG.md` entry every time it is completed —
written just before the git commit, in the same changeset.**

- Add the entry under `## [Unreleased]`, using the Keep a Changelog category
  headings (`Added` / `Changed` / `Fixed` / `Removed` / `Security`).
- One bullet per user-visible change; say what changed and why it matters, not
  how it's implemented.
- Notable bug fixes count too, not just features. Pure typo/rewording doc edits
  don't need an entry.
- Never commit a feature without its changelog entry, and never batch entries
  up for later — the entry is part of "done".
- **Release sections are keyed to the published image tag** — when `build.sh`
  publishes, `[Unreleased]` folds into `## [v<orca-version>-<rev>] - <date>`
  and the same string is applied as a git tag (clean tree only). The Docker
  tag is the project's only version; don't invent an independent project
  semver.

## Working in this repo — decisions already made

Don't relitigate these; they were verified once, the hard way:

- **Verify, don't guess, on packaging.** The OS package list in the `Dockerfile`
  was derived by running `ldd` against the real extracted `orca-ide` binary, not
  copied from a generic Electron-on-Docker recipe. If Orca is upgraded and
  startup fails with a missing `.so`, re-verify with `ldd` on the actual binary
  rather than guessing — several commonly-recommended packages (`libxss1`,
  `libxtst6`, `libappindicator3-1`) were deliberately left out because they
  aren't in this binary's `NEEDED` list.
- **Keep the corrections-vs-upstream-docs comment block at the top of the
  `Dockerfile` up to date** if you discover further discrepancies with Stably's
  published guide — it exists so already-verified fixes don't quietly regress.
- **Dockerfile mechanics:** `ARG NODE_VERSION` must stay declared before the
  first `FROM` (Docker requires that placement to interpolate it into a
  `FROM` line).
- **No secrets in source.** Never hardcode credentials or tokens into the
  `Dockerfile`, `entrypoint.sh`, or `docker-compose.yml`. Provider-CLI
  credentials (`~/.claude`, `~/.codex`, SSH keys) belong in the persisted
  `/home/orca` volume or a bind mount, never baked into the image; compose-side
  secrets go in `.env` (gitignored).
- **`ORCA_PAIRING_ADDRESS` in `docker-compose.yml` is a real LAN IP for this
  deployment** — treat it as environment-specific config, not something to
  genericize away without asking.
- **`docker-compose.yml` is the only intended local build/run path**, and
  `build.sh` is the only publishing path — keep both single and direct; no
  templating, multiple compose profiles, or extra abstraction unless actually
  needed.
- **Image tags follow distro-packaging style `v<orca-version>-<rev>`** (e.g.
  `v1.4.200-1`), with `latest` floating alongside. An image-only change bumps
  the revision; a new Orca release resets it to `-1`. `build.sh` auto-resolves
  `ORCA_VERSION` from the upstream electron-builder manifest and
  auto-increments `WRAPPER_REV` from already-published Docker Hub tags —
  don't hand-pin tags, and never push a tag that skipped the scan gate.
- **The Dockerfile's `org.opencontainers.image.version` LABEL and the pushed
  tag must never disagree** — both `ORCA_VERSION` and `WRAPPER_REV` are passed
  as build args into the LABEL; if you touch versioning, keep that property.
- **This is a small, self-contained infra repo — prefer minimal, direct changes
  over adding abstraction** unless genuinely required.
- **Keep `README.md` in sync.** When a change alters runtime behavior,
  configuration, or setup steps, update the README in the same changeset.
- **Commit messages follow Conventional Commits** (`feat:`, `fix:`, `docs:`,
  `chore:`, with an optional scope like `feat(compose):`) — match existing
  history.
- **Publishing is gated on a security scan.** `build.sh` scans the exact bits
  it will push (single-arch build first, same pinned `ORCA_VERSION`) with
  Trivy on HIGH/CRITICAL, `--ignore-unfixed` (bookworm-slim always carries
  some unfixable CVEs — that's deliberate, don't "fix" it by failing on
  them), with documented exceptions in `.trivyignore`.
- **`_bmad/` and `_bmad-output/` are local working state** (gitignored) — never
  commit them or treat them as repo source.
