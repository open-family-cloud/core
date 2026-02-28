# cloud-init モジュール — 入力変数

variable "deploy_pattern" {
  description = "デプロイパターン: compose または k8s"
  type        = string

  validation {
    condition     = contains(["compose", "k8s"], var.deploy_pattern)
    error_message = "deploy_pattern は 'compose' または 'k8s' のいずれか"
  }
}

variable "hostname" {
  description = "サーバーのホスト名"
  type        = string
  default     = "ofc-server"
}

variable "ssh_public_key" {
  description = "SSH 公開鍵の内容"
  type        = string
}

variable "block_device" {
  description = "Block Storage のデバイスパス (例: /dev/vdb)"
  type        = string
  default     = "/dev/vdb"
}

variable "mount_point" {
  description = "Block Storage のマウントポイント"
  type        = string
  default     = "/mnt/blockstorage"
}

variable "username" {
  description = "作成するシステムユーザー名"
  type        = string
  default     = "ofc"
}
