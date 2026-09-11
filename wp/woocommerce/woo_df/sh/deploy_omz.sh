#!/bin/bash
# 配置zsh(oh my zsh)相关插件,让体验向fish靠拢;
#    默认情况下,如果系统尚未安装过zsh(omz),则第一次运行会尝试安装oh-my-zsh(omz),设置zsh为默认shell后会进入zsh,脚本中断;
#        第二次运行,会安装增强插件;
#    如果已经安装过oh-my-zsh,则此脚本会尝试安装额外的插件(用户也可以自行制定),自动检测并更新oh-my-zsh配置文件(~/.zshrc)
#       国外服务器有限考虑从github下载插件,国内gitee可能会限流要求登录账号.
# 此部署代码尽量实现幂等性(避免反复运行导致配置文件内容混乱.);
# 此脚本配置的不全仅适用于zsh,对于bash没有作用,不过此脚本可以用bash执行部署;
# 软件要求:zsh需要用户实现安装好;对于一些精简的系统,可能要事先安装curl和git来拉去一些插件代码;
# 补全类插件要求比较严格,尤其是动态自动补全实现比较复杂需要更多的步骤
# 测试补全插件效果时,对于基础工具,注意区分gnu版本和bsd版本,可用选项和风格有所不同
# 卸载此套件:本脚本主要下载了oh-my-zsh配置框架(如果是默认选项会尝试为你安装),
# 并且下载了一组zsh插件,并且对于补型插件修改了配置文件(~/.zshrc);
# 若要删除插件,请进入 $ZSH_CUSTOM/plugins目录中,删除不需要的插件(目录),然后修改(~/.zshrc)配置中多余的代码片段
# 此脚本通过sed修改的配置片段都使用了起始和结束标记组合('>>>'和'<<<',模仿conda风格),用户可以清晰的识别出修改的代码片段
# 最后记得检查oh-my-zsh中的插件列表(plugins数组)中的插件是否移除多余内容.

# 一键部署(可能需要运行2次.第一次安装oh-my-zsh,第二次安装相关zsh插件并修改配置文件):
# bash <(curl -sSfL https://github.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/deploy_omz.sh) -s github
# 这里的链接gitee也可以换成gitee(适合国内用户,但是可能要登录gitee账号)
# 使用-h获取命令行帮助

version=20260911.1
# 插件仓库源
REPO_SOURCE="github" # gitee
repo_source_explicit=false

# 默认插件安装选项(仅补全类插件)
install_zsh_completions=true               # zcp插件,可选值:true|false
install_zsh_autocomplete=omz               # zac插件安装模式:可选值:omz|std|false
install_zsh_autocomplete_ref=latest        # latest|classic|bundled|<git-ref>
zac_ref_explicit=false
install_zsh_autosuggestions=true           # zasp
install_zsh_you_should_use=false           # zysu 可能有bug,某些情况下可能会让zsh出现异常(输出:alias -g|sort ...)
install_zsh_syntax_highlighting=true       # zshp
install_zsh_history_substring_search=false # zhssp
install_omz="default"                      # default|github|gitee
omz_only=false
update_zsh_plugins_only=false
assume_yes=false

# 定义使用帮助(help)
usage='
Oh-my-zsh(omz) and zsh plugins deployment script.

version:'"$version"'
usage:
    deploy_omz.sh [options]
options:
    -o|-omz|--install-omz) [false|default|gitee|github]
        install oh-my-zsh(omz) if omz is not available.
        This option try to install oh-my-zsh on default and standard path of current user.
        If you have already install oh-my-zsh (especially install in your custom dir ),you can use [false] to skip oh-my-zsh installation.
        This decision will be linked to the value of the [ZSH_CUSTOM] environment variable.
        To reinstall or force install again,run:
            rm ~/.oh-my-zsh -rf
        and then install omz again.(use -O install omz noly.)
    -O|--omz-only 
        install oh-my-zsh only without other plugins if true.
    -U|--update-zsh-plugins
        update installed zsh plugin repositories with fast-forward-only pulls.
        Also install zasync and refresh keybindings so Up/Down stay default
        history; autoload Completions helpers missed by omz early compinit.
    -y|--yes
        skip the update confirmation prompt. Required for non-interactive updates.
    -zc | --install-zsh-completions [true|false]
        install zsh-completions plugin if true
    -zac | --install-zsh-autocomplete [omz|std|false]
        install zsh-autocomplete plugin if true,if use std (standard) mode,this plugin will be installed without oh my zsh plugins list
    -zac-ref|--zsh-autocomplete-ref [latest|classic|bundled|<git-ref>]
        pin zsh-autocomplete. latest follows main; classic is 20f6c34
        (old fd async, before zasync); bundled is tag 26.08.04 / 52ce817
        (zasync still in-tree). Also accepts a commit/tag. -U without this
        flag keeps a previous pin. .zshrc snippets follow the checkout.
    -zasp|--install-zsh-autosuggesions [true|false]
        install zsh-autosuggestions plugin if true
    -zysu|--install-zsh-you-should-use [true|false]
        install zsh-you-should-use plugin if true
    -zshp|--install-zsh-syntax-highlighting [true|false]
        install zsh-syntax-highlighting plugin if true
    -zhssp|--install-zsh-history-substring-search [true|false]
        install zsh-history-substring-search plugin if true
    --zsh-custom
        set oh-my-zsh custom directory [ZSH_CUSTOM].
    -s|--repo-source [github|gitee|origin]
        select the preferred repository source for plugin installation or updates.
        origin (aliases: keep, current, existing) keeps each plugin
        current git remote during -U and does not rewrite origin.
        Install mode still requires github or gitee.
    -h,--help 
        show this help message.
'"
examples:
    # install oh-my-zsh only:
    bash $0 --omz-only

    # update installed zsh plugins only:
    bash $0 --update-zsh-plugins

    # non-interactive update using the GitHub repository URLs:
    bash $0 --update-zsh-plugins --repo-source github --yes

    # non-interactive update, keep each plugin's existing origin:
    bash $0 -U -s origin -y

    # non-interactive update from Gitee mirrors:
    bash $0 -U -s gitee -y

    # install without 'you-should-use' plugin or  disable the plugin in plugins list
    bash deploy_omz.sh -o false -zysu false

    # enable all predefined plugins
    bash deploy_omz.sh

    # pin zsh-autocomplete to the pre-zasync classic commit
    bash deploy_omz.sh -zac-ref classic -s github

    # pin to in-tree zasync (tag 26.08.04)
    bash deploy_omz.sh -zac-ref bundled -s github

    # go back to rolling main, including zasync fpath snippets
    bash deploy_omz.sh -U -zac-ref latest -s origin -y
