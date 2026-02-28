#!/bin/bash
# ============================================================
# Open Family Cloud — パターン3: 自宅サーバー + 固定IP バックアップ
#
# バックアップ対象:
#   - PostgreSQL 全データベースの dump
#   - OpenLDAP データ
#   - 各サービスの設定ファイル
#   - .env ファイル
#
# バックアップ先:
#   1. NAS ローカルディレクトリ（必須）
#   2. S3 Object Storage（オプション: restic 使用）
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
BACKUP_LOCAL="${BACKUP_LOCAL_PATH:-/mnt/nas/backup}"
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
# 5. NAS ローカルバックアップ（メイン保存先）
# ----------------------------------------------------------
if [[ -d "$BACKUP_LOCAL" ]]; then
    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    LOCAL_DEST="${BACKUP_LOCAL}/ofc-${TIMESTAMP}"
    mkdir -p "$LOCAL_DEST"

    log "NAS にバックアップをコピー中... (${LOCAL_DEST})"
    cp -a "$BACKUP_DIR"/* "$LOCAL_DEST/"

    # メールデータも NAS にバックアップ
    if [[ -d "${MAIL_STORAGE_PATH}/data" ]]; then
        log "メールデータを NAS にバックアップ中..."
        rsync -a --delete "${MAIL_STORAGE_PATH}/data/" "${LOCAL_DEST}/mail-data/" 2>/dev/null || \
            cp -a "${MAIL_STORAGE_PATH}/data" "${LOCAL_DEST}/mail-data" 2>/dev/null || \
            warn "メールデータのコピーに失敗しました"
    fi

    log "NAS ローカルバックアップ: OK (${LOCAL_DEST})"

    # 古いローカルバックアップの整理（7日以上前のものを削除）
    log "古いローカルバックアップを整理中..."
    find "$BACKUP_LOCAL" -maxdepth 1 -name "ofc-*" -type d -mtime +7 -exec rm -rf {} + 2>/dev/null || true
    log "ローカルバックアップの整理: OK"
else
    warn "NAS バックアップ先が見つかりません: ${BACKUP_LOCAL}"
    warn "バックアップは一時ディレクトリにのみ保存されます: ${BACKUP_DIR}"
fi

# ----------------------------------------------------------
# 6. S3 にアップロード（オプション: オフサイトバックアップ）
# ----------------------------------------------------------
EXTRA_TAGS=""
$PRE_UPDATE && EXTRA_TAGS="pre-update"

if [[ -n "${S3_BUCKET_BACKUP:-}" && -n "${BACKUP_ENCRYPTION_KEY:-}" ]]; then
    if upload_to_s3 "$BACKUP_DIR" "$EXTRA_TAGS"; then
        # メールデータも S3 にバックアップ
        if [[ -d "${MAIL_STORAGE_PATH}/data" ]]; then
            log "メールデータを S3 にバックアップ中..."
            restic backup --tag ofc-mail "${MAIL_STORAGE_PATH}/data"
            log "メール S3 バックアップ: OK"
        fi
        log "S3 オフサイトバックアップ: OK"
    fi
else
    info "S3 バックアップはスキップしました（S3_BUCKET_BACKUP または BACKUP_ENCRYPTION_KEY が未設定）"
fi

# ----------------------------------------------------------
# 7. クリーンアップ
# ----------------------------------------------------------
rm -rf "$BACKUP_DIR"
log "一時ファイルを削除しました"

echo ""
log "バックアップ完了"

# 最新のローカルバックアップを表示
if [[ -d "$BACKUP_LOCAL" ]]; then
    LATEST=$(ls -dt "${BACKUP_LOCAL}"/ofc-* 2>/dev/null | head -1)
    if [[ -n "$LATEST" ]]; then
        log "最新のローカルバックアップ: ${LATEST}"
        log "サイズ: $(du -sh "$LATEST" | cut -f1)"
    fi
fi

# restic スナップショットがあれば表示
if command -v restic &>/dev/null && [[ -n "${S3_BUCKET_BACKUP:-}" ]]; then
    export RESTIC_REPOSITORY="s3:${S3_ENDPOINT}/${S3_BUCKET_BACKUP}"
    export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
    export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"
    export RESTIC_PASSWORD="${BACKUP_ENCRYPTION_KEY}"
    restic snapshots --latest 3 2>/dev/null || true
fi
