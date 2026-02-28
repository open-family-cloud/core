#!/bin/bash
# PostgreSQL 初期化スクリプト — 各サービス用データベースとユーザーを作成
# 環境変数は Docker Compose の environment セクションから注入される
# shellcheck disable=SC2154
set -e

create_db_and_user() {
    local db=$1
    local user=$2
    local password=$3

    echo "Creating database '$db' with user '$user'"

    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname postgres <<-EOSQL
        CREATE USER ${user} WITH PASSWORD '${password}';
        CREATE DATABASE ${db} WITH OWNER ${user}
            ENCODING 'UTF8'
            LC_COLLATE='C'
            LC_CTYPE='C'
            TEMPLATE template0;
        GRANT ALL PRIVILEGES ON DATABASE ${db} TO ${user};
EOSQL
}

# Nextcloud
create_db_and_user \
    "${POSTGRES_NEXTCLOUD_DB}" \
    "${POSTGRES_NEXTCLOUD_USER}" \
    "${POSTGRES_NEXTCLOUD_PASSWORD}"

# Matrix Synapse
create_db_and_user \
    "${POSTGRES_SYNAPSE_DB}" \
    "${POSTGRES_SYNAPSE_USER}" \
    "${POSTGRES_SYNAPSE_PASSWORD}"

# Vaultwarden
create_db_and_user \
    "${POSTGRES_VAULTWARDEN_DB}" \
    "${POSTGRES_VAULTWARDEN_USER}" \
    "${POSTGRES_VAULTWARDEN_PASSWORD}"

echo "All databases initialized."
