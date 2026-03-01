.DEFAULT_GOAL := help

PROJECT_DIR := $(shell pwd)
PROVIDER ?= vultr

.PHONY: help install-tools lint format test check check-compose check-k8s
.PHONY: tf-init tf-plan tf-apply tf-destroy tf-validate bootstrap destroy

install-tools: ## 開発ツールをインストール
	uv tool install pre-commit
	pre-commit install
	go install mvdan.cc/sh/v3/cmd/shfmt@latest
	sudo apt-get install -y bats argon2
	@# AWS CLI (Vultr S3 バケット作成に必要)
	@if ! command -v aws >/dev/null 2>&1; then \
		echo "--- AWS CLI をインストール中 ---"; \
		curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$$(uname -m).zip" -o /tmp/awscliv2.zip; \
		unzip -qo /tmp/awscliv2.zip -d /tmp/; \
		sudo /tmp/aws/install --update; \
		rm -rf /tmp/awscliv2.zip /tmp/aws; \
	else \
		echo "--- AWS CLI は既にインストール済み: $$(aws --version) ---"; \
	fi
	@# Terraform (HashiCorp 公式 APT リポジトリ)
	@if ! command -v terraform >/dev/null 2>&1; then \
		echo "--- Terraform をインストール中 ---"; \
		sudo apt-get install -y gnupg software-properties-common; \
		wget -qO- https://apt.releases.hashicorp.com/gpg | sudo gpg --batch --yes --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg; \
		echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $$(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list; \
		sudo apt-get update && sudo apt-get install -y terraform; \
	else \
		echo "--- Terraform は既にインストール済み: $$(terraform version -json | head -1) ---"; \
	fi

lint: ## lint を実行（全ファイル対象）
	pre-commit run --all-files

format: ## シェルスクリプトをフォーマット
	pre-commit run shfmt --all-files

test: ## bats テストを実行
	bats --recursive tests/

check: check-compose ## 全パターンの設定を検証

check-compose: ## 全 Compose 変種のバリデーション
	@echo "=== Validating Compose files ==="
	cd platforms/vps-compose && docker compose config --quiet
	cd platforms/home-static-ip && docker compose config --quiet
	cd platforms/home-tunnel/home && docker compose config --quiet
	cd platforms/home-tunnel/vps && docker compose config --quiet

check-k8s: ## Kustomize マニフェストのバリデーション
	@echo "=== Validating Kustomize manifests ==="
	kustomize build platforms/vps-k8s/kustomize/overlays/single-node > /dev/null
	kustomize build platforms/vps-k8s/kustomize/overlays/multi-node > /dev/null

bootstrap: ## ワンコマンドデプロイ (CONFIG=infra/bootstrap.conf)
	infra/scripts/bootstrap.sh $(or $(CONFIG),infra/bootstrap.conf)

destroy: ## 全リソース削除 (CONFIG=infra/bootstrap.conf)
	infra/scripts/bootstrap.sh destroy $(or $(CONFIG),infra/bootstrap.conf)

tf-init: ## Terraform 初期化 (PROVIDER=vultr|linode|cloudflare)
	cd infra/$(PROVIDER) && terraform init

tf-plan: ## Terraform プラン確認 (PROVIDER=vultr|linode|cloudflare)
	cd infra/$(PROVIDER) && terraform plan

tf-apply: ## Terraform 適用 (PROVIDER=vultr|linode|cloudflare)
	cd infra/$(PROVIDER) && terraform apply

tf-destroy: ## Terraform リソース削除 (PROVIDER=vultr|linode|cloudflare)
	cd infra/$(PROVIDER) && terraform destroy

tf-validate: ## 全プロバイダの Terraform バリデーション
	@for dir in infra/vultr infra/linode infra/cloudflare; do \
		echo "=== $$dir ==="; \
		cd $(PROJECT_DIR)/$$dir && terraform init -backend=false && terraform validate; \
	done

help: ## ヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
