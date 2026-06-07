#!/bin/bash
# 为*uix系统安装最新版的neovim
# 先尝试homebrew(包括linuxbrew)安装,如果失败则手动下载并安装
# todo:检查本地版本是否已经是最新版本,如果不是,则安装最新版本

# 手动的基本流程(以x86_64平台为例):
# Download nvim-linux-x86_64.tar.gz
# Extract: tar xzvf nvim-linux-x86_64.tar.gz
# Run ./nvim-linux-x86_64/bin/nvim

INSTALLER_VERSION="20260504"

# --- 默认配置 ---
MODE="auto"               # 可选: auto, brew, manual
NVIM_VERSION="stable"     # 最新稳定版
REQUIRED_VERSION="0.11.2" # 如果当前版本低于此要求,则安装新版本
# 用户级别的软件包存放位置
LOCAL_SHARE="$HOME/.local/share/nvim-dist"
# 用户级别的可执行文件(符号链接存放位置,方便使用短路径)
LOCAL_BIN="$HOME/.local/bin"
GLOBAL_OPT="/opt/nvim"
DOWNLOAD_URL=""
GITHUB_MIRROR="https://gh-proxy.com"
DIRECT=0
# --- 打印帮助信息 ---
usage() {

    cat << EOF
为*uix系统安装最新版的neovim的脚本.
    INSTALLER_VERSION:$INSTALLER_VERSION
用法: $0 [选项]
选项:
    -m, --mode [auto|brew|manual]  安装模式 (默认: auto)
                                    auto: 优先尝试 brew，失败则手动下载
                                    brew: 仅使用 Homebrew 安装
                                    manual: 仅通过 GitHub 二进制包安装
    --url [url]                     指定下载 URL (默认: https://github.com/neovim/neovim/releases/download/stable/nvim-linux64.tar.gz);
                                    如果手动指定链接,则会禁用--github-mirror(设置为空).
    --github-mirror [url]           如果从github下载,考虑叠加前缀,指定 GitHub 镜像 URL (默认: https://gh-proxy.com)
    -d,--direct                     在手动安装模式下,忽略github-mirror直连github下载
    --required-version [tag]        检查版本要求
    -v, --version [tag]            指定版本 (默认: stable)
    -h, --help                     显示此帮助
EOF
    exit 0

}

# --- 解析参数 ---
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -m | --mode)
            MODE="$2"
            shift
            ;;
        -v | --version)
            NVIM_VERSION="$2"
            shift
            ;;
        --url)
            DOWNLOAD_URL="$2"
            shift
            ;;
        -d | --direct)
            DIRECT=1
            ;;
        --github-mirror)
            GITHUB_MIRROR="$2"
            shift
            ;;
        --required-version)
            REQUIRED_VERSION="$2"
            shift
            ;;
        -h | --help) usage ;;
        *)
            echo "未知参数: $1"
            usage
            ;;
    esac
    shift
done
# 1. 检查 nvim 是否存在于系统 PATH 中
if ! command -v nvim &> /dev/null; then
    echo " Neovim 未安装！"
fi

# 2. 获取当前安装的 Neovim 版本号 (例如提取出 0.11.2 或 0.12.0)
CURRENT_VERSION=$(nvim --version | head -n 1 | awk '{print $2}' | sed 's/^v//')

