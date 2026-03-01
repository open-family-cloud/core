#!/bin/bash
# ============================================================
# Open Family Cloud — パターン4: 自宅サーバー セットアップ
# .env の値をもとに WireGuard + 全サービスを構成・起動します
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
export PLATFORM_DIR

OFC_LOG_LABEL="OFC"
# shellcheck source=../../../../scripts/lib/common.sh
source "$PLATFORM_DIR/../../../scripts/lib/common.sh"
# shellcheck source=../../../../scripts/lib/env.sh
source "$PLATFORM_DIR/../../../scripts/lib/env.sh"
# shellcheck source=../../../../scripts/lib/template.sh
source "$PLATFORM_DIR/../../../scripts/lib/template.sh"

cd "$PLATFORM_DIR"

# ----------------------------------------------------------
# 1. .env ファイルの読み込みと検証
# ----------------------------------------------------------
load_env
validate_required_vars "${COMMON_REQUIRED_VARS[@]}"

# パターン4 追加変数の検証
TUNNEL_REQUIRED_VARS=(
    VPS_IP
    WG_SERVER_PORT
    WG_SERVER_PUBLIC_KEY
    WG_CLIENT_PRIVATE_KEY
    WG_CLIENT_IP
    WG_SERVER_IP
)
validate_required_vars "${TUNNEL_REQUIRED_VARS[@]}"

# ----------------------------------------------------------
# 2. 前提条件の確認
# ----------------------------------------------------------
for cmd in docker sed; do
    if ! command -v "$cmd" &>/dev/null; then
        err "$cmd が見つかりません。cloud-init が正常に完了しているか確認してください。"
        exit 1
    fi
done

# ----------------------------------------------------------
# 3. 設定ファイルの生成（テンプレートからプレースホルダーを置換）
# ----------------------------------------------------------
render_all_templates

# ----------------------------------------------------------
# 4. WireGuard クライアント設定の生成
# ----------------------------------------------------------
log "WireGuard クライアント設定を生成中..."

WG_CONF_DIR="${PLATFORM_DIR}/config/wireguard"
mkdir -p "$WG_CONF_DIR"

sed -e "s|WG_CLIENT_PRIVATE_KEY_PLACEHOLDER|${WG_CLIENT_PRIVATE_KEY}|g" \
    -e "s|WG_CLIENT_IP_PLACEHOLDER|${WG_CLIENT_IP}|g" \
    -e "s|WG_SERVER_PUBLIC_KEY_PLACEHOLDER|${WG_SERVER_PUBLIC_KEY}|g" \
    -e "s|VPS_IP_PLACEHOLDER|${VPS_IP}|g" \
    -e "s|WG_SERVER_PORT_PLACEHOLDER|${WG_SERVER_PORT}|g" \
    -e "s|WG_SERVER_IP_PLACEHOLDER|${WG_SERVER_IP}|g" \
    "${WG_CONF_DIR}/wg0.conf.example" >"${WG_CONF_DIR}/wg0.conf"

chmod 600 "${WG_CONF_DIR}/wg0.conf"
log "WireGuard クライアント設定の生成: OK"

# ----------------------------------------------------------
# 5. NAS マウントの確認
# ----------------------------------------------------------
if [[ ! -d "${MAIL_STORAGE_PATH}" ]]; then
    warn "メール保存先 ${MAIL_STORAGE_PATH} が存在しません"
    warn "NAS をマウントしてから再実行してください"
    warn "  例: mount -t nfs nas:/share ${MAIL_STORAGE_PATH}"
    exit 1
fi

mkdir -p "${MAIL_STORAGE_PATH}"/{data,state,logs}
mkdir -p mailserver-config
log "メール保存先の準備: OK (${MAIL_STORAGE_PATH})"

# ----------------------------------------------------------
# 6. Jellyfin メディアディレクトリの準備
# ----------------------------------------------------------
JELLYFIN_MEDIA="${JELLYFIN_MEDIA_PATH:-/mnt/nas/media}"

