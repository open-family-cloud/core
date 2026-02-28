# Linode プロバイダ — バージョン制約

terraform {
  required_version = ">= 1.5"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = ">= 2.0"
    }
  }
}
