#!/bin/bash
# ============================================================
# Open Family Cloud — バックアップ共通ライブラリ
# pg_dump, slapcat, config tar を $EXEC_CMD パラメータで抽象化
# ============================================================

[[ -n "${_OFC_LIB_BACKUP:-}" ]] && return 0
readonly _OFC_LIB_BACKUP=1

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# コンテナ実行コマンド
# Docker Compose: "docker exec"
# Kubernetes:     "kubectl exec -n ofc"
BACKUP_EXEC_CMD="${BACKUP_EXEC_CMD:-docker exec}"

# PostgreSQL コンテナ名 / Pod名
BACKUP_PG_TARGET="${BACKUP_PG_TARGET:-ofc-postgres}"

# OpenLDAP コンテナ名 / Pod名
BACKUP_LDAP_TARGET="${BACKUP_LDAP_TARGET:-ofc-openldap}"

# Vaultwarden コンテナ名 / Pod名
BACKUP_VW_TARGET="${BACKUP_VW_TARGET:-ofc-vaultwarden}"

# PostgreSQL ダンプ
# $1: バックアップ先ディレクトリ
dump_postgres() {
    local backup_dir=$1
    log "PostgreSQL をダンプ中..."

    for db in "${POSTGRES_NEXTCLOUD_DB}" "${POSTGRES_SYNAPSE_DB}" "${POSTGRES_VAULTWARDEN_DB}"; do
        # shellcheck disable=SC2086
        $BACKUP_EXEC_CMD $BACKUP_PG_TARGET pg_dump -U postgres -Fc "$db" \
            > "${backup_dir}/postgres-${db}.dump"
        log "  ${db}: $(du -sh "${backup_dir}/postgres-${db}.dump" | cut -f1)"
    done
}

# OpenLDAP ダンプ
# $1: バックアップ先ディレクトリ
dump_ldap() {
    local backup_dir=$1
    log "OpenLDAP をダンプ中..."

    # shellcheck disable=SC2086
    $BACKUP_EXEC_CMD $BACKUP_LDAP_TARGET slapcat -n 1 > "${backup_dir}/ldap-data.ldif"
    log "  LDAP: $(du -sh "${backup_dir}/ldap-data.ldif" | cut -f1)"
}

# 設定ファイルのアーカイブ
# $1: バックアップ先ディレクトリ
# $2: Compose/マニフェストファイルのパス（プラットフォーム依存）
tar_config() {
    local backup_dir=$1
    local platform_dir="${2:-${PLATFORM_DIR:-$PROJECT_ROOT}}"

    log "設定ファイルをコピー中..."

    local tar_files=()
    # .env（プラットフォームディレクトリにあれば）
    [[ -f "${platform_dir}/.env" ]] && tar_files+=("${platform_dir}/.env")
    # docker-compose.yml（あれば）
    [[ -f "${platform_dir}/docker-compose.yml" ]] && tar_files+=("${platform_dir}/docker-compose.yml")
    # docker-compose.override.yml（あれば）
    [[ -f "${platform_dir}/docker-compose.override.yml" ]] && tar_files+=("${platform_dir}/docker-compose.override.yml")
    # 共有 config/
    tar_files+=("${PROJECT_ROOT}/config/")

    tar czf "${backup_dir}/config.tar.gz" "${tar_files[@]}" 2>/dev/null || true
    log "  config: $(du -sh "${backup_dir}/config.tar.gz" | cut -f1)"
}

# Vaultwarden データのコピー
# $1: バックアップ先ディレクトリ
backup_vaultwarden() {
    local backup_dir=$1
    log "Vaultwarden データをコピー中..."

    # shellcheck disable=SC2086
    docker cp "${BACKUP_VW_TARGET}:/data" "${backup_dir}/vaultwarden-data" 2>/dev/null || \
        warn "Vaultwarden データのコピーに失敗（初回起動前の可能性）"
}

# restic を使った S3 アップロード
# $1: バックアップディレクトリ  $2: 追加タグ（オプション）
upload_to_s3() {
    local backup_dir=$1
    local extra_tags="${2:-}"

    if ! command -v restic &>/dev/null; then
        warn "restic がインストールされていません。ローカルのみにバックアップします。"
        warn "  apt install restic  でインストールできます"
        warn "  バックアップ先: ${backup_dir}"
        return 1
    fi

    export RESTIC_REPOSITORY="s3:${S3_ENDPOINT}/${S3_BUCKET_BACKUP}"
    export AWS_ACCESS_KEY_ID="${S3_ACCESS_KEY}"
    export AWS_SECRET_ACCESS_KEY="${S3_SECRET_KEY}"
    export RESTIC_PASSWORD="${BACKUP_ENCRYPTION_KEY}"

    # リポジトリがなければ初期化
    if ! restic snapshots &>/dev/null; then
        log "restic リポジトリを初期化中..."
        restic init
    fi

    local tags="--tag ofc-system"
    [[ -n "$extra_tags" ]] && tags="$tags --tag $extra_tags"

    log "S3 にアップロード中..."
    # shellcheck disable=SC2086
    restic backup $tags "$backup_dir"

    # 保持ポリシー: 日次7、週次4、月次6
    log "古いバックアップを整理中..."
    restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

    log "S3 アップロード: OK"
}
