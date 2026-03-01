# Vultr — 出力

output "vps_public_ip" {
  description = "VPS のパブリック IP アドレス (Reserved IP)"
  value       = vultr_reserved_ip.ofc.subnet
}

output "vps_id" {
  description = "VPS インスタンス ID"
  value       = vultr_instance.ofc.id
}

output "s3_endpoint" {
  description = "S3 互換エンドポイント URL"
  value       = "https://${vultr_object_storage.ofc.s3_hostname}"
}

output "s3_access_key" {
  description = "S3 アクセスキー"
  value       = vultr_object_storage.ofc.s3_access_key
  sensitive   = true
}

output "s3_secret_key" {
  description = "S3 シークレットキー"
  value       = vultr_object_storage.ofc.s3_secret_key
  sensitive   = true
}

output "s3_region" {
  description = "S3 リージョン"
  value       = var.region
}

output "s3_bucket_nextcloud" {
  description = "Nextcloud 用 S3 バケット名"
  value       = "${local.s3_bucket_prefix}-nextcloud"
}

output "s3_bucket_synapse" {
  description = "Synapse メディア用 S3 バケット名"
  value       = "${local.s3_bucket_prefix}-synapse-media"
}

output "s3_bucket_jellyfin" {
  description = "Jellyfin メディア用 S3 バケット名"
  value       = "${local.s3_bucket_prefix}-jellyfin-media"
}

output "s3_bucket_backup" {
  description = "バックアップ用 S3 バケット名"
  value       = "${local.s3_bucket_prefix}-backup"
}

output "block_storage_mount_point" {
  description = "Block Storage のマウントポイント"
  value       = "/mnt/block-storage"
}

output "env_vars" {
  description = ".env ファイルに書き込むための変数マップ"
  sensitive   = true
  value = {
    VPS_IP              = vultr_reserved_ip.ofc.subnet
    JVB_ADVERTISE_IP    = vultr_reserved_ip.ofc.subnet
    S3_ENDPOINT         = "https://${vultr_object_storage.ofc.s3_hostname}"
    S3_ACCESS_KEY       = vultr_object_storage.ofc.s3_access_key
    S3_SECRET_KEY       = vultr_object_storage.ofc.s3_secret_key
    S3_REGION           = var.region
    S3_BUCKET_NEXTCLOUD = "${local.s3_bucket_prefix}-nextcloud"
    S3_BUCKET_SYNAPSE   = "${local.s3_bucket_prefix}-synapse-media"
    S3_BUCKET_JELLYFIN  = "${local.s3_bucket_prefix}-jellyfin-media"
    S3_BUCKET_BACKUP    = "${local.s3_bucket_prefix}-backup"
    MAIL_STORAGE_PATH   = "/mnt/block-storage/mail"
  }
}
