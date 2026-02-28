#!/bin/bash
# ============================================================
# Open Family Cloud — テンプレートレンダリングライブラリ
# config/ 内のプレースホルダーを .env の値で置換
# ============================================================

[[ -n "${_OFC_LIB_TEMPLATE:-}" ]] && return 0
readonly _OFC_LIB_TEMPLATE=1

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# Traefik 静的設定のレンダリング
# $1: 入力ファイル（デフォルト: $PROJECT_ROOT/config/traefik/traefik.yml）
# $2: 出力ファイル（デフォルト: 入力と同じ = インプレース置換）
render_traefik_config() {
    local input="${1:-${PROJECT_ROOT}/config/traefik/traefik.yml}"
    local output="${2:-$input}"

    sed "s|\${ACME_EMAIL}|${ACME_EMAIL}|g" "$input" >"${output}.tmp"
    mv "${output}.tmp" "$output"
    log "Traefik 設定を生成しました: $output"
}

# Synapse homeserver.yaml のレンダリング
# $1: 入力ファイル（デフォルト: $PROJECT_ROOT/config/synapse/homeserver.yaml）
# $2: 出力ファイル（デフォルト: 入力と同じ）
render_synapse_config() {
    local input="${1:-${PROJECT_ROOT}/config/synapse/homeserver.yaml}"
    local output="${2:-$input}"

    cp "$input" "${input}.bak" 2>/dev/null || true
    sed -e "s|SYNAPSE_SERVER_NAME_PLACEHOLDER|${SYNAPSE_SERVER_NAME}|g" \
        -e "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" \
        -e "s|POSTGRES_SYNAPSE_USER_PLACEHOLDER|${POSTGRES_SYNAPSE_USER}|g" \
        -e "s|POSTGRES_SYNAPSE_PASSWORD_PLACEHOLDER|${POSTGRES_SYNAPSE_PASSWORD}|g" \
        -e "s|POSTGRES_SYNAPSE_DB_PLACEHOLDER|${POSTGRES_SYNAPSE_DB}|g" \
        -e "s|LDAP_BASE_DN_PLACEHOLDER|${LDAP_BASE_DN}|g" \
        -e "s|LDAP_ADMIN_PASSWORD_PLACEHOLDER|${LDAP_ADMIN_PASSWORD}|g" \
        -e "s|S3_BUCKET_SYNAPSE_PLACEHOLDER|${S3_BUCKET_SYNAPSE}|g" \
        -e "s|S3_ENDPOINT_PLACEHOLDER|${S3_ENDPOINT}|g" \
        -e "s|S3_ACCESS_KEY_PLACEHOLDER|${S3_ACCESS_KEY}|g" \
        -e "s|S3_SECRET_KEY_PLACEHOLDER|${S3_SECRET_KEY}|g" \
        -e "s|S3_REGION_PLACEHOLDER|${S3_REGION}|g" \
        "${input}.bak" >"$output"
    log "Synapse 設定を生成しました: $output"
}

# Element Web config.json のレンダリング
# $1: 入力ファイル（デフォルト: $PROJECT_ROOT/config/element/config.json）
# $2: 出力ファイル（デフォルト: 入力と同じ）
render_element_config() {
    local input="${1:-${PROJECT_ROOT}/config/element/config.json}"
    local output="${2:-$input}"

    sed "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" "$input" >"${output}.tmp"
    mv "${output}.tmp" "$output"
    log "Element 設定を生成しました: $output"
}

# LDAP bootstrap LDIF のレンダリング
# $1: 入力ファイル（デフォルト: $PROJECT_ROOT/config/ldap/bootstrap/01-structure.ldif）
# $2: 出力ファイル（デフォルト: 入力と同じ）
render_ldap_config() {
    local input="${1:-${PROJECT_ROOT}/config/ldap/bootstrap/01-structure.ldif}"
    local output="${2:-$input}"

    sed "s|LDAP_BASE_DN_PLACEHOLDER|${LDAP_BASE_DN}|g" "$input" >"${output}.tmp"
    mv "${output}.tmp" "$output"
    log "LDAP 設定を生成しました: $output"
}

# 全テンプレートを一括レンダリング
render_all_templates() {
    log "設定ファイルを生成中..."
    render_traefik_config
    render_synapse_config
    render_element_config
    render_ldap_config
    log "設定ファイルの生成: OK"
}
