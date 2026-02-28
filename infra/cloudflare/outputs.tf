# Cloudflare — 出力

output "subdomain_records" {
  description = "作成されたサブドメインレコードの FQDN リスト"
  value = {
    for key, record in cloudflare_dns_record.subdomains : key => {
      fqdn    = "${record.name}.${var.domain}"
      proxied = record.proxied
    }
  }
}

output "root_record" {
  description = "ルートドメインレコード"
  value = {
    fqdn    = var.domain
    proxied = cloudflare_dns_record.root.proxied
  }
}

output "nameservers" {
  description = "Cloudflare に設定するネームサーバー (ゾーン作成時に確認)"
  value       = "Cloudflare ダッシュボードでネームサーバーを確認してください"
}
