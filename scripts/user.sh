#!/bin/bash
# ============================================================
# Open Family Cloud — ユーザー管理スクリプト
#
# 使い方:
#   ./scripts/user.sh add   <ユーザー名> <メール> <表示名>
#   ./scripts/user.sh list
#   ./scripts/user.sh delete <ユーザー名>
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

OFC_LOG_LABEL="USER"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/ldap.sh
source "$SCRIPT_DIR/lib/ldap.sh"

# .env を探索して読み込む（PLATFORM_DIR が設定されていればそちらを優先）
load_env

usage() {
    echo "使い方:"
    echo "  $0 add <ユーザー名> <メール> <表示名>"
    echo "  $0 list"
    echo "  $0 delete <ユーザー名>"
    echo ""
    echo "例:"
    echo "  $0 add taro taro@example.com \"山田太郎\""
    echo "  $0 list"
    echo "  $0 delete taro"
    exit 1
}

# --- メイン ---
case "${1:-}" in
    add)
        [[ $# -lt 4 ]] && usage
        ldap_user_add "$2" "$3" "$4"
        ;;
    list)
        ldap_user_list
        ;;
    delete)
        [[ $# -lt 2 ]] && usage
        ldap_user_delete "$2"
        ;;
    *)
        usage
        ;;
esac
