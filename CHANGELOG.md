# Changelog

このプロジェクトのすべての注目すべき変更をこのファイルに記録します。
フォーマットは [Keep a Changelog](https://keepachangelog.com/ja/1.0.0/) に準拠し、
バージョニングは [Semantic Versioning](https://semver.org/lang/ja/) に従います。

## [0.1.0] - 2026-02-28

### 追加

- 初回リリース
- docker-compose.yml: 全 14 サービスの構成定義
- .env.example: 家庭ごとの設定テンプレート
- docker-compose.override.example.yml: カスタマイズ例
- scripts/setup.sh: 初期セットアップ自動化
- scripts/update.sh: Git ベースのアップデート
- scripts/backup.sh: S3 + restic バックアップ
- scripts/healthcheck.sh: 全サービスのヘルスチェック
- Traefik リバースプロキシ + Let's Encrypt 自動 TLS
- OpenLDAP 統合認証
- PostgreSQL 共有データベース（Nextcloud / Synapse / Vaultwarden）
- Redis 共有キャッシュ
- docker-mailserver（LDAP 連携）
- Matrix Synapse + Element Web（LDAP 連携）
- Jitsi Meet（LDAP 認証）
- Nextcloud（S3 Primary Storage / CalDAV / CardDAV）
- Jellyfin メディアサーバー
- Vaultwarden パスワード管理

### セキュリティ

- backend ネットワークを internal: true に設定（外部アクセス不可）
- Jitsi 内部ネットワークの分離
- Traefik でのセキュリティヘッダー適用
- HTTP → HTTPS 自動リダイレクト
