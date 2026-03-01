#!/bin/bash
# ============================================================
# Open Family Cloud — パターン3: 自宅サーバー + 固定IP セットアップ
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
# 自宅サーバー向け Traefik 設定をコピーしてからレンダリング
log "自宅サーバー向け Traefik 設定をコピー中..."
cp "$PLATFORM_DIR/config/traefik/traefik.yml" "$PROJECT_ROOT/config/traefik/traefik.yml"
log "Traefik 設定のコピー: OK"

# DNS challenge 用のプレースホルダーも置換
render_all_templates

# DNS challenge プロバイダーの置換（自宅サーバー固有）
if [[ -n "${ACME_DNS_PROVIDER:-}" ]]; then
    sed -i "s|\${ACME_DNS_PROVIDER}|${ACME_DNS_PROVIDER}|g" \
        "$PROJECT_ROOT/config/traefik/traefik.yml"
    log "DNS challenge プロバイダー設定: ${ACME_DNS_PROVIDER}"
fi

# ----------------------------------------------------------
# 4. NAS マウントの確認
# ----------------------------------------------------------
# メール用 NAS パスの確認
if [[ ! -d "${MAIL_STORAGE_PATH}" ]]; then
    warn "メール保存先 ${MAIL_STORAGE_PATH} が存在しません"
    warn "NAS をマウントしてから再実行してください"
    warn "  例: mount -t nfs nas.local:/volume1/mail ${MAIL_STORAGE_PATH}"
    warn "  例: mount -t cifs //nas.local/mail ${MAIL_STORAGE_PATH}"
    exit 1
fi

mkdir -p "${MAIL_STORAGE_PATH}"/{data,state,logs}
mkdir -p mailserver-config
log "メール保存先の準備: OK (${MAIL_STORAGE_PATH})"

# ----------------------------------------------------------
# 5. Jellyfin メディアディレクトリの確認（NAS 直接マウント）
# ----------------------------------------------------------
JELLYFIN_MEDIA="${JELLYFIN_MEDIA_PATH:-/mnt/nas/media}"

if [[ ! -d "${JELLYFIN_MEDIA}" ]]; then
    warn "メディアディレクトリ ${JELLYFIN_MEDIA} が存在しません"
    warn "NAS をマウントしてから再実行してください"
    warn "  例: mount -t nfs nas.local:/volume1/media ${JELLYFIN_MEDIA}"
    warn "  例: mount -t cifs //nas.local/media ${JELLYFIN_MEDIA}"
    exit 1
fi

log "Jellyfin メディアディレクトリ: OK (${JELLYFIN_MEDIA})"

# ----------------------------------------------------------
# 6. NAS ローカルバックアップディレクトリの準備
# ----------------------------------------------------------
BACKUP_LOCAL="${BACKUP_LOCAL_PATH:-/mnt/nas/backup}"

if [[ -d "$(dirname "$BACKUP_LOCAL")" ]]; then
    mkdir -p "$BACKUP_LOCAL"
    log "ローカルバックアップ先の準備: OK (${BACKUP_LOCAL})"
else
    warn "バックアップ先の親ディレクトリが存在しません: $(dirname "$BACKUP_LOCAL")"
    warn "NAS バックアップはスキップされます"
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
log "ポートフォワーディングの確認:"
echo "  ルーターで以下のポートが自宅サーバーに転送されているか確認してください:"
echo "    TCP  80   — HTTP（Let's Encrypt + リダイレクト）"
echo "    TCP  443  — HTTPS（全 Web サービス）"
echo "    TCP  25   — SMTP（メール受信）"
echo "    TCP  465  — SMTPS（メール送信）"
echo "    TCP  587  — Submission（メール送信）"
echo "    TCP  993  — IMAPS（メール受信）"
echo "    UDP  ${JVB_PORT}  — Jitsi Meet（JVB メディア通信）"
echo ""
log "次のステップ:"
echo "  1. 上記の DNS レコード（DKIM / SPF / DMARC）を設定"
echo "  2. ルーターのポートフォワーディングを確認"
echo "  3. LDAP 管理画面または scripts/user.sh でユーザーを追加"
echo "  4. 各クライアントからログインを確認"
echo "  5. scripts/backup.sh でバックアップをテスト"
