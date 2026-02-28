# Vultr プロバイダ — 入力変数

# === 認証 ===
variable "vultr_api_key" {
  description = "Vultr API キー (環境変数 VULTR_API_KEY でも設定可)"
  type        = string
  sensitive   = true
}

# === 基本設定 ===
variable "domain" {
  description = "メインドメイン (例: family.example.com)"
  type        = string
}

variable "region" {
  description = "Vultr リージョン (例: nrt = 東京)"
  type        = string
  default     = "nrt"
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
  description = "Vultr VPS プラン (例: vc2-2c-4gb)"
  type        = string
  default     = "vc2-2c-4gb"
}

variable "vps_label" {
  description = "VPS のラベル"
  type        = string
  default     = "ofc-server"
}

variable "vps_os_id" {
  description = "Vultr OS ID (2284 = Ubuntu 24.04 LTS)"
  type        = number
  default     = 2284
}

# === Block Storage ===
variable "block_storage_size_gb" {
  description = "Block Storage サイズ (GB)"
  type        = number
  default     = 40
}

variable "block_storage_label" {
  description = "Block Storage のラベル"
  type        = string
  default     = "ofc-blockstorage"
}

# === Object Storage ===
variable "object_storage_cluster_id" {
  description = "Vultr Object Storage クラスタ ID (例: nrt1)"
  type        = string
  default     = "nrt1"
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