if [[ ! -d "${JELLYFIN_MEDIA}" ]]; then
    warn "メディアディレクトリ ${JELLYFIN_MEDIA} が存在しません"
    warn "NAS のメディアパスを確認してください"
    mkdir -p "${JELLYFIN_MEDIA}"
    log "メディアディレクトリを作成しました: ${JELLYFIN_MEDIA}"
fi

# ----------------------------------------------------------
# 7. Synapse 署名鍵の生成（一時ディレクトリ方式）
# ----------------------------------------------------------
if [[ ! -f "${PROJECT_ROOT}/config/synapse/signing.key" ]]; then
    log "Synapse 署名鍵を生成中..."

    SYNAPSE_TMP="$(mktemp -d)"
    cleanup_synapse_tmp() { sudo rm -rf "$SYNAPSE_TMP"; }
    trap cleanup_synapse_tmp EXIT

    docker run --rm \
        -v "${SYNAPSE_TMP}:/data" \
        -e SYNAPSE_SERVER_NAME="${SYNAPSE_SERVER_NAME}" \
        -e SYNAPSE_REPORT_STATS=no \
        matrixdotorg/synapse:latest generate

    sudo cp "${SYNAPSE_TMP}/${SYNAPSE_SERVER_NAME}.signing.key" \
        "${PROJECT_ROOT}/config/synapse/signing.key"
    sudo chown "$(id -u):$(id -g)" "${PROJECT_ROOT}/config/synapse/signing.key"

    trap - EXIT
    sudo rm -rf "$SYNAPSE_TMP"

    log "Synapse 署名鍵の生成: OK"
fi

# ----------------------------------------------------------
# 8. Docker Compose 起動
# ----------------------------------------------------------
log "Docker イメージを取得中..."
docker compose pull

log "サービスを起動中..."
docker compose up -d

# ----------------------------------------------------------
# 9. 起動確認
# ----------------------------------------------------------
log "サービスの起動を待機中（60秒）..."
sleep 60

"$SCRIPT_DIR/healthcheck.sh"

# ----------------------------------------------------------
# 10. DKIM 鍵の生成 + DNS レコード情報表示
# ----------------------------------------------------------
generate_dkim() {
    if [[ -d "mailserver-config/opendkim/keys/${DOMAIN}" ]]; then
        log "DKIM 鍵は既に存在します。スキップします。"
        return
    fi

    log "DKIM 鍵を生成中..."
    docker exec ofc-mailserver setup config dkim domain "${DOMAIN}"
    log "DKIM 鍵の生成: OK"

    echo ""
    log "============================================"
    log " DNS レコードの設定"
    log "============================================"
    echo ""
    echo "  以下の DNS レコードを追加してください:"
    echo ""

    local dkim_record
    dkim_record="mailserver-config/opendkim/keys/${DOMAIN}/mail.txt"
    if [[ -f "$dkim_record" ]]; then
        echo "  ■ DKIM (TXT レコード):"
        sed 's/^/    /' "$dkim_record"
        echo ""
    fi

    echo "  ■ SPF (TXT レコード):"
    echo "    ホスト: @"
    echo "    値:     v=spf1 mx -all"
    echo ""

    echo "  ■ DMARC (TXT レコード):"
    echo "    ホスト: _dmarc"
    echo "    値:     v=DMARC1; p=quarantine; rua=mailto:postmaster@${DOMAIN}"
    echo ""
}

generate_dkim

