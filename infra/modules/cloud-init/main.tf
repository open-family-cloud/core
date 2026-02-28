# cloud-init モジュール
# デプロイパターンに応じた cloud-init 設定を生成する

locals {
  # 共通初期化スクリプト
  common_setup = file("${path.module}/scripts/common-setup.sh")

  # パターンに応じたテンプレートを選択
  template_file = var.deploy_pattern == "compose" ? (
    "${path.module}/templates/compose.yaml.tpl"
  ) : "${path.module}/templates/k8s.yaml.tpl"
}

data "template_file" "cloud_init" {
  template = file(local.template_file)

  vars = {
    common_setup_script = base64encode(local.common_setup)
    hostname            = var.hostname
    ssh_public_key      = var.ssh_public_key
    block_device        = var.block_device
    mount_point         = var.mount_point
    username            = var.username
  }
}
