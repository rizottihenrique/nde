# Upgrading

NDE ships as a rolling container image. Upgrading is a pull + restart; migrations
run automatically on startup via the one-shot `migrate` service.

## Standard upgrade

```bash
docker compose pull
docker compose up -d
```

`migrate` runs first and applies any new schema; `serve`, `worker` and
`scheduler` start only after it succeeds.

## Pin a version in production

`:latest` is convenient for trying NDE, but in production pin an explicit tag so
upgrades are deliberate and reproducible. In your compose override:

```yaml
x-nde-app: &nde-app
  image: ghcr.io/rizottihenrique/nde:v0.1.0
```

Bump the tag when you choose to upgrade, then pull + up.

## Before upgrading

- **Back up the database** (see production.md) so you can roll back.
- Skim the release notes for breaking changes.

## Rolling back

Migrations roll forward. To roll back, restore the database backup taken before
the upgrade and pin the previous image tag:

```bash
docker compose down
# restore your pre-upgrade dump into a fresh db volume, then:
docker compose up -d
```

Keep at least one known-good backup + image tag pair so a rollback is always
possible.
