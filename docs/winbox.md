# Winbox bastion (optional)

NDE can open a **Winbox** session to a MikroTik device straight from the browser,
tunneled through a container on the server. This is **off by default and not part
of the public image** — the container embeds MikroTik's proprietary Winbox
binary, which is not ours to redistribute. You build the bastion image yourself,
which downloads Winbox at build time under MikroTik's terms.

## Why it's separate

- The Winbox binary is MikroTik's proprietary software. Shipping it inside a
  public image would redistribute it; building it locally (you fetching it) keeps
  that between you and MikroTik.
- The bastion gives interactive, credentialed access to equipment — a higher risk
  tier than the read-only collection core. Opt-in by design.

## Enabling it

The build files live in [`docker/`](../docker/) — `Dockerfile.winbox-v3`,
`Dockerfile.winbox-v4` and `entrypoint-winbox.sh` — with a dedicated
[docker/README.md](../docker/README.md). At a high level:

1. Build the bastion image(s) on the NDE host (from the repo root):

   ```bash
   docker build -f docker/Dockerfile.winbox-v3 -t nde-winbox-v3:latest .
   docker build -f docker/Dockerfile.winbox-v4 -t nde-winbox-v4:latest .
   ```

   The build downloads Winbox from MikroTik's site, under MikroTik's terms.

2. Give the `serve` service access to the Docker socket so it can launch
   per-session bastion containers (this effectively grants host-level privilege
   to that service — understand the trade-off before enabling).
3. Turn Winbox on in the admin panel (Settings → Winbox).

See [docker/README.md](../docker/README.md) and the inline notes for resource
limits and security caveats (isolated Docker network, idle timeouts, session
caps).

> If you don't manage MikroTik gear, ignore this entirely — the core (collection,
> inventory, maps, API) needs none of it.
