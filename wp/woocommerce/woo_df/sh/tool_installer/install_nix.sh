#!/bin/bash

# Nix 多用户安装脚本（国内优化版）
# 用法: ./install-nix.sh [选项]

set -e

# 默认配置
INSTALL_MODE="daemon" # 多用户模式
NIX_VERSION="latest"  # 默认最新版
TRUSTED_USERS="$(whoami)"

MIRROR="bfsu"                         # 镜像源（bfsu/ustc/tuna/sjtu/nju）
CHANNEL_MIRROR="ustc"                 # channel 镜像源
BINARY_CACHE_MIRRORS="ustc,sjtu,tuna" # 二进制缓存镜像列表
CHANNEL_NAME="nixpkgs-unstable"       # 使用的 channel,通常是nixpkgs-unstable

ENABLE_FLAKES="yes"      # 启用 flakes
ENABLE_NIX_COMMAND="yes" # 启用 nix-command
SET_MIRRORS_ONLY=false   # 仅配置镜像而跳过安装nix环节
CONFIG_SCOPE="system"    # 配置范围（user/system）
# curl User-Agent
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}
show_help() {
    cat << EOF
Nix 多用户安装脚本（国内镜像优化）

用法: $0 [选项]

选项:
    --mode <mode>           安装模式: daemon(多用户,默认) | single(单用户)
    -t,--trusted-users      配置受信任的用户名列表,默认包含root和当前用户名
                            (可以手动指定多个用户名写在引号中,并用空格隔开不同用户名,此时通常也应该手动填写当前用户名),
                            或者反复使用-t选项每次分别指定用户名;
    --version <version>     Nix 版本: latest(默认) | 2.18.0 | 2.19.0 | etc
    -A,--user-agent         部分情况下没有指定UA的curl会被镜像源拒绝服务,考虑指定UA
    -m,--mirror <mirror>       安装包镜像源:   bfsu(北外) | tuna(清华)  | nju(南大) | nixorg(官方源)
                            注意:部分镜像会检查网段请求量,可能会被限流而无法请求,这种情况下请更换源;
                            ustc(中科大) | sjtu(上交) 似乎没有提供安装脚本,但是提供了channel和binary-cache
    -c,--channel-mirror <mirror> Channel 镜像源 (默认: ustc)
    -b,--binary-mirrors <list> 二进制缓存镜像列表, 逗号分隔 (默认: ustc,sjtu,tuna)
    -S,--set-mirrors-only      仅配置镜像源加速相关部分(不执行安装)

    --flakes <yes/no>       启用 flakes 特性 (默认: yes)
    --nix-command <yes/no>  启用 nix-command 特性 (默认: yes)

    --config-scope <scope>  配置范围: user(用户级) | system(系统级,默认)
    --channel <name>        使用的 channel 名称 (默认: nixpkgs-unstable)
    --no-channel-update     跳过 channel 更新步骤
    -h,--help                  显示此帮助信息

镜像说明:
    bfsu  - 北京外国语大学 (https://mirrors.bfsu.edu.cn)
    tuna  - 清华大学 (https://mirrors.tuna.tsinghua.edu.cn)
    nju   - 南京大学 (https://mirror.nju.edu.cn)
    ustc  - 中国科学技术大学 (https://mirrors.ustc.edu.cn)
    sjtu  - 上海交通大学 (https://mirror.sjtu.edu.cn)

示例:
    $0                                          # 使用默认配置安装
    $0 --mirror tuna --channel-mirror tuna     # 使用清华镜像
    $0 --flakes no --config-scope system       # 不启用 flakes，系统级配置
    $0 --version 2.19.0 --binary-mirrors tuna  # 安装指定版本，仅使用清华镜像

EOF
}
# trusted_users_list=()
# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            INSTALL_MODE="$2"
            if [[ "$INSTALL_MODE" == "single" ]]; then
                INSTALL_MODE=""
            elif [[ "$INSTALL_MODE" == "daemon" ]]; then
                INSTALL_MODE="--daemon"
            else
                print_error "无效的安装模式: $2"
                exit 2
            fi
            shift 2
            ;;
        -t | --trusted-users)
            # TRUSTED_USERS="$2"
            TRUSTED_USERS="$TRUSTED_USERS $2"
            # trusted_users_list+=("$2")
            shift 2
            ;;
        --version)
            NIX_VERSION="$2"
            shift 2
            ;;
        -A | --user-agent)
            UA="$2"
            shift 2
            ;;
        --mirror)
            MIRROR="$2"
            shift 2
            ;;
        -S | --set-mirrors-only)
            SET_MIRRORS_ONLY=true
            shift
            ;;
        --flakes)
            ENABLE_FLAKES="$2"
            shift 2
            ;;
        --nix-command)
            ENABLE_NIX_COMMAND="$2"
            shift 2
            ;;
        --config-scope)
            CONFIG_SCOPE="$2"
            shift 2
            ;;
        -b | --binary-mirrors)
            BINARY_CACHE_MIRRORS="$2"
            shift 2
            ;;
        -c | --channel-mirror)
            CHANNEL_MIRROR="$2"
            shift 2
            ;;
        --channel)
            # 通常是nixpkgs-unstable
            CHANNEL_NAME="$2"
            shift 2
            ;;
        --no-channel-update)
            SKIP_CHANNEL_UPDATE="yes"
            shift
            ;;
        -h | --help)
            show_help
            exit 0
            ;;
        *)
            print_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done
