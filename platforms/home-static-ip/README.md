# パターン3: 自宅サーバー + 固定グローバル IP

自宅サーバーに固定グローバル IP を割り当て、Docker Compose で全14サービスをデプロイするパターンです。

## パターン1（VPS）との主な違い

| 項目 | パターン1（VPS） | パターン3（自宅サーバー） |
|------|-----------------|-------------------------|
| メール保存先 | VPS Block Storage | NAS（`/mnt/nas/mail`） |
| Jellyfin メディア | S3 via rclone mount | NAS 直接マウント（`/mnt/nas/media`） |
| TLS 証明書 | HTTP challenge のみ | HTTP challenge + DNS challenge 対応 |
| ネットワーク | VPS がグローバル IP を持つ | ルーターのポートフォワーディングが必要 |

## 前提条件

- 自宅サーバー（4GB+ RAM、Ubuntu/Debian 推奨）
- Docker + Docker Compose v2
- 固定グローバル IP アドレス
- ドメイン名（DNS A レコードをグローバル IP に設定済み）
- NAS またはローカルストレージ（メール・メディア用）
- S3 Object Storage（Nextcloud / Synapse / バックアップ用）

## ファイアウォール / ポートフォワーディング

ルーターで以下のポートを自宅サーバーに転送してください:

| ポート | プロトコル | 用途 |
|--------|-----------|------|
| 80 | TCP | HTTP（Let's Encrypt + リダイレクト） |
| 443 | TCP | HTTPS（全 Web サービス） |
| 25 | TCP | SMTP（メール受信） |
| 465 | TCP | SMTPS（メール送信） |
| 587 | TCP | Submission（メール送信） |
| 993 | TCP | IMAPS（メール受信） |
| 10000 | UDP | Jitsi Meet（JVB メディア通信） |

> DNS challenge を使う場合はポート 80 の転送は不要ですが、HTTP→HTTPS リダイレクトのため推奨します。

## セットアップ

```bash
# 1. リポジトリをクローン
git clone https://github.com/open-family-cloud/core.git
cd core/platforms/home-static-ip

# 2. .env を作成
cp .env.example .env
nano .env  # 各項目を設定

# 3. セットアップ実行
./scripts/setup.sh
```

## 運用コマンド

```bash
./scripts/update.sh       # アップデート（git pull + backup + image update）
./scripts/backup.sh       # バックアップ（PostgreSQL/LDAP/config → NAS + S3）
./scripts/healthcheck.sh  # 全サービスのヘルスチェック

# ユーザー管理（リポジトリルートから実行）
../../scripts/user.sh add <username> <email> <display_name>
../../scripts/user.sh list
../../scripts/user.sh delete <username>
```

## ストレージ

| データ | 保存先 |
|-------|--------|
| PostgreSQL / Redis / LDAP | ローカル SSD（Docker Volume） |
| メール | NAS（`MAIL_STORAGE_PATH`） |
| Nextcloud ファイル | S3 Object Storage |
| Synapse メディア | S3 Object Storage |
| Jellyfin メディア | NAS 直接マウント（`JELLYFIN_MEDIA_PATH`） |
| バックアップ | NAS ローカル + S3（オプション） |
