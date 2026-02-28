#!/bin/bash
# ============================================================
# Open Family Cloud — LDAP ユーザー操作ライブラリ
# add / list / delete を $EXEC_CMD パラメータで抽象化
# ============================================================

[[ -n "${_OFC_LIB_LDAP:-}" ]] && return 0
readonly _OFC_LIB_LDAP=1

# shellcheck source=common.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# LDAP コマンド実行プレフィックス
# Docker Compose: "docker exec ofc-openldap"
# Kubernetes:     "kubectl exec -n ofc deploy/openldap --"
LDAP_EXEC_CMD="${LDAP_EXEC_CMD:-docker exec ofc-openldap}"

# ユーザー追加
# $1: uid  $2: mail  $3: cn（表示名）
ldap_user_add() {
    local uid=$1
    local mail=$2
    local cn=$3
    local sn
    sn=$(echo "$cn" | awk '{print $NF}')

    read -s -p "パスワード: " password
    echo ""
    read -s -p "パスワード（確認）: " password2
    echo ""

    if [[ "$password" != "$password2" ]]; then
        err "パスワードが一致しません"
        return 1
    fi

    local ldif
    ldif=$(cat <<EOF
dn: uid=${uid},ou=users,${LDAP_BASE_DN}
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
uid: ${uid}
cn: ${cn}
sn: ${sn}
mail: ${mail}
userPassword: ${password}
EOF
)

    # shellcheck disable=SC2086
    echo "$ldif" | $LDAP_EXEC_CMD ldapadd \
        -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PASSWORD}"

    # family グループに追加
    local modify_ldif
    modify_ldif=$(cat <<EOF
dn: cn=family,ou=groups,${LDAP_BASE_DN}
changetype: modify
add: member
member: uid=${uid},ou=users,${LDAP_BASE_DN}
EOF
)

    # shellcheck disable=SC2086
    echo "$modify_ldif" | $LDAP_EXEC_CMD ldapmodify \
        -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PASSWORD}" 2>/dev/null || true

    log "ユーザー ${uid} (${mail}) を追加しました"
    echo ""
    info "各サービスへのログイン情報:"
    echo "  ユーザー名: ${uid}"
    echo "  メール: ${mail}"
    echo "  パスワード: (設定したもの)"
    echo ""
    info "以下のサービスで LDAP 認証が使用できます:"
    echo "  - Nextcloud (cloud.${DOMAIN})"
    echo "  - Matrix/Element (chat.${DOMAIN})"
    echo "  - Jitsi Meet (meet.${DOMAIN})"
    echo "  - メール (mail.${DOMAIN})"
}

# ユーザー一覧
ldap_user_list() {
    log "登録済みユーザー一覧:"
    echo ""
    # shellcheck disable=SC2086
    $LDAP_EXEC_CMD ldapsearch \
        -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PASSWORD}" \
        -b "ou=users,${LDAP_BASE_DN}" \
        "(objectClass=inetOrgPerson)" \
        uid cn mail 2>/dev/null | \
    awk '
    /^dn:/ { if (uid) printf "  %-15s %-30s %s\n", uid, mail, cn; uid=""; mail=""; cn="" }
    /^uid:/ { uid=$2 }
    /^cn:/ { sub(/^cn: /, ""); cn=$0 }
    /^mail:/ { mail=$2 }
    END { if (uid) printf "  %-15s %-30s %s\n", uid, mail, cn }
    '
}

# ユーザー削除
# $1: uid
ldap_user_delete() {
    local uid=$1

    read -p "ユーザー ${uid} を削除しますか? この操作は取り消せません (y/N): " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then
        log "キャンセルしました"
        return 0
    fi

    # family グループから削除
    local modify_ldif
    modify_ldif=$(cat <<EOF
dn: cn=family,ou=groups,${LDAP_BASE_DN}
changetype: modify
delete: member
member: uid=${uid},ou=users,${LDAP_BASE_DN}
EOF
)
    # shellcheck disable=SC2086
    echo "$modify_ldif" | $LDAP_EXEC_CMD ldapmodify \
        -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PASSWORD}" 2>/dev/null || true

    # ユーザー削除
    # shellcheck disable=SC2086
    $LDAP_EXEC_CMD ldapdelete \
        -x -D "cn=admin,${LDAP_BASE_DN}" -w "${LDAP_ADMIN_PASSWORD}" \
        "uid=${uid},ou=users,${LDAP_BASE_DN}"

    log "ユーザー ${uid} を削除しました"
    echo ""
    info "注意: 各サービス内のデータ（メール、ファイル等）は残ります"
    info "必要に応じて手動で削除してください"
}
