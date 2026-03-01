# Linode — 出力

output "vps_public_ip" {
  description = "VPS のパブリック IP アドレス"
  value       = linode_instance.ofc.ip_address
}

output "vps_id" {
  description = "VPS インスタンス ID"
  value       = linode_instance.ofc.id
}

output "s3_endpoint" {
  description = "S3 互換エンドポイント URL"
  value       = "https://${var.object_storage_region}.linodeobjects.com"
}

output "s3_access_key" {
  description = "S3 アクセスキー"
  value       = linode_object_storage_key.ofc.access_key
  sensitive   = true
}

output "s3_secret_key" {
  description = "S3 シークレットキー"
  value       = linode_object_storage_key.ofc.secret_key
  sensitive   = true
}

output "s3_region" {
  description = "S3 リージョン"
  value       = var.object_storage_region
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
    VPS_IP              = linode_instance.ofc.ip_address
    JVB_ADVERTISE_IP    = linode_instance.ofc.ip_address
    S3_ENDPOINT         = "https://${var.object_storage_region}.linodeobjects.com"
    S3_ACCESS_KEY       = linode_object_storage_key.ofc.access_key
    S3_SECRET_KEY       = linode_object_storage_key.ofc.secret_key
    S3_REGION           = var.object_storage_region
    S3_BUCKET_NEXTCLOUD = "${local.s3_bucket_prefix}-nextcloud"
    S3_BUCKET_SYNAPSE   = "${local.s3_bucket_prefix}-synapse-media"
    S3_BUCKET_JELLYFIN  = "${local.s3_bucket_prefix}-jellyfin-media"
    S3_BUCKET_BACKUP    = "${local.s3_bucket_prefix}-backup"
    MAIL_STORAGE_PATH   = "/mnt/block-storage/mail"
  }
}
