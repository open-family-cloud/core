#!/usr/bin/env bats
# shellcheck disable=SC2154

# Terraform インフラ構造の検証テスト

setup() {
    PROJECT_DIR="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    INFRA_DIR="$PROJECT_DIR/infra"
}

# ------------------------------------------------------------
# 共有モジュールの検証
# ------------------------------------------------------------

@test "modules/cloud-init に必須ファイルが存在する" {
    [[ -f "$INFRA_DIR/modules/cloud-init/main.tf" ]]
    [[ -f "$INFRA_DIR/modules/cloud-init/variables.tf" ]]
    [[ -f "$INFRA_DIR/modules/cloud-init/outputs.tf" ]]
}

@test "modules/cloud-init にテンプレートが存在する" {
    [[ -f "$INFRA_DIR/modules/cloud-init/templates/compose.yaml.tpl" ]]
    [[ -f "$INFRA_DIR/modules/cloud-init/templates/k8s.yaml.tpl" ]]
}

@test "modules/cloud-init に共通セットアップスクリプトが存在する" {
    [[ -f "$INFRA_DIR/modules/cloud-init/scripts/common-setup.sh" ]]
}

@test "modules/dns-records に必須ファイルが存在する" {
    [[ -f "$INFRA_DIR/modules/dns-records/main.tf" ]]
    [[ -f "$INFRA_DIR/modules/dns-records/variables.tf" ]]
    [[ -f "$INFRA_DIR/modules/dns-records/outputs.tf" ]]
}

# ------------------------------------------------------------
# Vultr プロバイダの検証
# ------------------------------------------------------------

@test "vultr/ に必須 .tf ファイルが存在する" {
    [[ -f "$INFRA_DIR/vultr/versions.tf" ]]
    [[ -f "$INFRA_DIR/vultr/variables.tf" ]]
    [[ -f "$INFRA_DIR/vultr/main.tf" ]]
    [[ -f "$INFRA_DIR/vultr/compute.tf" ]]
    [[ -f "$INFRA_DIR/vultr/storage.tf" ]]
    [[ -f "$INFRA_DIR/vultr/network.tf" ]]
    [[ -f "$INFRA_DIR/vultr/outputs.tf" ]]
}

@test "vultr/terraform.tfvars.example が存在する" {
    [[ -f "$INFRA_DIR/vultr/terraform.tfvars.example" ]]
}

@test "vultr/versions.tf に vultr プロバイダが定義されている" {
    grep -q 'vultr/vultr' "$INFRA_DIR/vultr/versions.tf"
}

# ------------------------------------------------------------
# Linode プロバイダの検証
# ------------------------------------------------------------

@test "linode/ に必須 .tf ファイルが存在する" {
    [[ -f "$INFRA_DIR/linode/versions.tf" ]]
    [[ -f "$INFRA_DIR/linode/variables.tf" ]]
    [[ -f "$INFRA_DIR/linode/main.tf" ]]
    [[ -f "$INFRA_DIR/linode/compute.tf" ]]
    [[ -f "$INFRA_DIR/linode/storage.tf" ]]
    [[ -f "$INFRA_DIR/linode/network.tf" ]]
    [[ -f "$INFRA_DIR/linode/outputs.tf" ]]
}

@test "linode/terraform.tfvars.example が存在する" {
    [[ -f "$INFRA_DIR/linode/terraform.tfvars.example" ]]
}

@test "linode/versions.tf に linode プロバイダが定義されている" {
    grep -q 'linode/linode' "$INFRA_DIR/linode/versions.tf"
}

# ------------------------------------------------------------
# Cloudflare プロバイダの検証
# ------------------------------------------------------------

@test "cloudflare/ に必須 .tf ファイルが存在する" {
    [[ -f "$INFRA_DIR/cloudflare/versions.tf" ]]
    [[ -f "$INFRA_DIR/cloudflare/variables.tf" ]]
    [[ -f "$INFRA_DIR/cloudflare/main.tf" ]]
    [[ -f "$INFRA_DIR/cloudflare/outputs.tf" ]]
}

@test "cloudflare/terraform.tfvars.example が存在する" {
    [[ -f "$INFRA_DIR/cloudflare/terraform.tfvars.example" ]]
}

@test "cloudflare/versions.tf に cloudflare プロバイダが定義されている" {
    grep -q 'cloudflare/cloudflare' "$INFRA_DIR/cloudflare/versions.tf"
}

# ------------------------------------------------------------
# スクリプトの検証
# ------------------------------------------------------------

@test "scripts/generate-env.sh が存在する" {
    [[ -f "$INFRA_DIR/scripts/generate-env.sh" ]]
}

@test "scripts/generate-env.sh に shebang がある" {
    head -1 "$INFRA_DIR/scripts/generate-env.sh" | grep -qE '^#!/(usr/)?bin/(env )?bash'
}

@test "scripts/generate-env.sh に set -euo pipefail がある" {
    grep -q 'set -euo pipefail' "$INFRA_DIR/scripts/generate-env.sh"
}

# ------------------------------------------------------------
# ブートストラップの検証
# ------------------------------------------------------------

@test "scripts/bootstrap.sh が存在し実行可能である" {
    [[ -x "$INFRA_DIR/scripts/bootstrap.sh" ]]
}

@test "scripts/bootstrap.sh に shebang がある" {
    head -1 "$INFRA_DIR/scripts/bootstrap.sh" | grep -qE '^#!/(usr/)?bin/(env )?bash'
}

@test "scripts/bootstrap.sh に set -euo pipefail がある" {
    grep -q 'set -euo pipefail' "$INFRA_DIR/scripts/bootstrap.sh"
}

@test "bootstrap.example.conf が存在する" {
    [[ -f "$INFRA_DIR/bootstrap.example.conf" ]]
}

@test "bootstrap.example.conf に全プロバイダの設定変数がある" {
    grep -q 'VULTR_API_KEY' "$INFRA_DIR/bootstrap.example.conf"
    grep -q 'LINODE_TOKEN' "$INFRA_DIR/bootstrap.example.conf"
    grep -q 'CLOUDFLARE_API_TOKEN' "$INFRA_DIR/bootstrap.example.conf"
    grep -q 'DOMAIN' "$INFRA_DIR/bootstrap.example.conf"
}

# ------------------------------------------------------------
# README の検証
# ------------------------------------------------------------

@test "infra/README.md が存在する" {
    [[ -f "$INFRA_DIR/README.md" ]]
}
