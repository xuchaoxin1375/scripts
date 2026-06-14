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
git config --global core.autocrlf true
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

  - 仓库内查看[pwshModulebyCxxu.md](./PwshModuleByCxxu.md)
  - 文档此文档内提供了一键部署此项目的方案
- 其他入口

  - [Scripts:PwshModuleByCxxu - GitCode](https://gitcode.com/xuchaoxin1375/Scripts/blob/main/PwshModuleByCxxu.md)
  - [Gitee|PwshModuleByCxxu.md](https://gitee.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md)
  - [Github|PwshModuleByCxxu.md](https://github.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md)



### 一键部署powershell模块(full)

部署完整的powershell模块,适合长期使用.

> gitee 可能要求登录账号;

```powershell
irm 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'|iex

```

> 分步执行:(可以指定参数,例如仓库源指向github.)
>
> ```powershell
> irm 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1' > ~/dcp.ps1
> ~/dcp.ps1 -RepoSource github
> # 如果需要强制覆盖已有仓库,可以运行
> Deploy-CxxuPsModules  -Verbose -Confirm # -RepoSource github 也可以zhi'd
> ```
>
> 

更具体的说明查看此文档：[部署说明](./PS/Deploy/readme.md)

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
irm https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Tools/Tools.psm1|iex

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
curl -SfL https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/wp/woocommerce/woo_df/sh/update_repos.sh -o $sh/update_repos.sh

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
# 开始clone:
git clone --recursive --depth 1 --shallow-submodules https://gitee.com/xuchaoxin1375/scripts.git C:/repos/scripts
# 可选的设置环境变量：
setx PsModulePath C:/repos/scripts/PS

```

> gitee可能要求用户登录自己的gitee账号才能clone.

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
repo_source="gitee.com" # 根据需要可以切换为github.com
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
