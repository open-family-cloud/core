# Linode — VPS インスタンス

resource "linode_instance" "ofc" {
  label  = var.vps_label
  region = var.region
  type   = var.vps_plan
  image  = var.vps_image

  root_pass       = var.root_pass
  authorized_keys = [trimspace(file(pathexpand(var.ssh_public_key_path)))]

  metadata {
    user_data = module.cloud_init.rendered_base64
  }

  tags = ["ofc", var.deploy_pattern]
}
