# headless-orca

Runs [Orca](https://www.onorca.dev/) headless (`orca serve`) in a container, so a remote Orca
client (desktop or mobile) can pair with an agent-CLI environment running somewhere other than
your own machine — a homelab box, a Tailscale node, a cloud VM, anywhere you'd rather not run the
Orca desktop app directly.

Built from a Dockerfile verified directly against the real Orca Linux AppImage (extracted it, ran
`ldd` against the actual `orca-ide` binary) rather than assembled from a generic
"Electron on Docker" recipe. Full source, docs, and the verification notes:
**[github.com/randylowe/headless-orca](https://github.com/randylowe/headless-orca)**.

## What's in the image

- Orca's Linux AppImage, extracted at build time (no FUSE needed at runtime), multi-arch:
  `linux/amd64` and `linux/arm64`.
- Node.js bundled alongside it, so agent CLIs (Claude Code, Codex, OpenCode, Pi, etc.) have
  `npm`/`npx` available once you install them inside a running container.
- A virtual display (`xvfb`) and software rendering pre-wired, so Orca starts headless with no
  `$DISPLAY` set.
- Runs as an unprivileged user, not root.

## Quick start

```yaml
# docker-compose.yml
services:
  headless-orca:
    image: randylowe/headless-orca:latest
    container_name: headless-orca
    restart: unless-stopped
    environment:
      # Tailscale IP, LAN IP, or tunnel hostname of *this* Docker host — required,
      # the container refuses to start without a real one.
      ORCA_PAIRING_ADDRESS: "100.64.1.20"
      ORCA_PORT: "6768"
    ports:
      - "6768:6768"
    volumes:
      - orca-data:/home/orca

volumes:
  orca-data:
```

```sh
docker compose up -d
docker compose logs -f headless-orca
```

A healthy start prints an `Orca server ready` block with a pairing URL/code — open it in the
Orca desktop app or a browser to pair a new client. Paired devices reconnect automatically after
that; you won't see this again unless you're onboarding another client.

## Configuration

| Variable | Kind | Purpose |
|---|---|---|
| `ORCA_PAIRING_ADDRESS` | env | Address remote clients dial — a Tailscale IP, LAN IP, or tunnel hostname of the **Docker host** (not the container). Required unless `ORCA_ALLOW_AUTO_ADDRESS=1`. |
| `ORCA_ALLOW_AUTO_ADDRESS` | env | Set to `1` to skip the pairing-address check and let Orca auto-detect instead. Only useful with `--network host`. |
| `ORCA_PORT` | env | Port `orca serve` listens on. Default `6768`. |

`/home/orca` (mounted above as the `orca-data` volume) holds repos, worktrees, provider-CLI
credentials (`~/.claude`, `~/.codex`, etc.), and Orca's own state — all of it survives container
recreation and image upgrades.

## Why this exists

Orca is normally a desktop app. This image lets you run the same agent-CLI-in-a-terminal
workflow against a machine that stays on 24/7, and pair into it from a desktop, laptop, tablet,
or phone over your own network (LAN or Tailscale) instead of running Orca locally.

## Tags

- `latest` — tracks the newest Orca release at build time.
- Built from the `Dockerfile` in the linked GitHub repo; pin a specific Orca version by building
  from source with `--build-arg ORCA_VERSION=vX.Y.Z` if you need reproducibility.

## Full documentation

Configuration reference, Tailscale sidecar setup, persistence/upgrade notes, health checks,
troubleshooting, and known limitations all live in the
[project README](https://github.com/randylowe/headless-orca#readme).
