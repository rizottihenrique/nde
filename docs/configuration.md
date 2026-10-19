# Configuration

NDE reads a YAML config (`configs/config.yaml`, shipped inside the image) and
lets you override the environment-specific and secret values from environment
variables. For most deployments you only set the environment variables below and
leave the YAML alone.

## Environment variables

| Variable | Required | Purpose |
|---|---|---|
| `NDE_CREDENTIAL_KEY` | yes | AES-256 key (base64) encrypting device credentials at rest. Generate with `docker compose run --rm serve gen-key`. |
| `NDE_JWT_SECRET` | yes | Signing secret for session tokens (≥ 32 random bytes). |
| `NDE_DATABASE_DSN` | yes | PostgreSQL DSN. Overrides the YAML. Compose builds it from `POSTGRES_PASSWORD`. |
| `NDE_ENV` | prod | Set to `production` to enforce the security invariants (see production.md). Unset = development. |
| `NDE_SSH_KNOWN_HOSTS_FILE` | prod | Path to the SSH known_hosts file (host-key verification). |
| `NDE_NETBOX_URL` / `NDE_NETBOX_TOKEN` | opt | Enable and authenticate NetBox sync. |
| `NDE_ALERT_WEBHOOK` | opt | Webhook called on configuration-change alerts. |

## Overriding the whole config file

To change YAML options that have no environment variable (engine concurrency,
scheduler timezone, docs behavior, …), mount your own file over the shipped one:

```yaml
services:
  serve:
    volumes:
      - ./config.yaml:/opt/nde/configs/config.yaml:ro
```

Do the same for `worker`, `scheduler` and `migrate` so every role reads the same
config. Start from the shipped file (copy it out with
`docker compose run --rm serve sh -c 'cat configs/config.yaml'`) and edit from
there.

## Notable YAML sections

- `engine` — worker count, timeouts, lease/retry, and the distributed
  concurrency limits (global / per-vendor).
- `scheduler.timezone` — the zone cron routines are evaluated in
  (e.g. `America/Sao_Paulo`). Set it so a `06:00` routine doesn't drift on a
  UTC host.
- `ssh` — `known_hosts_file`, `host_key_strict` (accept-new vs strict) and the
  legacy-algorithm opt-in (refused in production).
- `netbox`, `ai`, `pam` — optional integrations, all off by default. The admin
  panel is the source of truth once configured; the YAML values are only the
  first-start seed.
