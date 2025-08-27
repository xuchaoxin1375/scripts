#!/bin/bash

# 要创建的用户名（可通过参数传入）
USERNAME="${1:-uploader}"

# 上传根目录
BASE_DIR="/srv/uploads"
USER_HOME="$BASE_DIR/$USERNAME"
UPLOAD_DIR="$USER_HOME/files"

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    echo "请以 root 用户运行此脚本"
    exit 1
fi

# 创建目录结构
echo "创建目录：$UPLOAD_DIR"
mkdir -p "$UPLOAD_DIR"

# 创建用户（无 shell 登录）
if id "$USERNAME" &>/dev/null; then
    echo "用户 $USERNAME 已存在，跳过创建"
else
    echo "创建用户：$USERNAME"
    useradd -m -d "$USER_HOME" -s /usr/sbin/nologin "$USERNAME"
    passwd "$USERNAME"
fi

# 设置目录权限
echo "设置目录权限"
chown root:root "$USER_HOME"
chmod 755 "$USER_HOME"

chown "$USERNAME":"$USERNAME" "$UPLOAD_DIR"


# 只为 uploader 用户添加 SFTP 限制，不影响 root
SSHD_CONFIG="/etc/ssh/sshd_config"
MATCH_BLOCK="Match User $USERNAME"

# 移除全局 ForceCommand internal-sftp（如果有）
if grep -q '^ForceCommand internal-sftp' "$SSHD_CONFIG"; then
    echo "检测到全局 ForceCommand internal-sftp，已注释以避免影响 root 登录"
    sed -i 's/^ForceCommand internal-sftp/#ForceCommand internal-sftp/' "$SSHD_CONFIG"
fi

# 检查是否已有该用户的 Match 块
if grep -q "$MATCH_BLOCK" "$SSHD_CONFIG"; then
    echo "SSH 配置中已存在用户规则，跳过写入"
else
    echo "写入 SSH 配置：$SSHD_CONFIG"
    cat >> "$SSHD_CONFIG" <<EOF

$MATCH_BLOCK
    ChrootDirectory $USER_HOME
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
EOF
fi

# 让uploader可以读写USER_HOME目录
chmod +x "$USER_HOME"

# 重启 SSH 服务
echo "重启 SSH 服务"
systemctl restart ssh

echo "✅ 用户 $USERNAME 创建完成，可通过 SFTP 登录并上传至 $UPLOAD_DIR"
