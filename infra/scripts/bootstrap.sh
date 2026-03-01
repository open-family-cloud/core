#!/usr/bin/env bash
# ============================================================
# Open Family Cloud — ワンコマンドブートストラップ
#
# 使い方:
#   ./bootstrap.sh <config-file>
#
# 1つの設定ファイルから Terraform (Vultr/Linode + Cloudflare) →
# VPS セットアップ → アプリ起動 → DKIM DNS 登録まで自動実行する。
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INFRA_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- 色付きログ ---
log() { echo -e "\033[0;32m[BOOTSTRAP]\033[0m $*"; }
warn() { echo -e "\033[0;33m[BOOTSTRAP]\033[0m $*"; }
err() { echo -e "\033[0;31m[BOOTSTRAP]\033[0m $*" >&2; }

# --- 一時ファイルのクリーンアップ ---
TMPFILE=""
cleanup() { [[ -n "$TMPFILE" && -f "$TMPFILE" ]] && rm -f "$TMPFILE"; }
trap cleanup EXIT

# === SSH ヘルパー ===
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

ssh_cmd() {
    # shellcheck disable=SC2086
    ssh $SSH_OPTS -i "$SSH_PRIVATE_KEY_PATH" "${SSH_USER}@${VPS_IP}" "$@"
}

scp_cmd() {
    # shellcheck disable=SC2086
    scp $SSH_OPTS -i "$SSH_PRIVATE_KEY_PATH" "$@"
}

# === 設定ファイル読み込み ===
load_config() {
    local config_file="${1:?使い方: $0 <config-file>}"
    if [[ ! -f "$config_file" ]]; then
        err "設定ファイルが見つかりません: $config_file"
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$config_file"
}

# === バリデーション ===
validate_config() {
    local missing=()
    for var in "$@"; do
        [[ -z "${!var:-}" ]] && missing+=("$var")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "未設定の必須変数:"
        printf '  %s\n' "${missing[@]}" >&2
        exit 1
    fi
}

# === デフォルト値の設定 ===
set_defaults() {
    TZ="${TZ:-Asia/Tokyo}"
    DEPLOY_PATTERN="${DEPLOY_PATTERN:-compose}"
    BLOCK_STORAGE_SIZE_GB="${BLOCK_STORAGE_SIZE_GB:-40}"
    S3_BUCKET_PREFIX="${S3_BUCKET_PREFIX:-$(echo "$DOMAIN" | tr '.' '-')}"
    CLOUDFLARE_PROXIED="${CLOUDFLARE_PROXIED:-false}"
    VPS_LABEL="${VPS_LABEL:-ofc-server}"
    ALLOWED_SSH_CIDRS="${ALLOWED_SSH_CIDRS:-0.0.0.0/0}"
    SSH_USER="${SSH_USER:-ofc}"
    GIT_REPO="${GIT_REPO:-https://github.com/open-family-cloud/core.git}"
    GIT_BRANCH="${GIT_BRANCH:-main}"

    # 導出値
    LDAP_DOMAIN="${LDAP_DOMAIN:-$DOMAIN}"
    LDAP_BASE_DN="${LDAP_BASE_DN:-dc=$(echo "$DOMAIN" | sed 's/\./,dc=/g')}"
    LDAP_ORGANISATION="${LDAP_ORGANISATION:-Family Cloud}"
    SYNAPSE_SERVER_NAME="${SYNAPSE_SERVER_NAME:-$DOMAIN}"
    NEXTCLOUD_ADMIN_USER="${NEXTCLOUD_ADMIN_USER:-admin}"

    # プロバイダ別デフォルト
    VULTR_REGION="${VULTR_REGION:-nrt}"
    VULTR_PLAN="${VULTR_PLAN:-vc2-2c-4gb}"
    VULTR_OS_ID="${VULTR_OS_ID:-2284}"
    VULTR_OBJECT_STORAGE_CLUSTER="${VULTR_OBJECT_STORAGE_CLUSTER:-16}"
    VULTR_OBJECT_STORAGE_TIER="${VULTR_OBJECT_STORAGE_TIER:-1}"
    LINODE_REGION="${LINODE_REGION:-ap-northeast}"
    LINODE_PLAN="${LINODE_PLAN:-g6-standard-2}"
    LINODE_IMAGE="${LINODE_IMAGE:-linode/ubuntu24.04}"
    LINODE_OBJECT_STORAGE_REGION="${LINODE_OBJECT_STORAGE_REGION:-ap-south-1}"

    # パターンに応じたプラットフォームディレクトリ
    case "$DEPLOY_PATTERN" in
        compose) PLATFORM_SUBDIR="platforms/vps-compose" ;;
        k8s) PLATFORM_SUBDIR="platforms/vps-k8s" ;;
        *)
            err "DEPLOY_PATTERN は 'compose' または 'k8s'"
            exit 1
            ;;
    esac
}

