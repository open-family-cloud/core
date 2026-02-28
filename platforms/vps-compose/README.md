# パターン1: VPS + Docker Compose

VPS 1台に Docker Compose で全14サービスをデプロイするパターンです。

## 前提条件

- VPS（2GB+ RAM、Ubuntu/Debian 推奨）
- Docker + Docker Compose v2
- ドメイン名（DNS A レコードを VPS IP に設定済み）
- Block Storage（メール用）
- S3 Object Storage（Nextcloud / Synapse / バックアップ用）

## セットアップ

```bash
# 1. リポジトリをクローン
git clone https://github.com/open-family-cloud/core.git
cd core/platforms/vps-compose

# 2. .env を作成
cp .env.example .env
nano .env  # 各項目を設定

# 3. セットアップ実行
./scripts/setup.sh
```

## 運用コマンド

```bash
./scripts/update.sh       # アップデート（git pull + backup + image update）
./scripts/backup.sh       # バックアップ（PostgreSQL/LDAP/config → S3）
./scripts/healthcheck.sh  # 全サービスのヘルスチェック

# ユーザー管理（リポジトリルートから実行）
../../scripts/user.sh add <username> <email> <display_name>
../../scripts/user.sh list
../../scripts/user.sh delete <username>
```

## ネットワーク構成

```
Internet → Traefik (:80/:443) → 各サービス
             ├── ofc-frontend（Web公開サービス）
             ├── ofc-backend（DB/キャッシュ/LDAP、内部のみ）
             └── ofc-jitsi（Jitsi内部通信、内部のみ）
```

## ストレージ

| データ | 保存先 |
|-------|--------|
| PostgreSQL / Redis / LDAP | VPS SSD（Docker Volume） |
| メール | Block Storage（`MAIL_STORAGE_PATH`） |
| Nextcloud ファイル | S3 Object Storage |
| Synapse メディア | S3 Object Storage |
| Jellyfin メディア | S3 via rclone mount |
| バックアップ | S3 via restic |
