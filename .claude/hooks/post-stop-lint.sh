#!/bin/bash
# Claude Code Stop hook — ターン終了時に変更ファイルの lint チェック
set -uo pipefail

# 変更のあるファイルだけ対象にする（未コミットの変更 + 未追跡ファイル）
CHANGED_FILES=$(
    git diff --name-only HEAD 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null
)

if [[ -z "$CHANGED_FILES" ]]; then
    exit 0
fi

HAS_SH=false
HAS_TF=false

while IFS= read -r f; do
    [[ "$f" == *.sh ]] && HAS_SH=true
    [[ "$f" == *.tf ]] && HAS_TF=true
done <<<"$CHANGED_FILES"

ERRORS=""

# シェルスクリプトの lint (shfmt check + shellcheck)
if $HAS_SH; then
    SH_FILES=$(echo "$CHANGED_FILES" | grep '\.sh$' || true)
    if [[ -n "$SH_FILES" ]]; then
        if command -v shfmt &>/dev/null; then
            # shellcheck disable=SC2086
            SHFMT_OUT=$(echo "$SH_FILES" | xargs shfmt -i 4 -ci -bn -d 2>&1) || true
            if [[ -n "$SHFMT_OUT" ]]; then
                ERRORS+="[shfmt] フォーマット差分あり:\n$SHFMT_OUT\n\n"
            fi
        fi
        if command -v shellcheck &>/dev/null; then
            # shellcheck disable=SC2086
            SC_OUT=$(echo "$SH_FILES" | xargs shellcheck --severity=warning 2>&1) || true
            if [[ -n "$SC_OUT" ]]; then
                ERRORS+="[shellcheck] 警告あり:\n$SC_OUT\n\n"
            fi
        fi
    fi
fi

# Terraform の lint (fmt check)
if $HAS_TF; then
    if command -v terraform &>/dev/null; then
        TF_DIRS=$(echo "$CHANGED_FILES" | grep '\.tf$' | xargs -I {} dirname {} | sort -u || true)
        for dir in $TF_DIRS; do
            FMT_OUT=$(terraform fmt -check -diff "$dir" 2>&1) || true
            if [[ -n "$FMT_OUT" ]]; then
                ERRORS+="[terraform fmt] $dir にフォーマット差分あり:\n$FMT_OUT\n\n"
            fi
        done
    fi
fi

if [[ -n "$ERRORS" ]]; then
    echo -e "⚠ Lint チェックで問題が見つかりました。修正してください:\n"
    echo -e "$ERRORS"
fi

exit 0
