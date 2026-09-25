[toc]

## abstract

实用脚本集合,改善命令行使用体验. 

- powershell(pwsh7跨平台)
- bash/zsh

仓库链接:

- [github.com/xuchaoxin1375/scripts](https://github.com/xuchaoxin1375/scripts)
- [gitee.com/xuchaoxin1375/scripts](https://gitee.com/xuchaoxin1375/scripts)

### 使用说明

1. windows 用户主要使用powershell模块(通过wsl或git-bash也可以使用第二类(shell)相关内容)
2. linux/macos用户主要使用shell中的脚本集合(也可以安装powershell使用第一类中的内容.)

### 代码clone注意事项

无论哪个方案,请事先安装好git;

#### windows用户git配置

对于**windows**用户,建议关闭`autocrlf`,否则一些bash脚本的换行方式会被修改为CRLF,造成脚本运行出错,包括git-bash.

```bash
git config --global core.autocrlf false
```

补救措施:(如果上述配置之前已经clone好代码了,有2种方案:

1. 删除代码仓库,配置好git(关闭`autocrlf`) ,重新clone.
2. 进入powershell(前提是已经配置好本仓库的powershell模块),执行如下命令:

```powershell
# 将$sh目录下的sh文件和.inputrc配置文件中的换行设置为LF
cd $sh;ls -Recurse *.sh,.inputrc.conf|Convert-CRLF -Replace -To LF ;cd -
```



#### alpine linux

> 对于部分精简的linux系统(例如alpine linux),可能还需要手动安装bash:
>
> ```bash
> sudo apk add bash git
> ```



## powershell

>  powershell(pwsh) 模块集,主要针对v7+版本适配.
>
> 可用于windows,linux,macos等系统.(主要用于windows,在其他系统提供有限的支持.)

- powershell模块部分详情查看说明文档:

  - 先看[文档入口地图](./PS/docs/README.md)(新用户按任务分流),新机部署看[部署指南](./PS/docs/Deploy-Guide.md)
  - 旧结构文档[ archive:pwshModulebyCxxu.md](./PwshModuleByCxxu.md)仅供考古,现状以 `PS/docs/` 为准
- 其他入口

  - [Scripts:PwshModuleByCxxu - GitCode](https://gitcode.com/xuchaoxin1375/Scripts/blob/main/PwshModuleByCxxu.md)
  - [Gitee|PwshModuleByCxxu.md](https://gitee.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md)
  - [Github|PwshModuleByCxxu.md](https://github.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md)



### 一键部署powershell模块(full)

部署完整的powershell模块,适合长期使用.

> 默认走 github + 加速镜像(2026-09-24 本机实测可用,见 `PS/TestLinks/TestLinks.psm1`);
> gitee 对 `irm|iex` 常误报拦截,只留兼容,不再作为默认源.

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1'|iex

```

> 分步执行:(可审查脚本内容,也可指定参数.)
>
> ```powershell
> irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1' > ~/dcp.ps1
> ~/dcp.ps1 -RepoSource github
> # 如果需要强制覆盖已有仓库,可以运行
> Deploy-CxxuPsModules  -Verbose -Confirm
> ```
>
> 

更具体的说明查看此文档：[部署说明](./PS/Deploy/readme.md)

### 轻量部署（仅 Windows PowerShell 5.1，免 git 免 pwsh）

新机器只有 v5 时，在 `powershell.exe` 里存下脚本再加 `-Light` 跑：走离线包下载（codeload + 中央镜像静默，不弹窗选源），落 `PSModulePath`（追加不覆盖），写 5.1 专属 profile，重开 `powershell.exe` 跑 `init` 即用（B 档可用范围与禁区见 [Feature-Guide §13](./PS/docs/Feature-Guide.md)）：

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/Deploy-CxxuPsModules.ps1' > ~/dcp.ps1
~/dcp.ps1 -Light
```

### 落仓库后的第二步与本地开发

- 补全栈（`Deploy-CompletionStack`）与 2 条命令极简版见 [部署指南](./PS/docs/Deploy-Guide.md)；出问题先跑 `doctor`，再按 [文档入口地图](./PS/docs/README.md) 分流。
- 未推送到远程时用本地最新代码测部署：仓库内直接运行一键脚本并加 `-Dev`（仓库根自动推导，4 个一键脚本通用），例如 `C:/repos/scripts/PS/Deploy/Deploy-CxxuPsModules.ps1 -Dev`（可叠 `-Light -WhatIf`）；会过期的资源清单与检查命令见 [部署指南 §14](./PS/docs/Deploy-Guide.md)。

> 如果clone过程中出错(比如git读取git配置出错,可以执行如下命令移除或备份配置)
>
> ```shell
> rm ~/.gitconfig
> ```
>
> 通过重命名来备份:
>
> ```powershell
> mv ~/.gitconfig ~/.gitconfig.bak #.$(Get-Date -Format "yyyy.MM.dd-HH-mm-ss")
> ```
>
> 

如果已经安装过powershell7和git,则上述命令会跳过相关软件下载,直接clone代码速度更快更稳.

> 如果没有实现安装,则会尝试为你的电脑安装powershell7和git两个软件,但是可靠性不保证.

### 常用powershell模块部署

适合临时使用,不获取全部代码.

#### Deploy系列

参考文档:[Deploy/readme.md](PS/Deploy/readme.md)

#### Tools系列

```powershell
irm 'https://gh-proxy.com/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Tools/Tools.psm1'|iex

```

## bash/zsh

如果macos或者linux用户(甚至是git-bash)，可以将仓库克隆到家目录下:

考虑扩展性，将来可能会克隆多个仓库，那么可以在家目录创建 `repos`目录，将仓库克隆到其中便于管理；



### `*nix`系统上的一键部署shell模块目录(面向bash/zsh shell)

这里提供使用自动判断可用仓库源的一键部署版本:

> 面向个人电脑和服务器的部署方式(对于服务器,此方案不会涉及服务器软件例如nginx的配置文件的部署.)

```bash
# 如果没有部署过,则完整克隆,否则执行代码更新
bash <( curl -sSfL https://gitee.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/update_shell_config.sh)

```



### 服务器上使用

适用于linux服务器的代码部署方案.

服务器上的代码和个人使用的shell方案相同,但是有专用的部分,例如服务器有一些专用的服务软件(nginx,fail2ban等),仓库提供了一些常用配置.

#### 一键部署



```bash
# 仅clone代码(不做额外操作)

## github
bash <(curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh) -U # -F -R

## gitee(国内方案)
bash <(curl -SfL https://raw.giteeusercontent.com/xuchaoxin1375/scripts/raw/main/wp/woocommerce/woo_df/sh/update_repos.sh) -U # -F -R

```

其中 `-F`会覆盖 `nginx`的主配置文件(nginx.conf),酌情使用,如果不想覆盖,可以移除 `-F`

对于隐藏在反向代理服务器的后端服务器,通常要使用额外的`-R`选项部署.



#### 更新脚本错误修复

> 如果某次更新引入错误导致更新脚本不可用时,通过下面的命令恢复,注意这依赖于`$sh`变量,如果是第一次使用本仓库代码,`$sh`未定义,导致脚本尝试下载到根目录下.
>
> 对于服务器版本,搜索仓库中的文件名:`update_repos.sh`

```bash
# 具体的脚本文件url请登录github获取,下面提供一个示例
curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh -o $HOME/update_repos.sh && bash $HOME/update_repos.sh

```

点击**原始数据**(raw)获取脚本链接:

- [scripts/wp/woocommerce/woo_df/sh/update_repos.sh at main · xuchaoxin1375/scripts](https://github.com/xuchaoxin1375/scripts/blob/main/wp/woocommerce/woo_df/sh/update_repos.sh)
- [wp/woocommerce/woo_df/sh/update_repos.sh · xuchaoxin1375/scripts - Gitee.com](https://gitee.com/xuchaoxin1375/scripts/blob/main/wp/woocommerce/woo_df/sh/update_repos.sh)

### 轻量虚拟化平台中和宿主机共用

这里主要是指虚拟机或模拟层(linux)中使用shell脚本模块.

#### 准备命令

```bash
# 准备
_REPO_BASE="repos/scripts"
_SH_RELATIVE="wp/woocommerce/woo_df/sh"
```

在家目录创建`repos`,`sh`目录便于访问;

#### windows的wsl中访问windows中的仓库目录

> 执行下面代码前,请确保执行了上面的准备命令!

```bash
ln -snfv /mnt/c/repos ~/repos
ln -snfv /mnt/c/$_REPO_BASE/$_SH_RELATIVE ~/sh
bash ~/sh/shellrc_addition.sh && exec bash
```



#### macos上lima虚拟机直接访问宿主机仓库

> 执行下面代码前,请确保执行了上面的准备命令!

如果用户需要在macos上的lima的linux实例中直接访问macos上的仓库,根据lima的特性,可以在虚拟机中无缝访问;

```bash
ln -snfv $HOME/repos ~/repos
ln -snfv $HOME/$_REPO_BASE/$_SH_RELATIVE ~/sh
# 配置shell环境
bash ~/sh/shellrc_addition.sh && exec bash
```

## 直接clone仓库(单纯clone)

不同系统下,clone的首选路径有所不同.

### windows系统（使用powershell运行）

```powershell
# 创建仓库存放目录
New-Item -itemtype directory C:/repos -Verbose -ErrorAction SilentlyContinue
# 开始clone(默认走 github;国内网络可先配好镜像/代理,见本文“github公益加速站”一节):
git clone --recursive --depth 1 --shallow-submodules https://github.com/xuchaoxin1375/scripts.git C:/repos/scripts
# 可选的设置环境变量：
setx PsModulePath C:/repos/scripts/PS

```

> 国内从 gitee clone 可能要求登录；github 免登录但直连不一定通，不通可走镜像或代理.

如果不想登录且网络环境允许,可用走github方案:将上述命令行中的`gitee`替换为`github`,当然还可以选择配置加速镜像或者代理:

```powershell
$repos = "C:/repos"
$proxy = "http://127.0.0.1:8800" # 设置代理url;
# 创建仓库存放目录
New-Item -itemtype directory C:/repos -Verbose -ErrorAction SilentlyContinue
# 开始clone:
git -c http.proxy="$Proxy" -c https.proxy="$Proxy" clone --recursive --depth 1 --shallow-submodules https://github.com/xuchaoxin1375/scripts.git C:/repos/scripts
# 可选的设置环境变量：
setx PsModulePath C:/repos/scripts/PS

```

### `*nix`系统

```bash
repos="$HOME/repos"
scripts="$repos/scripts"
repo_source="github.com" # 国内直连不通可切换代理/镜像,备选 gitee.com(可能要求登录)
mkdir -p "$repos" 
# clone代码
git clone --recursive --depth 1 --shallow-submodules https://"$repo_source"/xuchaoxin1375/scripts.git "$scripts"


# 可选的配置shell脚本库(兼容bash,zsh)
sh_script_dir="$scripts/wp/woocommerce/woo_df/sh"
sh_sym="$HOME/sh" sh="$sh_sym"
# ! [[ -L $sh_sym ]] && 
ln -snfv  "$sh_script_dir" "$sh_sym" 
# 部署shell 交互方案(prompt主题和补全方案)
bash $sh/shellrc_addition.sh
# 进程替换,让配置生效
exec bash
```



## clone参数说明

| **参数**                     | **说明**                                                         | **推荐用法**            |
| ---------------------------------- | ---------------------------------------------------------------------- | ----------------------------- |
| **`--depth 1`**            | **最核心参数**。只克隆最近的一次提交（Commit），不下载历史记录。 | `git clone --depth 1 [URL]` |
| **`--recursive`**          | 如果仓库包含**子模块（Submodules）**，此参数会一并克隆它们。     | `ble.sh` 建议带上此参数。   |
| **`--shallow-submodules`** | 确保子模块也只克隆最新版本（深度为 1），进一步节省空间。               | 配合 `--recursive` 使用。   |
| **`--single-branch`**      | 只克隆指定的某个分支（默认是主分支），忽略其他远程分支。               | 配合 `-b [branch]` 使用。   |

### 部署失败问题👺

本项目的许多一键部署脚本依赖于 `github.com` 的加速站点,如果这些站点过期了,那么会导致相关下载行为无法顺利执行 `irm,wget`等

仓库已收敛到统一方案(2026-09-24 本机实测,见 `PS/TestLinks/TestLinks.psm1`):
中央变量 `$env:PsGithubMirror`(不设则默认 `https://gh-proxy.com`,模块内静默测速会话缓存一次),
拼 raw 地址一律走 `Get-RepoRawUrl`(模块内)或同策略三行内联(独立 `Deploy-*.ps1` 脚本).
大多数情况下你可以在命令行中指定最新可用的加速镜像站来替换过期的加速站链接(例如 `-RepoSource github` 配合 `$env:PsGithubMirror`)
会过期的外部资源(镜像站/上游版本/第三方域)统一登记在 [部署指南 §14](./PS/docs/Deploy-Guide.md),部署失败时先查该表再换链接.

## github公益加速站👺

- 加速下载依赖于github加速镜像站,如果内置的镜像站过期或不可用,先跑 `Get-AvailableGithubMirrors` 测速,
  挑最快的持久化:`Add-EnvVar -EnvVar PsGithubMirror -NewValue 'https://xxx'`;
  也可以对照下面的搜集页自找(注意甄别,很多已停服):

  - [GitHub文件加速|列表集合](https://yishijie.gitlab.io/ziyuan/)(聚合页,非下载前缀)
  - [【镜像站点搜集】 · Issue #116 · hunshcn/gh-proxy (github.com)](https://github.com/hunshcn/gh-proxy/issues/116#issuecomment-2339526975)
- powershell模块中,几乎用到镜像加速站的独立模块都用 `$github_mirror`/`$env:PsGithubMirror` 变量来管理,
  不要再硬编码旧域名(`github.moeyy.xyz` 已停服,`ghproxy.cc`/`mirror.ghproxy.com` 已不可用,详见 `PS/TestLinks/TestLinks.psm1` 头部注释)

### 文档相对路径

```powershell
./PS/Deploy/readme.md
```

- 注意,这里区分大小写 `Readme.md`和 `readme.md`不同,在线仓库(gitee/github对大小写敏感,虽然windows上我用typora试过都可以)

### 适配说明

- 67 模块中 62 个兼容 Windows PowerShell 5.1（B 档：`init` + 提示符 + Tab 补全 + 历史可用；预测视图与 dll 链留 7 不降）；查数用 `Get-CxxuModuleCompatibility`（真相源是各模块自己的 `.psd1`），完整清单、降级用法与加码禁区见 [Feature-Guide §13](./PS/docs/Feature-Guide.md)。
- 5.1 下读 UTF-8 文档（含中文）用 `Get-ContentUTF8`（裸 `Get-Content` 按 GBK 解码必乱码）；新机器只有 v5 时走轻量部署（本文“一键部署”一节 `-Light`）。
- 仍强烈建议使用 PowerShell 7+（完整功能与最佳性能）；您可以到联想应用商店或利用 GitHub 加速镜像下载 PowerShell 7（前者成功率高，但版本可能不是最新，本模块集不要求最新版即可运行）。
