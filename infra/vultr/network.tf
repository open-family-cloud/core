# Vultr — ファイアウォール

resource "vultr_firewall_group" "ofc" {
  description = "Open Family Cloud ファイアウォール"
}

# --- SSH ---
resource "vultr_firewall_rule" "ssh" {
  for_each = toset(var.allowed_ssh_cidrs)

  firewall_group_id = vultr_firewall_group.ofc.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = split("/", each.value)[0]
  subnet_size       = tonumber(split("/", each.value)[1])
  port              = "22"
  notes             = "SSH from ${each.value}"
}

# --- HTTP/HTTPS ---
resource "vultr_firewall_rule" "http" {
  firewall_group_id = vultr_firewall_group.ofc.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "80"
  notes             = "HTTP"
}

resource "vultr_firewall_rule" "https" {
  firewall_group_id = vultr_firewall_group.ofc.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "443"
  notes             = "HTTPS"
}

# --- メール (SMTP/SMTPS/Submission/IMAPS) ---
resource "vultr_firewall_rule" "smtp" {
  firewall_group_id = vultr_firewall_group.ofc.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "25"
  notes             = "SMTP"
}

resource "vultr_firewall_rule" "smtps" {
  firewall_group_id = vultr_firewall_group.ofc.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "465"
  notes             = "SMTPS"
}

resource "vultr_firewall_rule" "submission" {
  firewall_group_id = vultr_firewall_group.ofc.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "587"
  notes             = "Submission"
}

resource "vultr_firewall_rule" "imaps" {
  firewall_group_id = vultr_firewall_group.ofc.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "993"
  notes             = "IMAPS"
}

# --- Jitsi (JVB UDP) ---
resource "vultr_firewall_rule" "jvb" {
  firewall_group_id = vultr_firewall_group.ofc.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "10000"
  notes             = "Jitsi JVB"
}
