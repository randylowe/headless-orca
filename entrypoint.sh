#!/bin/sh
set -e

PORT="${ORCA_PORT:-6768}"

# --pairing-address is genuinely optional to `orca serve` itself — confirmed
# via its own --help: every flag is bracketed/optional, and the binary's own
# help text says "--pairing-address changes only the client-advertised
# address" (auto-detected otherwise). This script still defaults to
# requiring it, because inside a typical Docker bridge network the
# auto-detected address is almost always the container's internal IP
# (e.g. 172.17.0.2) — the server starts fine, but hands out a pairing URL no
# client outside the container can ever reach. Set ORCA_ALLOW_AUTO_ADDRESS=1
# to skip this check and let Orca auto-detect anyway (e.g. you're running
# with --network host, where the container really does see the host's real
# interfaces, or you don't need remote pairing at all).
if [ -z "$ORCA_PAIRING_ADDRESS" ] && [ "$ORCA_ALLOW_AUTO_ADDRESS" != "1" ]; then
  echo "ERROR: ORCA_PAIRING_ADDRESS is not set." >&2
  echo "Set it to the address remote clients should use to reach this" >&2
  echo "container — a Tailscale IP, LAN IP, or tunnel hostname of the DOCKER HOST" >&2
  echo "(e.g. -e ORCA_PAIRING_ADDRESS=100.64.1.20)." >&2
  echo "Or set ORCA_ALLOW_AUTO_ADDRESS=1 to let Orca auto-detect instead" >&2
  echo "(usually only useful with --network host)." >&2
  exit 1
fi

# Built via `set --` (not string interpolation) so a pairing address
# containing spaces or shell metacharacters can't word-split into extra
# arguments — ORCA_PAIRING_ADDRESS is normally operator-controlled, but this
# keeps it safe even if that ever changes.
if [ -n "$ORCA_PAIRING_ADDRESS" ]; then
  set -- --port "$PORT" --pairing-address "$ORCA_PAIRING_ADDRESS" "$@"
else
  set -- --port "$PORT" "$@"
fi

# AppRun (not the raw extracted binary, which is named orca-ide — NOT orca)
# sets up LD_LIBRARY_PATH/APPDIR before exec'ing the real Electron binary.
#
# AppRun also auto-detects Chromium sandbox availability itself: it runs
# `unshare -Ur true` as a probe, and silently appends --no-sandbox if that
# fails (e.g. user namespaces blocked by the container runtime/seccomp
# profile). So you may not need --cap-add=SYS_ADMIN at all — try without it
# first. If startup logs still show a sandbox error, either add
# --cap-add=SYS_ADMIN to `docker run`, or pass --no-sandbox explicitly
# yourself: docker run ... headless-orca --no-sandbox
exec /opt/orca/squashfs-root/AppRun serve "$@"