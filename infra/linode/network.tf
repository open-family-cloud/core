# Linode — ファイアウォール

resource "linode_firewall" "ofc" {
  label = "ofc-firewall"

  # --- SSH ---
  dynamic "inbound" {
    for_each = var.allowed_ssh_cidrs
    content {
      label    = "SSH from ${inbound.value}"
      action   = "ACCEPT"
      protocol = "TCP"
      ports    = "22"
      ipv4     = [inbound.value]
    }
  }

  # --- HTTP ---
  inbound {
    label    = "HTTP"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # --- HTTPS ---
  inbound {
    label    = "HTTPS"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # --- SMTP ---
  inbound {
    label    = "SMTP"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "25"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # --- SMTPS ---
  inbound {
    label    = "SMTPS"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "465"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # --- Submission ---
  inbound {
    label    = "Submission"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "587"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # --- IMAPS ---
  inbound {
    label    = "IMAPS"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "993"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # --- Jitsi JVB ---
  inbound {
    label    = "Jitsi JVB"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "10000"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # --- デフォルト: 受信拒否 ---
  inbound_policy = "DROP"

  # --- 送信: 全許可 ---
  outbound_policy = "ACCEPT"

  linodes = [linode_instance.ofc.id]
}