# 3. 检查当前版本是否满足要求 (例如 >= 0.11.2)
echo "当前安装的 Neovim 版本为: v$CURRENT_VERSION"
# 比较版本号是否不低于指定版本
# 利用 awk 将版本号按 '.' 拆分并逐位对比
VERSION_CHECK=$(awk -v cur="$CURRENT_VERSION" -v req="$REQUIRED_VERSION" '
    BEGIN {
        split(cur, c, ".");
        split(req, r, ".");
        for (i=1; i<=3; i++) {
            if (c[i] + 0 > r[i] + 0) { print "PASS"; exit; }
            if (c[i] + 0 < r[i] + 0) { print "FAIL"; exit; }
        }
        print "PASS"; # 完全相等
    }
')

if [ "$VERSION_CHECK" = "PASS" ]; then
    echo "版本符合要求！(不低于 $REQUIRED_VERSION)"
else
    echo "版本过低！需要至少 $REQUIRED_VERSION"
fi
# 是否忽略github 镜像
if [[ $DIRECT -eq 1 ]]; then
    GITHUB_MIRROR=""
fi
# --- 1. 环境探测 ---
OS="$(uname -s)"
ARCH="$(uname -m)"
echo "--- 正在检测环境: $OS ($ARCH) ---"

# --- 2. Homebrew 安装函数 ---
install_with_brew() {
    if command -v brew > /dev/null 2>&1; then
        echo "检测到 Homebrew(brew)已安装..."
        # 判断当前用户是否是root,如果是需要定义brew命令的包装不能直接使用brew命令
        if [ "$(id -u)" = "0" ]; then
            echo "当前用户是root,请使用非root用户身份来运行brew命令,或者更换安装方式(使用普通方式安装)..."
            echo "如果完整clone了本仓库并部署了shell配置(包装了可在root在运行brew的函数),也可以在导入环境后运行 brew install neovim."
            # 根据用户输入判断继续使用brew安装
            cat <<- EOF
                继续使用brew安装?
                --------------------------------------------------
                请选择操作:
                1) 尝试导入环境后继续使用brew安装.
                2) 切换到mannual模式安装.
                3) 终止执行,重新设置脚本运行参数重试.
                --------------------------------------------------
EOF
            read -rp "选择操作序号: " USER_CHOICE
            echo "用户选中了[$USER_CHOICE]"
            case $USER_CHOICE in
                1)
                    echo "尝试导入环境后继续使用brew安装..."
                    # shellcheck disable=SC1090
                    brew_sh=~/sh/shell_utils/brew.sh
                    if [[ -e $brew_sh ]]; then
                        echo "导入[$brew_sh]..."
                        # shellcheck disable=SC1090
                        source "$brew_sh"
                        if command -v brewr &> /dev/null;then
                            echo "brewr函数已载入"
                            # shellcheck disable=SC2262
                            alias brew=brewr
                        else
                            echo "brewr不可用..."
                        fi
                    else
                        echo "依赖[$brew_sh]不存在"
                        exit 1
                    fi
                    ;;
                2)
                    echo "切换到manual模式安装."
                    install_manually
                    ;;
                *)
                    echo "操作已取消，脚本退出。"
                    exit 1
                    ;;
            esac
        else
            echo "当前用户可以直接运行brew命令..."
        fi
        brew install neovim
        # 为 Brew 安装的版本也创建 ~/.local/bin 的软链接
        # BREW_NVIM=$(brew --prefix neovim)/bin/nvim
        # mkdir -p "$LOCAL_BIN"
        # ln -sf "$BREW_NVIM" "$LOCAL_BIN/nvim"

        # echo "已安装 Neovim！"
        return 0
    else
        echo "未发现 Homebrew 。"
        return 1
    fi
}

