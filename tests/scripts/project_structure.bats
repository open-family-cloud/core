#!/usr/bin/env bats
# shellcheck disable=SC2154

# プロジェクト構造の検証テスト

setup() {
    PROJECT_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
}

# ------------------------------------------------------------
# シェルスクリプトの検証
# ------------------------------------------------------------

@test "全シェルスクリプトに shebang がある" {
    local failed=()
    while IFS= read -r -d '' file; do
        head -1 "$file" | grep -qE '^#!/(usr/)?bin/(env )?bash' || failed+=("$file")
    done < <(find "$PROJECT_DIR/scripts" "$PROJECT_DIR/config" "$PROJECT_DIR/platforms" -name '*.sh' -print0)

    if [[ ${#failed[@]} -gt 0 ]]; then
        echo "shebang がないスクリプト:" >&2
        printf '  %s\n' "${failed[@]}" >&2
        return 1
    fi
}

@test "全シェルスクリプトに set -euo pipefail がある（lib を除く）" {
    local failed=()
    while IFS= read -r -d '' file; do
        # lib/ 内のファイルはソースされるため set -euo pipefail は不要
        [[ "$file" == */scripts/lib/* ]] && continue
        grep -q 'set -euo pipefail' "$file" || failed+=("$file")
    done < <(find "$PROJECT_DIR/scripts" "$PROJECT_DIR/platforms" -name '*.sh' -print0)

    if [[ ${#failed[@]} -gt 0 ]]; then
        echo "set -euo pipefail がないスクリプト:" >&2
        printf '  %s\n' "${failed[@]}" >&2
        return 1
    fi
}

# ------------------------------------------------------------
# 共有ライブラリの検証
# ------------------------------------------------------------

@test "scripts/lib/ に共通ライブラリが存在する" {
    [[ -f "$PROJECT_DIR/scripts/lib/common.sh" ]]
    [[ -f "$PROJECT_DIR/scripts/lib/env.sh" ]]
    [[ -f "$PROJECT_DIR/scripts/lib/template.sh" ]]
    [[ -f "$PROJECT_DIR/scripts/lib/ldap.sh" ]]
    [[ -f "$PROJECT_DIR/scripts/lib/backup.sh" ]]
}

@test "scripts/user.sh が存在する" {
    [[ -f "$PROJECT_DIR/scripts/user.sh" ]]
}

@test "scripts/render-templates.sh が存在する" {
    [[ -f "$PROJECT_DIR/scripts/render-templates.sh" ]]
}

# ------------------------------------------------------------
# 共有設定ファイルの検証
# ------------------------------------------------------------

@test "ルートの .env.example が存在する" {
    [[ -f "$PROJECT_DIR/.env.example" ]]
}

@test "共有設定ファイルが config/ に存在する" {
    [[ -f "$PROJECT_DIR/config/element/config.json" ]]
    [[ -f "$PROJECT_DIR/config/synapse/homeserver.yaml" ]]
    [[ -f "$PROJECT_DIR/config/synapse/log.config" ]]
    [[ -f "$PROJECT_DIR/config/nextcloud/custom.config.php" ]]
    [[ -f "$PROJECT_DIR/config/postgres/init-databases.sh" ]]
    [[ -f "$PROJECT_DIR/config/ldap/bootstrap/01-structure.ldif" ]]
    [[ -f "$PROJECT_DIR/config/traefik/traefik.yml" ]]
    [[ -f "$PROJECT_DIR/config/traefik/dynamic/security.yml" ]]
}

# ------------------------------------------------------------
# プラットフォーム構造の検証
# ------------------------------------------------------------

@test "platforms/vps-compose が完全な構造を持つ" {
    [[ -f "$PROJECT_DIR/platforms/vps-compose/docker-compose.yml" ]]
    [[ -f "$PROJECT_DIR/platforms/vps-compose/.env.example" ]]
    [[ -f "$PROJECT_DIR/platforms/vps-compose/README.md" ]]
    [[ -x "$PROJECT_DIR/platforms/vps-compose/scripts/setup.sh" ]]
    [[ -x "$PROJECT_DIR/platforms/vps-compose/scripts/update.sh" ]]
    [[ -x "$PROJECT_DIR/platforms/vps-compose/scripts/backup.sh" ]]
    [[ -x "$PROJECT_DIR/platforms/vps-compose/scripts/healthcheck.sh" ]]
}

@test "platforms/vps-k8s が完全な構造を持つ" {
    [[ -f "$PROJECT_DIR/platforms/vps-k8s/kustomize/base/kustomization.yaml" ]]
    [[ -f "$PROJECT_DIR/platforms/vps-k8s/kustomize/base/namespace.yaml" ]]
    [[ -f "$PROJECT_DIR/platforms/vps-k8s/.env.example" ]]
    [[ -f "$PROJECT_DIR/platforms/vps-k8s/README.md" ]]
    [[ -x "$PROJECT_DIR/platforms/vps-k8s/scripts/setup.sh" ]]
    [[ -x "$PROJECT_DIR/platforms/vps-k8s/scripts/healthcheck.sh" ]]
}

@test "platforms/home-static-ip が完全な構造を持つ" {
    [[ -f "$PROJECT_DIR/platforms/home-static-ip/docker-compose.yml" ]]
    [[ -f "$PROJECT_DIR/platforms/home-static-ip/.env.example" ]]
    [[ -f "$PROJECT_DIR/platforms/home-static-ip/README.md" ]]
    [[ -f "$PROJECT_DIR/platforms/home-static-ip/config/traefik/traefik.yml" ]]
    [[ -x "$PROJECT_DIR/platforms/home-static-ip/scripts/setup.sh" ]]
    [[ -x "$PROJECT_DIR/platforms/home-static-ip/scripts/healthcheck.sh" ]]
}

@test "platforms/home-tunnel が完全な構造を持つ" {
    [[ -f "$PROJECT_DIR/platforms/home-tunnel/home/docker-compose.yml" ]]
    [[ -f "$PROJECT_DIR/platforms/home-tunnel/vps/docker-compose.yml" ]]
    [[ -f "$PROJECT_DIR/platforms/home-tunnel/.env.example" ]]
    [[ -f "$PROJECT_DIR/platforms/home-tunnel/README.md" ]]
    [[ -x "$PROJECT_DIR/platforms/home-tunnel/home/scripts/setup.sh" ]]
    [[ -x "$PROJECT_DIR/platforms/home-tunnel/vps/scripts/setup.sh" ]]
}

@test ".env.example に全パターン共通の必須変数が定義されている" {
    local required_vars=(
        DOMAIN
        ACME_EMAIL
        LDAP_ADMIN_PASSWORD
        LDAP_BASE_DN
        POSTGRES_PASSWORD
        NEXTCLOUD_ADMIN_PASSWORD
        S3_ENDPOINT
        S3_ACCESS_KEY
        S3_SECRET_KEY
        SYNAPSE_SERVER_NAME
    )
    local missing=()
    for var in "${required_vars[@]}"; do
        grep -q "^${var}=" "$PROJECT_DIR/.env.example" || missing+=("$var")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "不足している変数:" >&2
        printf '  %s\n' "${missing[@]}" >&2
        return 1
    fi
}

@test "各パターンの .env.example に DOMAIN が定義されている" {
    for envfile in \
        "$PROJECT_DIR/platforms/vps-compose/.env.example" \
        "$PROJECT_DIR/platforms/vps-k8s/.env.example" \
        "$PROJECT_DIR/platforms/home-static-ip/.env.example" \
        "$PROJECT_DIR/platforms/home-tunnel/.env.example"; do
        grep -q "^DOMAIN=" "$envfile" || {
            echo "$envfile に DOMAIN が定義されていません" >&2
            return 1
        }
    done
}
