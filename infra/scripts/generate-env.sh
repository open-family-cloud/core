#!/usr/bin/env bash
# Terraform output から .env 変数を生成するスクリプト
#
# 使い方:
#   ./generate-env.sh [vultr|linode] [compose|k8s]
#
# Terraform output の env_vars マップから KEY=VALUE 形式で出力する。
# 出力をリダイレクトすることで .env ファイルに追記可能:
#   ./generate-env.sh vultr compose >> ../../platforms/vps-compose/.env
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROVIDER="${1:?使い方: $0 [vultr|linode] [compose|k8s]}"
PATTERN="${2:-compose}"

# プロバイダディレクトリの存在確認
PROVIDER_DIR="${SCRIPT_DIR}/../${PROVIDER}"
if [[ ! -d "$PROVIDER_DIR" ]]; then
    echo "エラー: プロバイダディレクトリが見つかりません: ${PROVIDER_DIR}" >&2
    exit 1
fi

# terraform コマンドの存在確認
if ! command -v terraform &>/dev/null; then
    echo "エラー: terraform コマンドが見つかりません" >&2
    exit 1
fi

# jq コマンドの存在確認
if ! command -v jq &>/dev/null; then
    echo "エラー: jq コマンドが見つかりません" >&2
    exit 1
fi

# パターンに応じたプラットフォームディレクトリ
case "$PATTERN" in
    compose)
        PLATFORM_DIR="platforms/vps-compose"
        ;;
    k8s)
        PLATFORM_DIR="platforms/vps-k8s"
        ;;
    *)
        echo "エラー: パターンは 'compose' または 'k8s' を指定してください" >&2
        exit 1
        ;;
esac

echo "# ============================================================"
echo "# Terraform で生成されたインフラ変数"
echo "# プロバイダ: ${PROVIDER} / パターン: ${PATTERN}"
echo "# 生成日時: $(date -Iseconds)"
echo "# ============================================================"

cd "$PROVIDER_DIR"
terraform output -json env_vars | jq -r 'to_entries[] | "\(.key)=\(.value)"'
