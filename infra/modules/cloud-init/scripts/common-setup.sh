#!/bin/bash
# 共通初期化スクリプト
# cloud-init から呼び出される。ユーザー作成、SSH hardening、fail2ban を設定する。
set -euo pipefail

USERNAME="${1:?ユーザー名が必要です}"

# --- システムユーザー作成 ---
if ! id "$USERNAME" &>/dev/null; then
    useradd -m -s /bin/bash -G sudo "$USERNAME"
    echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
    chmod 0440 "/etc/sudoers.d/$USERNAME"
fi

# --- SSH 鍵をコピー (プロバイダが root に注入した鍵を ofc ユーザーに複製) ---
if [[ -f /root/.ssh/authorized_keys ]]; then
    mkdir -p "/home/$USERNAME/.ssh"
    cp /root/.ssh/authorized_keys "/home/$USERNAME/.ssh/"
    chown -R "$USERNAME:$USERNAME" "/home/$USERNAME/.ssh"
    chmod 700 "/home/$USERNAME/.ssh"
    chmod 600 "/home/$USERNAME/.ssh/authorized_keys"
fi

# --- SSH hardening ---
SSHD_CONFIG="/etc/ssh/sshd_config"
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' "$SSHD_CONFIG"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
sed -i 's/^#\?PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"
systemctl restart sshd || systemctl restart ssh

# --- fail2ban 設定 ---
cat > /etc/fail2ban/jail.local <<'JAIL'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true
port    = ssh
JAIL
systemctl enable fail2ban
systemctl restart fail2ban
