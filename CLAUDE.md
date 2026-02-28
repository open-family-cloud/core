# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Open Family Cloud is a self-hosted family cloud suite orchestrating 14 Docker containers. It provides mail, chat, video conferencing, file sharing, calendar, media streaming, and password management — all integrated through OpenLDAP for unified authentication.

The project supports 4 deployment patterns in a monorepo structure:

| # | Pattern | Location | TLS | Directory |
|---|---------|----------|-----|-----------|
| 1 | VPS + Docker Compose | VPS | Traefik (HTTP challenge) | `platforms/vps-compose/` |
| 2 | VPS + Kubernetes | VPS k8s | Ingress Controller | `platforms/vps-k8s/` |
| 3 | Home + Static IP | Home server | Traefik (HTTP/DNS) | `platforms/home-static-ip/` |
| 4 | Home + WireGuard | Home + VPS | VPS TLS → WireGuard | `platforms/home-tunnel/` |

The project is written entirely in Japanese (comments, scripts, docs). All shell scripts use `set -euo pipefail`.

## Commands

```bash
# Lint and test (all patterns)
make lint           # pre-commit on all files
make test           # bats tests
make check          # validate all Compose files
make check-k8s      # validate Kustomize manifests

# User management (shared across all patterns)
./scripts/user.sh add <username> <email> <display_name>
./scripts/user.sh list
./scripts/user.sh delete <username>

# Template rendering (shared)
./scripts/render-templates.sh

# Pattern-specific operations (example: vps-compose)
./platforms/vps-compose/scripts/setup.sh
./platforms/vps-compose/scripts/update.sh
./platforms/vps-compose/scripts/backup.sh
./platforms/vps-compose/scripts/healthcheck.sh
```

## Architecture

### Monorepo Structure

```
open-family-cloud/
├── config/           # Shared service configs (all patterns, 90%+ common)
├── scripts/
│   ├── lib/          # Shared script libraries (common, env, template, ldap, backup)
│   ├── user.sh       # User management (all patterns)
│   └── render-templates.sh
├── platforms/
│   ├── vps-compose/  # Pattern 1: docker-compose.yml + scripts
│   ├── vps-k8s/      # Pattern 2: Kustomize manifests + scripts
│   ├── home-static-ip/ # Pattern 3: Compose + DNS challenge Traefik
│   └── home-tunnel/  # Pattern 4: home/ + vps/ dual deploy
├── tests/
└── docs/
```

### Shared Script Libraries (`scripts/lib/`)

| Library | Purpose |
|---------|---------|
| `common.sh` | Colors, log/warn/err, PROJECT_ROOT detection |
| `env.sh` | .env loading, required vars validation |
| `template.sh` | Placeholder→value sed replacement |
| `ldap.sh` | LDAP user ops with `$LDAP_EXEC_CMD` (Docker/k8s) |
| `backup.sh` | pg_dump, slapcat, config tar with `$BACKUP_EXEC_CMD` |

Platform scripts source these via `source "$PLATFORM_DIR/../../scripts/lib/common.sh"`.

### Service Composition

Traefik v3 terminates TLS and routes to services by subdomain (`cloud.`, `chat.`, `matrix.`, `meet.`, `media.`, `vault.`, `ldap.` + `DOMAIN`). Mail ports (25/465/587/993) are exposed directly.

Shared infrastructure:
- **PostgreSQL 16** — 3 databases (Nextcloud, Synapse, Vaultwarden), initialized by `config/postgres/init-databases.sh`
- **Redis 7** — shared cache for Nextcloud and Synapse
- **OpenLDAP** — central identity provider

### Network Segmentation

Docker Compose patterns use 3 networks:
- `ofc-frontend` — Traefik + web-facing services
- `ofc-backend` (internal) — PostgreSQL, Redis, OpenLDAP
- `ofc-jitsi` (internal) — Jitsi internal components

k8s pattern uses NetworkPolicy to replicate this isolation.

### Configuration Template System

Config files under `config/` use `_PLACEHOLDER` suffixes (e.g., `SYNAPSE_SERVER_NAME_PLACEHOLDER`, `DOMAIN_PLACEHOLDER`). `scripts/lib/template.sh` replaces these with .env values via `sed`.

When modifying templates, use `_PLACEHOLDER` suffix convention and update `template.sh` accordingly.

### Storage Design

Varies by pattern:
- **Pattern 1 (VPS)**: SSD + Block Storage + S3
- **Pattern 2 (k8s)**: PVC + S3
- **Pattern 3 (Home)**: NAS + optional S3
- **Pattern 4 (Tunnel)**: NAS (home) / minimal (VPS)

### Container Naming

All containers use `ofc-` prefix (e.g., `ofc-traefik`, `ofc-postgres`). Pattern 4 VPS containers use `ofc-vps-` prefix.

## Key Files

- `.env.example` — all variables superset (reference); pattern-specific in `platforms/*/`
- `config/` — shared service config templates with placeholder values
- `scripts/lib/` — shared bash libraries
- `platforms/*/docker-compose.yml` — pattern-specific orchestration
- `platforms/vps-k8s/kustomize/` — Kubernetes manifests
- `docs/` — pattern selection guide, architecture, network topology

## Infrastructure as Code (Terraform)

VPS 系パターン（パターン1・2）のインフラを Terraform で自動構築する。`infra/` ディレクトリに格納。

```
infra/
├── modules/          # 共有モジュール (cloud-init, dns-records)
├── vultr/            # Vultr コンピュート実装 (VPS, Storage, Firewall)
├── linode/           # Linode コンピュート実装 (VPS, Storage, Firewall)
├── cloudflare/       # Cloudflare DNS 管理 (A レコード, メール DNS)
└── scripts/          # generate-env.sh (terraform output → .env 変換)
```

```bash
# Terraform コマンド (Makefile 経由)
make tf-init PROVIDER=vultr       # terraform init
make tf-plan PROVIDER=vultr       # terraform plan
make tf-apply PROVIDER=vultr      # terraform apply
make tf-apply PROVIDER=cloudflare # DNS 反映
make tf-validate                  # 全プロバイダの validate
```

- Vultr/Linode はコンピュート専用、DNS は Cloudflare で一元管理
- 各プロバイダは別ディレクトリで管理（workspace ではなく）
- 共通ロジックは `infra/modules/` に抽出
- `terraform.tfvars` は `.gitignore` 対象（API キーを含むため）
- `terraform.tfvars.example` を参照用として同梱

## Important Conventions

- Family-specific values go in `.env`, never hardcoded in tracked files
- Shared config lives in `config/`, platform-specific overrides in `platforms/*/config/`
- All platform scripts source shared libs from `scripts/lib/`
- `$EXEC_CMD` pattern enables Docker/k8s abstraction in lib/ldap.sh and lib/backup.sh
- LDAP bootstrap creates `ou=users` and `ou=groups` with `cn=family` group
- Synapse registration is disabled; users are provisioned via LDAP only