# 检查部分参数取值:
print_info "trusted-users=$TRUSTED_USERS"
# exit 1
# 选择镜像 URL(前缀部分)
get_mirror_url() {
    local mirror=$1
    case $mirror in
        ustc) echo "https://mirrors.ustc.edu.cn" ;;
        bfsu) echo "https://mirrors.bfsu.edu.cn" ;;
        nju) echo "https://mirror.nju.edu.cn" ;;
        tuna) echo "https://mirrors.tuna.tsinghua.edu.cn" ;;
        sjtu) echo "https://mirror.sjtu.edu.cn" ;;
        nixorg) echo "https://nixos.org/nix/install" ;;
        *) echo "https://nixos.org/nix/install" ;;
    esac
}
curlx() {
    local args=("$@")
    curl -L -A "$UA" "${args[@]}"
}
_install_nix() {
    # 检查是否已经安装过nix,如果有,则退出
    if command -v nix &> /dev/null; then
        print_info "nix已经安装过了,跳过后续操作."
        exit 1
    fi
    # 获取安装脚本install URL(计算前缀部分+路径)
    # 并非所有镜像源都提供(相同)的nix安装脚本,已知nju以及tuna和bfsu提供了安装脚本(两者采用相同的模板,限流规则也相似):
    # 例如tuna提供的(多用户模式)安装命令: sh <(curl -L https://mirrors.tuna.tsinghua.edu.cn/nix/latest/install) --daemon
    MIRROR_URL=$(get_mirror_url "$MIRROR")
    echo "[$MIRROR]选中URL: [$MIRROR_URL] ..."
    if [[ $MIRROR != "nixorg" ]]; then
        if [[ "$NIX_VERSION" == "latest" ]]; then
            # 一般是latest路径
            INSTALL_URL="${MIRROR_URL}/nix/latest/install"
        else
            # 备用
            INSTALL_URL="${MIRROR_URL}/nix/nix-${NIX_VERSION}/install"
        fi
    else
        INSTALL_URL="$MIRROR_URL"
    fi
    echo "测试INSTALL_URL($INSTALL_URL)可用性...."
    if curlx -I -f "$INSTALL_URL"; then
        echo "地址有效:$INSTALL_URL"
    else
        echo "地址无效:$INSTALL_URL"
        exit 1
    fi
    print_info "开始安装 Nix..."
    print_info "安装模式: ${INSTALL_MODE:-单用户}"
    print_info "镜像源: $MIRROR_URL"
    print_info "安装脚本: $INSTALL_URL"

    print_info "下载并执行安装脚本..."
    if [[ -n "$INSTALL_MODE" ]]; then
        sh <(curlx "$INSTALL_URL") $INSTALL_MODE
    else
        sh <(curlx "$INSTALL_URL")
    fi
}

