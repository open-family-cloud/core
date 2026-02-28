# DNS レコードモジュール — 入力変数

variable "domain" {
  description = "メインドメイン (例: example.com)"
  type        = string
}

variable "ip_address" {
  description = "A レコードに設定する IP アドレス"
  type        = string
}

variable "subdomains" {
  description = "作成するサブドメインのリスト"
  type        = list(string)
  default     = ["cloud", "chat", "matrix", "meet", "media", "vault", "ldap", "mail"]
}
