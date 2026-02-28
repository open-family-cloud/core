# Cloudflare プロバイダ — 入力変数

# === 認証 ===
variable "cloudflare_api_token" {
  description = "Cloudflare API トークン (環境変数 CLOUDFLARE_API_TOKEN でも設定可)"
  type        = string
  sensitive   = true
}

# === ゾーン ===
variable "zone_id" {
  description = "Cloudflare ゾーン ID (ダッシュボードの概要ページで確認)"
  type        = string
}

variable "domain" {
  description = "メインドメイン (例: example.com)"
  type        = string
}

# === VPS IP ===
variable "vps_ip" {
  description = "VPS のパブリック IP アドレス (Vultr/Linode の terraform output から取得)"
  type        = string
}

# === DNS レコード ===
variable "subdomains" {
  description = "作成するサブドメインのリスト"
  type        = list(string)
  default     = ["cloud", "chat", "matrix", "meet", "media", "vault", "ldap", "mail"]
}

variable "proxied" {
  description = "Cloudflare プロキシ (CDN/WAF) を有効にするか"
  type        = bool
  default     = false
}

variable "proxied_subdomains" {
  description = "プロキシを有効にするサブドメインのリスト (proxied=true 時のオーバーライド用)"
  type        = list(string)
  default     = []
}

variable "ttl" {
  description = "DNS レコードの TTL (秒)。proxied=true の場合は自動 (1)"
  type        = number
  default     = 300
}

# === メール DNS レコード ===
variable "enable_mail_dns" {
  description = "メール関連 DNS レコード (MX, SPF, DKIM, DMARC) を作成するか"
  type        = bool
  default     = false
}

variable "mail_mx_priority" {
  description = "MX レコードの優先度"
  type        = number
  default     = 10
}

variable "mail_dkim_record" {
  description = "DKIM TXT レコードの値 (mailserver が生成したもの)"
  type        = string
  default     = ""
}