"
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -zc | --install-zsh-completions)
                install_zsh_completions="$2"
                if ! [[ "${install_zsh_completions,,}" =~ ^(false|true)$ ]]; then
                    echo "Invalide zsh-completions install mode '$install_zsh_completions' !" >&2
                    echo "$usage"
                    exit 1
                fi
                shift
                ;;
            -zac | --install-zsh-autocomplete)
                install_zsh_autocomplete="$2"
                if ! [[ "${install_zsh_autocomplete,,}" =~ ^(omz|std|false)$ ]]; then
                    echo "Invalide zsh-autocomplete install mode '$install_zsh_autocomplete'!" >&2
                    echo "$usage"
                    exit 1
                fi
                shift
                ;;
            -zac-ref | --zsh-autocomplete-ref)
                install_zsh_autocomplete_ref="$2"
                if [[ -z $install_zsh_autocomplete_ref ]]; then
                    echo "[error]:-zac-ref 需要 latest|classic|bundled 或 git ref。" >&2
                    exit 1
                fi
                zac_ref_explicit=true
                shift
                ;;
            -zasp | --install-zsh-autosuggestions)
                install_zsh_autosuggestions="$2"
                shift
                ;;
            -zysu | --install-zsh-you-should-use)
                install_zsh_you_should_use="$2"
                shift
                ;;
            -zshp | --install-zsh-syntax-highlighting)
                install_zsh_syntax_highlighting="$2"
                shift
                ;;
            -zhssp | --install-zsh-history-substring-search)
                install_zsh_history_substring_search="$2"
                shift
                ;;
            -o | -omz | --install-omz)
                install_omz="$2"
                shift
                ;;
            -s | --repo-source)
                REPO_SOURCE="$2"
                case $REPO_SOURCE in
                    github | gitee) ;;
                    origin | keep | current | existing) REPO_SOURCE=origin ;;
                    *)
                        echo "[error]:未知仓库源 '$REPO_SOURCE'，可选值为 github、gitee 或 origin。" >&2
                        exit 1
                        ;;
                esac
                repo_source_explicit=true
                shift
                ;;
            -O | --omz-only)
                omz_only="true"

                ;;
            -U | --update-zsh-plugins)
                update_zsh_plugins_only="true"
                ;;
            -y | --yes)
                assume_yes=true
                ;;
            --zsh-custom)
                ZSH_CUSTOM="$2"
                shift
                ;;
            -h | --help)
                echo "$usage"
                exit 0
                ;;
            -*)
                echo "unknown option:[$1] "
                echo "$usage"
                exit 1
                ;;
        esac
        shift
    done
}
parse_args "$@"

confirm_zsh_plugin_update() {
    local choice answer

    if [[ $assume_yes == true ]]; then
        if [[ $repo_source_explicit == false ]]; then
            echo "[error]:使用 --yes 时必须显式传入 --repo-source github|gitee|origin。" >&2
            return 1
        fi
        return 0
    fi
    if [[ ! -t 0 ]]; then
        echo "[error]:非交互更新需要同时传入 --repo-source 和 --yes。" >&2
        return 1
    fi

    if [[ $repo_source_explicit == false ]]; then
        echo "请选择 Zsh 插件更新来源："
        echo "  1) 沿用各插件当前 origin（不修改 remote）"
        echo "  2) GitHub"
        echo "  3) Gitee"
        echo "  q) 取消"
        read -r -p "请选择 [1]: " choice
        case ${choice:-1} in
            1 | origin | keep | current | existing) REPO_SOURCE=origin ;;
            2 | github) REPO_SOURCE=github ;;
            3 | gitee) REPO_SOURCE=gitee ;;
            q | Q) echo "已取消更新。"; return 2 ;;
            *) echo "[error]:无效选择 '$choice'。" >&2; return 1 ;;
        esac
    fi

    if [[ $REPO_SOURCE == origin ]]; then
        echo "将沿用各插件现有 origin 更新，不修改 remote。"
    else
        echo "将使用 $REPO_SOURCE 来源更新已安装的 Zsh 插件；必要时会修改插件 origin。"
    fi
    read -r -p "确认继续？[y/N]: " answer
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]] || {
        echo "已取消更新。"
        return 2
    }
}

if [[ $update_zsh_plugins_only == true ]]; then
    confirm_zsh_plugin_update || {
        confirm_status=$?
        [[ $confirm_status -eq 2 ]] && exit 0
        exit "$confirm_status"
    }
fi

# 根据命令行选择脚本维护的首选插件仓库。安装和仅更新模式共用同一组地址。
set_zsh_plugin_repo_urls() {
    if [[ $REPO_SOURCE == origin ]]; then
        if [[ $update_zsh_plugins_only != true ]]; then
            echo "[error]:仓库源 origin 仅适用于 -U/--update-zsh-plugins。" >&2
            exit 1
        fi
        zcp_repo=
        zac_repo=
        zasp_repo=
        zysu_repo=
        zshp_repo=
        zhssp_repo=
        return 0
    fi
    if [[ $REPO_SOURCE == gitee ]]; then
        zcp_repo=https://gitee.com/duchenpaul/zsh-completions.git
        zac_repo=https://gitee.com/mirrors/zsh-autocomplete.git
        zasp_repo=https://gitee.com/mirrors/zsh-autosuggestions.git
        zysu_repo=https://gitee.com/mirrors/zsh-you-should-use.git
        zshp_repo=https://gitee.com/mirrors/zsh-syntax-highlighting.git
        zhssp_repo=https://gitee.com/mirror-hub/zsh-history-substring-search
    elif [[ $REPO_SOURCE == github ]]; then
        zcp_repo=https://github.com/zsh-users/zsh-completions.git
        zac_repo=https://github.com/marlonrichert/zsh-autocomplete.git
        zasp_repo=https://github.com/zsh-users/zsh-autosuggestions.git
        zysu_repo=https://github.com/MichaelAquilina/zsh-you-should-use.git
        zshp_repo=https://github.com/zsh-users/zsh-syntax-highlighting.git
        zhssp_repo=https://github.com/zsh-users/zsh-history-substring-search.git
    else
        echo "[error]:未知仓库源 '$REPO_SOURCE'，可选值为 github、gitee 或 origin。" >&2
        exit 1
    fi
}
set_zsh_plugin_repo_urls

if [[ $update_zsh_plugins_only == true ]]; then
    if [[ $REPO_SOURCE == origin ]]; then
        echo "Update mode keeps each plugin's existing origin"
    else
        echo "Update mode prefers repository URLs configured for source: $REPO_SOURCE"
    fi
else
    echo "Using repo source: $REPO_SOURCE"
fi

# 检查依赖。仅更新插件时不需要后续配置工具，但仍需要 git/curl。
if [[ $update_zsh_plugins_only == true ]]; then
    requirements=(git curl)
else
    requirements=(git curl zsh)
fi
meet_req=true
for req in "${requirements[@]}"; do
    if ! command -v "$req" >&/dev/null; then
        echo "[error]:'$req' is not available! Install $req and retry again."
        meet_req=false
    fi
done

if [[ $meet_req == false ]]; then exit 2; fi

# zsh-autocomplete 自 7633bc7 起不再内置 zasync，启动时会执行:
#   git clone https://github.com/marlonrichert/zasync.git "$HOME/.cache/zsh/zasync"
# 国内访问 GitHub 经常卡在 "Cloning into ..."。-U 也必须装好这份依赖，
# 并写入 fpath，否则只更新插件后动态补全会失效。
deploy_omz_script_dir() {
    local source=${BASH_SOURCE[0]:-$0}
    (cd "$(dirname "$source")" && pwd -P)
}

zasync_cache_dir() {
    echo "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zasync"
}

