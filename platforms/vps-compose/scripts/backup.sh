#!/bin/bash
# ============================================================
# Open Family Cloud — パターン1: VPS + Docker Compose バックアップ
#
# バックアップ対象:
#   - PostgreSQL 全データベースの dump
#   - OpenLDAP データ
#   - 各サービスの設定ファイル
#   - .env ファイル
#
# バックアップ先: S3 Object Storage（restic 使用）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
export PLATFORM_DIR

OFC_LOG_LABEL="BACKUP"
# shellcheck source=../../../scripts/lib/common.sh
source "$PLATFORM_DIR/../../scripts/lib/common.sh"
# shellcheck source=../../../scripts/lib/env.sh
source "$PLATFORM_DIR/../../scripts/lib/env.sh"
# shellcheck source=../../../scripts/lib/backup.sh
source "$PLATFORM_DIR/../../scripts/lib/backup.sh"

cd "$PLATFORM_DIR"
load_env

BACKUP_DIR="/tmp/ofc-backup-$(date +%Y%m%d-%H%M%S)"
PRE_UPDATE=false

if [[ "${1:-}" = "--pre-update" ]]; then
    PRE_UPDATE=true
    log "アップデート前バックアップモード"
fi

mkdir -p "$BACKUP_DIR"

# ----------------------------------------------------------
# 1-4. PostgreSQL / LDAP / config / Vaultwarden ダンプ
# ----------------------------------------------------------
dump_postgres "$BACKUP_DIR"
dump_ldap "$BACKUP_DIR"
tar_config "$BACKUP_DIR"
backup_vaultwarden "$BACKUP_DIR"

# ----------------------------------------------------------
# 5. S3 にアップロード
# ----------------------------------------------------------
EXTRA_TAGS=""
$PRE_UPDATE && EXTRA_TAGS="pre-update"

if upload_to_s3 "$BACKUP_DIR" "$EXTRA_TAGS"; then
    # ----------------------------------------------------------
    # 6. メール（Block Storage）のバックアップ
    # ----------------------------------------------------------
    if [[ -d "${MAIL_STORAGE_PATH}/data" ]]; then
        log "メールデータを S3 にバックアップ中..."
        restic backup --tag ofc-mail "${MAIL_STORAGE_PATH}/data"
        log "メールバックアップ: OK"
    fi

    # クリーンアップ
    rm -rf "$BACKUP_DIR"
    log "一時ファイルを削除しました"

    echo ""
    log "バックアップ完了"
    restic snapshots --latest 3
else
    # restic がない場合はローカルにのみバックアップ
    exit 0
fi
