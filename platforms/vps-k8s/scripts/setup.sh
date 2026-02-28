#!/bin/bash
# ============================================================
# Open Family Cloud — パターン2: VPS + Kubernetes セットアップ
# Kustomize マニフェストを適用し、サービスを起動します
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
# 1. 前提条件の確認
# ----------------------------------------------------------
for cmd in kubectl kustomize; do
    if ! command -v "$cmd" &>/dev/null; then
        err "${cmd} がインストールされていません"
        exit 1
    fi
done

# ----------------------------------------------------------
# 2. .env の読み込みと検証
# ----------------------------------------------------------
load_env
validate_required_vars "${COMMON_REQUIRED_VARS[@]}"

# ----------------------------------------------------------
# 3. 共有設定ファイルのテンプレートレンダリング
# ----------------------------------------------------------
render_all_templates

# ----------------------------------------------------------
# 4. Kubernetes Secret の生成
# ----------------------------------------------------------
log "Kubernetes Secret を生成中..."

kubectl create namespace ofc --dry-run=client -o yaml | kubectl apply -f -

# PostgreSQL Secret
kubectl create secret generic postgres-secret \
    --namespace=ofc \
    --from-literal=POSTGRES_PASSWORD="${POSTGRES_PASSWORD}" \
    --from-literal=POSTGRES_NEXTCLOUD_DB="${POSTGRES_NEXTCLOUD_DB}" \
    --from-literal=POSTGRES_NEXTCLOUD_USER="${POSTGRES_NEXTCLOUD_USER}" \
    --from-literal=POSTGRES_NEXTCLOUD_PASSWORD="${POSTGRES_NEXTCLOUD_PASSWORD}" \
    --from-literal=POSTGRES_SYNAPSE_DB="${POSTGRES_SYNAPSE_DB}" \
    --from-literal=POSTGRES_SYNAPSE_USER="${POSTGRES_SYNAPSE_USER}" \
    --from-literal=POSTGRES_SYNAPSE_PASSWORD="${POSTGRES_SYNAPSE_PASSWORD}" \
    --from-literal=POSTGRES_VAULTWARDEN_DB="${POSTGRES_VAULTWARDEN_DB}" \
    --from-literal=POSTGRES_VAULTWARDEN_USER="${POSTGRES_VAULTWARDEN_USER}" \
    --from-literal=POSTGRES_VAULTWARDEN_PASSWORD="${POSTGRES_VAULTWARDEN_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

