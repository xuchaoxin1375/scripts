#!/bin/bash
# Homebrew 源代码仓库,可以用来加速: brew update
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
# Homebrew 预编译二进制软件包与软件包元数据文件
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
# Homebrew 核心软件仓库(Brew 4.0 版本后默认使用元数据 JSON API 获取仓库信息，因此在大部分情况下都不再需要进行如下配置。可参考 homebrew-bottles 进行相关配置。)
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