# 1. 下载并执行官方安装脚本
if [[ $SET_MIRRORS_ONLY == false ]]; then

    _install_nix
else
    # 要求nix已经安装,否则配置镜像过程中会出错;
    echo "检查nix是否已经安装..."
    if command -v nix &> /dev/null; then
        echo "nix已安装"
    else
        echo "nix未安装,请先安装" >&2
        exit 1
    fi
fi
# 2. 加载 Nix 环境（如果尚未加载）通常不需要手动执行这个部分
if [[ -f ~/.nix-profile/etc/profile.d/nix.sh ]]; then
    # shellcheck disable=SC1090
    source ~/.nix-profile/etc/profile.d/nix.sh
fi

# 3. 配置 Nix
print_info "配置 Nix..."

# 计算配置文件路径,并判断是否使用sudo编辑
if [[ "$CONFIG_SCOPE" == "system" ]]; then
    # 多用户模式
    NIX_CONF_DIR="/etc/nix"
    # 判断文件是否可写,如果不可写,尝试启用sudo命令
    if [[ ! -w "$NIX_CONF_DIR" ]]; then
        print_warn "需要 sudo 权限写入系统配置"
        USE_SUDO="sudo"
    fi
else
    # 单用户模式安装
    NIX_CONF_DIR="$HOME/.config/nix"
    USE_SUDO=""
fi

$USE_SUDO mkdir -p "$NIX_CONF_DIR"
# 例如/etc/nix/nix.conf
NIX_CONF="$NIX_CONF_DIR/nix.conf"

# 构建 substituters 配置
SUBSTITUTERS=""
# 将逗号分隔的二进制缓存镜像列表字符串转换为数组,然后逐个拼接到一个字符串中
IFS=',' read -ra MIRRORS <<< "$BINARY_CACHE_MIRRORS"
for m in "${MIRRORS[@]}"; do
    mirror_url=$(get_mirror_url "$m")
    SUBSTITUTERS="$SUBSTITUTERS $mirror_url/nix-channels/store"
done
# 计算结果例如: https://mirror.sjtu.edu.cn/nix-channels/store https://...
# 追加一个默认源
SUBSTITUTERS="$SUBSTITUTERS https://cache.nixos.org"

# 构建 experimental-features 配置
# 通常构造出来的字符串是: nix-command flakes
# 这部分也可以设计成非开关方式,比如直接指定实验性选项的字符串,而不是通过开关逐个拼接;
EXPERIMENTAL_FEATURES=""
[[ "$ENABLE_NIX_COMMAND" == "yes" ]] && EXPERIMENTAL_FEATURES="$EXPERIMENTAL_FEATURES nix-command"
[[ "$ENABLE_FLAKES" == "yes" ]] && EXPERIMENTAL_FEATURES="$EXPERIMENTAL_FEATURES flakes"

EXPERIMENTAL_FEATURES=$(echo "$EXPERIMENTAL_FEATURES" | xargs) # 去除首尾空格
_set_nix_config() {
    # 写入配置文件
    print_info "写入配置文件: $NIX_CONF"
    # 使用here-doc标准输入重定向写入多行字符串到配置文件中(对于系统级配置文件,需要sudo权限,这里使用tee命令方便sudo生效)
    echo "下面的操作将会覆盖掉配置文件,覆盖前执行备份..."
    cp -v "$NIX_CONF" "${HOME}/nix.conf.bak.$(date +%F-%T)"
    # 写入配置文件(/etc/nix/nix.conf等)
    $USE_SUDO tee "$NIX_CONF" > /dev/null << EOF
# Nix 配置文件（自动生成）
# 生成时间: $(date)

# 构建用户(可选)
build-users-group = nixbld

# 二进制缓存镜像源
substituters = $SUBSTITUTERS
# 设置受信任用户(避免部分操作无法成功)
trusted-users = root $TRUSTED_USERS

# 启用实验性特性
experimental-features = $EXPERIMENTAL_FEATURES

# 自动优化存储（硬链接相同文件）
auto-optimise-store = true

# 并发构建数(是否允许远程机器使用缓存,如果使用了远程构建，建议开启此选项，能大幅节省计算资源和时间；如果只用本地构建，这个配置对你没有影响。)
builders-use-substitutes = true

EOF

    print_info "[$NIX_CONF]配置文件内容："
    cat "$NIX_CONF"
}
_set_nix_config

