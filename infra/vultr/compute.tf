# Vultr — VPS インスタンス

resource "vultr_instance" "ofc" {
  label     = var.vps_label
  region    = var.region
  plan      = var.vps_plan
  os_id     = var.vps_os_id
  user_data = module.cloud_init.rendered

  ssh_key_ids       = [vultr_ssh_key.ofc.id]
  firewall_group_id = vultr_firewall_group.ofc.id
  enable_ipv6       = true
  backups           = "enabled"
  reserved_ip_id    = vultr_reserved_ip.ofc.id
  activation_email  = false
  ddos_protection   = false
  hostname          = var.vps_label

  backups_schedule {
    type = "daily"
  }

  tags = ["ofc", var.deploy_pattern]
}
