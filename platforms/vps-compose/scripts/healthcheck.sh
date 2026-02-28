#!/bin/bash
# ============================================================
# Open Family Cloud — パターン1: VPS + Docker Compose ヘルスチェック
# 全サービスの稼働状態を確認します
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
export PLATFORM_DIR

OFC_LOG_LABEL="HEALTH"
# shellcheck source=../../../scripts/lib/common.sh
source "$PLATFORM_DIR/../../scripts/lib/common.sh"
# shellcheck source=../../../scripts/lib/env.sh
source "$PLATFORM_DIR/../../scripts/lib/env.sh"

load_env

PASS=0
FAIL=0
WARN=0

check_container() {
    local name=$1
    local status
    status=$(docker inspect --format='{{.State.Status}}' "$name" 2>/dev/null || echo "not_found")

    if [[ "$status" = "running" ]]; then
        echo -e "  ${OFC_GREEN}✓${OFC_NC} $name"
        ((PASS++))
    else
        echo -e "  ${OFC_RED}✗${OFC_NC} $name (status: $status)"
        ((FAIL++))
    fi
}

check_url() {
    local label=$1
    local url=$2
    local expected_code=${3:-200}

    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$url" 2>/dev/null || echo "000")

    if [[ "$code" = "$expected_code" ]]; then
        echo -e "  ${OFC_GREEN}✓${OFC_NC} ${label} (HTTP ${code})"
        ((PASS++))
    elif [[ "$code" = "000" ]]; then
        echo -e "  ${OFC_RED}✗${OFC_NC} ${label} (接続不可)"
        ((FAIL++))
    else
        echo -e "  ${OFC_YELLOW}△${OFC_NC} ${label} (HTTP ${code}, expected ${expected_code})"
        ((WARN++))
    fi
}

check_port() {
    local label=$1
    local host=$2
    local port=$3

    if timeout 5 bash -c "echo >/dev/tcp/${host}/${port}" 2>/dev/null; then
        echo -e "  ${OFC_GREEN}✓${OFC_NC} ${label} (port ${port})"
        ((PASS++))
    else
        echo -e "  ${OFC_RED}✗${OFC_NC} ${label} (port ${port} unreachable)"
        ((FAIL++))
    fi
}

check_disk() {
    local label=$1
    local path=$2
    local threshold=${3:-80}

    if [[ ! -d "$path" ]]; then
        echo -e "  ${OFC_YELLOW}△${OFC_NC} ${label}: パス ${path} が存在しません"
        ((WARN++))
        return
    fi

    local usage
    usage=$(df "$path" | tail -1 | awk '{print $5}' | tr -d '%')

    if [[ "$usage" -lt "$threshold" ]]; then
        echo -e "  ${OFC_GREEN}✓${OFC_NC} ${label}: ${usage}% 使用中"
        ((PASS++))
    elif [[ "$usage" -lt 95 ]]; then
        echo -e "  ${OFC_YELLOW}△${OFC_NC} ${label}: ${usage}% 使用中（${threshold}% 超過）"
        ((WARN++))
    else
        echo -e "  ${OFC_RED}✗${OFC_NC} ${label}: ${usage}% 使用中（危険）"
        ((FAIL++))
    fi
}

echo ""
echo "===== Open Family Cloud ヘルスチェック ====="
echo "$(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# --- コンテナ状態 ---
echo "■ コンテナ状態"
check_container ofc-traefik
check_container ofc-openldap
check_container ofc-postgres
check_container ofc-redis
check_container ofc-mailserver
check_container ofc-synapse
check_container ofc-element
check_container ofc-jitsi-web
check_container ofc-jitsi-prosody
check_container ofc-jitsi-jicofo
check_container ofc-jitsi-jvb
check_container ofc-nextcloud
check_container ofc-jellyfin
check_container ofc-vaultwarden
check_container ofc-fail2ban
echo ""

