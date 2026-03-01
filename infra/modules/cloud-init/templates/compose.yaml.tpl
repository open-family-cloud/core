#cloud-config
# パターン1: VPS + Docker Compose 用 cloud-init 設定

hostname: ${hostname}

package_update: true
package_upgrade: true

packages:
  - curl
  - git
  - jq
  - fail2ban
  - ufw
  - apt-transport-https
  - ca-certificates
  - gnupg
  - lsb-release

write_files:
  - path: /opt/ofc/common-setup.sh
    permissions: "0755"
    encoding: b64
    content: ${common_setup_script}

runcmd:
  # --- 共通初期化 ---
  - bash /opt/ofc/common-setup.sh "${username}"

  # --- Docker CE インストール ---
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  - chmod a+r /etc/apt/keyrings/docker.asc
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # --- ユーザーを docker グループに追加 ---
  - usermod -aG docker "${username}"

  # --- rclone インストール (Jellyfin S3 マウント用) ---
  - curl -fsSL https://rclone.org/install.sh | bash

  # --- Block Storage マウント ---
  - |
    DEVICE="${block_device}"
    MOUNT="${mount_point}"
    if [ -b "$DEVICE" ]; then
      if ! blkid "$DEVICE" | grep -q 'TYPE='; then
        mkfs.ext4 "$DEVICE"
      fi
      mkdir -p "$MOUNT"
      mount "$DEVICE" "$MOUNT"
      if ! grep -q "$DEVICE" /etc/fstab; then
        echo "$DEVICE $MOUNT ext4 defaults,nofail 0 2" >> /etc/fstab
      fi
      mkdir -p "$MOUNT/mail"
      chown -R "${username}:${username}" "$MOUNT"
    fi

  # --- UFW ファイアウォール ---
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow ssh
  - ufw allow 80/tcp
  - ufw allow 443/tcp
  - ufw allow 25/tcp
  - ufw allow 465/tcp
  - ufw allow 587/tcp
  - ufw allow 993/tcp
  - ufw allow 10000/udp
  - ufw --force enable
