# アーキテクチャ概要

## サービス構成

Open Family Cloud は以下の14サービスを統合します:

```
┌─────────────────────────────────────────────────────┐
│                   Traefik (リバースプロキシ)           │
│               TLS 終端 + サブドメインルーティング        │
├───────────┬──────────┬──────────┬───────────────────┤
│           │          │          │                   │
│  cloud.*  │  chat.*  │  meet.*  │  その他サービス     │
│ Nextcloud │  Element │  Jitsi   │  media.* vault.*  │
│           │          │          │  ldap.* mail.*    │
├───────────┴──────────┴──────────┴───────────────────┤
│                                                     │
│  ┌─────────┐  ┌───────┐  ┌──────────┐              │
│  │PostgreSQL│  │ Redis │  │ OpenLDAP │  共有インフラ  │
│  │  (3 DB) │  │(cache)│  │ (認証)   │              │
│  └─────────┘  └───────┘  └──────────┘              │
└─────────────────────────────────────────────────────┘
```

## ネットワーク分離

3つのネットワークでサービスを分離:

- **ofc-frontend**: Traefik + Web公開サービス
- **ofc-backend**: PostgreSQL, Redis, OpenLDAP + DB接続が必要なサービス（内部のみ）
- **ofc-jitsi**: Jitsi 内部通信（Prosody, Jicofo, JVB, Web）

## 認証フロー

```
ユーザー → 各サービス → OpenLDAP (認証)
                          ↑
                   scripts/user.sh で管理
```

全サービスが OpenLDAP に対して認証を行い、シングルサインオン（同一認証情報）を実現します。

## ディレクトリ構成

```
open-family-cloud/
├── config/          # 共有サービス設定（全パターン共通）
├── scripts/
│   ├── lib/         # 共有スクリプトライブラリ
│   ├── user.sh      # ユーザー管理（全パターン共通）
│   └── render-templates.sh
├── platforms/
│   ├── vps-compose/      # パターン1: VPS + Docker Compose
│   ├── vps-k8s/          # パターン2: VPS + Kubernetes
│   ├── home-static-ip/   # パターン3: 自宅 + 固定IP
│   └── home-tunnel/      # パターン4: 自宅 + WireGuard
├── tests/
└── docs/
```

## 設定テンプレートシステム

`config/` 内のファイルは `_PLACEHOLDER` サフィックスのプレースホルダーを使用:
- `DOMAIN_PLACEHOLDER` → `.env` の `DOMAIN` 値
- `LDAP_BASE_DN_PLACEHOLDER` → `.env` の `LDAP_BASE_DN` 値
- etc.

`scripts/render-templates.sh` または各パターンの `setup.sh` が `sed` で置換します。