# --- 3. GitHub 二进制安装函数 ---
install_manually() {
    echo "准备从 GitHub 下载二进制包..."

    # 确定平台字符串
    case "${OSTYPE}" in
        linux*)
            if [[ "${ARCH}" == "x86_64" ]]; then
                PLATFORM="linux-x86_64"
            elif [[ "${ARCH}" == "aarch64" ]]; then
                PLATFORM="linux-arm64"
            else
                echo "未知的 Linux 架构: $ARCH"
                exit 1
            fi
            ;;
        darwin*)
            if [[ "${ARCH}" == "arm64" ]]; then
                PLATFORM="macos-arm64"
            else PLATFORM="macos-x86_64"; fi
            ;;
        *)
            echo "不支持的系统: $OS"
            exit 1
            ;;
    esac
    if [[ $DOWNLOAD_URL ]]; then
        echo "正在使用指定的下载链接: $DOWNLOAD_URL"
    else

        DOWNLOAD_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/nvim-${PLATFORM}.tar.gz"
        # 确保在非空的镜像url有尾随的斜杠'/'
        if [[ $GITHUB_MIRROR ]]; then
            GITHUB_MIRROR="${GITHUB_MIRROR%/}/"
            echo "正在使用 GitHub 镜像: $GITHUB_MIRROR"
        fi
        DOWNLOAD_URL="${GITHUB_MIRROR}${DOWNLOAD_URL}"
    fi
    TEMP_DIR=$(mktemp -d)

    echo "正在下载: $DOWNLOAD_URL"
    if ! curl -L "$DOWNLOAD_URL" -o "${TEMP_DIR}/nvim.tar.gz"; then
        echo "下载失败，请检查网络或使用的镜像是否合适！"
        exit 1
    fi
    # 解压tar.gz包,需要用z选项(xz),而不是仅仅x选项
    tar -xzf "${TEMP_DIR}/nvim.tar.gz" -C "${TEMP_DIR}"
    # 列出解压后的结果:
    ls "$TEMP_DIR"
    # 使用通配符匹配
    SRC_DIRS=("${TEMP_DIR}/"nvim-*) # 通配符不要在""对中
    SRC_DIR="${SRC_DIRS[0]}"
    echo "得到解压路径(临时):$SRC_DIR"
    # SRC_DIR=$(find "${TEMP_DIR}" -maxdepth 1 -type d -name "nvim-*" | head -n 1)

    # 尝试全员安装
    INSTALL_SUCCESS=false
    echo "尝试全局安装到 $GLOBAL_OPT..."
    if [ "$EUID" -eq 0 ]; then
        echo "root 用户下免sudo"
        if mkdir -p "$GLOBAL_OPT" 2> /dev/null; then
            mv "${SRC_DIR}/"* "$GLOBAL_OPT/"
            nvim_path="$GLOBAL_OPT/bin/nvim" # /opt/nvim/bin/nvim (可执行文件的完整路径.)
            # 如果创建符号链接的命令失败（返回非0），执行 true（什么也不做，返回0），确保整个命令不会因错误而中断脚本
            ln -sf "$nvim_path" "/usr/local/bin/nvim" 2> /dev/null || true
            TARGET_BIN="$nvim_path"
            INSTALL_SUCCESS=true
        fi
    # fi
    # 尝试使用 sudo
    elif command -v sudo > /dev/null 2>&1; then
        echo "尝试全局安装(sudo)"
        if sudo mkdir -p "$GLOBAL_OPT" 2> /dev/null; then
            sudo mv "${SRC_DIR}/"* "$GLOBAL_OPT/"
            nvim_path="$GLOBAL_OPT/bin/nvim" # /opt/nvim/bin/nvim (可执行文件的完整路径.)
            # 如果创建符号链接的命令失败（返回非0），执行 true（什么也不做，返回0），确保整个命令不会因错误而中断脚本
            sudo ln -sf "$nvim_path" "/usr/local/bin/nvim" 2> /dev/null || true
            TARGET_BIN="$nvim_path"
            INSTALL_SUCCESS=true
        fi
    fi

    # 回退到当前用户级别的安装
    if [ "$INSTALL_SUCCESS" = false ]; then
        echo "全局安装失败,回退安装到用户目录: $LOCAL_SHARE"
        mkdir -p "$LOCAL_SHARE"
        mv "${SRC_DIR}/"* "$LOCAL_SHARE/"
        TARGET_BIN="$LOCAL_SHARE/bin/nvim"
    fi

    # 创建用户级符号链接
    mkdir -p "$LOCAL_BIN"
    ln -sfv "$TARGET_BIN" "$LOCAL_BIN/nvim"

    rm -rf "$TEMP_DIR"
    echo "手动安装完成！"
}

# --- 4. 执行逻辑 ---
case "$MODE" in
    brew)
        if ! install_with_brew; then
            echo "错误: 指定了 brew 模式但未找到 brew。"
            exit 1
        fi
        ;;
    manual)
        install_manually
        ;;
    auto)
        if ! install_with_brew; then
            install_manually
        fi
        ;;
    *)
        usage
        ;;
esac

# --- 5. 最终检查 ---
if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
    echo "[warning]: $LOCAL_BIN 未在您的 PATH 中。"
    echo -e "建议：将 $LOCAL_BIN 加入到您的 PATH 环境中。"
    echo "在您的 ~/.bashrc 或 ~/.zshrc 中添加(如果有其他shell配置类似地添加)："
    echo "export PATH=\"$LOCAL_BIN:\$PATH\"" | tee -a ~/.bashrc ~/.zshrc
fi

echo "建议刷新一下当前shell配置让新版本生效."
if command -v nvim &> /dev/null; then
    echo "当前版本$(nvim --version)"
fi

# echo -e "\n\033[32m安装成功！输入 'nvim' 开始编辑。\033[0m"
