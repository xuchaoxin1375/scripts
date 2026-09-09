#!/usr/bin/env bash

uv_config=~/.config/uv/uv.toml
uv_config_home="$(dirname $uv_config)"
mkdir -pv "$uv_config_home"

cat << eof > "$uv_config"

[[index]]
url = "https://mirrors.aliyun.com/pypi/simple/"
# url = "https://mirrors.ustc.edu.cn/pypi/simple"
# url = "https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple"
default = true

eof

echo "检查配置文件[$uv_config]"
nl "$uv_config"
