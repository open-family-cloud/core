#!/bin/bash
# ============================================================
# Open Family Cloud — 環境変数ライブラリ
# .env ロードと必須変数バリデーション
# ============================================================

[[ -n "${_OFC_LIB_ENV:-}" ]] && return 0
readonly _OFC_LIB_ENV=1

# common.sh を先に読み込む
# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# .env ファイルを読み込む
# $1: .env ファイルのパス（省略時は $PLATFORM_DIR/.env → $PROJECT_ROOT/.env を探索）
load_env() {
    local env_file="${1:-}"

    if [[ -z "$env_file" ]]; then
        # PLATFORM_DIR が設定されていればそちらを優先
        if [[ -n "${PLATFORM_DIR:-}" && -f "${PLATFORM_DIR}/.env" ]]; then
            env_file="${PLATFORM_DIR}/.env"
        elif [[ -f "${PROJECT_ROOT}/.env" ]]; then
            env_file="${PROJECT_ROOT}/.env"
        fi
    fi

    if [[ ! -f "$env_file" ]]; then
        err ".env ファイルが見つかりません"
        log "以下のコマンドで作成してください:"
        echo "  cp .env.example .env"
        echo "  nano .env  # 各項目を設定"
        return 1
    fi

    # shellcheck source=/dev/null
    source "$env_file"
    log ".env を読み込みました: $env_file"
}

# 必須変数のバリデーション
# $@: 検証する変数名の配列
validate_required_vars() {
    local vars=("$@")
    local missing=()

    for var in "${vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        err "以下の必須変数が .env に設定されていません:"
        for var in "${missing[@]}"; do
            echo "  - $var"
        done
        return 1
    fi

    log "環境変数の検証: OK"
}

# 全パターン共通の必須変数
COMMON_REQUIRED_VARS=(
    DOMAIN ACME_EMAIL TZ
    LDAP_ORGANISATION LDAP_DOMAIN LDAP_ADMIN_PASSWORD LDAP_BASE_DN
    POSTGRES_PASSWORD
    POSTGRES_NEXTCLOUD_DB POSTGRES_NEXTCLOUD_USER POSTGRES_NEXTCLOUD_PASSWORD
    POSTGRES_SYNAPSE_DB POSTGRES_SYNAPSE_USER POSTGRES_SYNAPSE_PASSWORD
    POSTGRES_VAULTWARDEN_DB POSTGRES_VAULTWARDEN_USER POSTGRES_VAULTWARDEN_PASSWORD
    NEXTCLOUD_ADMIN_USER NEXTCLOUD_ADMIN_PASSWORD
    S3_ENDPOINT S3_ACCESS_KEY S3_SECRET_KEY S3_BUCKET_NEXTCLOUD S3_REGION
    SYNAPSE_SERVER_NAME
    MAIL_STORAGE_PATH
    JVB_ADVERTISE_IP
)
