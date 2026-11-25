<p align="center">
  <img src="assets/logo.svg" alt="NDE logo" width="96" height="96">
</p>

<h1 align="center">NDE — Network Documentation Engine</h1>

<p align="center"><em>Self-hosted, free to run.</em></p>

NDE is a modular platform to collect, parse and document an ISP's network:
assets & credentials, scheduled read-only collection, multi-vendor parsing into
normalized models, an inventory with snapshots / diff / compliance, interactive
topology, BGP/OSPF/L2VPN/L3VPN/IPAM/VLAN maps, a web admin panel and a REST API.

---

## What you get

- **Collection** — scheduled, read-only SSH collection with a concurrent worker
  pool, leases and retries. Vendor-agnostic core with a per-vendor plugin layer
  (Cisco, Huawei, Juniper, Nokia, MikroTik, and more).
- **Inventory** — a PostgreSQL source of truth with configuration snapshots,
  diffs between collections and compliance checks.
- **Maps & docs** — interactive topology and routing maps, plus an
  auto-generated static wiki (Hugo) served at `/wiki/`.
- **Admin & API** — a web admin panel and a REST API, both served by the same
  binary.
- **Optional integrations** — NetBox sync, Zabbix, a local AI assistant via
  Ollama. All off by default.

The MikroTik **Winbox** web bastion is **not** included in the public image (it
embeds MikroTik's proprietary binary). It is an opt-in add-on you build yourself
— see [docs/winbox.md](docs/winbox.md).

---

## Supported vendors

Collection is over SSH, parsed into normalized models by a per-vendor plugin.
Current vendors:

| Vendor | Platform / OS |
|---|---|
| Cisco | IOS / IOS-XE |
| Huawei | VRP |
| Juniper | Junos |
| Nokia | SR OS/ISAM |
| MikroTik | RouterOS |
| Fiberhome | AN5000/AN6000 Series |

Each plugin collects inventory/version, interfaces and descriptions, neighbors
(LLDP) and IP addressing, with routing details (BGP / OSPF) where the platform
exposes them. The core is vendor-agnostic (plugin architecture), so new vendors
are added as plugins without touching it.

---

## Requirements

- A Linux host with **Docker** and the **Docker Compose** plugin.
- ~1 vCPU / 1 GB RAM to start; more as your fleet and collection frequency grow.
- Outbound HTTPS if you enable NetBox / CVE / AI features.

---

## Quickstart

```bash
# 1. Get the stack
git clone https://github.com/rizottihenrique/nde.git
cd nde

# 2. Create your secrets file
cp .env.example .env

# 3. Generate the three secrets and paste them into .env
docker compose run --rm serve gen-key        # -> NDE_CREDENTIAL_KEY
openssl rand -base64 48 | tr -d '\n'; echo   # -> NDE_JWT_SECRET
openssl rand -hex 24                         # -> POSTGRES_PASSWORD

# 4. Start everything
docker compose up -d
```

Open **http://localhost:8080** and sign in with `admin` / `admin` — you are
required to change the password on first login.

> ⚠️ **Back up `NDE_CREDENTIAL_KEY`.** It encrypts your device credentials at
> rest. Lose it and the encrypted data is unrecoverable.

### Updating

```bash
docker compose pull && docker compose up -d
```

Migrations run automatically on startup (the one-shot `migrate` service).

---

## Going to production

The quickstart runs in **development** mode on plain HTTP for convenience. Before
putting real equipment behind it, read **[docs/production.md](docs/production.md)**:
`NDE_ENV=production` (which enforces TLS to PostgreSQL and SSH host-key
verification), a reverse proxy with HTTPS in front of the app, and backups.

---

## Documentation

- [docs/configuration.md](docs/configuration.md) — the `config.yaml` options.
- [docs/production.md](docs/production.md) — hardening checklist.
- [docs/upgrading.md](docs/upgrading.md) — upgrades and rollbacks.
- [docs/winbox.md](docs/winbox.md) — optional MikroTik Winbox bastion.

---

## License & terms

- This repository (Compose files, scripts, documentation) is licensed under the
  **MIT License** — see [LICENSE](LICENSE).
- The **NDE container image** is proprietary and provided free to self-host —
  **use only; no modification or redistribution** — under the terms in
  **[TERMS.md](TERMS.md)**.
