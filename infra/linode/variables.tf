# Linode プロバイダ — 入力変数

# === 認証 ===
variable "linode_token" {
  description = "Linode API トークン (環境変数 LINODE_TOKEN でも設定可)"
  type        = string
  sensitive   = true
}

# === 基本設定 ===
variable "domain" {
  description = "メインドメイン (例: family.example.com)"
  type        = string
}

variable "region" {
  description = "Linode リージョン (例: ap-northeast = 東京)"
  type        = string
  default     = "ap-northeast"
}

variable "deploy_pattern" {
  description = "デプロイパターン: compose または k8s"
  type        = string
  default     = "compose"

  validation {
    condition     = contains(["compose", "k8s"], var.deploy_pattern)
    error_message = "deploy_pattern は 'compose' または 'k8s' のいずれか"
  }
}

# === SSH ===
variable "ssh_public_key_path" {
  description = "SSH 公開鍵ファイルパス"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

# === VPS ===
variable "vps_plan" {
  description = "Linode インスタンスタイプ (例: g6-standard-2)"
  type        = string
  default     = "g6-standard-2"
}

variable "vps_label" {
  description = "VPS のラベル"
  type        = string
  default     = "ofc-server"
}

variable "vps_image" {
  description = "Linode イメージ (例: linode/ubuntu24.04)"
  type        = string
  default     = "linode/ubuntu24.04"
}

variable "root_pass" {
  description = "root パスワード (cloud-init でパスワード認証を無効化するため初回のみ使用)"
  type        = string
  sensitive   = true
}

# === Block Storage (Volume) ===
variable "block_storage_size_gb" {
  description = "Block Storage (Volume) サイズ (GB)"
  type        = number
  default     = 40
}

variable "block_storage_label" {
  description = "Block Storage のラベル"
  type        = string
  default     = "ofc-blockstorage"
}

# === Object Storage ===
variable "object_storage_region" {
  description = "Object Storage リージョン (例: ap-south-1)"
  type        = string
  default     = "ap-south-1"
}

variable "s3_bucket_prefix" {
  description = "S3 バケット名のプレフィックス (空の場合はドメイン名から自動生成: example.com → example-com)"
  type        = string
  default     = ""
}

variable "s3_buckets" {
  description = "作成する S3 バケット名サフィックスのリスト"
  type        = list(string)
  default     = ["nextcloud", "synapse-media", "jellyfin-media", "backup"]
}

# === Firewall ===
variable "allowed_ssh_cidrs" {
  description = "SSH 接続を許可する CIDR (空なら全許可)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