# --- HTTP エンドポイント ---
echo "■ HTTP エンドポイント"
check_url "Nextcloud"   "https://cloud.${DOMAIN}/status.php"
check_url "Element"     "https://chat.${DOMAIN}"
check_url "Synapse"     "https://matrix.${DOMAIN}/_matrix/client/versions"
check_url "Jitsi Meet"  "https://meet.${DOMAIN}"
check_url "Jellyfin"    "https://media.${DOMAIN}/health"
check_url "Vaultwarden" "https://vault.${DOMAIN}/alive"
echo ""

# --- メールポート ---
echo "■ メールポート"
check_port "SMTP"       "localhost" 25
check_port "Submission" "localhost" 587
check_port "IMAPS"      "localhost" 993
echo ""

# --- データベース ---
echo "■ データベース接続"
if docker exec ofc-postgres pg_isready -U postgres >/dev/null 2>&1; then
    echo -e "  ${OFC_GREEN}✓${OFC_NC} PostgreSQL"
    ((PASS++))
else
    echo -e "  ${OFC_RED}✗${OFC_NC} PostgreSQL"
    ((FAIL++))
fi

if docker exec ofc-redis redis-cli ping 2>/dev/null | grep -q PONG; then
    echo -e "  ${OFC_GREEN}✓${OFC_NC} Redis"
    ((PASS++))
else
    echo -e "  ${OFC_RED}✗${OFC_NC} Redis"
    ((FAIL++))
fi
echo ""

# --- ディスク使用率 ---
echo "■ ディスク使用率"
check_disk "システム SSD" "/" 80
check_disk "メール (Block Storage)" "${MAIL_STORAGE_PATH}" 80
echo ""

# --- TLS 証明書 ---
echo "■ TLS 証明書"
CERT_EXPIRY=$(echo | openssl s_client -servername "cloud.${DOMAIN}" \
    -connect "cloud.${DOMAIN}:443" 2>/dev/null | \
    openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || echo "")

if [[ -n "$CERT_EXPIRY" ]]; then
    EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    DAYS_LEFT=$(( (EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

    if [[ "$DAYS_LEFT" -gt 14 ]]; then
        echo -e "  ${OFC_GREEN}✓${OFC_NC} 有効期限: ${CERT_EXPIRY} (残り ${DAYS_LEFT} 日)"
        ((PASS++))
    elif [[ "$DAYS_LEFT" -gt 0 ]]; then
        echo -e "  ${OFC_YELLOW}△${OFC_NC} 有効期限: ${CERT_EXPIRY} (残り ${DAYS_LEFT} 日 — 要確認)"
        ((WARN++))
    else
        echo -e "  ${OFC_RED}✗${OFC_NC} 証明書が期限切れです"
        ((FAIL++))
    fi
else
    echo -e "  ${OFC_YELLOW}△${OFC_NC} 証明書を確認できませんでした（DNS 未設定の可能性）"
    ((WARN++))
fi
echo ""

# --- Docker リソース ---
echo "■ Docker リソース"
DOCKER_DISK=$(docker system df --format '{{.Size}}' 2>/dev/null | head -1 || echo "N/A")
echo "  使用ディスク: ${DOCKER_DISK}"
echo ""

# --- サマリー ---
echo "==========================================="
TOTAL=$((PASS + FAIL + WARN))
echo -e "結果: ${OFC_GREEN}${PASS} 成功${OFC_NC} / ${OFC_RED}${FAIL} 失敗${OFC_NC} / ${OFC_YELLOW}${WARN} 警告${OFC_NC} (全${TOTAL}項目)"

if [[ "$FAIL" -gt 0 ]]; then
    echo -e "${OFC_RED}問題が検出されました。上記のログを確認してください。${OFC_NC}"
    exit 1
elif [[ "$WARN" -gt 0 ]]; then
    echo -e "${OFC_YELLOW}△ 警告があります。確認を推奨します。${OFC_NC}"
    exit 0
else
    echo -e "${OFC_GREEN}✓ すべて正常です${OFC_NC}"
    exit 0
fi
