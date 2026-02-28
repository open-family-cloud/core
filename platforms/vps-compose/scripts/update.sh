#!/bin/bash
# ============================================================
# Open Family Cloud — パターン1: VPS + Docker Compose アップデート
# リポジトリの最新版を取得し、サービスを更新します
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLATFORM_DIR="$(dirname "$SCRIPT_DIR")"
export PLATFORM_DIR

OFC_LOG_LABEL="OFC"
# shellcheck source=../../../scripts/lib/common.sh
source "$PLATFORM_DIR/../../scripts/lib/common.sh"

cd "$PROJECT_ROOT"

# ----------------------------------------------------------
# 1. 現在のバージョン確認
# ----------------------------------------------------------
CURRENT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
log "現在のバージョン: ${CURRENT} (${BRANCH})"

# ----------------------------------------------------------
# 2. リモートの変更を確認
# ----------------------------------------------------------
log "リモートリポジトリを確認中..."
git fetch origin

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse "origin/${BRANCH}")

if [[ "$LOCAL" = "$REMOTE" ]]; then
    log "すでに最新版です。更新はありません。"
    exit 0
fi

# ----------------------------------------------------------
# 3. 変更内容を表示
# ----------------------------------------------------------
echo ""
info "===== 変更履歴 ====="
git log --oneline "${LOCAL}..${REMOTE}"
echo ""

if git diff "${LOCAL}..${REMOTE}" -- CHANGELOG.md | grep -q '^+'; then
    info "===== CHANGELOG の更新 ====="
    git diff "${LOCAL}..${REMOTE}" -- CHANGELOG.md | grep '^+' | head -30
    echo ""
fi

if git diff --name-only "${LOCAL}..${REMOTE}" | grep -q 'docker-compose.yml'; then
    warn "docker-compose.yml に変更があります"
    warn "  サービス構成が変更される可能性があります"
    echo ""
fi

if git diff --name-only "${LOCAL}..${REMOTE}" | grep -q '.env.example'; then
    warn ".env.example に変更があります"
    warn "  新しい設定項目が追加された可能性があります"
    warn "  更新後に .env.example を確認し、必要に応じて .env に追記してください"
    echo ""
fi

# ----------------------------------------------------------
# 4. 確認プロンプト
# ----------------------------------------------------------
read -p "アップデートを適用しますか? (y/N): " confirm
if [[ ! "$confirm" =~ ^[yY]$ ]]; then
    log "アップデートをキャンセルしました"
    exit 0
fi

# ----------------------------------------------------------
# 5. バックアップ
# ----------------------------------------------------------
log "アップデート前のバックアップを実行中..."
"$SCRIPT_DIR/backup.sh" --pre-update || {
    err "バックアップに失敗しました。アップデートを中止します。"
    exit 1
}

# ----------------------------------------------------------
# 6. ローカル変更の退避と更新適用
# ----------------------------------------------------------
log "ローカル変更を退避中..."
STASH_RESULT=$(git stash 2>&1)
STASHED=false
if [[ "$STASH_RESULT" != *"No local changes"* ]]; then
    STASHED=true
fi

log "最新版をマージ中..."
if ! git merge "origin/${BRANCH}"; then
    err "マージ競合が発生しました"
    err "手動で解決してください:"
    echo "  git status           # 競合ファイルを確認"
    echo "  nano <ファイル>      # 競合を解決"
    echo "  git add <ファイル>   # 解決済みとしてマーク"
    echo "  git commit           # マージをコミット"
    if $STASHED; then
        echo "  git stash pop      # 退避した変更を戻す"
    fi
    exit 1
fi

if $STASHED; then
    log "退避した変更を復元中..."
    if ! git stash pop; then
        warn "退避した変更の復元で競合が発生しました"
        warn "手動で解決してください: git stash pop"
    fi
fi

# ----------------------------------------------------------
# 7. Docker イメージの更新と再起動
# ----------------------------------------------------------
cd "$PLATFORM_DIR"

log "Docker イメージを更新中..."
docker compose pull

log "サービスを再起動中..."
docker compose up -d --remove-orphans

docker image prune -f

# ----------------------------------------------------------
# 8. ヘルスチェック
# ----------------------------------------------------------
log "サービスの起動を待機中（30秒）..."
sleep 30

"$SCRIPT_DIR/healthcheck.sh"

NEW_VERSION=$(git rev-parse --short HEAD)
echo ""
log "============================================"
log " アップデート完了: ${CURRENT} → ${NEW_VERSION}"
log "============================================"
