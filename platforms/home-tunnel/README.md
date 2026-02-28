# パターン4: 自宅サーバー + WireGuard トンネル

自宅サーバーで全14サービスを稼働し、VPS 経由で WireGuard トンネルを通じて
インターネットに公開するパターンです。

## アーキテクチャ

```
Internet
  │
  ▼
VPS（TLS 終端）
  ├── Traefik v3 (:80/:443)  ←  Let's Encrypt 証明書
  └── WireGuard サーバー (:51820/udp)
        │
        │  WireGuard トンネル（10.100.0.0/24）
        │
        ▼
自宅サーバー
  ├── WireGuard クライアント
  ├── Traefik（トンネル経由で受信）
  ├── ofc-frontend（Web公開サービス）
  ├── ofc-backend（DB/キャッシュ/LDAP、内部のみ）
  └── ofc-jitsi（Jitsi内部通信、内部のみ）
```

### 通信フロー

1. クライアントが `https://cloud.example.com` にアクセス
2. DNS は VPS の公開 IP を返す
3. VPS 側の Traefik が TLS を終端し、WireGuard トンネル経由で自宅サーバーへ転送
4. 自宅サーバー側の Traefik がリクエストを適切なサービスにルーティング

### メリット

- 自宅の高速回線・大容量ストレージを活用できる
- VPS のコストを最小限に抑えられる（TLS 終端 + WireGuard のみ）
- 自宅の IP アドレスを公開しない（VPS が盾になる）

### デメリット

- WireGuard トンネル経由のため VPS 直接デプロイより遅延が大きい
- 自宅の回線が落ちるとサービス全体が停止する
- 2拠点の管理が必要

## デプロイ先

| ディレクトリ | デプロイ先 | 役割 |
|-------------|-----------|------|
| `home/` | 自宅サーバー | 全14サービス + WireGuard クライアント |
| `vps/` | VPS | Traefik TLS 終端 + WireGuard サーバー |

## 前提条件

### VPS
- 最小スペック: 512MB+ RAM、Ubuntu/Debian 推奨
- Docker + Docker Compose v2
- ドメイン名（DNS A レコードを VPS IP に設定済み）
- UDP ポート 51820 を開放

### 自宅サーバー
- 4GB+ RAM 推奨
- Docker + Docker Compose v2
- NAS またはローカルストレージ（メール・メディア用）
- S3 Object Storage（Nextcloud / Synapse 用）

## セットアップ手順

### 1. WireGuard 鍵ペアの生成

```bash
# VPS 側
wg genkey | tee server-private.key | wg pubkey > server-public.key

# 自宅サーバー側
wg genkey | tee client-private.key | wg pubkey > client-public.key
```

生成した鍵を `.env` の対応する変数に設定してください。

### 2. VPS 側のセットアップ

```bash
cd platforms/home-tunnel/vps
cp ../.env.example .env
nano .env  # 各項目を設定（WireGuard 鍵を含む）
./scripts/setup.sh
```

### 3. 自宅サーバー側のセットアップ

```bash
cd platforms/home-tunnel/home
cp ../.env.example .env
nano .env  # 各項目を設定（WireGuard 鍵を含む）
./scripts/setup.sh
```

### 4. トンネル接続の確認

```bash
# 自宅サーバーから VPS への疎通確認
ping 10.100.0.1

# VPS から自宅サーバーへの疎通確認
ping 10.100.0.2
```

## 運用コマンド

### 自宅サーバー側

```bash
cd platforms/home-tunnel/home
./scripts/update.sh       # アップデート
./scripts/backup.sh       # バックアップ（NAS ローカル）
./scripts/healthcheck.sh  # ヘルスチェック（トンネル接続含む）
```

### VPS 側

```bash
cd platforms/home-tunnel/vps
./scripts/healthcheck.sh  # ヘルスチェック（TLS + トンネル確認）
```

### ユーザー管理（自宅サーバー側で実行）

```bash
../../scripts/user.sh add <username> <email> <display_name>
../../scripts/user.sh list
../../scripts/user.sh delete <username>
```

## ストレージ

| データ | 保存先 |
|-------|--------|
| PostgreSQL / Redis / LDAP | 自宅サーバー SSD（Docker Volume） |
| メール | NAS（`MAIL_STORAGE_PATH`） |
| Nextcloud ファイル | S3 Object Storage |
| Synapse メディア | S3 Object Storage |
| Jellyfin メディア | NAS（`JELLYFIN_MEDIA_PATH`） |
| バックアップ | NAS ローカル |

## ネットワーク構成

### VPS 側
```
Internet → Traefik (:80/:443) → WireGuard トンネル → 自宅サーバー
```

### 自宅サーバー側
```
WireGuard トンネル → Traefik → 各サービス
  ├── ofc-frontend（Web公開サービス）
  ├── ofc-backend（DB/キャッシュ/LDAP、内部のみ）
  └── ofc-jitsi（Jitsi内部通信、内部のみ）
```

## トラブルシューティング

### WireGuard トンネルが切断される

```bash
# 自宅サーバー側で WireGuard の状態を確認
docker exec ofc-wireguard wg show

# ハンドシェイクの最終時刻を確認（2分以内が正常）
docker logs ofc-wireguard --tail 20
```

### VPS 側から自宅サーバーに接続できない

```bash
# VPS 側で WireGuard の状態を確認
docker exec ofc-vps-wireguard wg show

# ファイアウォールで UDP 51820 が開放されているか確認
sudo ufw status | grep 51820
```
