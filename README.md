# Open Family Cloud

家族のための自己ホスト型クラウドスイート。メール、チャット、ビデオ会議、ファイル共有、カレンダー、メディアサーバー、パスワード管理を一つの統合環境で提供します。

## サービス一覧

| サービス | ソフトウェア | サブドメイン | 用途 |
| --------- | ------------- | ------------- | ------ |
| リバースプロキシ | Traefik v3 | — | TLS 終端・ルーティング |
| 認証基盤 | OpenLDAP | ldap.example.com | 統合ユーザー管理 |
| メール | docker-mailserver | mail.example.com | IMAP/SMTP |
| チャット | Matrix Synapse + Element | matrix/chat.example.com | メッセージング |
| ビデオ会議 | Jitsi Meet | meet.example.com | オンライン通話 |
| ファイル共有 | Nextcloud | cloud.example.com | ファイル・カレンダー・連絡先 |
| メディア | Jellyfin | media.example.com | 動画・音楽ストリーミング |
| パスワード管理 | Vaultwarden | vault.example.com | Bitwarden 互換 |
| データベース | PostgreSQL 16 | (内部) | 共有 DB |
| キャッシュ | Redis 7 | (内部) | 共有キャッシュ |

## 前提条件

- VPS: 8GB RAM / 4 vCPU 以上（推奨: Linode Shared 8GB）
- Block Storage: 80GB 以上（メール保存用）
- Object Storage: S3 互換（Nextcloud ファイル・メディア・バックアップ用）
- ドメイン名: DNS を管理できるもの
- Docker Engine 24+ / Docker Compose v2

## クイックスタート

```bash
# 1. リポジトリをクローン
git clone https://github.com/your-org/open-family-cloud.git
cd open-family-cloud

# 2. 環境設定ファイルを作成
cp .env.example .env
nano .env  # 各項目を設定

# 3. （任意）カスタマイズ
cp docker-compose.override.example.yml docker-compose.override.yml
nano docker-compose.override.yml

# 4. セットアップ実行
chmod +x scripts/*.sh
./scripts/setup.sh
```

## DNS 設定

以下のレコードをドメインの DNS に追加してください:

```txt
# A レコード（すべてサーバーの IP を指定）
cloud.example.com    → 203.0.113.1
chat.example.com     → 203.0.113.1
matrix.example.com   → 203.0.113.1
meet.example.com     → 203.0.113.1
media.example.com    → 203.0.113.1
vault.example.com    → 203.0.113.1
ldap.example.com     → 203.0.113.1
mail.example.com     → 203.0.113.1

# MX レコード
example.com          MX 10 mail.example.com

# SPF / DKIM / DMARC（メール到達性向上）
example.com          TXT "v=spf1 mx -all"
_dmarc.example.com   TXT "v=DMARC1; p=quarantine"
# DKIM は setup.sh 実行後に生成されるキーを設定
```

## ディレクトリ構成

```txt
open-family-cloud/
├── docker-compose.yml              # メイン構成（リポジトリ管理）
├── docker-compose.override.yml     # 家庭ごとのカスタマイズ（.gitignore）
├── docker-compose.override.example.yml
├── .env                            # 家庭固有の設定値（.gitignore）
├── .env.example
├── config/
│   ├── traefik/                    # リバースプロキシ設定
│   ├── mailserver/                 # メール設定
│   ├── ldap/bootstrap/             # LDAP 初期データ
│   ├── nextcloud/                  # Nextcloud カスタム設定
│   ├── synapse/                    # Matrix Synapse 設定
│   ├── element/                    # Element Web 設定
│   └── postgres/                   # DB 初期化スクリプト
├── scripts/
│   ├── setup.sh                    # 初期セットアップ
│   ├── update.sh                   # アップデート
│   ├── backup.sh                   # バックアップ
│   ├── healthcheck.sh              # ヘルスチェック
│   └── user.sh                     # ユーザー管理
├── CHANGELOG.md
└── README.md
```

## 運用ガイド

### ユーザー管理

```bash
# ユーザー追加
./scripts/user.sh add taro taro@example.com "山田太郎"

# ユーザー一覧
./scripts/user.sh list

# ユーザー削除
./scripts/user.sh delete taro
```

### アップデート

```bash
./scripts/update.sh
```

更新の流れ:

1. 自動バックアップ
2. Git で最新版を取得（差分を表示して確認を求める）
3. Docker イメージの更新・再起動
4. ヘルスチェック

### バックアップ

```bash
# 手動バックアップ
./scripts/backup.sh

# cron で自動化（毎日 3:00）
echo "0 3 * * * /path/to/open-family-cloud/scripts/backup.sh" | crontab -
```

バックアップ対象:

- PostgreSQL 全データベース
- OpenLDAP データ
- 設定ファイル・.env
- Vaultwarden データ
- メール（Block Storage）

※ Nextcloud ファイル・Matrix メディア・Jellyfin メディアは S3 上にあり、プロバイダー側の冗長化で保護されます。

### ヘルスチェック

```bash
./scripts/healthcheck.sh
```

確認項目: 全コンテナ状態、HTTP エンドポイント、メールポート、DB 接続、ディスク使用率、TLS 証明書期限

## カスタマイズ

`docker-compose.override.yml` で本体を変更せずにカスタマイズできます。例:

- サービスの無効化（profiles: disabled）
- GPU トランスコードの有効化
- リソース制限の設定
- Watchtower による自動イメージ更新

詳細は `docker-compose.override.example.yml` を参照してください。

## ストレージ設計

| データ種別 | 保存先 | 理由 |
| ----------- | -------- | ------ |
| メール | Block Storage | 継続的増加・独立スケーリング |
| Nextcloud ファイル | Object Storage (S3) | 大容量・自動スケーリング |
| Matrix メディア | Object Storage (S3) | 同上 |
| Jellyfin メディア | Object Storage (S3) | 大容量（Direct Play 推奨） |
| バックアップ | Object Storage (S3) | restic で暗号化・重複排除 |
| PostgreSQL | VPS 内蔵 SSD | 低レイテンシ必須 |
| Redis | VPS 内蔵 SSD | 同上 |
| OpenLDAP | Docker Volume (SSD) | 軽量・低レイテンシ |

## ネットワーク設計

```txt
Internet
  │
  ├── :80/:443 ──→ Traefik ──→ [frontend network]
  │                              ├── Nextcloud
  │                              ├── Element
  │                              ├── Synapse
  │                              ├── Jitsi Web
  │                              ├── Jellyfin
  │                              ├── Vaultwarden
  │                              └── phpLDAPadmin
  │
  ├── :25/:465/:587/:993 ──→ Mailserver
  │
  └── :10000/udp ──→ Jitsi JVB

[backend network] (internal)
  ├── PostgreSQL
  ├── Redis
  ├── OpenLDAP
  └── (Nextcloud, Synapse, Vaultwarden, Mailserver も接続)

[jitsi-internal network] (internal)
  ├── Jitsi Prosody
  ├── Jitsi Jicofo
  ├── Jitsi JVB
  └── Jitsi Web
```

## 月額コスト目安（Linode）

| 構成 | ユーザー数 | 月額 | 年額 |
| ------ | ----------- | ------ | ------ |
| Small | 3-5人 | ~$33 | ~$396 |
| Standard | 5-15人 | ~$71 | ~$857 |

## ライセンス

MIT License