# ----------------------------------------------------------
# 11. Nextcloud LDAP 自動設定
# ----------------------------------------------------------
configure_nextcloud_ldap() {
    local occ="docker exec -u www-data ofc-nextcloud php occ"

    if $occ ldap:show-config s01 &>/dev/null; then
        log "Nextcloud LDAP 設定は既に存在します。スキップします。"
        return
    fi

    log "Nextcloud LDAP 連携を設定中..."

    local retry=0
    local max_retry=30
    while ! $occ status --output=json 2>/dev/null | grep -q '"installed":true'; do
        retry=$((retry + 1))
        if [[ "$retry" -ge "$max_retry" ]]; then
            warn "Nextcloud の初期化が完了しませんでした。LDAP 設定をスキップします。"
            warn "手動で設定してください: 管理画面 > LDAP/AD 統合"
            return
        fi
        log "Nextcloud 初期化を待機中... (${retry}/${max_retry})"
        sleep 10
    done

    $occ app:enable user_ldap
    $occ ldap:create-empty-config

    $occ ldap:set-config s01 ldapHost openldap
    $occ ldap:set-config s01 ldapPort 389
    $occ ldap:set-config s01 ldapBase "ou=users,${LDAP_BASE_DN}"
    $occ ldap:set-config s01 ldapAgentName "cn=admin,${LDAP_BASE_DN}"
    $occ ldap:set-config s01 ldapAgentPassword "${LDAP_ADMIN_PASSWORD}"

    $occ ldap:set-config s01 ldapUserFilter "(objectClass=inetOrgPerson)"
    $occ ldap:set-config s01 ldapUserFilterObjectclass "inetOrgPerson"
    $occ ldap:set-config s01 ldapLoginFilter "(&(objectClass=inetOrgPerson)(|(uid=%uid)(mail=%uid)))"
    $occ ldap:set-config s01 ldapLoginFilterUsername 1

    $occ ldap:set-config s01 ldapBaseGroups "ou=groups,${LDAP_BASE_DN}"
    $occ ldap:set-config s01 ldapGroupFilter "(&(objectClass=groupOfNames)(cn=family))"
    $occ ldap:set-config s01 ldapGroupFilterObjectclass "groupOfNames"
    $occ ldap:set-config s01 ldapGroupMemberAssocAttr "member"

    $occ ldap:set-config s01 ldapEmailAttribute "mail"
    $occ ldap:set-config s01 ldapUserDisplayName "cn"

    $occ ldap:set-config s01 ldapConfigurationActive 1

    if $occ ldap:test-config s01; then
        log "Nextcloud LDAP 設定: OK"
    else
        warn "Nextcloud LDAP 接続テストに失敗しました"
        warn "管理画面から設定を確認してください: https://cloud.${DOMAIN}/settings/admin/ldap"
    fi
}

configure_nextcloud_ldap

# ----------------------------------------------------------
# 12. セットアップ完了メッセージ
# ----------------------------------------------------------
echo ""
log "============================================"
log " Open Family Cloud セットアップ完了！"
log " （パターン4: 自宅サーバー + WireGuard トンネル）"
log "============================================"
echo ""
echo "  各サービスの URL:"
echo "    ファイル共有  : https://cloud.${DOMAIN}"
echo "    チャット      : https://chat.${DOMAIN}"
echo "    オンライン会議: https://meet.${DOMAIN}"
echo "    メディア      : https://media.${DOMAIN}"
echo "    パスワード管理: https://vault.${DOMAIN}"
echo "    LDAP 管理     : https://ldap.${DOMAIN}"
echo ""
echo "  メール設定:"
echo "    IMAP: mail.${DOMAIN}:993 (SSL/TLS)"
echo "    SMTP: mail.${DOMAIN}:587 (STARTTLS)"
echo ""
echo "  WireGuard トンネル:"
echo "    VPS IP       : ${VPS_IP}"
echo "    トンネル IP  : ${WG_CLIENT_IP} → ${WG_SERVER_IP}"
echo ""
log "次のステップ:"
echo "  1. VPS 側のセットアップが完了していることを確認"
echo "  2. WireGuard トンネルの疎通を確認: ping ${WG_SERVER_IP}"
echo "  3. 上記の DNS レコード（DKIM / SPF / DMARC）を設定"
echo "  4. LDAP 管理画面または scripts/user.sh でユーザーを追加"
echo "  5. 各クライアントからログインを確認"
echo "  6. scripts/backup.sh でバックアップをテスト"
