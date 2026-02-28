#!/bin/bash
# ============================================================
# Open Family Cloud — テンプレートレンダリング単体実行
# .env の値をもとに config/ 内のプレースホルダーを置換します
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

OFC_LOG_LABEL="TEMPLATE"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/template.sh
source "$SCRIPT_DIR/lib/template.sh"

load_env
validate_required_vars "${COMMON_REQUIRED_VARS[@]}"
render_all_templates