zasync_plugin_dir() {
    echo "${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zasync"
}

zasync_vendor_dir() {
    echo "$(deploy_omz_script_dir)/vendor/zasync"
}

zasync_tree_complete() {
    local dest=$1
    [[ -f $dest/zasync && -f $dest/Functions/.zasync.start && -f $dest/Functions/.zasync.fd-callback ]]
}

copy_zasync_tree() {
    local src=$1 dest=$2
    mkdir -p "$dest/Functions"
    cp "$src/zasync" "$dest/zasync"
    cp "$src/Functions"/.zasync.* "$dest/Functions/"
    [[ -f $src/LICENSE ]] && cp "$src/LICENSE" "$dest/LICENSE"
    zasync_tree_complete "$dest"
}

download_zasync_tarball() {
    local tarball=$1
    local url
    local -a tarball_urls=(
        "https://ghproxy.net/https://github.com/marlonrichert/zasync/archive/refs/heads/main.tar.gz"
        "https://github.com/marlonrichert/zasync/archive/refs/heads/main.tar.gz"
    )
    for url in "${tarball_urls[@]}"; do
        echo "下载 zasync: $url"
        if curl -fsSL --max-time 30 -o "$tarball" "$url"; then
            return 0
        fi
        echo "[warn]:zasync 下载失败: $url" >&2
    done
    return 1
}

install_zasync_from_network() {
    local dest=$1
    local tmp tarball
    tmp=$(mktemp -d)
    tarball="$tmp/zasync.tar.gz"
    mkdir -p "$dest"
    if ! download_zasync_tarball "$tarball"; then
        return 1
    fi
    if ! tar -tzf "$tarball" &> /dev/null; then
        echo "[warn]:zasync 下载内容不是 tar.gz" >&2
        return 1
    fi
    if ! tar -xzf "$tarball" --strip-components=1 -C "$dest"; then
        echo "[warn]:解压 zasync 失败。" >&2
        return 1
    fi
    zasync_tree_complete "$dest"
}

download_zasync_via_jsdelivr() {
    local dest=$1
    local base="https://cdn.jsdelivr.net/gh/marlonrichert/zasync@main"
    local file
    mkdir -p "$dest/Functions"
    if ! curl -fsSL --max-time 20 -o "$dest/zasync" "$base/zasync"; then
        return 1
    fi
    for file in .zasync.cancel .zasync.fd-callback .zasync.help .zasync.reply .zasync.start; do
        if ! curl -fsSL --max-time 20 -o "$dest/Functions/$file" "$base/Functions/$file"; then
            return 1
        fi
    done
    zasync_tree_complete "$dest"
}

mark_zasync_cache_fetched() {
    local dest=$1
    local origin
    mkdir -p "$dest"
    if ! git -C "$dest" rev-parse --is-inside-work-tree &> /dev/null; then
        git -C "$dest" init -q
    fi
    origin=$(git -C "$dest" remote get-url origin 2> /dev/null || true)
    if [[ $origin == *github.com* ]]; then
        git -C "$dest" remote remove origin
    fi
    : > "$dest/.git/FETCH_HEAD"
}

