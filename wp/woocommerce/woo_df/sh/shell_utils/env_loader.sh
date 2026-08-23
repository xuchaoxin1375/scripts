#!/usr/bin/env bash
# 读取要注入到环境中的密钥环境变量(export VAR=VAL),例如: model_credentials.local.env;
# 并且我们假设每个环境变量配置都遵循 shell(bash)语法.且允许省略export,这里统一处理
# 加载所有 .env 文件
# 从 ~/.config 下(最多两层)的 *.env 读取变量并导出
# 兼容 bash 和 zsh
# set -u
ENV_CONFIG_DIR="$HOME/.config"
echo "[env_loader.sh]:Loading and exporting environment variables from .env files ..."

# 用 find 枚举文件, 避免 bash/zsh globstar 行为不一致的问题
# -mindepth 1 -maxdepth 2 等价于 ~/.config/{,*/}*.env
while IFS= read -r env_config; do
    # echo "Processing File: $env_config"

    if [ ! -r "$env_config" ]; then
        echo "  Warning: 不可读, 跳过" >&2
        continue
    fi

    # || [ -n "$line" ] 兼容最后一行没有换行符的情况
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}" # 去掉 CRLF 换行的 \r

        # 跳过空行和注释行
        case "$line" in
            '' | '#'*) continue ;;
        esac

        # 严格校验 KEY=VALUE 格式, 并拒绝可能被 eval 注入的字符
        if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] &&
            [[ ! "$line" =~ [\;\`\$\(\)\&\|\<\>] ]]; then
            # echo "  Export: ${line%%=*}" #调试用
            eval "export $line"
        else
            echo "  Skip 无效或不安全的行: [$line]" >&2
        fi
    done < "$env_config"

done < <(find "$ENV_CONFIG_DIR" -mindepth 1 -maxdepth 2 -type f -name '*.env' 2> /dev/null | LC_ALL=C sort)
