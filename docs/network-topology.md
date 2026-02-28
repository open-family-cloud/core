# パターン別ネットワーク構成

## パターン1: VPS + Docker Compose

```
Internet
   │
   ▼
┌──────────────┐
│  VPS         │
│              │
│  :80/:443    │
│  Traefik ────┤── ofc-frontend ── [Nextcloud, Element, Jitsi-Web, ...]
│  (TLS)       │
│              ├── ofc-backend ─── [PostgreSQL, Redis, OpenLDAP]
│              │
│  :25/587/993 ├── ofc-jitsi ───── [Prosody, Jicofo, JVB]
│  Mailserver  │
│              │
│  :10000/udp  │
│  JVB         │
└──────────────┘
```

## パターン2: VPS + Kubernetes

```
Internet
   │
   ▼
┌──────────────────────────┐
│  Kubernetes Cluster      │
│                          │
│  Ingress Controller      │
│  (cert-manager)          │
│    │                     │
│    ├── ofc namespace     │
│    │   ├── frontend pods │
│    │   ├── backend pods  │  ← NetworkPolicy で分離
│    │   └── jitsi pods    │
│    │                     │
│  NodePort :30025/587/993 │  ← メール
│  NodePort :30000/udp     │  ← JVB
└──────────────────────────┘
```

## パターン3: 自宅 + 固定IP

```
Internet
   │
   ▼ ポートフォワーディング
┌──────────────┐
│  ルーター     │
│  :80,443 ─────┤
│  :25,587,993  │
│  :10000/udp   │
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  自宅サーバー  │
│              │
│  Traefik ────┤── ofc-frontend
│  (HTTP/DNS   │
│   challenge) ├── ofc-backend
│              │
│  NAS ────────┤── メール、メディア、バックアップ
└──────────────┘
```

## パターン4: 自宅 + WireGuard トンネル

```
Internet
   │
   ▼
┌──────────────────────┐           ┌──────────────────────┐
│  VPS                 │           │  自宅サーバー          │
│                      │           │                      │
│  Traefik             │ WireGuard │  14サービス           │
│  (TLS終端)    ◄──────┼───────────┼──►  (Nextcloud等)    │
│  :443 → wg0          │ トンネル   │  wg0 ← :80          │
│                      │           │                      │
│  WireGuard Server    │           │  WireGuard Client    │
│  10.100.0.1          │           │  10.100.0.2          │
└──────────────────────┘           │                      │
                                   │  NAS ── メール/メディア │
                                   └──────────────────────┘
```