ensure_zasync_zshrc() {
    local zshrc=${1:-${zshrc_path:-$HOME/.zshrc}}
    local tmp
    [[ -f $zshrc ]] || return 0
    tmp=$(mktemp)
    awk '
        BEGIN {
            snippet = "# >>> zasync\n# 让 zsh-autocomplete 直接 autoload zasync，避免启动时 git clone GitHub。\nfpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zasync\n# <<< zasync"
        }
        $0 == "# >>> zasync" { skip = 1; next }
        skip && $0 == "# <<< zasync" { skip = 0; next }
        skip { next }
        /^plugins=\(/ && !inserted {
            print snippet
            print ""
            inserted = 1
        }
        { print }
        END {
            if (!inserted) {
                print ""
                print snippet
            }
        }
    ' "$zshrc" > "$tmp"
    cat "$tmp" > "$zshrc"
}

verify_zasync_autoload() {
    local plugin_dir=$1
    local quoted
    command -v zsh &> /dev/null || return 0
    printf -v quoted '%q' "$plugin_dir"
    zsh -df -c "fpath+=($quoted); builtin autoload -Uz +X zasync" &> /dev/null
}

install_or_update_zasync() {
    local cache_dir plugin_dir vendor_dir
    cache_dir=$(zasync_cache_dir)
    plugin_dir=$(zasync_plugin_dir)
    vendor_dir=$(zasync_vendor_dir)
    echo "安装/更新 zsh-autocomplete 依赖 zasync ..."
    mkdir -p "$cache_dir" "$plugin_dir"

    if [[ -f $vendor_dir/zasync ]] && copy_zasync_tree "$vendor_dir" "$cache_dir"; then
        echo "[ok]:zasync 使用脚本内置副本 $vendor_dir"
    elif install_zasync_from_network "$cache_dir"; then
        echo "[ok]:zasync 使用网络 tarball"
    elif download_zasync_via_jsdelivr "$cache_dir"; then
        echo "[ok]:zasync 使用 jsDelivr"
    else
        echo "[error]:无法获取 zasync。zsh-autocomplete 动态补全会失效，启动时还可能卡在 git clone。" >&2
        return 1
    fi

    copy_zasync_tree "$cache_dir" "$plugin_dir" || return 1
    mark_zasync_cache_fetched "$cache_dir"
    ensure_zasync_zshrc "${zshrc_path:-$HOME/.zshrc}"
    if verify_zasync_autoload "$plugin_dir"; then
        echo "[ok]:zasync autoload 检查通过 -> $plugin_dir"
    else
        echo "[warn]:zasync 文件已安装，但当前环境 autoload 检查未通过。" >&2
    fi
}

write_zac_bindkey_config() {
    cat > "$HOME/zsh_bindkey_config.sh" << 'EOF'
# shellcheck disable=SC2148
# zsh-autocomplete 官方建议：在插件加载之后 bindkey。
# omz 会在 source 插件之前 compinit，Completions/ 下的 _autocomplete__*
# 不会进入 dump。必须在这里 autoload，上箭头的历史列表才能工作。
() {
  emulate -L zsh
  local dir=${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-autocomplete/Completions
  [[ -d $dir ]] || return
  fpath=($dir $fpath)
  autoload -Uz $dir/_autocomplete__*(N)
}

# Tab / Shift-Tab 进入菜单并在菜单中移动
bindkey              '^I' menu-select
[[ -n "${terminfo[kcbt]}" ]] && bindkey "${terminfo[kcbt]}" menu-select
bindkey -M menuselect              '^I' menu-complete
[[ -n "${terminfo[kcbt]}" ]] && bindkey -M menuselect "${terminfo[kcbt]}" reverse-menu-complete

# 菜单中 Enter 始终提交命令行
bindkey -M menuselect '^M' .accept-line

# 菜单中左右键始终移动命令行光标
bindkey -M menuselect \
    '^[[C' .forward-char  '^[OC' .forward-char \
    '^[[D' .backward-char '^[OD' .backward-char

# 命令行左右键移动光标
bindkey -M emacs \
    '^[[C' forward-char  '^[OC' forward-char \
    '^[[D' backward-char '^[OD' backward-char

# 不要把 ↑/↓ 改成 .up-line-or-history。
# 插件默认：↑ = up-line-or-search（弹出历史命令列表），
# ↓ = down-line-or-select（进入补全菜单）。autoload 后即可恢复更新前效果。

# 不让历史补全追加分号
zstyle ':autocomplete:*' add-semicolon no

# 当前词含 glob（* ? [）时不要实时列出匹配文件。
# 否则 ls *md 会先画出 globbed files/expansion，再按 ↑ 会 Loading 后卡死或响铃
# （zsh-autocomplete #843，zsh 5.8 上更明显）。Shift-Tab 仍是 expand-word。
zstyle ':autocomplete:*' ignored-input '*[\*\?\[]*'

# 含 glob 的当前词不要走 history-search / menu-select，改用普通历史翻页。
.zac:up-line-or-search() {
  if [[ ${BUFFER##* } == *[\*\?\[]* ]]; then
    builtin zle .up-line-or-history
    return $?
  fi
  builtin zle up-line-or-search
}
.zac:down-line-or-select() {
  if [[ ${BUFFER##* } == *[\*\?\[]* ]]; then
    builtin zle .down-line-or-history
    return $?
  fi
  builtin zle down-line-or-select
}
zle -N .zac:up-line-or-search
zle -N .zac:down-line-or-select
bindkey '^[[A' .zac:up-line-or-search
bindkey '^[OA' .zac:up-line-or-search
bindkey '^P'   .zac:up-line-or-search
bindkey '^[[B' .zac:down-line-or-select
bindkey '^[OB' .zac:down-line-or-select
bindkey '^N'   .zac:down-line-or-select

EOF
}

# zsh-autocomplete 在加载时 bindkey menu-search / recent-paths，
# 真正 zle -N/-C 要到 precmd。zsh < 5.9 的 syntax-highlighting 会在
# 加载时 wrap 全部 widget，看到残缺 widget 就报 unhandled ZLE widget。
# 在 source oh-my-zsh.sh 之前占位，警告消失；precmd 仍会覆盖成正式 widget。
ensure_zac_zsyh_widgets_zshrc() {
    local zshrc=${1:-${zshrc_path:-$HOME/.zshrc}}
    local mode=${2:-upsert}
    local tmp
    [[ -f $zshrc ]] || return 0
    tmp=$(mktemp)
    if [[ $mode == remove ]]; then
        awk '
            $0 == "# >>> zac zsyh widgets" { skip = 1; next }
            skip && $0 == "# <<< zac zsyh widgets" { skip = 0; next }
            skip { next }
            { print }
        ' "$zshrc" > "$tmp"
        cat "$tmp" > "$zshrc"
        rm -f "$tmp"
        return 0
    fi
    awk '
        BEGIN {
            snippet = "# >>> zac zsyh widgets\n# zsh-autocomplete 在 bindkey 时引用 menu-search / recent-paths，\n# 真正 zle -N/-C 要到 precmd。zsh < 5.9 的 syntax-highlighting 会在加载时 wrap 全部 widget，\n# 从而报 unhandled ZLE widget。zsh >= 5.9 走 add-zle-hook-widget，不受影响。\nif autoload -Uz is-at-least 2>/dev/null && ! is-at-least 5.9; then\n  zle -N menu-search\n  zle -N recent-paths\nfi\n# <<< zac zsyh widgets"
        }
        $0 == "# >>> zac zsyh widgets" { skip = 1; next }
        skip && $0 == "# <<< zac zsyh widgets" { skip = 0; next }
        skip { next }
        $0 ~ /^source[[:space:]]+\$ZSH\/oh-my-zsh\.sh/ && !inserted {
            print snippet
            print ""
            inserted = 1
        }
        { print }
        END {
            if (!inserted) {
                print ""
                print snippet
            }
        }
    ' "$zshrc" > "$tmp"
    cat "$tmp" > "$zshrc"
    rm -f "$tmp"
}


# zsh-autocomplete 钉扎。classic = 移出/引入 zasync 之前的旧 fd 实现；
# bundled = zasync 仍在仓库内（tag 26.08.04）；latest = 跟随 main，需要外置 zasync。
# classic 必须写满 40 位。GitHub 浅克隆不能 fetch 短 SHA。
zac_ref_classic=20f6c34f20270084b21211428afb6d2534aae8e9
zac_ref_bundled=26.08.04

zac_normalize_ref_name() {
    local raw=${1:-$install_zsh_autocomplete_ref}
    raw=${raw,,}
    case $raw in
        '' | latest | main | master | origin) echo latest ;;
        classic | stable | pre-zasync | fd | 20f6c34*) echo classic ;;
        bundled | in-tree | subtree | 52ce817* | 26.08.04) echo bundled ;;
        *) echo "$raw" ;;
    esac
}

zac_resolve_ref() {
    local name
    name=$(zac_normalize_ref_name "$1")
    case $name in
        latest) echo '' ;;
        classic) echo "$zac_ref_classic" ;;
        bundled) echo "$zac_ref_bundled" ;;
        *) echo "$1" ;;
    esac
}

zac_pin_file() {
    echo "${1:-${zac:-${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-autocomplete}}/.deploy_omz_ref"
}

zac_write_pin() {
    local dir=$1 name=$2 resolved=$3
    printf 'ref=%s\nresolved=%s\n' "$name" "$resolved" > "$(zac_pin_file "$dir")"
}

zac_read_pin_name() {
    local file
    file=$(zac_pin_file "$1")
    [[ -f $file ]] || return 1
    awk -F= '$1=="ref" {print $2; exit}' "$file"
}

remove_zasync_zshrc() {
    local zshrc=${1:-${zshrc_path:-$HOME/.zshrc}}
    local tmp
    [[ -f $zshrc ]] || return 0
    tmp=$(mktemp)
    awk '
        $0 == "# >>> zasync" { skip = 1; next }
        skip && $0 == "# <<< zasync" { skip = 0; next }
        skip { next }
        { print }
    ' "$zshrc" > "$tmp"
    cat "$tmp" > "$zshrc"
    rm -f "$tmp"
}

