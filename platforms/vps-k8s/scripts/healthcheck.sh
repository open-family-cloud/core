#!/bin/bash
# ============================================================
# Open Family Cloud — パターン2: VPS + Kubernetes ヘルスチェック
# Pod 状態とエンドポイントを確認します
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

echo ""
echo "===== Open Family Cloud (k8s) ヘルスチェック ====="
echo "$(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# --- Pod 状態 ---
echo "■ Pod 状態"
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    ready=$(echo "$line" | awk '{print $2}')
    status=$(echo "$line" | awk '{print $3}')

    if [[ "$status" = "Running" ]]; then
        echo -e "  ${OFC_GREEN}✓${OFC_NC} ${name} (${ready})"
        ((PASS++))
    else
        echo -e "  ${OFC_RED}✗${OFC_NC} ${name} (${status})"
        ((FAIL++))
    fi
done < <(kubectl get pods -n ofc --no-headers 2>/dev/null || echo "")
echo ""

# --- Service エンドポイント ---
echo "■ Service エンドポイント"
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    endpoints=$(echo "$line" | awk '{print $2}')

    if [[ "$endpoints" != "<none>" && -n "$endpoints" ]]; then
        echo -e "  ${OFC_GREEN}✓${OFC_NC} ${name}"
        ((PASS++))
    else
        echo -e "  ${OFC_RED}✗${OFC_NC} ${name} (エンドポイントなし)"
        ((FAIL++))
    fi
done < <(kubectl get endpoints -n ofc --no-headers 2>/dev/null || echo "")
echo ""

# --- Ingress 状態 ---
echo "■ Ingress"
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    hosts=$(echo "$line" | awk '{print $3}')
    address=$(echo "$line" | awk '{print $4}')

    if [[ -n "$address" && "$address" != "<none>" ]]; then
        echo -e "  ${OFC_GREEN}✓${OFC_NC} ${name} → ${hosts}"
        ((PASS++))
    else
        echo -e "  ${OFC_YELLOW}△${OFC_NC} ${name} → ${hosts} (IP 未割当)"
        ((WARN++))
    fi
done < <(kubectl get ingress -n ofc --no-headers 2>/dev/null || echo "")
echo ""

# --- データベース接続 ---
echo "■ データベース接続"
if kubectl exec -n ofc deploy/postgres -- pg_isready -U postgres >/dev/null 2>&1; then
    echo -e "  ${OFC_GREEN}✓${OFC_NC} PostgreSQL"
    ((PASS++))
else
    echo -e "  ${OFC_RED}✗${OFC_NC} PostgreSQL"
    ((FAIL++))
fi

if kubectl exec -n ofc deploy/redis -- redis-cli ping 2>/dev/null | grep -q PONG; then
    echo -e "  ${OFC_GREEN}✓${OFC_NC} Redis"
    ((PASS++))
else
    echo -e "  ${OFC_RED}✗${OFC_NC} Redis"
    ((FAIL++))
fi
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
