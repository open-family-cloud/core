#!/bin/bash
# ============================================================
# Open Family Cloud — パターン1: VPS + Docker Compose セットアップ
# .env の値をもとに設定ファイルを生成し、サービスを起動します
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
export PLATFORM_DIR

OFC_LOG_LABEL="OFC"
# shellcheck source=../../../scripts/lib/common.sh
source "$PLATFORM_DIR/../../scripts/lib/common.sh"
# shellcheck source=../../../scripts/lib/env.sh
source "$PLATFORM_DIR/../../scripts/lib/env.sh"
# shellcheck source=../../../scripts/lib/template.sh
source "$PLATFORM_DIR/../../scripts/lib/template.sh"

cd "$PLATFORM_DIR"

# ----------------------------------------------------------
# 1. .env ファイルの読み込みと検証
# ----------------------------------------------------------
load_env
validate_required_vars "${COMMON_REQUIRED_VARS[@]}"

# ----------------------------------------------------------
# 2. 設定ファイルの生成（テンプレートからプレースホルダーを置換）
# ----------------------------------------------------------
render_all_templates

# ----------------------------------------------------------
# 3. メール用 Block Storage ディレクトリの準備
# ----------------------------------------------------------
if [[ ! -d "${MAIL_STORAGE_PATH}" ]]; then
    warn "メール保存先 ${MAIL_STORAGE_PATH} が存在しません"
    warn "Block Storage をマウントしてから再実行してください"
    warn "  例: mount /dev/vdb1 ${MAIL_STORAGE_PATH}"
    exit 1
fi

mkdir -p "${MAIL_STORAGE_PATH}"/{data,state,logs}
mkdir -p mailserver-config
log "メール保存先の準備: OK (${MAIL_STORAGE_PATH})"

# ----------------------------------------------------------
# 4. Jellyfin メディアディレクトリの準備 + rclone マウント
# ----------------------------------------------------------
JELLYFIN_MEDIA="${JELLYFIN_MEDIA_PATH:-/mnt/s3/jellyfin}"

if [[ "${JELLYFIN_MEDIA}" == /mnt/s3/* ]]; then
    if ! command -v rclone &>/dev/null; then
        warn "rclone がインストールされていません"
        warn "S3 マウントをスキップします。手動でインストール後に再実行してください:"
        warn "  curl https://rclone.org/install.sh | sudo bash"
        sudo mkdir -p "${JELLYFIN_MEDIA}"
        sudo chown "$(id -un):$(id -gn)" "${JELLYFIN_MEDIA}"
    else
        log "rclone で S3 マウントを設定中..."

        S3_BUCKET_JELLYFIN="${S3_BUCKET_JELLYFIN:?S3_BUCKET_JELLYFIN が未設定です}"

        sudo mkdir -p /root/.config/rclone
        sudo tee /root/.config/rclone/rclone.conf >/dev/null <<RCLONE_EOF
[jellyfin-s3]
type = s3
provider = Other
env_auth = false
access_key_id = ${S3_ACCESS_KEY}
secret_access_key = ${S3_SECRET_KEY}
endpoint = ${S3_ENDPOINT}
region = ${S3_REGION}
acl = private
RCLONE_EOF

        sudo mkdir -p "${JELLYFIN_MEDIA}"
        sed -e "s|MOUNT_PATH_PLACEHOLDER|${JELLYFIN_MEDIA}|g" \
            -e "s|BUCKET_PLACEHOLDER|${S3_BUCKET_JELLYFIN}|g" \
            "${PROJECT_ROOT}/config/rclone/rclone-jellyfin.service" \
            | sudo tee /etc/systemd/system/rclone-jellyfin.service >/dev/null

        sudo systemctl daemon-reload
        sudo systemctl enable rclone-jellyfin.service
        sudo systemctl start rclone-jellyfin.service

        log "rclone マウント: OK (${JELLYFIN_MEDIA})"
    fi
else
    if [[ ! -d "${JELLYFIN_MEDIA}" ]]; then
        mkdir -p "${JELLYFIN_MEDIA}"
        log "Jellyfin メディアディレクトリを作成しました: ${JELLYFIN_MEDIA}"
    fi
fi

# ----------------------------------------------------------
# 5. Synapse 署名鍵の生成（一時ディレクトリ方式）
# ----------------------------------------------------------
if [[ ! -f "${PROJECT_ROOT}/config/synapse/signing.key" ]]; then
    log "Synapse 署名鍵を生成中..."

    SYNAPSE_TMP="$(mktemp -d)"
    cleanup_synapse_tmp() { rm -rf "$SYNAPSE_TMP"; }
    trap cleanup_synapse_tmp EXIT

    docker run --rm \
        -v "${SYNAPSE_TMP}:/data" \
        -e SYNAPSE_SERVER_NAME="${SYNAPSE_SERVER_NAME}" \
        -e SYNAPSE_REPORT_STATS=no \
        matrixdotorg/synapse:latest generate

    cp "${SYNAPSE_TMP}/${SYNAPSE_SERVER_NAME}.signing.key" \
        "${PROJECT_ROOT}/config/synapse/signing.key"

    trap - EXIT
    rm -rf "$SYNAPSE_TMP"

    log "Synapse 署名鍵の生成: OK"
fi

# ----------------------------------------------------------
# 6. Docker Compose 起動
# ----------------------------------------------------------
log "Docker イメージを取得中..."
docker compose pull

log "サービスを起動中..."
docker compose up -d

# ----------------------------------------------------------
# 7. 起動確認
# ----------------------------------------------------------
log "サービスの起動を待機中（60秒）..."
sleep 60

"$SCRIPT_DIR/healthcheck.sh"

# ----------------------------------------------------------
# 8. DKIM 鍵の生成 + DNS レコード情報表示
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
# 9. Nextcloud LDAP 自動設定
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
# 10. セットアップ完了メッセージ
# ----------------------------------------------------------
echo ""
log "============================================"
log " Open Family Cloud セットアップ完了！"
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
log "次のステップ:"
echo "  1. 上記の DNS レコード（DKIM / SPF / DMARC）を設定"
echo "  2. LDAP 管理画面または scripts/user.sh でユーザーを追加"
echo "  3. 各クライアントからログインを確認"
echo "  4. scripts/backup.sh でバックアップをテスト"