# === CIDR 文字列 → HCL リスト変換 ===
cidrs_to_hcl() {
    local input="$1"
    local result=""
    IFS=',' read -ra parts <<<"$input"
    for cidr in "${parts[@]}"; do
        cidr="$(echo "$cidr" | xargs)"
        [[ -n "$result" ]] && result+=", "
        result+="\"$cidr\""
    done
    echo "[$result]"
}

# ============================================================
# Phase 1: Terraform — コンピュートインフラ構築
# ============================================================

generate_vultr_tfvars() {
    cat >"$INFRA_DIR/vultr/terraform.tfvars" <<EOF
vultr_api_key             = "$VULTR_API_KEY"
domain                    = "$DOMAIN"
region                    = "$VULTR_REGION"
deploy_pattern            = "$DEPLOY_PATTERN"
ssh_public_key_path       = "$SSH_PUBLIC_KEY_PATH"
vps_plan                  = "$VULTR_PLAN"
vps_label                 = "$VPS_LABEL"
vps_os_id                 = $VULTR_OS_ID
block_storage_size_gb     = $BLOCK_STORAGE_SIZE_GB
object_storage_cluster_id = $VULTR_OBJECT_STORAGE_CLUSTER
object_storage_tier_id    = $VULTR_OBJECT_STORAGE_TIER
s3_bucket_prefix          = "$S3_BUCKET_PREFIX"
allowed_ssh_cidrs         = $(cidrs_to_hcl "$ALLOWED_SSH_CIDRS")
EOF
}

generate_linode_tfvars() {
    cat >"$INFRA_DIR/linode/terraform.tfvars" <<EOF
linode_token            = "$LINODE_TOKEN"
domain                  = "$DOMAIN"
region                  = "$LINODE_REGION"
deploy_pattern          = "$DEPLOY_PATTERN"
ssh_public_key_path     = "$SSH_PUBLIC_KEY_PATH"
vps_plan                = "$LINODE_PLAN"
vps_label               = "$VPS_LABEL"
vps_image               = "$LINODE_IMAGE"
root_pass               = "$LINODE_ROOT_PASS"
block_storage_size_gb   = $BLOCK_STORAGE_SIZE_GB
object_storage_region   = "$LINODE_OBJECT_STORAGE_REGION"
s3_bucket_prefix        = "$S3_BUCKET_PREFIX"
allowed_ssh_cidrs       = $(cidrs_to_hcl "$ALLOWED_SSH_CIDRS")
EOF
}

deploy_compute() {
    log "Phase 1/3: $PROVIDER インフラを構築中..."

    case "$PROVIDER" in
        vultr) generate_vultr_tfvars ;;
        linode) generate_linode_tfvars ;;
    esac

    terraform -chdir="$INFRA_DIR/$PROVIDER" init -input=false
    terraform -chdir="$INFRA_DIR/$PROVIDER" apply -auto-approve -input=false

    # Output 取得
    VPS_IP=$(terraform -chdir="$INFRA_DIR/$PROVIDER" output -raw vps_public_ip)
    ENV_VARS_JSON=$(terraform -chdir="$INFRA_DIR/$PROVIDER" output -json env_vars)

    log "VPS IP: $VPS_IP"
}

# ============================================================
# Phase 1b: Terraform — Cloudflare DNS
# ============================================================

cloudflare_apply() {
    local dkim_value="${1:-}"

    # shellcheck disable=SC2086
    terraform -chdir="$INFRA_DIR/cloudflare" apply -auto-approve -input=false \
        -var="cloudflare_api_token=$CLOUDFLARE_API_TOKEN" \
        -var="zone_id=$CLOUDFLARE_ZONE_ID" \
        -var="domain=$DOMAIN" \
        -var="vps_ip=$VPS_IP" \
        -var="proxied=$CLOUDFLARE_PROXIED" \
        -var="enable_mail_dns=true" \
        -var="mail_dkim_record=$dkim_value"
}

