# Linode プロバイダ — メイン設定

provider "linode" {
  token = var.linode_token
}

# --- S3 バケット名プレフィックス (ドメイン名ベースで自動生成) ---
locals {
  s3_bucket_prefix = var.s3_bucket_prefix != "" ? var.s3_bucket_prefix : replace(var.domain, ".", "-")
}

# --- SSH Key ---
resource "linode_sshkey" "ofc" {
  label   = "${var.vps_label}-key"
  ssh_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
}

# --- cloud-init ---
module "cloud_init" {
  source = "../modules/cloud-init"

  deploy_pattern = var.deploy_pattern
  hostname       = var.vps_label
  ssh_public_key = trimspace(file(pathexpand(var.ssh_public_key_path)))
  block_device   = "/dev/disk/by-id/scsi-0Linode_Volume_${var.block_storage_label}"
  mount_point    = "/mnt/blockstorage"
  username       = "ofc"
}
