#cloud-config
# パターン2: VPS + Kubernetes 用 cloud-init 設定

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

  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1

runcmd:
  # --- 共通初期化 ---
  - bash /opt/ofc/common-setup.sh "${username}"

  # --- カーネルモジュール ---
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system

  # --- containerd インストール ---
  - install -m 0755 -d /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  - chmod a+r /etc/apt/keyrings/docker.asc
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  - apt-get update
  - apt-get install -y containerd.io
  - mkdir -p /etc/containerd
  - containerd config default > /etc/containerd/config.toml
  - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  - systemctl restart containerd
  - systemctl enable containerd

  # --- kubeadm / kubelet / kubectl インストール ---
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" > /etc/apt/sources.list.d/kubernetes.list
  - apt-get update
  - apt-get install -y kubelet kubeadm kubectl
  - apt-mark hold kubelet kubeadm kubectl

  # --- kubeadm init (シングルノード) ---
  - kubeadm init --pod-network-cidr=10.244.0.0/16
  - mkdir -p /home/${username}/.kube
  - cp /etc/kubernetes/admin.conf /home/${username}/.kube/config
  - chown -R ${username}:${username} /home/${username}/.kube
  - kubectl --kubeconfig=/home/${username}/.kube/config taint nodes --all node-role.kubernetes.io/control-plane-

  # --- Flannel CNI ---
  - kubectl --kubeconfig=/home/${username}/.kube/config apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

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
  - ufw allow 6443/tcp
  - ufw --force enable
