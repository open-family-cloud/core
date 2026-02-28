#!/bin/bash
# ============================================================
# Open Family Cloud — パターン2: VPS + Kubernetes アップデート
# マニフェストを再適用し、ローリングアップデートを実行します
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

cd "$PLATFORM_DIR"
load_env

# ----------------------------------------------------------
# 1. バックアップ
# ----------------------------------------------------------
log "アップデート前のバックアップを実行中..."
"$SCRIPT_DIR/backup.sh" --pre-update || {
    err "バックアップに失敗しました。アップデートを中止します。"
    exit 1
}

# ----------------------------------------------------------
# 2. マニフェスト再適用
# ----------------------------------------------------------
OVERLAY="${OFC_K8S_OVERLAY:-single-node}"
log "Kustomize overlay: ${OVERLAY}"

kustomize build "kustomize/overlays/${OVERLAY}" | kubectl apply -f -
log "マニフェスト再適用: OK"

# ----------------------------------------------------------
# 3. ローリングアップデート
# ----------------------------------------------------------
log "Deployment を再起動中..."
kubectl rollout restart deployment --namespace=ofc

log "ローリングアップデートを待機中..."
kubectl rollout status deployment --namespace=ofc --timeout=300s \
    || warn "一部の Deployment がまだ更新中です"

# ----------------------------------------------------------
# 4. ヘルスチェック
# ----------------------------------------------------------
"$SCRIPT_DIR/healthcheck.sh"

log "アップデート完了"
