# headless-orca

Runs [Orca](https://www.onorca.dev/) headless (`orca serve`) in Docker, so a remote Orca client
(desktop/mobile) can pair with an agent-CLI environment running elsewhere — a Tailscale/LAN box,
a home server, anywhere you'd rather not run the Orca desktop app directly.

Verified directly against the real Orca Linux AppImage (extracted it, ran `ldd` on the actual
binary, inspected `AppRun`) rather than built from Stably's
[headless-Linux-server guide](https://github.com/stablyai/orca/blob/main/docs/reference/headless-linux-server.md)
alone — the corrections and one open item versus that guide live in the Dockerfile's header
comment.

## Why

I'm new to Orca and haven't used it extensively, but I wanted to run it from my homelab server —
which stays powered on 24/7 — instead of my desktop, which I reboot from time to time.

My use case: connect to the Orca server from my Mac Mini, MacBook Air, iPad, and iPhone to do
coding, reaching into my home network over Tailscale.

## Quick start

Requires Docker with Compose v2 (`docker compose`).

### Fastest: use the published image

[`randylowe/headless-orca`](https://hub.docker.com/r/randylowe/headless-orca) on Docker Hub is
built from this repo (multi-arch: amd64 + arm64) — pull it instead of building locally:

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

A healthy start prints one `Orca server ready` block with the bound and advertised endpoints —
that's your pairing info.

### Building from source instead

Use this repo's `Dockerfile` directly if you want to pin a specific `ORCA_VERSION`, set
`ORCA_UID`/`ORCA_GID` for a bind-mounted volume, or otherwise customize the build (see
"Configuration" and "Architecture" below).

1. Edit `ORCA_PAIRING_ADDRESS` in `docker-compose.yml` — same requirement as above.
2. Build and start:
   ```sh
   docker compose up -d --build
   ```
3. Confirm it's up the same way: `docker compose logs -f headless-orca`.

## Pairing

The ready block in the logs (`docker compose logs -f headless-orca`) is where the pairing code
lives. Real sample output (address and code below are scrambled placeholders, not a usable
credential):

```
headless-orca  | Orca server ready
headless-orca  | Bound endpoint: ws://0.0.0.0:6768
headless-orca  | Advertised endpoint: ws://192.0.2.10:6768
headless-orca  | Web client URL: http://192.0.2.10:6768/web-index.html#pairing=orca%3A%2F%2Fpair%3Fcode%3DQzR2WkxwOTBtRktUZ0h1WWJlN3NBcU4zZExYd1JqUDh2Q2lFbzZmVHlNMXpVeGtIN3NHcVZiTjJkTHhSbzlwQWNXaEV5VDNtS3VGWmo4TGdOMVJ2WXNJZ2JQVHFrT3pINXdBdUUyY2ZWbUxYbjRyRHRZb0JwU2c3aUtxTjBlV3pWY0psTXhIdVJmQjZzRHRQZzNvWWFOMXZLbUxjWGpFdzlUcUZoUnpCOG9WZ0x5U2NNdUlwRHJIdEFXbjJmWnE=
headless-orca  | Pairing URL: orca://pair?code=QzR2WkxwOTBtRktUZ0h1WWJlN3NBcU4zZExYd1JqUDh2Q2lFbzZmVHlNMXpVeGtIN3NHcVZiTjJkTHhSbzlwQWNXaEV5VDNtS3VGWmo4TGdOMVJ2WXNJZ2JQVHFrT3pINXdBdUUyY2ZWbUxYbjRyRHRZb0JwU2c3aUtxTjBlV3pWY0psTXhIdVJmQjZzRHRQZzNvWWFOMXZLbUxjWGpFdzlUcUZoUnpCOG9WZ0x5U2NNdUlwRHJIdEFXbjJmWnE=
```

`Pairing URL` and `Web client URL` carry the same code, just in two forms: open the `orca://`
one directly on the desktop app (it's a custom URL scheme Orca registers), or open the `http://`
one in a browser for the same pairing flow with no app install needed. Either works — use
whichever the client supports. Every real server start mints a fresh code; yours will differ from
this sample.

- **Treat it as a credential, not just an address.** The pairing offer carries a device
  credential and E2EE material. Don't paste it into shared logs, tickets, or a reverse-proxy
  access log.
- **You only need it once per client.** A paired device reconnects automatically on future
  container restarts/upgrades — the pairing URL is only for onboarding a *new* client.
- **If pairing fails, check `Advertised endpoint` reachability first**, not the code — it has to
  actually be reachable from wherever the client is (firewall, correct IP, port published). This
  is exactly what `ORCA_PAIRING_ADDRESS` controls.
- **If the server can't mint an offer at all**, it stays usable but reports it explicitly rather
  than silently omitting pairing — with `--json` you'd see `pairing.available: false` and a
  `reason` such as `disabled_by_operator`, `websocket_unavailable`, `device_registry_unavailable`,
  `e2ee_key_unavailable`, or `invalid_advertised_endpoint`.

## Configuration

Set via `docker-compose.yml`'s `environment:` (runtime) and `build.args:` (build-time):

| Variable | Kind | Purpose |
|---|---|---|
| `ORCA_PAIRING_ADDRESS` | env | Address remote clients dial — a Tailscale IP, LAN IP, or tunnel hostname of the **Docker host** (not the container). Required unless `ORCA_ALLOW_AUTO_ADDRESS=1`. Currently set to a real LAN IP — treat that as environment-specific, not a placeholder to genericize. |
| `ORCA_ALLOW_AUTO_ADDRESS` | env | Set to `1` to skip the pairing-address check and let Orca auto-detect instead. Only useful with `--network host`, where the container actually sees the host's real interfaces. |
| `ORCA_PORT` | env | Port `orca serve` listens on. Default `6768`. |
| `ORCA_VERSION` | build arg | Orca release tag to install, e.g. `v1.4.199`. Defaults to `latest`, which drifts on every rebuild — pin it once you've tested a version. |
| `NODE_VERSION` | build arg | Node.js version/line to bundle. Defaults to `current` (tracks newest release line, not just LTS). |
| `ORCA_UID` / `ORCA_GID` | build args | Default `1000:1000`. Bake a matching UID/GID into the image for bind-mounted host directories. Runtime alternative with no rebuild: compose's `user:` override — what `docker-compose.yml` actually uses; see "Persistence" below. |

To let agent CLIs inside the container use your existing SSH keys for git, uncomment the
`~/.ssh` volume mount in `docker-compose.yml`. If startup logs show a Chromium sandbox error,
uncomment `cap_add: [SYS_ADMIN]` — but try without it first: `AppRun` probes sandbox availability
itself (`unshare -Ur true`) and silently adds `--no-sandbox` when user namespaces aren't usable,
so you often don't need it.

## Tailscale sidecar

The samples above assume Tailscale is already installed on the Docker host itself, and
`ORCA_PAIRING_ADDRESS` is set to that host's Tailscale IP. If you'd rather not install Tailscale
on the host — or want this container reachable at its own stable Tailscale identity, independent
of the host — run Tailscale as a sidecar container instead, using
[`tailscale/tailscale`](https://hub.docker.com/r/tailscale/tailscale) and sharing its network
namespace with `network_mode: service:tailscale`.

Env vars below are verified against Tailscale's own
[`containerboot`](https://github.com/tailscale/tailscale/blob/main/cmd/containerboot/settings.go)
source, not guessed. One detail that's easy to get wrong: `TS_USERSPACE` **defaults to `true`**
(outbound-only SOCKS5/HTTP proxying, no real network interface) — that's not enough for clients
to dial *into* Orca, so it must be set to `false` explicitly to get a real `tailscale0` interface.

Put the secret in `.env` (already gitignored in this repo) rather than the compose file:

```sh
# .env
TS_AUTHKEY=tskey-auth-xxxxxxxxxxxx-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TS_HOSTNAME=headless-orca
```

```yaml
# docker-compose.yml
services:
  tailscale:
    image: tailscale/tailscale:latest
    container_name: headless-orca-ts
    hostname: ${TS_HOSTNAME:-headless-orca}
    environment:
      TS_AUTHKEY: ${TS_AUTHKEY}
      TS_HOSTNAME: ${TS_HOSTNAME:-headless-orca}
      TS_STATE_DIR: /var/lib/tailscale
      TS_USERSPACE: "false"   # real tun interface — required so peers can dial in
      TS_EXTRA_ARGS: --accept-dns=true
    volumes:
      - ts-state:/var/lib/tailscale
      - /dev/net/tun:/dev/net/tun
    cap_add:
      - NET_ADMIN
      - NET_RAW
    restart: unless-stopped

  headless-orca:
    image: randylowe/headless-orca:latest
    container_name: headless-orca
    network_mode: service:tailscale   # shares tailscale's network stack — no ports: here
    depends_on:
      - tailscale
    environment:
      # MagicDNS name is stable across restarts, unlike the tailnet IP. Replace
      # <tailnet-name> with yours (Tailscale admin console → DNS tab).
      ORCA_PAIRING_ADDRESS: "${TS_HOSTNAME:-headless-orca}.<tailnet-name>.ts.net"
      ORCA_PORT: "6768"
    restart: unless-stopped
    volumes:
      - orca-data:/home/orca

volumes:
  ts-state:
  orca-data:
```

| Variable | Required | Purpose |
|---|---|---|
| `TS_AUTHKEY` | Yes | Auth key so the sidecar joins your tailnet non-interactively. Generate one at [the Tailscale admin console](https://login.tailscale.com/admin/settings/keys) — a *reusable* key is convenient for recreating the container; an *ephemeral* key auto-removes the device when the container stops, which you probably don't want for a server you expect to stay paired. |
| `TS_HOSTNAME` | No (defaults to the container's hostname) | Becomes this device's name in your tailnet and its MagicDNS name. |
| `TS_USERSPACE` | Effectively yes — must be `"false"` | See above; the sidecar default (`true`) won't allow inbound connections. |

Notes:
- Don't add `ports:` to `headless-orca` here — it shares the `tailscale` service's network stack
  entirely, so it's reachable at `<TS_HOSTNAME>.<tailnet-name>.ts.net:6768` from anywhere in your
  tailnet, and nowhere else (no LAN/internet exposure unless you separately publish a port on the
  `tailscale` service).
- `ORCA_ALLOW_AUTO_ADDRESS` isn't needed with this setup — `ORCA_PAIRING_ADDRESS` is set
  explicitly to the MagicDNS name.
- First boot needs internet access to reach Tailscale's coordination server before the tailnet
  identity exists; after that, `docker compose logs tailscale` will confirm the assigned IP and
  hostname.

## Architecture

- **`Dockerfile`** — 3-stage, multi-arch (amd64/arm64) build:
  1. **`fetch`** (`debian:bookworm-slim`) — downloads the Orca AppImage for `$TARGETARCH`
     (amd64 → `orca-linux.AppImage`, arm64 → `orca-linux-arm64.AppImage` — Orca ships real
     separate per-arch builds, not a fat binary), extracts it at **build** time
     (`--appimage-extract`, so the running container never needs FUSE), and records the version
     in `/opt/orca/VERSION`.
  2. **`node`** — the official `node:${NODE_VERSION}-bookworm-slim` image, used only as a
     `COPY --from` source (same base OS, so glibc matches), so agent CLIs like
     `@anthropic-ai/claude-code` have Node/npm available at runtime.
  3. **runtime** (`debian:bookworm-slim`) — installs the exact OS libraries `orca-ide` actually
     links against (verified with `ldd` against the real binary, not copied from a generic
     "Electron on Docker" recipe), copies in the extracted Orca tree and the Node install, creates
     an unprivileged `orca` user and `chown -R`s everything to it — this, not loosening mode bits
     the way the upstream systemd guide does, is what makes `squashfs-root` (which
     `--appimage-extract` leaves `drwx------`, unreadable by anyone but the extracting user)
     readable: by making `orca` the *owner*. Also installs `sudo` with a passwordless rule for
     `orca` (see "Root inside the container (`sudo`)" below). Runs as `USER orca`.
- **`entrypoint.sh`** — the container's `ENTRYPOINT`. Wraps `AppRun serve`; refuses to start
  without `ORCA_PAIRING_ADDRESS` set (or an explicit opt-out), because a Docker bridge network's
  auto-detected address is almost always the container's internal IP — unreachable from any
  client outside the container.
- **`docker-compose.yml`** — the intended way to build/run this locally. Exposes port 6768,
  persists `/home/orca` in the `orca-data` named volume.
- **`AGENTS.md`** — working conventions for this repo (the verify-don't-guess policy for the
  package list, no hardcoded secrets, changelog discipline) — read before making structural
  changes. It is the canonical copy; `CLAUDE.md` is just a pointer that imports it, so all
  agents read the same rules.
- **`CHANGELOG.md`** — required on every completed feature (and notable bug fix): the entry is
  written just before the git commit, in the same changeset.

`LIBGL_ALWAYS_SOFTWARE=1` and `xvfb` are set/installed so Orca can render and auto-start its own
virtual display with no `$DISPLAY` set — nothing in this setup ever sets one. Build both
architectures at once with `docker buildx build --platform linux/amd64,linux/arm64 ...`.

The Dockerfile's header comment is the canonical record of every place this setup deliberately
diverges from — or goes further than — Stably's guide (binary naming, sandbox auto-detection,
per-arch asset URLs, the `ldd`-verified package list, the one open/unverified item). Check it
before assuming something here is wrong just because it looks different from the guide's
bare-metal/systemd instructions.

## Persistence

`/home/orca` is the `orca-data` named volume. It holds repos, worktrees, provider-CLI credentials
(`~/.claude`, `~/.codex`, etc.), and Orca's own settings/state — all of it survives
`docker compose up -d --build` and container recreation without a rebuild.

`NPM_CONFIG_PREFIX` points inside `$HOME` (`/home/orca/.npm-global`) rather than `/usr/local`, so
`npm install -g @anthropic-ai/claude-code` (or any other agent CLI) run **inside the running
container** also persists in the volume — install once, keep it forever, add more CLIs the same
way whenever you like.

**Named volume vs. bind mount:** the default named volume needs no permission setup — it's
Docker-managed. (One exception: when compose's `user:` override is active, a *fresh* volume still
initializes with the image's 1000:1000 ownership, so hand it to the runtime UID once — step 2
below.) If you bind-mount a real host directory instead, standard POSIX UID/GID matching applies
(Docker does not remap this): the container's `orca` user is UID/GID 1000:1000 by default, and if
that doesn't match the host directory's owner, writes fail with `EACCES` — `npm install -g`,
`git clone`, writing `~/.claude` credentials, all of it. Fix it either way: rebuild with
`--build-arg ORCA_UID=$(id -u) --build-arg ORCA_GID=$(id -g)` matching the host user, or skip the
rebuild with the compose `user:` override (next section). There is deliberately no
`PUID`/`PGID`-at-startup pattern (linuxserver.io-style root entrypoint) here — the image's
entrypoint never executes anything as root. (The paired user *can* elevate inside the running
container with passwordless `sudo` — that's a choice made inside the container, not a root
entrypoint; see "Root inside the container (`sudo`)" below.)

### Sharing a host folder at `/mnt/projects` (runtime UID override)

`docker-compose.yml` sets `user: "1001:1001"`: the numeric UID/GID of the host user that owns the
Syncthing-synced projects folder (`dockerApps` — check with `id dockerApps` on the Docker host and
keep the two in sync). Compose applies `user:` when the container is created, overriding the
image's `USER orca` with no rebuild. Because bind mounts translate numeric IDs literally:

- Files and folders the container creates under the bind mount are owned by that host user, so the
  host's Syncthing (running as the same user) keeps full access and the sync works in both
  directions. New synced content arrives owned by the same UID, so the container can work with it.
- Git inside the container sees matching owner/UID on `/mnt/projects` repos — no "dubious
  ownership" rejections.
- Cosmetic: `whoami`/`id` inside the container can't resolve uid 1001 to a name (the passwd entry
  is still `orca` = 1000). Harmless — `$HOME` comes from `ORCA_HOME`, npm global installs go to
  `$HOME/.npm-global` via `NPM_CONFIG_PREFIX`, and nothing in this stack looks the name up.

Setup against an existing deployment is two one-time steps:

```sh
# 1. In docker-compose.yml, uncomment the /mnt/projects bind mount and set the real
#    host path (host-specific, deliberately not committed).

# 2. Hand the named volume to the runtime UID — stop the container first.
docker compose stop headless-orca
docker run --rm -v orca-data:/data alpine chown -R 1001:1001 /data
docker compose up -d
```

Verify:

```sh
docker compose exec headless-orca id                       # uid=1001 gid=1001
docker compose exec headless-orca touch /mnt/projects/.write-test
ls -l /mnt/projects/.write-test                             # on the host: owned by the host user
```

Rollback is the same steps inverted: remove `user:` from `docker-compose.yml`, `chown -R 1000:1000`
the volume, `docker compose up -d`.

## Installing agent CLIs

After adding your server to your local Orca desktop client, open a new tab and install an agent.
A few examples:

### Claude
```sh
curl -fsSL https://claude.ai/install.sh | bash
```

### OpenCode
```sh
curl -fsSL https://opencode.ai/install | bash
```

Installs to `$HOME/.opencode/bin` and adds it to `PATH` via your shell's rc file (`.bashrc`,
`.profile`, etc.) — that only takes effect in an interactive shell that sources it. A one-off
`docker compose exec headless-orca opencode ...` right after install may need the full path
(`~/.opencode/bin/opencode`) until you open an interactive shell at least once.

### Pi
```sh
curl -fsSL https://pi.dev/install.sh | sh
```

All three install under `$HOME` (`/home/orca`), so — same as `npm install -g` in "Persistence"
above — they persist across container recreation without a rebuild.

## Root inside the container (`sudo`)

The `orca` user has passwordless `sudo`: `sudo -i` from any Orca terminal gives a root shell
inside the container. It ships that way on purpose — the `orca` account has no password at all
(so a password prompt could never succeed), and anyone who can pair to this server already has
an interactive shell as this exact user, so a prompt would add friction, not security.

Two things to know before living in it:

- **OS packages installed this way are ephemeral.** `sudo apt-get install …` writes to the
  container filesystem, which is wiped on every recreate/rebuild — unlike the agent CLIs and
  npm globals above, which persist in the `/home/orca` volume. Fine for ad-hoc tools; anything
  you want to keep belongs in the Dockerfile's package list.
- **Root breaks the ownership setups in "Persistence" above.** Files created as root under the
  `/mnt/projects` bind mount land **root-owned on the host**, breaking the host-side Syncthing
  user's access until you `chown` them back — and a root-owned file in the `orca-data` volume
  can lock `orca` out entirely. When you only need to *run* one privileged command, prefer
  `sudo -u orca <command>` (or `sudo <command>` for the single command) over camping in a
  root shell.

Container root is still container-scoped: no Docker socket is mounted and the default
capability set applies — root in here is not root on the Docker host. (Host-side,
`docker compose exec -u root headless-orca bash` also gets you a root shell with no image
support at all; same trust boundary, just without `sudo` inside.)

**If you use the compose `user:` UID override:** sudo can only run for a UID that exists in the
image's `/etc/passwd`. Under an override to a UID other than the image's `orca` (e.g.
`user: "1001:1001"` against a default build, where `orca` is 1000), it fails with
`sudo: unknown uid 1001, who are you?` — build with `ORCA_UID`/`ORCA_GID` set to match the
override instead, so the baked-in passwd entry matches. Check which case you're in with `id`
in an Orca terminal.

## Installing Orca skills

Orca's agent skills (CLI usage, orchestration, computer use, etc.) are normally installed from
Orca's desktop Settings UI — which this headless container doesn't have.

Use `orca skills install` instead, run from a terminal tab opened in the Orca client (same
tab/window as installing an agent CLI above — you're already inside the container, no
`docker compose exec` needed):

```sh
orca skills install                 # list installable skills
orca skills install --all            # install every bundled skill
orca skills install --all --dry-run  # preview the command, don't run it
```

This needs `node`/`npx` — already included in this image — and doesn't need a running Orca
runtime.

With no desktop Settings UI to pick which agent CLIs get a skill, `orca` normally infers
`--agent` from what it detects installed on the host. This container ships no agent CLI by
default (you `npm install -g` or `curl`-install them yourself — see "Installing agent CLIs"
above), so on a fresh container `orca skills install` will detect nothing and stop, asking for
`--agent` explicitly rather than guessing:

```sh
orca skills install --skill orca-cli --agent claude-code,codex
orca skills install --skill orca-cli --agent universal
```

To refresh already-installed skills, `orca skills update` mirrors the same flags — it's a no-op
(exit 0) for any skill not already installed, so install it first:

```sh
orca skills update --all
```

## Publishing

`build.sh` is the only publishing path. `./build.sh` resolves the current Orca release from the
upstream manifest, builds a single-arch image, gates it on a Trivy HIGH/CRITICAL scan, then
pushes multi-arch to Docker Hub as `v<orca-version>-<rev>` with `latest` floating alongside —
the revision auto-increments from already-published tags.

To test image changes before publishing, `./build.sh --local` runs the same pipeline — same
pinned version, same scan gate — and stops before anything touches Docker Hub: no tag lookup,
no push, no git tag. Run the exact scanned bits locally with a retag + `--no-build` (compose
uses the default builder, so it can't reuse the script's buildx cache — a plain
`up --build` would rebuild from scratch instead of running what was scanned):

```sh
./build.sh --local
docker tag headless-orca:scan headless-orca
docker compose up -d --no-build
```

Publish for real afterwards with plain `./build.sh` — its amd64 half reuses the local build's
layer cache, so only arm64 compiles fresh. Local builds never affect the revision numbering:
the counter is derived from tags on Docker Hub, which `--local` doesn't touch.

## Upgrading

Published images are tagged `v<orca-version>-<rev>` (e.g. `randylowe/headless-orca:v1.4.200-1`)
alongside the floating `latest` — pin `image:` to an exact tag in `docker-compose.yml` if you'd
rather control upgrades explicitly than track `latest`. Running the published image:
`docker compose pull && docker compose up -d` gets the latest `randylowe/headless-orca:latest`.
Building from source: bumping `ORCA_VERSION` and rebuilding is
the equivalent of the upstream guide's binary swap. Either way, the same risk the guide warns
about for its own systemd flow applies here too: once a newer build
starts, it can rewrite `orca-data.json` (under `/home/orca/.config` in the volume) into a newer
schema, and an older build loading that file afterward can silently discard fields it doesn't
recognize. There is no built-in rollback path, so stop the container and back up the volume before
bumping the version (stopping first avoids snapshotting mid-write):

```sh
docker compose stop headless-orca
docker run --rm -v orca-data:/data -v "$PWD":/backup debian:bookworm-slim \
  tar czf /backup/orca-data-$(date +%F).tgz -C / data
```

To roll back, restore that archive into the volume before starting the old image again:

```sh
docker compose stop headless-orca
docker run --rm -v orca-data:/data -v "$PWD":/backup debian:bookworm-slim \
  bash -c "rm -rf /data/* && tar xzf /backup/orca-data-YYYY-MM-DD.tgz -C /"
docker compose up -d
```

Restarting or recreating the container (`docker compose up -d --build`, `restart`, `down`) kills
every live terminal and agent process in it — persisted layout/history survives in the volume,
but in-flight work does not. Check what's running first:

```sh
docker compose exec headless-orca orca-ide terminal list --json
```

## Health check

`Dockerfile` declares a `HEALTHCHECK` that opens a plain TCP connection to `$ORCA_PORT`
(`bash`'s `/dev/tcp`, not `curl` — `orca serve` exposes no HTTP endpoint to poll, only a stdout
log line `HEALTHCHECK` can't read). It only confirms the listener is bound, not that pairing/E2EE
setup succeeded — check `docker compose logs` for the actual readiness block if you need that
confirmation.

```sh
docker compose ps
docker inspect --format='{{.State.Health.Status}}' headless-orca
```

A failing healthcheck does not by itself restart the container: `restart: unless-stopped` only
reacts to the container actually exiting, not to `unhealthy` status while it's still running.
Automatic recovery on unhealthy status needs an external watcher (or Swarm/Kubernetes) — nothing
here provides that today.

## Startup log noise

These show up on every start (confirmed against a real run) but don't affect `orca serve` —
if you see `Orca server ready` with a `Pairing URL`, the container is fine:

- **`dbus/bus.cc` "Failed to connect to the bus"** (repeated) — Electron probing for a system
  D-Bus socket that doesn't exist here. Expected: the upstream guide says a D-Bus session isn't
  required headless. Only used opportunistically for things like tray/notifications/keyring.
- **`[codex-trust-grant] ... Error: spawn codex ENOENT`** — Orca tries to shell out to a `codex`
  binary to compute a trust value; not installed here since this image ships no agent CLIs by
  default. It falls back gracefully and continues. Resolves on its own once you install the
  Codex CLI (see "Persistence"); otherwise harmless.
- **`[serve] orca CLI install: installed ...` / `bare orca dispatcher installed`** — not errors,
  informational. Confirms the self-install behavior described in "Pairing" above worked.
- **PostHog `ECONNREFUSED`** (~20s after ready) — Orca's own bundled analytics failing to phone
  home. Fires after readiness is already reported, so it doesn't affect functionality. No
  documented opt-out found in the upstream guide.

## Known limitations

- **No push notifications.** Background push to a paired phone never fires from a headless
  `orca serve` — agent-completion detection runs in the desktop renderer, which headless mode
  doesn't start. The phone still registers and pairs successfully; it just won't push.
- **Two packages from the upstream guide's prerequisite list are unverified here**
  (`libx11-xcb1`, `libxcb-dri3-0`) — see the Dockerfile's "OPEN / UNVERIFIED" comment block. Every
  other package decision in this Dockerfile was checked directly with `ldd` against the real
  binary; these two weren't (no container runtime was available on the machine that wrote this
  note). Not currently installed — flagged rather than guessed either way.

## Troubleshooting

- **Won't start, complains about `ORCA_PAIRING_ADDRESS`** — expected; set it to a real address
  your clients can reach, or set `ORCA_ALLOW_AUTO_ADDRESS=1` if you know what you're doing
  (usually only safe with `--network host`).
- **Chromium sandbox errors in logs** — uncomment `cap_add: [SYS_ADMIN]` in `docker-compose.yml`.
- **`sudo: unknown uid 1001, who are you?`** — you're running under a compose `user:` override
  to a UID that isn't in the image's passwd (`orca` is 1000 in a default build). sudo refuses
  to run for an unknown UID no matter what the sudoers file says. Fix: build with
  `ORCA_UID`/`ORCA_GID` matching the override — see "Root inside the container (`sudo`)".
- **Missing shared library on startup** — re-verify with `ldd`, don't guess: extract the AppImage
  and run `ldd squashfs-root/orca-ide` (the Electron binary is named `orca-ide`, not `orca` —
  `ldd` on a wrong/nonexistent path prints nothing and exits cleanly, which reads as a clean
  result in exactly the situation where you're hunting a missing library).
- **Pairing offer looks valid but clients can't connect** — `ORCA_PAIRING_ADDRESS` is only the
  *advertised* address; it doesn't change the bind address. Confirm DNS/firewall/port-publishing
  actually routes that advertised address to the container's published port.