# LDAP Secret
kubectl create secret generic ldap-secret \
    --namespace=ofc \
    --from-literal=LDAP_ORGANISATION="${LDAP_ORGANISATION}" \
    --from-literal=LDAP_DOMAIN="${LDAP_DOMAIN}" \
    --from-literal=LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD}" \
    --from-literal=LDAP_CONFIG_PASSWORD="${LDAP_CONFIG_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Nextcloud Secret
kubectl create secret generic nextcloud-secret \
    --namespace=ofc \
    --from-literal=POSTGRES_DB="${POSTGRES_NEXTCLOUD_DB}" \
    --from-literal=POSTGRES_USER="${POSTGRES_NEXTCLOUD_USER}" \
    --from-literal=POSTGRES_PASSWORD="${POSTGRES_NEXTCLOUD_PASSWORD}" \
    --from-literal=NEXTCLOUD_ADMIN_USER="${NEXTCLOUD_ADMIN_USER}" \
    --from-literal=NEXTCLOUD_ADMIN_PASSWORD="${NEXTCLOUD_ADMIN_PASSWORD}" \
    --from-literal=OVERWRITEHOST="cloud.${DOMAIN}" \
    --from-literal=MAIL_DOMAIN="${DOMAIN}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Vaultwarden Secret
kubectl create secret generic vaultwarden-secret \
    --namespace=ofc \
    --from-literal=DOMAIN="https://vault.${DOMAIN}" \
    --from-literal=DATABASE_URL="postgresql://${POSTGRES_VAULTWARDEN_USER}:${POSTGRES_VAULTWARDEN_PASSWORD}@postgres/${POSTGRES_VAULTWARDEN_DB}" \
    --from-literal=SIGNUPS_ALLOWED="${VAULTWARDEN_SIGNUPS_ALLOWED}" \
    --from-literal=ADMIN_TOKEN="${VAULTWARDEN_ADMIN_TOKEN}" \
    --from-literal=SMTP_FROM="vault@${DOMAIN}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Jitsi Secret
kubectl create secret generic jitsi-secret \
    --namespace=ofc \
    --from-literal=PUBLIC_URL="https://meet.${DOMAIN}" \
    --from-literal=LDAP_BASE="${LDAP_BASE_DN}" \
    --from-literal=LDAP_BINDDN="cn=admin,${LDAP_BASE_DN}" \
    --from-literal=LDAP_BINDPW="${LDAP_ADMIN_PASSWORD}" \
    --from-literal=LDAP_FILTER="(objectClass=inetOrgPerson)" \
    --from-literal=JICOFO_COMPONENT_SECRET="${JITSI_SECRET_JICOFO_COMPONENT}" \
    --from-literal=JICOFO_AUTH_PASSWORD="${JITSI_SECRET_JICOFO_AUTH}" \
    --from-literal=JVB_AUTH_PASSWORD="${JITSI_SECRET_JVB_AUTH}" \
    --from-literal=JVB_PORT="${JVB_PORT}" \
    --from-literal=JVB_ADVERTISE_IPS="${JVB_ADVERTISE_IP}" \
    --dry-run=client -o yaml | kubectl apply -f -

# Mailserver Secret
kubectl create secret generic mailserver-secret \
    --namespace=ofc \
    --from-literal=LDAP_SERVER_HOST="ldap://openldap" \
    --from-literal=LDAP_SEARCH_BASE="${LDAP_BASE_DN}" \
    --from-literal=LDAP_BIND_DN="cn=admin,${LDAP_BASE_DN}" \
    --from-literal=LDAP_BIND_PW="${LDAP_ADMIN_PASSWORD}" \
    --dry-run=client -o yaml | kubectl apply -f -

log "Secret 生成: OK"

# ----------------------------------------------------------
# 5. Kustomize マニフェストの適用
# ----------------------------------------------------------
OVERLAY="${OFC_K8S_OVERLAY:-single-node}"
log "Kustomize overlay: ${OVERLAY}"

kustomize build "kustomize/overlays/${OVERLAY}" | kubectl apply -f -
log "マニフェスト適用: OK"

# ----------------------------------------------------------
# 6. デプロイ完了待機
# ----------------------------------------------------------
log "Pod の起動を待機中..."
kubectl wait --namespace=ofc \
    --for=condition=Ready pod \
    --selector=app.kubernetes.io/component=database \
    --timeout=120s || warn "PostgreSQL の起動に時間がかかっています"

log "全 Pod の起動を待機中（最大5分）..."
kubectl wait --namespace=ofc \
    --for=condition=Ready pod --all \
    --timeout=300s || warn "一部の Pod がまだ起動していません"

# ----------------------------------------------------------
# 7. ヘルスチェック
# ----------------------------------------------------------
"$SCRIPT_DIR/healthcheck.sh"

echo ""
log "============================================"
log " Open Family Cloud (k8s) セットアップ完了！"
log "============================================"
echo ""
echo "  各サービスの URL:"
echo "    ファイル共有  : https://cloud.${DOMAIN}"
echo "    チャット      : https://chat.${DOMAIN}"
echo "    オンライン会議: https://meet.${DOMAIN}"
echo "    メディア      : https://media.${DOMAIN}"
echo "    パスワード管理: https://vault.${DOMAIN}"
echo ""
log "次のステップ:"
echo "  1. cert-manager の ClusterIssuer を設定"
echo "  2. scripts/user.sh でユーザーを追加"
echo "  3. 各クライアントからログインを確認"
