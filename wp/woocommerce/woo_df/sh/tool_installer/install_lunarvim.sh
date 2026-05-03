#!/usr/bin/env bash
# lunarvim 更新较慢,对于较新版本neovim适配可能不太好,且依赖较多,难以一键安装,考虑使用lazyvim或astrovim
set -e

# ─────────────────────────────────────────────
# 颜色输出
# ─────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ─────────────────────────────────────────────
# 检测操作系统
# ─────────────────────────────────────────────
OS="$(uname -s)"
case "$OS" in
  Linux*)   PLATFORM="linux" ;;
  Darwin*)  PLATFORM="macos" ;;
  *)        error "不支持的操作系统: $OS" ;;
esac
info "检测到平台: $PLATFORM"

# ─────────────────────────────────────────────
# 确认 brew 可用
# ─────────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  error "未找到 brew，请先安装 Homebrew: https://brew.sh"
fi
info "Homebrew 可用: $(brew --version | head -1)"

# ─────────────────────────────────────────────
# brew 安装辅助函数（已安装则跳过）
# ─────────────────────────────────────────────
brew_install() {
  local pkg="$1"
  local cmd="${2:-$1}"   # 第二个参数是检测用的命令名，默认与包名相同

  if command -v "$cmd" &>/dev/null; then
    info "已存在，跳过: $pkg ($(command -v "$cmd"))"
  else
    info "安装中: $pkg"
    brew install "$pkg"
  fi
}

# ─────────────────────────────────────────────
# 1. 安装基础依赖
# ─────────────────────────────────────────────
info "========== 安装基础依赖 =========="

brew_install "git"
brew_install "make"
brew_install "python3"     "python3"
brew_install "node"        "node"
brew_install "npm"         "npm"
brew_install "rust"        "rustc"     # rust 工具链（含 cargo）
brew_install "ripgrep"     "rg"
brew_install "lazygit"     "lazygit"

# cargo 由 rust 提供，单独检查一次
if ! command -v cargo &>/dev/null; then
  # rust 已通过 brew 安装，刷新 PATH
  if [[ -f "$HOME/.cargo/env" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.cargo/env"
  fi
  command -v cargo &>/dev/null || warn "cargo 仍未找到，请手动检查 Rust 安装"
fi

# pip（通常随 python3 一起安装）
if ! command -v pip3 &>/dev/null; then
  warn "pip3 未找到，尝试通过 python3 引导安装..."
  python3 -m ensurepip --upgrade || warn "ensurepip 失败，请手动安装 pip"
else
  info "已存在，跳过: pip3 ($(command -v pip3))"
fi

# ─────────────────────────────────────────────
# 2. 安装 Neovim（>= 0.9）
# ─────────────────────────────────────────────
info "========== 安装 / 检查 Neovim =========="

install_or_upgrade_neovim() {
  if command -v nvim &>/dev/null; then
    NVIM_VERSION="$(nvim --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
    NVIM_MAJOR="$(echo "$NVIM_VERSION" | cut -d. -f1)"
    NVIM_MINOR="$(echo "$NVIM_VERSION" | cut -d. -f2)"

    if [[ "$NVIM_MAJOR" -gt 0 ]] || [[ "$NVIM_MAJOR" -eq 0 && "$NVIM_MINOR" -ge 9 ]]; then
      info "Neovim $NVIM_VERSION 已满足要求（>= 0.9），跳过安装"
      return
    else
      warn "Neovim $NVIM_VERSION 版本过低，尝试升级..."
      brew upgrade neovim 2>/dev/null || brew install neovim
    fi
  else
    info "安装中: neovim"
    brew install neovim
  fi
}

install_or_upgrade_neovim

# ─────────────────────────────────────────────
# 3. 验证所有依赖
# ─────────────────────────────────────────────
info "========== 依赖验证 =========="

MISSING=()
for dep_cmd in git make python3 pip3 node npm cargo rg nvim lazygit; do
  if command -v "$dep_cmd" &>/dev/null; then
    info "  ✔  $dep_cmd → $(command -v "$dep_cmd")"
  else
    warn "  ✘  $dep_cmd 未找到"
    MISSING+=("$dep_cmd")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  error "以下依赖缺失，请手动安装后重新运行: ${MISSING[*]}"
fi
# 其他可选依赖
pip install pynvim
brew install fd ripgrep
# 安装lunarvim
github_mirror="https://gh-proxy.com/"
# 建议使用github镜像加速或国内代码仓库托管平台代替(脚本下载+仓库clone,注意第二阶段的clone加速设置)
LV_BRANCH='release-1.4/neovim-0.9' bash <(curl -s "$github_mirror"https://raw.githubusercontent.com/LunarVim/LunarVim/release-1.4/neovim-0.9/utils/installer/install.sh)

# 安装常用且效果极佳的 JetBrains Mono Nerd Font
# brew tap homebrew/cask-fonts # 新版brew不需要指定cask
brew install font-jetbrains-mono-nerd-font
# 安装完字体后，你必须在终端软件的设置中手动切换字体。

# echo -e "\uf17c  \uf007  \ue706  \ufb8a"
# 渲染结果:       ﮊ