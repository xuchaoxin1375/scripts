[toc]

## abstract

- 记录日常编写的脚本,函数
- 以powershell7为主,将这些代码组成相应的模块,支持一键灵活导入,配置简单

## powershell 7+模块集

- 此脚本仓库重点是 `powershell` 脚本和模块,详情查看说明文档:

  - 仓库内查看[pwshModulebyCxxu.md](./PwshModuleByCxxu.md)
  - 文档此文档内提供了一键部署此项目的方案
- 其他入口

  - [Scripts:PwshModuleByCxxu - GitCode](https://gitcode.com/xuchaoxin1375/Scripts/blob/main/PwshModuleByCxxu.md)
  - [Gitee|PwshModuleByCxxu.md](https://gitee.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md)
  - [Github|PwshModuleByCxxu.md](https://github.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md)

### 常用powershell模块在线运行🎈

#### Deploy系列

- 参考文档:[Deploy/readme.md](PS/Deploy/readme.md)

#### Tools系列

- ```powershell
  irm https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Tools/Tools.psm1|iex
  
  ```

## 一键部署此项目

```powershell
irm 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'|iex

```

更具体的说明查看此文档：[部署说明](./PS/Deploy/readme.md)

如果已经安装过powershell7和git,则上述命令会跳过相关软件下载,直接clone代码速度更快更稳.

> 如果没有实现安装,则会尝试为你的电脑安装powershell7和git两个软件,但是可靠性不保证.

### 单纯克隆

> 无论哪个方案,请事先安装好git;
>
> 对于部分精简的linux系统(例如alpine linux),可能还需要手动安装bash:
>
> ```bash
> sudo apk add bash git
> ```
>
> 

windows系统（使用powershell运行）

```powershell
new-item -itemtype directory C:/repos -Verbose -ErrorAction SilentlyContinue
git clone --recursive --depth 1 --shallow-submodules https://gitee.com/xuchaoxin1375/scripts.git C:/repos/scripts
# 可选的设置环境变量：
setx PsModulePath C:/repos/scripts/PS

```

如果macos或者linux用户，可以将仓库克隆到家目录下（考虑扩展性，将来可能会克隆多个仓库，那么可以在家目录创建 `repos`目录，将仓库克隆到其中便于管理；

```bash

repos="$HOME/repos"
scripts="$repos/scripts"
sh_script_dir="$scripts/wp/woocommerce/woo_df/sh"
repo_source="gitee.com" # 根据需要可以切换为github.com
sh_sym="$HOME/sh" sh="$sh_sym"
mkdir -p "$repos" && git clone --recursive --depth 1 --shallow-submodules https://"$repo_source"/xuchaoxin1375/scripts.git "$scripts"
# 可选的配置shell脚本库（兼容bash，zsh)
ln -s "$sh_script_dir" "$sh_sym" -fv 
# 部署shell 交互方案(prompt主题和补全方案)
bash $sh/shellrc_addition.sh

```

clone参数说明:

| **参数**                     | **说明**                                                         | **推荐用法**            |
| ---------------------------------- | ---------------------------------------------------------------------- | ----------------------------- |
| **`--depth 1`**            | **最核心参数**。只克隆最近的一次提交（Commit），不下载历史记录。 | `git clone --depth 1 [URL]` |
| **`--recursive`**          | 如果仓库包含**子模块（Submodules）**，此参数会一并克隆它们。     | `ble.sh` 建议带上此参数。   |
| **`--shallow-submodules`** | 确保子模块也只克隆最新版本（深度为 1），进一步节省空间。               | 配合 `--recursive` 使用。   |
| **`--single-branch`**      | 只克隆指定的某个分支（默认是主分支），忽略其他远程分支。               | 配合 `-b [branch]` 使用。   |

### 部署失败问题👺

本项目的许多一键部署脚本依赖于 `github.com`的加速站点,如果这些站点过期了,那么会导致相关下载行为无法顺利执行 `irm,wget`等

并且这些加速镜像站点是硬编码内置在代码中,当然大多情况下你可以在命令行中指定最新可用的加速镜像站来修复过期的加速站链接

仓库中许多代码都使用了这种不完美的配置方案,以便于提供独立的功能(比如用户可以独立调用 `Deploy-GitForwindows`,`Deploy-Pwsh7Portable`等,维护这些模块时,需要注意批量替换这些加速站地址

## github公益加速站👺

- 加速下载依赖于github加速镜像站,如果内置的镜像站过期或不可用,您可以通过github相关加速站点获取可用方案

  - [GitHub文件加速|列表集合](https://yishijie.gitlab.io/ziyuan/)
  - [GitHub Mirror 文件加速|列表集合](https://github-mirror.us.kg/)
  - [【镜像站点搜集】 · Issue #116 · hunshcn/gh-proxy (github.com)](https://github.com/hunshcn/gh-proxy/issues/116#issuecomment-2339526975)
- powershell模块中,几乎用到镜像加速站的独立模块都用 `$github_mirror`变量来存储和管理,如果需要替换镜像链接

  - 设 `$github_mirror='https://olddomain.com'`,如果你要替换为新的镜像链接 `https://newdomain.com`
  - 可以打开vscode,然后在仓库中搜索所有 `https://olddomain.com`,替换为 `https://newdomain.com`

### 文档相对路径

```powershell
./PS/Deploy/readme.md
```

- 注意,这里区分大小写 `Readme.md`和 `readme.md`不同,在线仓库(gitee/github对大小写敏感,虽然windows上我用typora试过都可以)

### 适配说明

- 适配于powershell7的模块/函数/别名集合,对于windows powershell5.1仅提供有限的支持
  - 部分简单函数支持powershell5.1,但是用到新特性的powershell函数需要powershell7+
  - powershell模块集中如果存在powershell5.1不支持的语法或排版,就可能导致整个模块中定义的函数都无法被powershell5.1使用,这种情况下,你需要手动复制对应的函数(支持powershell5.1),然后存放到对应的脚本文件或模块中以提供兼容,例如 `scoop`国内加速版的部署相关函数
  - 这里在强调一下,**强烈建议使用powershell7+以上的版本**,您可以到联想应用商店或利用github加速镜像下载powershell7(前者成功率高,但是版本可能不是最新的,本模块集不要求最新版即可运行)
