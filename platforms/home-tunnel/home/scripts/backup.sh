#!/bin/bash
# ============================================================
# Open Family Cloud — パターン4: 自宅サーバー バックアップ
#
# バックアップ対象:
#   - PostgreSQL 全データベースの dump
#   - OpenLDAP データ
#   - 各サービスの設定ファイル
#   - .env ファイル
#
# バックアップ先: NAS ローカルストレージ（S3 不要）
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
export PLATFORM_DIR

OFC_LOG_LABEL="BACKUP"
# shellcheck source=../../../../scripts/lib/common.sh
source "$PLATFORM_DIR/../../../scripts/lib/common.sh"
# shellcheck source=../../../../scripts/lib/env.sh
source "$PLATFORM_DIR/../../../scripts/lib/env.sh"
# shellcheck source=../../../../scripts/lib/backup.sh
source "$PLATFORM_DIR/../../../scripts/lib/backup.sh"

cd "$PLATFORM_DIR"
load_env

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_BASE="${BACKUP_DIR:-/mnt/nas/backup/ofc}"
BACKUP_PATH="${BACKUP_BASE}/${TIMESTAMP}"
PRE_UPDATE=false

if [[ "${1:-}" = "--pre-update" ]]; then
    PRE_UPDATE=true
    BACKUP_PATH="${BACKUP_BASE}/pre-update-${TIMESTAMP}"
    log "アップデート前バックアップモード"
fi

mkdir -p "$BACKUP_PATH"

# ----------------------------------------------------------
# 1. バックアップ先ディレクトリの確認
# ----------------------------------------------------------
if [[ ! -d "$BACKUP_BASE" ]]; then
    warn "バックアップ先 ${BACKUP_BASE} が存在しません"
    warn "NAS がマウントされているか確認してください"
    exit 1
fi

log "バックアップ先: ${BACKUP_PATH}"

# ----------------------------------------------------------
# 2-5. PostgreSQL / LDAP / config / Vaultwarden ダンプ
# ----------------------------------------------------------
dump_postgres "$BACKUP_PATH"
dump_ldap "$BACKUP_PATH"
tar_config "$BACKUP_PATH"
backup_vaultwarden "$BACKUP_PATH"

# ----------------------------------------------------------
# 6. WireGuard 設定のバックアップ
# ----------------------------------------------------------
log "WireGuard 設定をコピー中..."
if [[ -f "${PLATFORM_DIR}/config/wireguard/wg0.conf" ]]; then
    cp "${PLATFORM_DIR}/config/wireguard/wg0.conf" "${BACKUP_PATH}/wireguard-wg0.conf"
    log "  WireGuard 設定: OK"
else
    warn "  WireGuard 設定ファイルが見つかりません"
fi

# ----------------------------------------------------------
# 7. 古いバックアップの整理（7世代保持）
# ----------------------------------------------------------
cleanup_old_backups() {
    local keep=${1:-7}
    local count

    count=$(find "$BACKUP_BASE" -maxdepth 1 -mindepth 1 -type d | wc -l)

    if [[ "$count" -gt "$keep" ]]; then
        log "古いバックアップを整理中（${keep} 世代保持）..."
        find "$BACKUP_BASE" -maxdepth 1 -mindepth 1 -type d \
            | sort | head -n -"${keep}" \
            | while read -r dir; do
                rm -rf "$dir"
                log "  削除: $(basename "$dir")"
            done
    fi
}

cleanup_old_backups 7

# ----------------------------------------------------------
# 8. バックアップサマリー
# ----------------------------------------------------------
BACKUP_SIZE=$(du -sh "$BACKUP_PATH" | cut -f1)

echo ""
log "============================================"
log " バックアップ完了"
log "============================================"
echo "  場所: ${BACKUP_PATH}"
echo "  サイズ: ${BACKUP_SIZE}"
echo ""

if $PRE_UPDATE; then
    log "アップデート前バックアップが完了しました"
fi
