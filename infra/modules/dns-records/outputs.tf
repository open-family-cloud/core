# DNS レコードモジュール — 出力

output "records" {
  description = "サブドメインごとの DNS レコード情報マップ"
  value       = local.records
}
