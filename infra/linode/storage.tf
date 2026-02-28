# Linode — Block Storage (Volume) + Object Storage

# --- Block Storage (Volume) ---
resource "linode_volume" "ofc" {
  label     = var.block_storage_label
  region    = var.region
  size      = var.block_storage_size_gb
  linode_id = linode_instance.ofc.id
}

# --- Object Storage Key ---
resource "linode_object_storage_key" "ofc" {
  label = "${var.vps_label}-s3-key"

  dynamic "bucket_access" {
    for_each = toset(var.s3_buckets)
    content {
      cluster     = var.object_storage_region
      bucket_name = "${local.s3_bucket_prefix}-${bucket_access.value}"
      permissions = "read_write"
    }
  }
}

# --- Object Storage Buckets ---
resource "linode_object_storage_bucket" "ofc" {
  for_each = toset(var.s3_buckets)

  cluster = var.object_storage_region
  label   = "${local.s3_bucket_prefix}-${each.value}"
}
