# cloud-init モジュール — 出力

output "rendered" {
  description = "レンダリング済み cloud-init 設定 (YAML)"
  value       = data.template_file.cloud_init.rendered
}

output "rendered_base64" {
  description = "Base64 エンコード済み cloud-init 設定"
  value       = base64encode(data.template_file.cloud_init.rendered)
}
