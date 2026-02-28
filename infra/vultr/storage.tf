# Vultr — Block Storage + Object Storage

# --- Block Storage ---
resource "vultr_block_storage" "ofc" {
  label               = var.block_storage_label
  region              = var.region
  size_gb             = var.block_storage_size_gb
  attached_to_instance = vultr_instance.ofc.id
  live                = true
}

# --- Object Storage ---
resource "vultr_object_storage" "ofc" {
  cluster_id = var.object_storage_cluster_id
  label      = "${var.vps_label}-s3"
}

# --- S3 バケット作成 (Vultr は Terraform リソースがないため aws-cli で作成) ---
resource "terraform_data" "s3_buckets" {
  for_each = toset(var.s3_buckets)

  triggers_replace = [vultr_object_storage.ofc.id]

  provisioner "local-exec" {
    command = <<-EOT
      aws s3api create-bucket \
        --bucket "${local.s3_bucket_prefix}-${each.value}" \
        --endpoint-url "https://${vultr_object_storage.ofc.s3_hostname}" \
        2>/dev/null || true
    EOT

    environment = {
      AWS_ACCESS_KEY_ID     = vultr_object_storage.ofc.s3_access_key
      AWS_SECRET_ACCESS_KEY = vultr_object_storage.ofc.s3_secret_key
      AWS_DEFAULT_REGION    = var.region
    }
  }
}
