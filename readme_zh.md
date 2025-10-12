[toc]



## abstract

- 记录日常编写的脚本,函数
- 以powershell7为主,将这些代码组成相应的模块,支持一键灵活导入,配置简单

## powershell 7+模块集

- 此脚本仓库重点是`powershell` 脚本和模块,详情查看说明文档:
  - 仓库内查看[pwshModulebyCxxu.md](./PwshModuleByCxxu.md)
  
  - 文档此文档内提供了一键部署此项目的方案
  
- 其他入口
  -  [Scripts:PwshModuleByCxxu - GitCode](https://gitcode.com/xuchaoxin1375/Scripts/blob/main/PwshModuleByCxxu.md)
  -  [Gitee|PwshModuleByCxxu.md](https://gitee.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md)
  -  [Github|PwshModuleByCxxu.md](https://github.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md)

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

### 部署失败问题👺

本项目的许多一键部署脚本依赖于`github.com`的加速站点,如果这些站点过期了,那么会导致相关下载行为无法顺利执行`irm,wget`等

并且这些加速镜像站点是硬编码内置在代码中,当然大多情况下你可以在命令行中指定最新可用的加速镜像站来修复过期的加速站链接

仓库中许多代码都使用了这种不完美的配置方案,以便于提供独立的功能(比如用户可以独立调用`Deploy-GitForwindows`,`Deploy-Pwsh7Portable`等,维护这些模块时,需要注意批量替换这些加速站地址



## github公益加速站👺

- 加速下载依赖于github加速镜像站,如果内置的镜像站过期或不可用,您可以通过github相关加速站点获取可用方案
  - [GitHub文件加速|列表集合](https://yishijie.gitlab.io/ziyuan/)
  - [GitHub Mirror 文件加速|列表集合](https://github-mirror.us.kg/)
  - [【镜像站点搜集】 · Issue #116 · hunshcn/gh-proxy (github.com)](https://github.com/hunshcn/gh-proxy/issues/116#issuecomment-2339526975)
  
- powershell模块中,几乎用到镜像加速站的独立模块都用`$github_mirror`变量来存储和管理,如果需要替换镜像链接

  - 设`$github_mirror='https://olddomain.com'`,如果你要替换为新的镜像链接`https://newdomain.com`
  - 可以打开vscode,然后在仓库中搜索所有`https://olddomain.com`,替换为`https://newdomain.com`

  


### 文档相对路径

```powershell
./PS/Deploy/readme.md
```

- 注意,这里区分大小写`Readme.md`和`readme.md`不同,在线仓库(gitee/github对大小写敏感,虽然windows上我用typora试过都可以)

### 适配说明

- 适配于powershell7的模块/函数/别名集合,对于windows powershell5.1仅提供有限的支持
  - 部分简单函数支持powershell5.1,但是用到新特性的powershell函数需要powershell7+
  - powershell模块集中如果存在powershell5.1不支持的语法或排版,就可能导致整个模块中定义的函数都无法被powershell5.1使用,这种情况下,你需要手动复制对应的函数(支持powershell5.1),然后存放到对应的脚本文件或模块中以提供兼容,例如`scoop`国内加速版的部署相关函数
  - 这里在强调一下,**强烈建议使用powershell7+以上的版本**,您可以到联想应用商店或利用github加速镜像下载powershell7(前者成功率高,但是版本可能不是最新的,本模块集不要求最新版即可运行)

