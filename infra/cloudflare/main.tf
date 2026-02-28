# Cloudflare プロバイダ — メイン設定

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

# --- DNS レコードマップ生成 ---
module "dns_records" {
  source = "../modules/dns-records"

  domain     = var.domain
  ip_address = var.vps_ip
  subdomains = var.subdomains
}

locals {
  # プロキシ対象サブドメインのセット (個別指定がなければ proxied 変数に従う)
  proxied_set = toset(var.proxied_subdomains)

  # メール関連サブドメインはプロキシ不可 (SMTP/IMAP が通らないため)
  mail_subdomains = toset(["mail"])
}

# --- サブドメイン A レコード ---
resource "cloudflare_record" "subdomains" {
  for_each = module.dns_records.records

  zone_id = var.zone_id
  name    = each.value.name
  content = each.value.ip
  type    = "A"
  ttl     = contains(local.mail_subdomains, each.key) ? var.ttl : (local.is_proxied[each.key] ? 1 : var.ttl)
  proxied = contains(local.mail_subdomains, each.key) ? false : local.is_proxied[each.key]
}

locals {
  # 各サブドメインのプロキシ状態を計算
  is_proxied = {
    for sub in var.subdomains : sub => (
      length(var.proxied_subdomains) > 0
      ? contains(var.proxied_subdomains, sub)
      : var.proxied
    )
  }
}

# --- ルートドメイン A レコード ---
resource "cloudflare_record" "root" {
  zone_id = var.zone_id
  name    = "@"
  content = var.vps_ip
  type    = "A"
  ttl     = var.proxied ? 1 : var.ttl
  proxied = var.proxied
}

# ============================================================
# メール DNS レコード (任意)
# ============================================================

# --- MX レコード ---
resource "cloudflare_record" "mx" {
  count = var.enable_mail_dns ? 1 : 0

  zone_id  = var.zone_id
  name     = "@"
  content  = "mail.${var.domain}"
  type     = "MX"
  priority = var.mail_mx_priority
  ttl      = var.ttl
}

# --- SPF レコード ---
resource "cloudflare_record" "spf" {
  count = var.enable_mail_dns ? 1 : 0

  zone_id = var.zone_id
  name    = "@"
  content = "v=spf1 mx a:mail.${var.domain} -all"
  type    = "TXT"
  ttl     = var.ttl
}

# --- DMARC レコード ---
resource "cloudflare_record" "dmarc" {
  count = var.enable_mail_dns ? 1 : 0

  zone_id = var.zone_id
  name    = "_dmarc"
  content = "v=DMARC1; p=quarantine; rua=mailto:postmaster@${var.domain}"
  type    = "TXT"
  ttl     = var.ttl
}

# --- DKIM レコード ---
resource "cloudflare_record" "dkim" {
  count = var.enable_mail_dns && var.mail_dkim_record != "" ? 1 : 0

  zone_id = var.zone_id
  name    = "mail._domainkey"
  content = var.mail_dkim_record
  type    = "TXT"
  ttl     = var.ttl
}
