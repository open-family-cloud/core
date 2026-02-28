#!/bin/bash
# ============================================================
# Open Family Cloud — パターン4: VPS 側セットアップ
# WireGuard サーバー + Traefik TLS 終端を構成・起動します
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
export PLATFORM_DIR

OFC_LOG_LABEL="OFC-VPS"
# shellcheck source=../../../../scripts/lib/common.sh
source "$PLATFORM_DIR/../../../scripts/lib/common.sh"
# shellcheck source=../../../../scripts/lib/env.sh
source "$PLATFORM_DIR/../../../scripts/lib/env.sh"

cd "$PLATFORM_DIR"

# ----------------------------------------------------------
# 1. .env ファイルの読み込みと検証
# ----------------------------------------------------------
load_env

VPS_REQUIRED_VARS=(
    DOMAIN ACME_EMAIL TZ
    VPS_IP
    WG_SERVER_PORT
    WG_SERVER_PRIVATE_KEY
    WG_CLIENT_PUBLIC_KEY
    WG_SERVER_IP
    WG_CLIENT_IP
)
validate_required_vars "${VPS_REQUIRED_VARS[@]}"

# ----------------------------------------------------------
# 2. WireGuard サーバー設定の生成
# ----------------------------------------------------------
log "WireGuard サーバー設定を生成中..."

WG_CONF_DIR="${PLATFORM_DIR}/config/wireguard"
mkdir -p "$WG_CONF_DIR"

sed -e "s|WG_SERVER_PRIVATE_KEY_PLACEHOLDER|${WG_SERVER_PRIVATE_KEY}|g" \
    -e "s|WG_SERVER_IP_PLACEHOLDER|${WG_SERVER_IP}|g" \
    -e "s|WG_SERVER_PORT_PLACEHOLDER|${WG_SERVER_PORT}|g" \
    -e "s|WG_CLIENT_PUBLIC_KEY_PLACEHOLDER|${WG_CLIENT_PUBLIC_KEY}|g" \
    -e "s|WG_CLIENT_IP_PLACEHOLDER|${WG_CLIENT_IP}|g" \
    "${WG_CONF_DIR}/wg0.conf.example" >"${WG_CONF_DIR}/wg0.conf"

chmod 600 "${WG_CONF_DIR}/wg0.conf"
log "WireGuard サーバー設定の生成: OK"

# ----------------------------------------------------------
# 3. Traefik 設定の生成
# ----------------------------------------------------------
log "Traefik 設定を生成中..."

# 静的設定 — ACME_EMAIL を置換
TRAEFIK_CONF="${PLATFORM_DIR}/config/traefik/traefik.yml"
sed -i "s|\${ACME_EMAIL}|${ACME_EMAIL}|g" "$TRAEFIK_CONF"
log "Traefik 静的設定: OK"

# 動的設定 — ドメインと WireGuard クライアント IP を置換
DYNAMIC_DIR="${PLATFORM_DIR}/config/traefik/dynamic"
mkdir -p "$DYNAMIC_DIR"

for f in "$DYNAMIC_DIR"/*.yml; do
    [[ -f "$f" ]] || continue
    sed -i -e "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" \
        -e "s|WG_CLIENT_IP_PLACEHOLDER|${WG_CLIENT_IP}|g" \
        "$f"
done
log "Traefik 動的設定: OK"

# ----------------------------------------------------------
# 4. ファイアウォール確認
# ----------------------------------------------------------
log "ファイアウォール設定を確認中..."

if command -v ufw &>/dev/null; then
    if ! ufw status | grep -q "${WG_SERVER_PORT}/udp"; then
        warn "UFW で WireGuard ポート (${WG_SERVER_PORT}/udp) が許可されていません"
        warn "以下のコマンドで開放してください:"
        echo "  sudo ufw allow ${WG_SERVER_PORT}/udp comment 'WireGuard'"
    else
        log "UFW: WireGuard ポート OK"
    fi
fi

# ----------------------------------------------------------
# 5. Docker Compose 起動
# ----------------------------------------------------------
log "Docker イメージを取得中..."
docker compose pull

log "サービスを起動中..."
docker compose up -d

# ----------------------------------------------------------
# 6. 起動確認
# ----------------------------------------------------------
log "サービスの起動を待機中（15秒）..."
sleep 15

"$SCRIPT_DIR/healthcheck.sh"

# ----------------------------------------------------------
# 7. セットアップ完了メッセージ
# ----------------------------------------------------------
echo ""
log "============================================"
log " VPS 側セットアップ完了！"
log " （パターン4: WireGuard サーバー + TLS 終端）"
log "============================================"
echo ""
echo "  VPS 構成:"
echo "    Traefik (TLS 終端): :80, :443"
echo "    WireGuard サーバー : :${WG_SERVER_PORT}/udp"
echo ""
echo "  WireGuard トンネル:"
echo "    サーバー IP: ${WG_SERVER_IP}"
echo "    クライアント IP: ${WG_CLIENT_IP}"
echo ""
log "次のステップ:"
echo "  1. DNS A レコードを VPS IP (${VPS_IP}) に設定"
echo "  2. 自宅サーバー側のセットアップを実行"
echo "  3. トンネル疎通を確認: ping ${WG_CLIENT_IP}"