deploy_dns() {
    log "Cloudflare DNS を設定中 (MX/SPF/DMARC)..."
    terraform -chdir="$INFRA_DIR/cloudflare" init -input=false
    cloudflare_apply ""
    log "DNS レコード作成完了 (DKIM はサービス起動後に追加)"
}

# ============================================================
# Phase 2: VPS セットアップ
# ============================================================

wait_for_ssh() {
    log "Phase 2/3: VPS の SSH 接続を待機中..."
    local attempt=0
    local max=60
    while ! ssh_cmd true 2>/dev/null; do
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max ]]; then
            err "SSH 接続タイムアウト (${max} 回試行)"
            exit 1
        fi
        sleep 5
    done
    log "SSH 接続確立"
}

wait_for_cloud_init() {
    log "cloud-init 完了を待機中 (Docker/Block Storage 等のセットアップ)..."
    ssh_cmd "sudo cloud-init status --wait" >/dev/null 2>&1
    log "cloud-init 完了"
}

# === Vaultwarden トークンの Argon2id ハッシュ化 ===
hash_vaultwarden_token() {
    local plain_token="$1"

    # 既にハッシュ済み ($argon2id$ で始まる) ならそのまま返す
    if [[ "$plain_token" == '$argon2id$'* ]]; then
        echo "$plain_token"
        return
    fi

    if command -v argon2 &>/dev/null; then
        local salt
        salt=$(openssl rand -base64 32)
        local hashed
        hashed=$(echo -n "$plain_token" | argon2 "$salt" -e -id -k 65540 -t 3 -p 4)
        log "VAULTWARDEN_ADMIN_TOKEN を Argon2id でハッシュ化しました"
        echo "$hashed"
    else
        warn "argon2 が見つかりません。VAULTWARDEN_ADMIN_TOKEN を平文のまま使用します。"
        warn "セキュリティ向上のため argon2 のインストールを推奨します:"
        warn "  sudo apt-get install -y argon2  または  make install-tools"
        echo "$plain_token"
    fi
}