# 4. 配置 channel（可选）
if [[ "$SKIP_CHANNEL_UPDATE" != "yes" ]]; then
    print_info "配置 Nix channel..."
    CHANNEL_URL=$(get_mirror_url "$CHANNEL_MIRROR")/nix-channels/$CHANNEL_NAME

    print_info "添加 channel: $CHANNEL_URL"
    nix-channel --add "$CHANNEL_URL" nixpkgs

    print_info "更新 channel..."
    nix-channel --update
else
    print_info "跳过 channel 配置"
fi

# 5. 重启 nix-daemon（如果使用 systemd 且为多用户模式）
# 单独安装的 Nix 在更改完配置文件之后需要重启 nix-daemon 才能应用配置
if [[ -n "$INSTALL_MODE" ]] && command -v systemctl &> /dev/null; then
    print_info "重启 nix-daemon 服务..."
    sudo systemctl restart nix-daemon 2> /dev/null || true
fi

# 6. 验证安装
print_info "验证安装..."

# 验证命令可用
if nix --version &> /dev/null; then
    print_info "Nix 版本: $(nix --version)"
else
    print_error "Nix 命令未找到，请重新加载 shell 或重启终端"
    exit 1
fi

# 验证实验特性
if [[ "$ENABLE_NIX_COMMAND" == "yes" ]] && nix profile --help &> /dev/null; then
    print_info "✓ nix-command 已启用"
fi

if [[ "$ENABLE_FLAKES" == "yes" ]] && nix flake --help &> /dev/null; then
    print_info "✓ flakes 已启用"
fi

print_info "=========================================="
print_info "✅ Nix 安装完成！"
print_info "=========================================="
print_info "常用命令："
print_info "  nix profile add nixpkgs#包名   # 安装包"
print_info "  nix profile list                   # 列出已安装包"
print_info "  nix profile remove <索引>          # 移除包"
print_info "  nix search nixpkgs 关键词          # 搜索包(不推荐本地执行,建议直接用在线网站搜索包获取包信息)"
print_info "  nix shell nixpkgs#包名             # 临时进入环境"
print_info "=========================================="

# 如果启用了flakes,国内加速镜像可能要额外配置才能加速部分内容
# 相关讨论:https://discourse.nixos.org/t/how-to-use-nix-profile-without-github-com/72289
if [[ "$ENABLE_FLAKES" == "yes" ]]; then
    # 绕过 GitHub 访问限制，直接从 CDN 拉取 nixpkgs
    # 执行下面的nix registry后，当你在 Nix 命令（如 nix run、nix build）中使用 nixpkgs#... 时，会直接从这个 URL 获取 nixpkgs，而不是 从 github:NixOS/nixpkgs 或系统配置的 channel 获取。
    echo "=================="
    echo "[Warning]:Run next line command to pass by github and download packages from mirror."
    echo ""
    echo "nix registry add nixpkgs https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.xz"
    echo "=================="
    # 尝试自动source当前shell的配置文件(常见shell)

    # 恢复默认registry:
    # nix registry remove nixpkgs
fi

# 测试安装(使用flakes的情况下可能会很慢,考虑挪到最后)
# print_info "测试安装一个包(hello)..."
# nix profile add nixpkgs#hello 2> /dev/null || {
#     print_warn "测试安装失败，可能需要重新加载环境"
# }

# if command -v hello &> /dev/null; then
#     print_info "测试成功: $(hello --version)"
# fi
