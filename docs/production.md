# Production hardening

The quickstart runs NDE in **development** mode on plain HTTP so you can try it
in minutes. Before you point it at real equipment, work through this checklist.
NDE has access to device credentials and management planes — treat it as critical
infrastructure.

## 1. Turn on production mode

Set `NDE_ENV=production` on the app services (`migrate`, `serve`, `worker`,
`scheduler`). In this mode NDE **fails to start** unless the security invariants
below hold — that is intentional.

Production mode enforces:

| Invariant | Why |
|---|---|
| PostgreSQL DSN uses `sslmode=verify-full` | the DB link is authenticated and encrypted |
| `ssh.known_hosts_file` is set | SSH host-key verification is on (no silent MITM) |
| `ssh.allow_legacy_algorithms` is false | no global crypto downgrade |
| NetBox (if enabled) is HTTPS, no `insecure_skip_verify` | no unauthenticated sync |

## 2. Encrypted, verified PostgreSQL

`verify-full` requires a TLS-enabled PostgreSQL and a CA you trust. Use a managed
Postgres with TLS, or enable TLS on your own instance, then point the DSN at it:

```
NDE_DATABASE_DSN=postgres://nde:SECRET@db.example.net:5432/nde?sslmode=verify-full&sslrootcert=/opt/nde/pki/postgres-ca.pem
```

Mount the CA file into the app containers (e.g. a read-only volume at
`/opt/nde/pki`). The default compose Postgres (plaintext, in-network) is fine for
development but does **not** satisfy `verify-full`.

## 3. SSH host-key verification

Set the known_hosts path so collection and the bastion verify device keys:

```
NDE_SSH_KNOWN_HOSTS_FILE=/opt/nde/known_hosts
```

Mount a writable volume there. The default policy is **accept-new / TOFU**: the
key is learned on first contact and a key that later **changes** is rejected
(likely MITM) — so the file may start empty. For stricter control, pre-populate
it and set `ssh.host_key_strict: true`, which also rejects unknown hosts.

## 4. HTTPS in front — never expose 8080

`serve` listens on plain HTTP inside the container. Put a reverse proxy with
HTTPS in front of it and bind the app port to loopback only. In your compose
override:

```yaml
services:
  serve:
    environment:
      NDE_ENV: production
    ports:
      - "127.0.0.1:8080:8080"   # only the host/proxy reaches it
```

Example nginx server block (with a real domain + certbot):

```nginx
server {
  server_name nde.example.com;
  location / {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header Upgrade $http_upgrade;     # websockets (live terminal/maps)
    proxy_set_header Connection "upgrade";
  }
}
# then: certbot --nginx -d nde.example.com
```

## 5. Secrets & backups

- **Back up `NDE_CREDENTIAL_KEY`** somewhere safe and separate. It decrypts your
  device credentials; without it, the encrypted data is lost forever.
- Keep `.env` readable only by the deploy user (`chmod 600 .env`).
- Back up the database volume regularly and test a restore:

  ```bash
  docker compose exec -T db pg_dump -U nde nde | gzip > nde-$(date +%F).sql.gz
  ```

## 6. Put it together

A minimal `docker-compose.override.yml` that flips the whole stack to production:

```yaml
services:
  migrate:   { environment: { NDE_ENV: production } }
  worker:    { environment: { NDE_ENV: production } }
  scheduler: { environment: { NDE_ENV: production } }
  serve:
    environment: { NDE_ENV: production }
    ports: ["127.0.0.1:8080:8080"]
```

Set `NDE_DATABASE_DSN` (verify-full) and `NDE_SSH_KNOWN_HOSTS_FILE` in your `.env`
so every service inherits them. Then `docker compose up -d` and confirm all
services stay healthy — if a service exits on boot, read its logs: production
mode refuses to start when an invariant above is not met.
