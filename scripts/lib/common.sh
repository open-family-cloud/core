#!/bin/bash
# ============================================================
# Open Family Cloud — 共通ライブラリ
# 色定義、ログ関数、プロジェクトルート検出
# ============================================================

# 多重読込み防止
[[ -n "${_OFC_LIB_COMMON:-}" ]] && return 0
readonly _OFC_LIB_COMMON=1

# カラー出力
readonly OFC_RED='\033[0;31m'
readonly OFC_GREEN='\033[0;32m'
readonly OFC_YELLOW='\033[1;33m'
readonly OFC_CYAN='\033[0;36m'
readonly OFC_NC='\033[0m'

# ログ関数（ラベルはソース側で上書き可能）
OFC_LOG_LABEL="${OFC_LOG_LABEL:-OFC}"

log()  { echo -e "${OFC_GREEN}[${OFC_LOG_LABEL}]${OFC_NC} $*"; }
warn() { echo -e "${OFC_YELLOW}[${OFC_LOG_LABEL} WARN]${OFC_NC} $*"; }
err()  { echo -e "${OFC_RED}[${OFC_LOG_LABEL} ERROR]${OFC_NC} $*" >&2; }
info() { echo -e "${OFC_CYAN}[${OFC_LOG_LABEL} INFO]${OFC_NC} $*"; }

# プロジェクトルート検出
# 呼び出し元スクリプトの位置から git リポジトリのルートを探す
detect_project_root() {
    local dir="${1:-$(pwd)}"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/CLAUDE.md" && -d "$dir/config" && -d "$dir/scripts/lib" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    err "プロジェクトルートが見つかりません"
    return 1
}

# LIB_DIR: このファイル自身のディレクトリ
OFC_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# PROJECT_ROOT: リポジトリルート（未設定の場合のみ検出）
if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(detect_project_root "$OFC_LIB_DIR")"
fi
