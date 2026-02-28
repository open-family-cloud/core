#!/bin/bash
# Claude Code PostToolUse hook — 編集されたファイルを自動フォーマット
set -euo pipefail

FILE_PATH=$(jq -r '.tool_input.file_path // empty')

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# シェルスクリプト → shfmt (プロジェクトの .pre-commit-config.yaml と同じオプション)
if [[ "$FILE_PATH" == *.sh ]]; then
    if command -v shfmt &>/dev/null; then
        shfmt -i 4 -ci -bn -w "$FILE_PATH" 2>/dev/null || true
    fi
fi

# Terraform → terraform fmt
if [[ "$FILE_PATH" == *.tf ]]; then
    if command -v terraform &>/dev/null; then
        terraform fmt "$FILE_PATH" 2>/dev/null || true
    fi
fi

exit 0
