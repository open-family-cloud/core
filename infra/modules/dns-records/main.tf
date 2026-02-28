# DNS レコードモジュール
# サブドメインリストから DNS レコードのマップを生成する

locals {
  records = {
    for sub in var.subdomains : sub => {
      name   = sub
      domain = var.domain
      ip     = var.ip_address
      fqdn   = "${sub}.${var.domain}"
    }
  }
}
