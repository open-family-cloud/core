# Vultr プロバイダ — メイン設定

provider "vultr" {
  api_key = var.vultr_api_key
}

# --- S3 バケット名プレフィックス (ドメイン名ベースで自動生成) ---
locals {
  s3_bucket_prefix = var.s3_bucket_prefix != "" ? var.s3_bucket_prefix : replace(var.domain, ".", "-")
}

# --- SSH Key ---
resource "vultr_ssh_key" "ofc" {
  name    = "${var.vps_label}-ssh-key"
  ssh_key = file(pathexpand(var.ssh_public_key_path))
}

# --- cloud-init ---
module "cloud_init" {
  source = "../modules/cloud-init"

  deploy_pattern = var.deploy_pattern
  hostname       = var.vps_label
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))
  block_device   = "/dev/vdb"
  mount_point    = "/mnt/block-storage"
  username       = "ofc"
}