ensure_zac_pin_zshrc() {
    local zshrc=${1:-${zshrc_path:-$HOME/.zshrc}}
    local mode=${2:-upsert}
    local name=$3 resolved=$4
    local tmp
    [[ -f $zshrc ]] || return 0
    tmp=$(mktemp)
    if [[ $mode == remove || $name == latest || -z $name ]]; then
        awk '
            $0 == "# >>> zac pin" { skip = 1; next }
            skip && $0 == "# <<< zac pin" { skip = 0; next }
            skip { next }
            { print }
        ' "$zshrc" > "$tmp"
        cat "$tmp" > "$zshrc"
        rm -f "$tmp"
        return 0
    fi
    awk -v name="$name" -v resolved="$resolved" '
        BEGIN {
            snippet = "# >>> zac pin\n# zsh-autocomplete 钉扎: " name " (" resolved ")\n# 改回滚动 main: bash deploy_omz.sh -U -zac-ref latest -s origin -y\n# <<< zac pin"
        }
        $0 == "# >>> zac pin" { skip = 1; next }
        skip && $0 == "# <<< zac pin" { skip = 0; next }
        skip { next }
        /^plugins=\(/ && !inserted {
            print snippet
            print ""
            inserted = 1
        }
        { print }
        END {
            if (!inserted) {
                print ""
                print snippet
            }
        }
    ' "$zshrc" > "$tmp"
    cat "$tmp" > "$zshrc"
    rm -f "$tmp"
}

zac_detect_profile() {
    local dir=${1:-${zac:-${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-autocomplete}}
    local f
    for f in "$dir/Functions/Init/.autocomplete__async" "$dir/zsh-autocomplete.plugin.zsh"; do
        if [[ -f $f ]] && grep -q 'marlonrichert/zasync.git' "$f"; then
            echo external
            return 0
        fi
    done
    if [[ -f $dir/.gitmodules ]] && grep -qi zasync "$dir/.gitmodules"; then
        echo bundled
        return 0
    fi
    if [[ -f $dir/zasync || -d $dir/zasync || -d $dir/z-async ]]; then
        echo bundled
        return 0
    fi
    echo legacy
}

zac_fetch_ref() {
    local dir=$1 url=$2 ref=$3
    if git -C "$dir" fetch --depth 1 origin "$ref"; then
        return 0
    fi
    echo "[warn]:origin 按 $ref 浅取失败，尝试完整 fetch。" >&2
    if git -C "$dir" fetch origin "$ref"; then
        return 0
    fi
    if [[ $url != *github.com/marlonrichert/zsh-autocomplete* ]]; then
        echo "[warn]:回退到 GitHub 拉取 zsh-autocomplete $ref" >&2
        if git -C "$dir" fetch --depth 1 https://github.com/marlonrichert/zsh-autocomplete.git "$ref"; then
            return 0
        fi
        git -C "$dir" fetch https://github.com/marlonrichert/zsh-autocomplete.git "$ref"
    fi
}

zac_checkout_latest() {
    local dir=$1 url=$2
    local branch current_url
    if [[ -n $url ]]; then
        current_url=$(git -C "$dir" remote get-url origin 2> /dev/null || true)
        if [[ -z $current_url ]]; then
            git -C "$dir" remote add origin "$url"
        elif [[ $REPO_SOURCE != origin && $current_url != "$url" ]]; then
            git -C "$dir" remote set-url origin "$url"
        fi
    fi
    branch=$(git -C "$dir" ls-remote --symref origin HEAD 2> /dev/null | awk '/^ref:/ {print $2; exit}')
    branch=${branch#refs/heads/}
    branch=${branch:-main}
    echo "zsh-autocomplete 跟随 $branch ..."
    git -C "$dir" fetch --depth 1 origin "$branch" || git -C "$dir" fetch origin "$branch" || return 1
    git -C "$dir" checkout -B "$branch" FETCH_HEAD || return 1
    rm -f "$(zac_pin_file "$dir")"
}

install_or_checkout_zsh_autocomplete() {
    local dir=$1 url=$2
    local name resolved
    name=$(zac_normalize_ref_name)
    resolved=$(zac_resolve_ref)

    if [[ $zac_ref_explicit == false && -d $dir ]]; then
        local pinned
        pinned=$(zac_read_pin_name "$dir" || true)
        if [[ -n $pinned && $name == latest ]]; then
            name=$pinned
            install_zsh_autocomplete_ref=$pinned
            resolved=$(zac_resolve_ref "$pinned")
            echo "沿用已钉扎的 zsh-autocomplete: $name ($resolved)"
        fi
    fi

    if [[ ! -d $dir ]]; then
        if [[ -z $url ]]; then
            echo "[error]:没有 zsh-autocomplete 仓库地址，无法 clone。" >&2
            return 1
        fi
        echo "clone zsh-autocomplete -> $dir"
        git clone --depth 1 "$url" "$dir" || git clone "$url" "$dir" || return 1
    elif ! git -C "$dir" rev-parse --is-inside-work-tree &> /dev/null; then
        echo "[warn]:$dir 不是 Git 仓库，跳过 checkout。" >&2
        return 1
    elif [[ -n $(git -C "$dir" status --porcelain) ]]; then
        echo "[warn]:zsh-autocomplete 有未提交改动，跳过 checkout。" >&2
        return 1
    fi

    if [[ $name == latest ]]; then
        zac_checkout_latest "$dir" "$url" || return 1
        echo "[ok]:zsh-autocomplete $(git -C "$dir" rev-parse --short HEAD) (latest)"
        return 0
    fi

    echo "钉扎 zsh-autocomplete -> $name ($resolved)"
    if ! git -C "$dir" cat-file -e "${resolved}^{commit}" 2> /dev/null; then
        zac_fetch_ref "$dir" "$url" "$resolved" || {
            echo "[error]:无法获取 zsh-autocomplete $resolved" >&2
            return 1
        }
    fi
    if git -C "$dir" checkout --detach "$resolved" 2> /dev/null \
        || git -C "$dir" checkout --detach FETCH_HEAD; then
        resolved=$(git -C "$dir" rev-parse --short HEAD)
        zac_write_pin "$dir" "$name" "$resolved"
        echo "[ok]:zsh-autocomplete 钉在 $name ($resolved)"
        return 0
    fi
    echo "[error]:checkout zsh-autocomplete $resolved 失败。" >&2
    return 1
}

ensure_zsh_autocomplete_compat() {
    local zac_dir=${1:-${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}/plugins/zsh-autocomplete}
    local profile name resolved zshrc
    [[ -d $zac_dir ]] || return 0
    zshrc=${zshrc_path:-$HOME/.zshrc}
    profile=$(zac_detect_profile "$zac_dir")
    name=$(zac_normalize_ref_name)
    resolved=$(git -C "$zac_dir" rev-parse --short HEAD 2> /dev/null || true)
    echo "zsh-autocomplete 兼容配置: profile=$profile ref=$name commit=$resolved"

    if [[ $profile == external ]]; then
        install_or_update_zasync || return 1
    else
        echo "[ok]:$profile 不需要外置 zasync，移除 ~/.zshrc 中的 zasync 片段。"
        remove_zasync_zshrc "$zshrc"
    fi
    write_zac_bindkey_config
    ensure_zac_zsyh_widgets_zshrc "$zshrc" upsert
    if [[ $name == latest ]]; then
        ensure_zac_pin_zshrc "$zshrc" remove
        rm -f "$(zac_pin_file "$zac_dir")"
    else
        [[ -n $resolved ]] || resolved=$(zac_resolve_ref)
        zac_write_pin "$zac_dir" "$name" "$resolved"
        ensure_zac_pin_zshrc "$zshrc" upsert "$name" "$resolved"
    fi
}

# 仅更新已安装的 Zsh 插件仓库，并处理 zsh-autocomplete 的 zasync 依赖。
update_zsh_plugins() {
    local custom_dir=${ZSH_CUSTOM:-${ZSH:-$HOME/.oh-my-zsh}/custom}
    local failed=false
    local found=false

    update_zsh_plugin_repo() {
        local name=$1
        local repo_dir=$2
        local preferred_url=$3
        local before after branch current_url

        [[ -d $repo_dir ]] || return 0
        found=true

        if ! git -C "$repo_dir" rev-parse --is-inside-work-tree &> /dev/null; then
            echo "[warn]:跳过 $name: $repo_dir 不是 Git 仓库。" >&2
            failed=true
            return 0
        fi
        if [[ -n $(git -C "$repo_dir" status --porcelain) ]]; then
            echo "[warn]:跳过 $name: 仓库存在未提交改动。" >&2
            failed=true
            return 0
        fi
        if ! branch=$(git -C "$repo_dir" symbolic-ref --quiet --short HEAD); then
            echo "[warn]:跳过 $name: 仓库当前处于 detached HEAD。" >&2
            failed=true
            return 0
        fi

        current_url=$(git -C "$repo_dir" remote get-url origin 2> /dev/null || true)
        if [[ $REPO_SOURCE == origin ]]; then
            if [[ -z $current_url ]]; then
                echo "[warn]:跳过 $name: 没有 origin，且选择了沿用原来源。" >&2
                failed=true
                return 0
            fi
            preferred_url=$current_url
        elif [[ -z $current_url ]]; then
            git -C "$repo_dir" remote add origin "$preferred_url"
        elif [[ $current_url != "$preferred_url" ]]; then
            echo "首选 $name origin: $current_url -> $preferred_url"
            git -C "$repo_dir" remote set-url origin "$preferred_url"
        fi

        before=$(git -C "$repo_dir" rev-parse --short HEAD)
        echo "更新 $name ($before) from $preferred_url ..."
        if git -C "$repo_dir" pull --ff-only origin "$branch"; then
            after=$(git -C "$repo_dir" rev-parse --short HEAD)
            echo "[ok]:$name $before -> $after"
            return 0
        fi

        echo "[warn]:$name 的首选仓库更新失败: $preferred_url" >&2
        if [[ $REPO_SOURCE != origin && -n $current_url && $current_url != "$preferred_url" ]]; then
            echo "[warn]:$name 回退到原 upstream: $current_url" >&2
            git -C "$repo_dir" remote set-url origin "$current_url"
            if git -C "$repo_dir" pull --ff-only origin "$branch"; then
                after=$(git -C "$repo_dir" rev-parse --short HEAD)
                echo "[ok]:$name $before -> $after (fallback)"
                return 0
            fi
        elif [[ $REPO_SOURCE != origin && -z $current_url ]]; then
            git -C "$repo_dir" remote remove origin
        fi

        echo "[error]:$name 没有可用的更新仓库。" >&2
        failed=true
    }

    update_zsh_plugin_repo zsh-completions "$custom_dir/plugins/zsh-completions" "$zcp_repo"
    if [[ -d $custom_dir/plugins/zsh-autocomplete ]]; then
        found=true
        if ! install_or_checkout_zsh_autocomplete "$custom_dir/plugins/zsh-autocomplete" "$zac_repo"; then
            failed=true
        fi
    fi
    update_zsh_plugin_repo zsh-autosuggestions "$custom_dir/plugins/zsh-autosuggestions" "$zasp_repo"
    update_zsh_plugin_repo you-should-use "$custom_dir/plugins/you-should-use" "$zysu_repo"
    update_zsh_plugin_repo zsh-syntax-highlighting "$custom_dir/plugins/zsh-syntax-highlighting" "$zshp_repo"
    update_zsh_plugin_repo zsh-history-substring-search "$custom_dir/plugins/zsh-history-substring-search" "$zhssp_repo"

    if [[ -d $custom_dir/plugins/zsh-autocomplete ]]; then
        if ! ensure_zsh_autocomplete_compat "$custom_dir/plugins/zsh-autocomplete"; then
            failed=true
        fi
    fi

    if [[ $found == false ]]; then
        echo "未在 $custom_dir/plugins 中找到已安装的目标插件。"
    fi
    [[ $failed == false ]]
}

if [[ $update_zsh_plugins_only == true ]]; then
    zshrc_path="$HOME/.zshrc"
    [[ -f $zshrc_path ]] || touch "$zshrc_path"
    update_zsh_plugins
    exit $?
fi

# 以下代码需要gnu sed,如果gsed不可用,请用户安装
if [[ $OSTYPE == darwin* ]]; then
    if command -v gsed &> /dev/null; then
        # 临时设置别名
        alias sed=gsed
    else
        echo "macOS:gnu sed not found, please install gnu sed first!"
        if command -v brew &> /dev/null; then
            brew install gnu-sed
        else
            echo "Please install gnu-sed first!"
            exit 1
        fi
    fi
fi
# 将工作目录转移到家目录
current_wd=$(pwd)
cd ~ || exit 1
zshrc_path="$HOME/.zshrc"
# 对于某些精简系统安装完zsh可能不存在~/.zshrc
[[ -f $zshrc_path ]] || touch "$zshrc_path"
omz_installer() {
    if [[ $install_omz != false ]]; then
        echo "检查oh-my-zsh是否已经安装..."
        if [[ -d $HOME/.oh-my-zsh ]]; then
            # if command -v omz &> /dev/null; then # omz是一个zsh中的函数,bash脚本不便判断
            echo "oh-my-zsh已经安装(如果安装不完整或者要重新安装请删除$HOME/.oh-my-zsh目录):"
            echo -e "\t rm ~/.oh-my-zsh -rf"
            return 0
        fi
        echo "将要安装oh-my-zsh [$install_omz]"
    else
        echo "跳过安装oh-my-zsh !"
        return 0
    fi
    # 开始安装(如果需要的话)
    # 根据 Oh My Zsh 官方仓库 README 和 官方 tools/install.sh 安装脚本源码,下面到环境变量设置可以减少交互.
    export CHSH=yes
    export RUNZSH=no
    export KEEP_ZSHRC=no
    export OVERWRITE_CONFIRMATION=no

    echo "Environment variable about omz install:RUNZSH=$RUNZSH; CHSH=$CHSH;OVERWRITE_CONFIRMATION=$OVERWRITE_CONFIRMATION"
    if [[ $install_omz == default ]]; then
        sh -c "$(curl -fsSL https://install.ohmyz.sh/)"
    elif [[ $install_omz == github ]]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    elif [[ $install_omz == gitee ]]; then
        curl https://gitee.com/mirrors/oh-my-zsh/raw/master/tools/install.sh -o ~/install.sh
        # 由于国内网络问题,可能需要多尝试几次一下source 命令才可以安装成功.(我将其注释掉,采用换源后再执行clone
        #source install.sh
        #本段代码将修改install.sh中的拉取源,以便您能够冲gitee上成功将需要的文件clone下来.

        # 本段代码会再修改前做备份(备份文件名为install.shE)
        # shellcheck disable=SC2016
        sed '/(^remote)|(^repo)/I s/^#*/#/ ;
/^#*remote/I a\
REPO=${REPO:-mirrors/oh-my-zsh}\
REMOTE=${REMOTE:-https://gitee.com/${REPO}.git} ' -r ~/install.sh > ~/gitee_install.sh
        # 执行安装
        # shellcheck source=/dev/null
        source ~/gitee_install.sh

    fi
    unset RUNZSH CHSH OVERWRITE_CONFIRMATION
}
omz_installer
# 如果仅安装omz,那么后续内容跳过执行;
if [[ $omz_only == true ]]; then
    [[ $install_omz != false ]] && exec zsh
    return 0
else
    echo "继续安装插件..."
fi
# 将推荐的插件下载到指定目录下:(git 已经指定好了目录)
zasp=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
zshp=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
zhssp=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search
zcp=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions
zysu=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/you-should-use
zac=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete
# zsh-completions这个项目gitee官方可能没有镜像,使用个人用户的自镜像版本(建议有需要的可以自己拉取一份比较安全)
# 另外这个插件比其他zsh插件不同,在配合oh my zsh使用时需要额外注意配置文件的写法;
[[ $install_zsh_completions == true ]] &&
    ! [[ -d $zcp ]] && git clone --depth 1 "$zcp_repo" "$zcp"
# 自动动态的补全预测,属于较复杂插件(代替incr.zsh)
[[ $install_zsh_autocomplete != false ]] && install_or_checkout_zsh_autocomplete "$zac" "$zac_repo"
[[ $install_zsh_autocomplete != false ]] && ensure_zsh_autocomplete_compat "$zac"

[[ $install_zsh_autosuggestions == true ]] &&
    ! [[ -d $zasp ]] && git clone --depth 1 "$zasp_repo" "$zasp"

[[ $install_zsh_you_should_use == true ]] &&
    ! [[ -d $zysu ]] && git clone --depth 1 "$zysu_repo" "$zysu"

[[ $install_zsh_syntax_highlighting == true ]] &&
    ! [[ -d $zshp ]] && git clone --depth 1 "$zshp_repo" "$zshp"

[[ $install_zsh_history_substring_search == true ]] &&
    ! [[ -d $zhssp ]] && git clone --depth 1 "$zhssp_repo" "$zhssp"

# 构造新的plugins插件列表(字符串),保存到全局变量plugins_list中
get_omz_plugins_list() {

    # 配置插件(不要在下面的列表中添加zsh-completions这个特殊插件)

    # backslash='\\'
    plugins_list=$(
        cat << EOF
git
z
$([[ $install_zsh_autosuggestions == false ]] && echo '#')zsh-autosuggestions
$([[ $install_zsh_history_substring_search == false ]] && echo '#')zsh-history-substring-search
$([[ $install_zsh_you_should_use == false ]] && echo '#')you-should-use
$([[ $install_zsh_autocomplete == false ]] && echo '#')zsh-autocomplete
$([[ $install_zsh_syntax_highlighting == false ]] && echo '#')zsh-syntax-highlighting
EOF
    )
    # 拼接法(比较啰嗦)
    #     if [[ $install_zsh_autocomplete == "omz" ]]; then
    #         front_plugins=$(
    #             cat << EOF
    # zsh-autocomplete
    # EOF
    #         )
    #         plugins_list="${front_plugins}"$'\n'"${plugins_list}"

    #     fi

    # 为每行插件名末尾增加`\`便于在sed中使用(注意最后一个比较特殊,手动补充\\)
    plugins_list="${plugins_list//$'\n'/\\$'\n'}\\"
    echo "[$plugins_list]"
    # exit 1 # debug plugins_list
    echo "[$zshrc_path]"
}
get_omz_plugins_list

# 将.zshrc中的列表更新
update_omz_plugins_rc() {

    if grep '^plugins=(.*)' "$zshrc_path"; then
        echo "初次覆盖plugins(单行)"
        sed -i 's/^plugins=(.*)/\
plugins=(\
'"$plugins_list"'
)/' "$zshrc_path"
    elif grep '^plugins=($' "$zshrc_path"; then
        echo "覆盖插件列表(多行plugins更新)"
        sed -i '/^plugins=(/,/)/c\
plugins=(\
'"$plugins_list"'
)' "$zshrc_path"

    fi
}

update_omz_plugins_rc

# 将补全(completions,complete)相关插件的配置写入.zshrc
update_comp_plugins_config_rc() {

    echo "checking and install completion related plugins (zc,zac) ..."
    # 在plugins= 行或者source $ZSH/oh-my-zsh.sh行上方插入额外片段行(适用于zsh-completions)
    # shellcheck disable=SC2016
    # sed -i '/source \$ZSH/oh-my-zsh\.sh/i\
    update_zc_config_rc() {
        # 定义zsh-completions片段
        mark_zc_start='# >>> zsh-completions'
        mark_zc_end='# <<< zsh-completions'
        if [[ "$install_zsh_completions" == "true" ]]; then
            echo "安装zsh-completions ..."
            _switch=''
            # 如果zsh-autocomplete启用,则设置注释开关
            if [[ $install_zsh_autocomplete != "false" ]]; then
                _switch='#'
            fi
            # 检查是否曾经配置过zsh-completions片段
            # 如果已有,则原地更新(可以通过删除旧片段),然后统一执行插入

            if grep "$mark_zc_start" "$zshrc_path"; then
                echo "Remove old zsh-completions  snippet..."
                sed -i "/$mark_zc_start/,/$mark_zc_end/d" "$zshrc_path"
            fi
            # 在合适的位置插入zsh_completions配置片段
            sed -i '/^plugins=(/i\
# >>> zsh-completions\
fpath+=${ZSH_CUSTOM:-${ZSH:-~/.oh-my-zsh}/custom}/plugins/zsh-completions/src\
'"$_switch"'autoload -U compinit \&\& compinit # 有zsh-autocomplete时这一行注释掉防止冲突\
# <<< zsh-completions\
' ~/.zshrc
            # 重建补全(词库)
            rm -f ~/.zcompdump
        else
            # zsh-completions不安装(配置撤销)
            sed -i "/$mark_zc_start/,/$mark_zc_end/d" "$zshrc_path"
        fi
    }
    update_zc_config_rc
    if [[ $install_zsh_autocomplete != false ]]; then
        ensure_zsh_autocomplete_compat "$zac"
    else
        remove_zasync_zshrc "$zshrc_path"
        ensure_zac_pin_zshrc "$zshrc_path" remove
    fi
    # 安装zsh-autocomplete的方案分2类
    # 标准方式安装zsh-autocomplete(不依赖于oh my zsh等配置框架)
    update_zac_config_rc() {
        # 向.zshrc文件头部插入source命令(根据插件官方知道要让autocomplete插件尽早加载,写在.zshrc文件头部,如果oh my zsh插件管理中的加载时机无法正常生效时,可以考虑下面的方案,代替插件列表中的简单配置)
        if [[ "$install_zsh_autocomplete" == "std" ]]; then
            echo "安装zsh-autocomplete ..."
            if ! grep '# >>> zsh-autocomplete' "$zshrc_path"; then
                # shellcheck disable=SC2016
                sed -i '1i\
# >>> zsh-autocomplete\
# source /path/to/zsh-autocomplete/zsh-autocomplete.plugin.zsh\
source ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autocomplete/zsh-autocomplete.plugin.zsh\
# <<< zsh-autocomplete\
' ~/.zshrc
            fi
            echo "Try to remove zsh-autocomplete from plugin list(of my zsh)..."
            # 移除可能omz安装模式下,oh my zsh中的plugins残留插件名
            # plugins_list=$(echo "$plugins_list" | sed '/zsh-autocomplete/d')
            # 将 zsh-autocomplete 替换为空字符
            plugins_list="${plugins_list//zsh-autocomplete/}"

        elif [[ $install_zsh_autocomplete == "omz" ]]; then
            # 移除可能在std模式下,在~/.zshrc头部插入的source代码片段;
            echo "Try to remove 'source .../zsh-autocomplete' code snippet..."
            sed -i '/# >>> zsh-autocomplete/,/# <<< zsh-autocomplete/d' "$zshrc_path"
        fi
        # 时候后置的动作(收尾部分)
        if [[ "$install_zsh_autocomplete" == "false" ]]; then
            sed -i '/# >>> zsh-autocomplete/,/# <<< zsh-autocomplete/d' "$zshrc_path"
            plugins_list="${plugins_list//zsh-autocomplete/}"
            sed -i '/# >>> zac bindkey config/,/# <<< zac bindkey config/d' "$zshrc_path"
            ensure_zac_zsyh_widgets_zshrc "$zshrc_path" remove
            remove_zasync_zshrc "$zshrc_path"
            ensure_zac_pin_zshrc "$zshrc_path" remove
        else
            # 按需关闭补全代码检查(linuxbrew),将环境变量插入配置文件开头
            sed -i '/# >>> disable_compfix/,/# <<< disable_compfix/d' "$zshrc_path"
            sed -i '1i\
# >>> disable_compfix\
ZSH_DISABLE_COMPFIX=true\
# <<< disable_compfix\
' "$zshrc_path"
            # 设置 compinit。Homebrew 的补全目录可能由其他账户持有，从而触发
            # insecure directories 警报；这里暂时不报告该警告，并允许加载这些目录。
            # 同时保留 -i/-u 以兼容既有配置，参数按顺序解析，最后的 -u 生效。
            # 插入前清空可能的旧片段
            sed -i '/# >>> zac_compinit/,/# <<< zac_compinit/d' "$zshrc_path"
            sed -i '$a\
# >>> zac_compinit\
# 避免zsh compinit: insecure directories and files, run compaudit for list.\
# compaudit | xargs chmod g-w,o-w --verbose # 通常是linuxbrew单独用户的原因(所有者问题),建议忽略这部分的检查\
zstyle '"'*:compinit'"' arguments -i -u \
# <<< zac_compinit\
' "$zshrc_path"
            # 配置快捷键

            # 定义快捷键片段
            # shellcheck disable=SC2016
            # shellcheck disable=SC2125
            write_zac_bindkey_config
            # 如果此前配置过,则清空相应区域,以便统一更新相应配置
            sed -i '/# >>> zac bindkey config/,/# <<< zac bindkey config/d' "$zshrc_path"
            # 快捷键脚本文件插入到.zshrc
            sed -i '$a\
# >>> zac bindkey config\
source ~/zsh_bindkey_config.sh\
# <<< zac bindkey config\
' ~/.zshrc

            # 如果是ubuntu系统,设置.zshenv
            if [[ -f /etc/os-release ]] && grep -q -i 'NAME="Ubuntu' /etc/os-release; then
                echo "ubuntu系统设置.zshenv"
                zshenv=~/.zshenv
                append_zshenv=true
                if [[ -f $zshenv ]]; then
                    grep '^skip_global_compinit=1' $zshenv && append_zshenv=false
                fi
                if [[ $append_zshenv == true ]]; then
                    echo 'skip_global_compinit=1' >> $zshenv
                fi
            fi
            # When using Nix, add to your home.nix file:
            # programs.zsh.enableCompletion = false;
        fi
    }
    # 内部函数:更新.zshrc文件中hss插件的配置行
    update_hss_config_rc() {
        if [[ $install_zsh_history_substring_search == true ]]; then
            local zsh_bindkey_hss_config
            zsh_bindkey_hss_config=$(
                cat << 'EOF'
# zsh-history-substring-search 快捷键配置
# ^[[A 和 ^[[B 是大多数终端（如 iTerm2, VS Code 终端, Putty）发送给 Shell 的原始"向上"和"向下"信号。
# 绑定向上箭头
# bindkey '^[[A' history-substring-search-up
# # 绑定向下箭头
# bindkey '^[[B' history-substring-search-down
# # ${terminfo}[kcuu1] 代表从系统的终端信息数据库中读取"向上箭头"的定义。
# bindkey "${terminfo[kcuu1]}" history-substring-search-up
# bindkey "${terminfo[kcud1]}" history-substring-search-down

# 兼容性写法
# 为了让你的配置在所有终端都"硬核"工作，建议使用条件判断和备选硬编码。这样即便 terminfo 挂了，脚本也不会报错：
# 向上键
if [[ -n "${terminfo[kcuu1]}" ]]; then
bindkey "${terminfo[kcuu1]}" history-substring-search-up
else
# 备选方案：手动绑定常见的 ANSI 序列
bindkey "^[[A" history-substring-search-up
fi

# 向下键
if [[ -n "${terminfo[kcud1]}" ]]; then
bindkey "${terminfo[kcud1]}" history-substring-search-down
else
bindkey "^[[B" history-substring-search-down
fi

# 如果你使用 Vi 模式，还可以绑定 j 和 k
# bindkey -M vicmd 'k' history-substring-search-up
# bindkey -M vicmd 'j' history-substring-search-down
EOF
            )
            echo "$zsh_bindkey_hss_config" > ~/zsh_bindkey_hss_config.sh
            sed -i '/# >>> zhss bindkey config/,/# <<< zhss bindkey config/d' "$zshrc_path"
            # 快捷键脚本文件插入到.zshrc
            sed -i '$a\
# >>> zhss bindkey config\
source ~/zsh_bindkey_hss_config.sh\
# <<< zhss bindkey config\
' "$zshrc_path"
        else
            # 尝试移除zhss插件的快捷键配置片段
            sed -i '/# >>> zhss bindkey config/,/# <<< zhss bindkey config/d' "$zshrc_path"
        fi

    }
    update_hss_config_rc
    update_zac_config_rc
    # 将最终的plugins列表写回到~/.zshrc中
    update_omz_plugins_rc
}
update_comp_plugins_config_rc

# 利用sed并启用扩展正则原地修改,将Zsh主题设置为随机
sed -Ei 's/(^ZSH_THEME=)(.*)/\1"random"/' "$zshrc_path"
#设置随机选择的主题的列表为ys,junkfood,rkj-repos;具体可以改成自己喜欢的主题
sed -Ei.bak 's/(^#*\s*)(ZSH_THEME_RANDOM.*=)(.*)/\2("ys" "junkfood" )/' "$zshrc_path"

#检查修改结果
#检查配置文件是否有相应的行
cat "$zshrc_path" | grep -e zsh-syntax-highlighting -e zsh-autosuggestions \
    -e zsh-history-substring-search -e zsh-autocomplete -e zsh-completions
cat "$zshrc_path" | grep -E '^[^#]' | grep -e random -e THEME -e RANDOM | cat -n

# 移除多余空行(大片空行压缩)
sed -i '/^$/N;/^\n$/D' "$zshrc_path"

#刷新配置结果
# shellcheck disable=SC1090
# source "$zshrc_path"
cd "$current_wd" || exit 1
echo "======END======"
exec zsh
