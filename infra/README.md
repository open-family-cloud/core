# Infrastructure as Code (Terraform)

Open Family Cloud の VPS 系パターン（パターン1: VPS+Compose、パターン2: VPS+k8s）で必要なインフラを
Terraform で自動プロビジョニングします。

## アーキテクチャ

コンピュートとDNSを分離して管理します:

- **コンピュート** (Vultr or Linode): VPS、Block Storage、Object Storage、Firewall
- **DNS** (Cloudflare): サブドメイン A レコード、メール DNS (MX, SPF, DKIM, DMARC)

```
┌──────────────────┐     ┌──────────────────┐
│ Vultr or Linode  │     │    Cloudflare     │
│                  │     │                   │
│  VPS             │◄────│  *.example.com    │
│  Block Storage   │ IP  │  A レコード       │
│  Object Storage  │     │  メール DNS       │
│  Firewall        │     │  CDN/WAF (任意)   │
└──────────────────┘     └──────────────────┘
```

## 対応プロバイダ

| プロバイダ | ディレクトリ | 役割 |
|-----------|-------------|------|
| **Vultr** | `vultr/` | コンピュート (VPS, Storage, Firewall) |
| **Linode** | `linode/` | コンピュート (VPS, Storage, Firewall) |
| **Cloudflare** | `cloudflare/` | DNS 管理 (A レコード, メール DNS) |

## プロビジョニングされるリソース

### コンピュート (Vultr / Linode)

| リソース | 用途 |
|---------|------|
| VPS (Compute) | サーバー本体 |
| SSH Key | VPS アクセス用 |
| Block Storage | メールデータ (`/mnt/blockstorage/mail`) |
| Object Storage | S3 バケット×4 (nextcloud, synapse, jellyfin, backup) |
| Firewall | ポート制限 (22, 80, 443, 25, 465, 587, 993, 10000/udp) |

### DNS (Cloudflare)

| リソース | 用途 |
|---------|------|
| A レコード | サブドメイン (cloud, chat, matrix, meet, media, vault, ldap, mail) |
| MX レコード | メール配送 (任意) |
| TXT レコード | SPF, DKIM, DMARC (任意) |

## ディレクトリ構成

```
infra/
├── README.md                 # このファイル
├── modules/                  # 共有モジュール
│   ├── cloud-init/           # cloud-init テンプレート (compose/k8s)
│   └── dns-records/          # DNS レコードマップ生成
├── vultr/                    # Vultr コンピュート
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── compute.tf
│   ├── storage.tf
│   ├── network.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
├── linode/                   # Linode コンピュート
│   └── (同上)
├── cloudflare/               # Cloudflare DNS
│   ├── versions.tf
│   ├── variables.tf
│   ├── main.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
└── scripts/
    └── generate-env.sh       # terraform output → .env 変換
```

## ワンコマンドデプロイ (推奨)

設定ファイル 1 つを書くだけで、インフラ構築からサービス起動まで全自動で実行します。

