# パターン2: VPS + Kubernetes

Kubernetes（Kustomize）で全サービスをデプロイするパターンです。

## 前提条件

- Kubernetes クラスタ（k3s / microk8s / kubeadm 等）
- kubectl + kustomize
- Ingress Controller（Traefik / nginx-ingress）
- cert-manager（TLS 証明書管理）
- ドメイン名（DNS A レコードをクラスタ IP に設定済み）
- S3 Object Storage（Nextcloud / Synapse / バックアップ用）

## セットアップ

```bash
# 1. リポジトリをクローン
git clone https://github.com/open-family-cloud/core.git
cd core/platforms/vps-k8s

# 2. .env を作成（Secret 生成用）
cp .env.example .env
nano .env

# 3. セットアップ実行
./scripts/setup.sh
```

## オーバーレイ

| オーバーレイ | 用途 |
|-------------|------|
| `single-node` | VPS 1台のシンプルな構成 |
| `multi-node` | 複数ノードでの可用性重視構成 |

## 運用コマンド

```bash
./scripts/update.sh       # マニフェスト再適用
./scripts/backup.sh       # kubectl exec で pg_dump 等
./scripts/healthcheck.sh  # Pod 状態 + エンドポイント確認
```