generate_dotenv() {
    # Terraform output から取得する値
    local s3_endpoint s3_access_key s3_secret_key s3_region
    local s3_bucket_nextcloud s3_bucket_synapse s3_bucket_jellyfin s3_bucket_backup
    local mail_storage_path jvb_advertise_ip
    local vw_admin_token

    # Vaultwarden トークンをハッシュ化
    vw_admin_token=$(hash_vaultwarden_token "$VAULTWARDEN_ADMIN_TOKEN")

    s3_endpoint=$(echo "$ENV_VARS_JSON" | jq -r '.S3_ENDPOINT')
    s3_access_key=$(echo "$ENV_VARS_JSON" | jq -r '.S3_ACCESS_KEY')
    s3_secret_key=$(echo "$ENV_VARS_JSON" | jq -r '.S3_SECRET_KEY')
    s3_region=$(echo "$ENV_VARS_JSON" | jq -r '.S3_REGION')
    s3_bucket_nextcloud=$(echo "$ENV_VARS_JSON" | jq -r '.S3_BUCKET_NEXTCLOUD')
    s3_bucket_synapse=$(echo "$ENV_VARS_JSON" | jq -r '.S3_BUCKET_SYNAPSE')
    s3_bucket_jellyfin=$(echo "$ENV_VARS_JSON" | jq -r '.S3_BUCKET_JELLYFIN')
    s3_bucket_backup=$(echo "$ENV_VARS_JSON" | jq -r '.S3_BUCKET_BACKUP')
    mail_storage_path=$(echo "$ENV_VARS_JSON" | jq -r '.MAIL_STORAGE_PATH')
    jvb_advertise_ip=$(echo "$ENV_VARS_JSON" | jq -r '.JVB_ADVERTISE_IP')

    cat <<EOF
# ============================================================
# Open Family Cloud — 環境変数
# bootstrap.sh により自動生成 ($(date -Iseconds))
# ============================================================

# --- 基本設定 ---
DOMAIN="${DOMAIN}"
TZ="${TZ}"

# --- Let's Encrypt ---
ACME_EMAIL="${ACME_EMAIL}"

# --- OpenLDAP ---
LDAP_ORGANISATION="${LDAP_ORGANISATION}"
LDAP_DOMAIN="${LDAP_DOMAIN}"
LDAP_ADMIN_PASSWORD="${LDAP_ADMIN_PASSWORD}"
LDAP_CONFIG_PASSWORD="${LDAP_CONFIG_PASSWORD}"
LDAP_BASE_DN="${LDAP_BASE_DN}"

# --- PostgreSQL ---
POSTGRES_PASSWORD="${POSTGRES_PASSWORD}"
POSTGRES_NEXTCLOUD_DB="nextcloud"
POSTGRES_NEXTCLOUD_USER="nextcloud"
POSTGRES_NEXTCLOUD_PASSWORD="${POSTGRES_NEXTCLOUD_PASSWORD}"
POSTGRES_SYNAPSE_DB="synapse"
POSTGRES_SYNAPSE_USER="synapse"
POSTGRES_SYNAPSE_PASSWORD="${POSTGRES_SYNAPSE_PASSWORD}"
POSTGRES_VAULTWARDEN_DB="vaultwarden"
POSTGRES_VAULTWARDEN_USER="vaultwarden"
POSTGRES_VAULTWARDEN_PASSWORD="${POSTGRES_VAULTWARDEN_PASSWORD}"

# --- Nextcloud ---
NEXTCLOUD_ADMIN_USER="${NEXTCLOUD_ADMIN_USER}"
NEXTCLOUD_ADMIN_PASSWORD="${NEXTCLOUD_ADMIN_PASSWORD}"

# --- S3 Object Storage (Terraform output) ---
S3_ENDPOINT="${s3_endpoint}"
S3_ACCESS_KEY="${s3_access_key}"
S3_SECRET_KEY="${s3_secret_key}"
S3_REGION="${s3_region}"
S3_BUCKET_NEXTCLOUD="${s3_bucket_nextcloud}"

# --- Matrix Synapse ---
SYNAPSE_SERVER_NAME="${SYNAPSE_SERVER_NAME}"
SYNAPSE_REPORT_STATS="no"
S3_BUCKET_SYNAPSE="${s3_bucket_synapse}"

# --- Jitsi Meet ---
JITSI_SECRET_JICOFO_COMPONENT="${JITSI_SECRET_JICOFO_COMPONENT}"
JITSI_SECRET_JICOFO_AUTH="${JITSI_SECRET_JICOFO_AUTH}"
JITSI_SECRET_JVB_AUTH="${JITSI_SECRET_JVB_AUTH}"
JVB_PORT="10000"
JVB_ADVERTISE_IP="${jvb_advertise_ip}"

# --- docker-mailserver ---
MAIL_STORAGE_PATH="${mail_storage_path}"

# --- Jellyfin ---
JELLYFIN_MEDIA_PATH="/mnt/s3/jellyfin"
S3_BUCKET_JELLYFIN="${s3_bucket_jellyfin}"

# --- Vaultwarden ---
VAULTWARDEN_SIGNUPS_ALLOWED="true"
VAULTWARDEN_ADMIN_TOKEN='${vw_admin_token}'

# --- バックアップ ---
S3_BUCKET_BACKUP="${s3_bucket_backup}"
BACKUP_ENCRYPTION_KEY="${BACKUP_ENCRYPTION_KEY}"

# --- Docker ネットワーク ---
DOCKER_SUBNET="172.20.0.0/16"
EOF
}

deploy_application() {
    log "リポジトリを clone 中..."
    ssh_cmd "git clone -b '$GIT_BRANCH' '$GIT_REPO' ~/core 2>/dev/null || (cd ~/core && git pull origin '$GIT_BRANCH')"

    log ".env を転送中..."
    TMPFILE=$(mktemp)
    generate_dotenv >"$TMPFILE"
    scp_cmd "$TMPFILE" "${SSH_USER}@${VPS_IP}:~/core/${PLATFORM_SUBDIR}/.env"

    log "setup.sh を実行中 (サービス起動)..."
    ssh_cmd "cd ~/core/${PLATFORM_SUBDIR} && ./scripts/setup.sh"
}

