#!/usr/bin/env bash
# 使用 root 权限执行(sudo bash ~/install_mihomo_server.sh)
# 参考文档:https://wiki.metacubex.one/startup/service/#systemd
# 标准化systemd服务安装
# 另一种方式是将systemd配置mihomo.service内容中的路径更改为当前值.
# 参数解析
set -euo pipefail

args_pos=()
usage="
使用 root 权限执行.
usage $0 [options]

options:
    -c 指定要迁移的配置文件路径
    -m 指定mihomo工作目录

    -h 显示帮助
examples:

    sudo bash $0 -c ~/.config/mihomo/config.yaml

"
mihomo_std_home="/usr/local/bin"
mihomo_std="$mihomo_std_home/mihomo"
config_std_home="/etc/mihomo"
config_std="$config_std_home/config.yaml"
# 额外依赖
geoipdb_std="$config_std_home/geoip.metadb"

mihomo="$(which mihomo)"
# 建议请在命令行调用时指定config_yaml的路径(非root用户使用sudo运行此脚本时,$HOME会变成/root/,可能读取不到正确的配置文件)
config_yaml="$HOME/.config/mihomo/config.yaml"
parse_args() {

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help)
                echo "$usage"
                exit 0
                ;;
            -m | --mihomo-path)
                mihomo="$2"
                shift
                ;;
            -c | --config-path)
                config_yaml="$2"
                shift
                ;;
            --)
                shift
                break
                ;;
            -?*)
                echo "Unknown option:$1" >&2 #输出错误信息到标准错误
                echo "$usage" >&2
                exit 2 #直接退出脚本
                ;;
            *)
                args_pos+=("$1")
                ;;
        esac
        shift
    done
    # 参数解析并调整完毕
}
parse_args "$@"
set -- "${args_pos[@]}"

# 清理可能残留的错误路径
[[ -f "$mihomo_std_home" ]] && rm -fv "$mihomo_std_home"
[[ -f "$config_std_home" ]] && rm -fv "$config_std_home"
# 创建或确保必要目录存在

mkdir -pv "$mihomo_std_home"
mkdir -pv "$config_std_home"

cp "$mihomo" $mihomo_std -fv || true
cp "$config_yaml" $config_std -fv || true

# 创建 systemd 配置文件
cat << EOF > /etc/systemd/system/mihomo.service
[Unit]
Description=mihomo Daemon.
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart="$mihomo_std" -d "$config_std_home"
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target

EOF

# 检查metadb依赖
if [[ ! -e $geoipdb_std ]]; then
    echo "尝试下载依赖[$geoipdb_std]..."
    if curl -L -o "geoipdb_std" https://gh-proxy.com/https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip.metadb; then
        echo "下载成功."
    else
        echo "下载失败."
    fi

else
    echo "检测到依赖文件[$geoipdb_std]已经存在..."
fi

echo "重载守护线程服务"
systemctl daemon-reload

echo "启动(重启)mihomo进程"
# systemctl enable mihomo.service
# 重载mihomo
# systemctl reload mihomo
systemctl restart mihomo.service

echo "检查mihomo服务状态"
systemctl status mihomo.service

# mihomo日志
# journalctl -u mihomo -o cat -e # -f
