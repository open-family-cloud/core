#!/bin/bash
# ============================================================
# Open Family Cloud — パターン2: VPS + Kubernetes バックアップ
# kubectl exec で PostgreSQL / LDAP をダンプし、S3 にアップロード
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

# k8s 向けに実行コマンドを上書き
BACKUP_EXEC_CMD="kubectl exec -n ofc"
BACKUP_PG_TARGET="deploy/postgres --"
BACKUP_LDAP_TARGET="deploy/openldap --"

BACKUP_DIR="/tmp/ofc-backup-$(date +%Y%m%d-%H%M%S)"
PRE_UPDATE=false

if [[ "${1:-}" = "--pre-update" ]]; then
    PRE_UPDATE=true
    log "アップデート前バックアップモード"
fi

mkdir -p "$BACKUP_DIR"

# ----------------------------------------------------------
# 1-2. PostgreSQL / LDAP ダンプ
# ----------------------------------------------------------
dump_postgres "$BACKUP_DIR"
dump_ldap "$BACKUP_DIR"

# ----------------------------------------------------------
# 3. 設定ファイルのアーカイブ
# ----------------------------------------------------------
tar_config "$BACKUP_DIR"

# ----------------------------------------------------------
# 4. S3 にアップロード
# ----------------------------------------------------------
EXTRA_TAGS=""
$PRE_UPDATE && EXTRA_TAGS="pre-update"

if upload_to_s3 "$BACKUP_DIR" "$EXTRA_TAGS"; then
    rm -rf "$BACKUP_DIR"
    log "一時ファイルを削除しました"
    echo ""
    log "バックアップ完了"
    restic snapshots --latest 3
else
    exit 0
fi