# ============================================================
# Phase 3: DKIM DNS 登録
# ============================================================

setup_dkim_dns() {
    log "Phase 3/3: DKIM レコードを取得中..."

    local dkim_file="\$HOME/core/${PLATFORM_SUBDIR}/mailserver-config/opendkim/keys/${DOMAIN}/mail.txt"

    # DKIM ファイルから TXT レコード値を抽出
    # awk でダブルクォート内のテキストを連結
    local dkim_value
    dkim_value=$(ssh_cmd "test -f $dkim_file && awk -F'\"' '{for(i=2;i<=NF;i+=2) printf \"%s\",\$i}' $dkim_file || true")

    if [[ -z "$dkim_value" ]]; then
        warn "DKIM レコードが生成されていません。メール設定後に手動で追加してください。"
        return 0
    fi

    log "Cloudflare に DKIM レコードを追加中..."
    cloudflare_apply "$dkim_value"
    log "DKIM DNS 登録完了"
}

# ============================================================
# 完了サマリー
# ============================================================

show_summary() {
    echo ""
    echo "========================================================"
    log "デプロイ完了"
    echo "========================================================"
    echo ""
    echo "  VPS IP:    $VPS_IP"
    echo "  SSH:       ssh ${SSH_USER}@${VPS_IP}"
    echo ""
    echo "  サービス URL:"
    echo "    Nextcloud:    https://cloud.${DOMAIN}"
    echo "    Element:      https://chat.${DOMAIN}"
    echo "    Jitsi Meet:   https://meet.${DOMAIN}"
    echo "    Jellyfin:     https://media.${DOMAIN}"
    echo "    Vaultwarden:  https://vault.${DOMAIN}"
    echo "    phpLDAPadmin: https://ldap.${DOMAIN}"
    echo "    Webmail:      https://mail.${DOMAIN}"
    echo ""
    echo "  ユーザー追加:"
    echo "    ssh ${SSH_USER}@${VPS_IP}"
    echo "    cd ~/core && ./scripts/user.sh add <username> <email> <display_name>"
    echo ""
    echo "========================================================"
}

# ============================================================
# メイン
# ============================================================

main() {
    load_config "${1:-}"
    set_defaults

    # 共通バリデーション
    validate_config \
        PROVIDER DOMAIN ACME_EMAIL \
        SSH_PUBLIC_KEY_PATH SSH_PRIVATE_KEY_PATH \
        CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID \
        LDAP_ADMIN_PASSWORD LDAP_CONFIG_PASSWORD \
        POSTGRES_PASSWORD POSTGRES_NEXTCLOUD_PASSWORD \
        POSTGRES_SYNAPSE_PASSWORD POSTGRES_VAULTWARDEN_PASSWORD \
        NEXTCLOUD_ADMIN_PASSWORD \
        JITSI_SECRET_JICOFO_COMPONENT JITSI_SECRET_JICOFO_AUTH JITSI_SECRET_JVB_AUTH \
        VAULTWARDEN_ADMIN_TOKEN BACKUP_ENCRYPTION_KEY

    # プロバイダ別バリデーション
    case "$PROVIDER" in
        vultr) validate_config VULTR_API_KEY VULTR_OBJECT_STORAGE_CLUSTER ;;
        linode) validate_config LINODE_TOKEN LINODE_ROOT_PASS ;;
        *)
            err "PROVIDER は 'vultr' または 'linode'"
            exit 1
            ;;
    esac

    # ツール確認
    for cmd in terraform jq ssh scp; do
        command -v "$cmd" &>/dev/null || {
            err "$cmd が見つかりません"
            exit 1
        }
    done
    if [[ "$PROVIDER" == "vultr" ]]; then
        command -v aws &>/dev/null || {
            err "aws-cli が見つかりません (Vultr S3 バケット作成に必要)"
            exit 1
        }
    fi

    echo ""
    echo "========================================================"
    log "Open Family Cloud ブートストラップ開始"
    echo "  プロバイダ: $PROVIDER / パターン: $DEPLOY_PATTERN"
    echo "  ドメイン:   $DOMAIN"
    echo "========================================================"
    echo ""

    deploy_compute
    deploy_dns
    wait_for_ssh
    wait_for_cloud_init
    deploy_application
    setup_dkim_dns
    show_summary
}

main "$@"