### 前提条件

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- jq
- Vultr or Linode の API キー
- Cloudflare API トークン (Zone.Zone Read + Zone.DNS Edit 権限)
- SSH 鍵ペア (`~/.ssh/id_ed25519` + `.pub`)
- Vultr の場合: [AWS CLI](https://aws.amazon.com/cli/) (S3 バケット作成用)

### 手順

```bash
# 1. 設定ファイルを作成
cd infra
cp bootstrap.example.conf bootstrap.conf

# 2. 全変数を編集 (API キー、ドメイン、パスワード等)
vim bootstrap.conf

# 3. ワンコマンドでデプロイ
./scripts/bootstrap.sh bootstrap.conf
```

これだけで以下が自動実行されます:

1. **Terraform apply (Vultr/Linode)** — VPS、Block Storage、Object Storage、Firewall
2. **Terraform apply (Cloudflare)** — DNS レコード (A × 9 + MX + SPF + DMARC)
3. **cloud-init 完了待ち** — Docker、ユーザー作成、SSH hardening
4. **リポジトリ clone + .env 配置** — 全変数を自動生成して VPS に転送
5. **setup.sh 実行** — テンプレート展開、14 コンテナ起動、LDAP 統合
6. **DKIM DNS 登録** — mailserver が生成した DKIM キーを自動で Cloudflare に追加

Make 経由でも実行できます:

```bash
make bootstrap CONFIG=infra/bootstrap.conf
```

---

## 手動デプロイ (個別ステップ)

各 Terraform モジュールを個別に操作したい場合:

### 1. コンピュートの構築

```bash
cd infra/vultr
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

terraform init
terraform plan
terraform apply
```

### 2. DNS の設定 (Cloudflare)

```bash
cd infra/cloudflare
cp terraform.tfvars.example terraform.tfvars

# VPS IP を取得して terraform.tfvars に設定
cd ../vultr && terraform output -raw vps_public_ip

cd ../cloudflare
vim terraform.tfvars
terraform init
terraform apply
```

### 3. .env 変数の生成

```bash
cd infra/scripts
./generate-env.sh vultr compose >> ../../platforms/vps-compose/.env
```

### 4. サーバーに SSH 接続

```bash
cd infra/vultr
ssh ofc@$(terraform output -raw vps_public_ip)
```

## Make コマンド

```bash
make tf-init PROVIDER=vultr       # terraform init
make tf-plan PROVIDER=vultr       # terraform plan
make tf-apply PROVIDER=vultr      # terraform apply
make tf-apply PROVIDER=cloudflare # DNS 反映
make tf-destroy                   # terraform destroy
make tf-validate                  # 全プロバイダの validate

# プロバイダを切り替える場合
make tf-init PROVIDER=linode
make tf-plan PROVIDER=linode
```

## Cloudflare DNS 設定の詳細

### プロキシ設定

Cloudflare プロキシ (オレンジ雲) を有効にすると CDN/WAF が適用されますが、
メール関連ポート (25, 465, 587, 993) が通らなくなるため、`mail` サブドメインは
自動的にプロキシ無効で作成されます。

```hcl
# 全サブドメインでプロキシを有効 (mail は自動で除外)
proxied = true

# 特定のサブドメインだけプロキシを有効にする場合
proxied = false
proxied_subdomains = ["cloud", "vault"]
```

### メール DNS レコード

mailserver のセットアップ後、以下を有効にしてメール配送用 DNS を追加できます:

```hcl
enable_mail_dns = true
mail_dkim_record = "v=DKIM1; k=rsa; p=MIGf..."  # mailserver が生成した DKIM キー
```

作成されるレコード:
- `MX @ → mail.example.com`
- `TXT @ → v=spf1 mx a:mail.example.com -all`
- `TXT _dmarc → v=DMARC1; p=quarantine; ...`
- `TXT mail._domainkey → (DKIM 値)`

## cloud-init について

VPS 作成時に cloud-init で以下が自動設定されます:

### パターン1 (Compose)
- システム更新 + 基本パッケージ
- Docker CE + Docker Compose プラグイン
- `ofc` ユーザー作成 (docker グループ追加)
- Block Storage マウント (`/mnt/blockstorage`)
- SSH hardening (パスワード認証無効化)
- fail2ban 設定
- UFW ファイアウォール

### パターン2 (k8s)
- 上記に加えて:
- containerd ランタイム
- kubeadm / kubelet / kubectl
- シングルノード Kubernetes クラスタ初期化
- Flannel CNI デプロイ

## インフラの削除

DNS を先に削除してからコンピュートを削除します:

```bash
cd infra/cloudflare && terraform destroy
cd infra/vultr && terraform destroy   # または infra/linode
```

## トラブルシューティング

### Vultr Object Storage のバケットが作成されない
AWS CLI がインストールされていることを確認してください。
Vultr の Object Storage バケットは `aws s3api` コマンドで作成されます。

### cloud-init の進行状況を確認
```bash
ssh ofc@<VPS_IP> 'sudo cloud-init status --wait'
ssh ofc@<VPS_IP> 'sudo cat /var/log/cloud-init-output.log'
```

### Cloudflare の API トークン権限
API トークンには以下の権限が必要です:
- Zone → Zone → Read
- Zone → DNS → Edit
- ゾーンリソース: 対象ドメインを含める
