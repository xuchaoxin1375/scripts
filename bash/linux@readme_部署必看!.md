## configuration introduction

*   [UNABLE TO CHANGE Computer name on WIndows 10 Pro - Microsoft Community](https://answers.microsoft.com/en-us/windows/forum/all/unable-to-change-computer-name-on-windows-10-pro/6a20f7e6-b5f8-4b96-9bdb-596a03892da8)

## part1@关于importer.sh文件

### for real linux

*   修改script变量的值(只需在real linux 上uncomment 该行 `# export scripts=/home/cxxu`即可)

### for wsl(pass)

*   默认配置是给wsl,无需修改该部分
*   但是注意用户名`cxxu`,否则需要做改动!!!

### importer.sh文件说明

- 在`/etc/profile`中配置全局环境变量`importConfig`(可以被子shell继承);但是普通别名无法被子shell继承

- 我找到这个变通的方法,在任何地方都可以访问全局变量(运行`$importConfig`),不过,配置`~/.profile` 似乎会更加方便一些(不用sudo)

- 在wsl中,既可以导入别名配置(这里的环境变量值是一条source 命令)然而,在真实的linux系统中,似乎不允许环境变量是一条指令,而且指令中包含变量的时候,需要使用eval 执行字符串指令执行导入aliases 的命令,配置在/etc/profile 中,

- 这样开机后第一个shell启动就会加载这些别名,而其他shell更是有第一个shell派生出来,更加会继承这些内容,配合alias |grep ,您可以快速查找到当前环境的相关别名配置

- 开机自启脚本的执行过程中若报错,则后续内容将没有机会运行,也即是说配置失败,需要修改配置脚本

- `/etc/profile`:导入以下内容到/etc/profile(追加 tee -a)

  脚本所在路径

  ```bash
  source $repos/scripts/linuxShellScripts/.importer.sh
  
  cat $repos/scripts/linuxShellScripts/.importer.sh | sudo tee -a /etc/profile
  
  ```

- `/etc/rc.local`

  - ```bash
    cat $repos/scripts/linuxShellScripts/.aliasesUpdate.sh | sudo tee -a /etc/rc.local
    ```

  - 使配置立即生效`source /etc/rc.local`

- Note:

  - 环境变量的导入需要在别名导入之前执行.

  - 本文件(`importer.sh`)中最好不要使用别名,提高稳定性,但是可以用**变量**来提高可维护性

## part2@关于/etc/profile(基础开机运行文件)

### for real linux

在该文件中添加

```plaintext
 source /home/cxxu/linuxShellScripts/importer.sh
 echo "running profile scripts done!"
```

#### zsh

*   如果是默认bash(root用户),那么上述修改已经足够了
*   对于zsh,您可能需要添加 `别名`(环境变量)
    *   `alias importConfig="source /home/cxxu/linuxShellScripts/importer.sh"`
    *   `importConfig`
        *   这样,每次载入zsh,就会重新导入(刷新)一次配置
        *   当然,如果不加第二局,每次都要手动导入才能够使用
*   不要过分要求bash和zsh使用同一份配置文件,bash,zsh的配置文件体系不同,我们只好分开处理,毕竟,你也就用这两种shell,配置一次,几乎是一劳永逸,花费过多时间求同意,不仅兼容性得不到保证,而且容易,耗费不必要的时间!
    *   不过我想到了一种可能的共用方案,就是通过zsh的命名体系,对bash的配置文件配置一个硬链接,这样维护一份文件就可以
    *   不过通过导入的方式,本身就已经有很高的重用性

### for wsl🎈

*   执行本地部署脚本
*   在这之前，您应当根据下面博客中的脚本进行安装zsh以及基本的优化操作!
    *   [linux\_linux自动化换源等优化美化自动化操作脚本/oh my zsh安装/卸载与删除/vim/vi卸载与更新异常/linux发行版本/内核版本查看\_xuchaoxin1375的博客-CSDN博客\_kali换源](https://blog.csdn.net/xuchaoxin1375/article/details/120999508?csdn_share_tail=%7B%22type%22%3A%22blog%22%2C%22rType%22%3A%22article%22%2C%22rId%22%3A%22120999508%22%2C%22source%22%3A%22xuchaoxin1375%22%7D)

- ```bash
  touch ~/.hushlogin #停止提示安装完整组件
  cd ~
  #和powershell不同,变量定义时不需要$符号,引用的时候才需要
  conf_dir="/mnt/d/repos/scripts/linuxShellScripts"
  ln -s $conf_dir -f
  # 可以考虑备份原有的.zshrc
  # cp .zshrc .zshrc_bak
  # ln采用-f选项,自动删除掉已有的文件.zshrc文件
  
  ln -s $conf_dir/.zshrc .zshrc -f
  source $conf_dir/importer.sh
  ```
### for msys2
- ```bash
  cd ~
  #和powershell不同,变量定义时不需要$符号,引用的时候才需要
  conf_dir="/d/repos/scripts/linuxShellScripts"
  ln -s $conf_dir -f
  # 可以考虑备份原有的.zshrc
  # cp .zshrc .zshrc_bak
  # ln采用-f选项,自动删除掉已有的文件.zshrc文件
  
  ln -s $conf_dir/.zshrc .zshrc -f
  source $conf_dir/importer.sh
  ```

## 附@zsh的配置文件

*   man zsh 中末尾介绍了一些
*   [Moving to zsh, part 2: Configuration Files – Scripting OS X](https://scriptingosx.com/2019/06/moving-to-zsh-part-2-configuration-files/)

| **all users** | **user** | **login shell** | **interactive shell** | **scripts** | **Terminal.app** |
| --- | --- | --- | --- | --- | --- |
| `/etc/zshenv` | `.zshenv` | √ | √ | √ | √ |
| `/etc/zprofile` | `.zprofile` | √ | x | x | √ |
| `/etc/zshrc` | `.zshrc` | √ | √ | x | √ |
| `/etc/zlogin` | `.zlogin` | √ | x | x | √ |
| `/etc/zlogout` | `.zlogout` | √ | x | x | √ |