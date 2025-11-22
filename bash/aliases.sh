# #alias `<aliasName>="original alias"`

#新建aliases文件,如果需要为指定shell启用该别名配置,那么可以将给文件复制一份(新名称为:bash_aliases/zsh_aliases)
#不过更佳的做法是,在/etc/profile中配置一条命令(updateAliasesNow),该命令用来刷新别名状态(就是应用修改过的本文件,这种方式更加优雅,也保持了动态生效的能力)
#您可以在根目录或者/etc/目录下放置一份aliases文件,将其视为一份脚本文件(普通的脚本文件,然后在/etc/profile中配置运行改文件(aliases),这样一来,您不仅可以将别名清单单独放置到一个文件中,而且可以更加灵活控制要不要导入这个别名文件,甚至于,您可以在运行时手动刷新以应用新的修改,灵活性大大滴❤️)
#------------
#对于wsl子系统而言,可以不采用上述策略
#可以将运行本脚本文件的命令写入到启动自动运行的/etc/profile中
# 配置一条应用本文件更新的别名updateAliasNow
#强烈建议您不要在别名文件中执行别名配置的其他行为,这样可能引起难以发现的异常,这是使用aliases文件来管理别名的一个约定🎶(aliases文件不应该插手其他领域)
#直接复制一下内容到aliases(推荐保存在/etc/下)
#为了和某些内置命令区分开,您可以考虑将你的缩写以大写(首字母)或者增加某个前(后)置符(可以是未被系统占用的字符(例如 `_`,甚至是英文字母))作为一种区分标志

## #基础命令
#配置文件中不允许等号`=`和后面跟随的字符串值间有多余的格
# 关与别名文件中的顺序问题:答案是不用关心顺序:因为,在你调用某个别名之前,整个文件已经被执行完毕了,同时每一条别名配置指令,都是当作字符串来赋值
# 但是只有一条必须位于所有指令前面,即,本文将中的每一行别名配置指令都是依赖于alias命令,

#😄basic alias definition:
echo "unset all aliases,then to reset and update ☆*: .｡. o(≧▽≦)o .｡.:*☆"
alias a="alias" #@@@@@@@@@@
echo "the basic aliases updating!"

# a testOrder="echo ok!"
# pwd
# @@kill&pkill:使用别名 sudo pkill &sudo kill 会导致auto suggestion 插件触发异常的[sudo] password:输入请求,很烦!,不要配置这个别名)---
########################(●'◡'●)(❁´◡`❁)☆*:-----insert your new aliases below the delimiter-----################################
a dir_all_size_ayalyze="du -h --max-depth=1  -a |sort -hr"  
a dir_subdir_sizes="du -h --max-depth=1 |sort -hr"
a ps_cpu="ps axu --sort=-%cpu|less"
a btm_cxxu="btm --color nord-light"
a dicts dl
# a bat=batcat #如果是通过apt等工具安装的,那么包名为batcat(除了别名,也可以配置硬连接到/usr/local/bin,具体使用type/whereis查看)
a bat="batcat --theme ansi "#以浅色主题ansi 打开某个文件
a vimR="vim -R"#使用只读模式的vim来查看文件也是不错的
# 测试代理是否可以加速:
# curl https://duckduckgo.com/
# wget www.google.com
curl_gg="curl -i google.com|nl"
# 通过别名/bash函数来配置,方便控制开关.
# e https_proxy=127.0.0.1:7897
# e http_proxy=127.0.0.1:7897
# echo  {https_proxy,http_proxy}=127.0.0.1:7897
# 分配律等价于: https_proxy=127.0.0.1:7897 http_proxy=127.0.0.1:7897
a proxy_on="export {https_proxy,http_proxy}=127.0.0.1:7897"
a proxy_off="unset {https_proxy,http_proxy}=127.0.0.1:7897"
a remove_perge_package="sudo apt-get purge --auto-remove "
a gccp="g++"
a cp="cp"
a mv="sudo mv"
a c="code "
a glances="glances --theme-white"
a git_clone_shallow="git clone --depth=1"
a gits="git status"
a gitLogGraphDetail="git log --graph --all"
a gitLogGraphSingleLine="git log --all --decorate --oneline --graph"
a gitAddAll="git add .;gits"
# git clone -b <branch> <url> --depth=1 (或许可以指定克隆分支/过滤大文件: --fileter=blob:none)

a updatedb="sudo updatedb"
a cman="man -M /usr/share/man/zh_CN "
# 执行类似以下语句进行创建py命令
# sudo ln -s /usr/bin/python3.10 py
# 或者直接 a py="/usr/bin/python3.10";但是创建symlink可以更易于迁移
a py="python3"
# linux上,traceroute不是自带的工具,需要自行安装!
a te=test
a get_links="ll |grep '\->'"
a npm="sudo npm"
a tracert=traceroute
a cfiles="lse *.c"
a gr=egrep
a h="help"
a b="bash -c"
a pipH="sudo -H py -m pip"
a pip="py -m pip"
# a pip3=pip
a listPython="ls -1l /usr/bin/python*"
a updateAliasesNow="s $linuxShellScripts/importer.sh;echo '❤️aliases updated this session just now!'"
a au="updateAliasesNow"
a linuxVer="lsb_release -a;cat /etc/issue"
a linuxKernelVer="uname -a"
a ln="sudo ln -f "
a PathShow="echo $PATH|sed 's/:/\n/g'|sort"
a showPath=PathShow
a de=declare
a dec=de
a dtype="declare -p"
a startProject="django-admin startproject"
a pmg="py manage.py"
a startapp="pmg startapp"
#default makemigrations all apps!(if without specific app name)

a pmgmk="pmg makemigrations"
a pmgmi="pmg migrate"
a pmgs="pmg showmigrations"
a mi="pmg migrate"
a append="tee -a"
a runserver_dj="nohup py manage.py runserver 0:8000 &"
a l1="ls -1"
a li="ls -li"
a ll1="ls -l1"
a lsa="ls -a"
a lsl="ls -l"
a lsla="ls -la"
a tree_exa='exa --icons --tree'
a lse="exa -higl --icons "
a lseg="lse --git"
a ld="lsd -l --color never"
a lsdir="ls -lpa | grep '^d'"
a lsf="ls -lpa|grep -v '.*/'"
a exp=export
a ec=echo
a jobs="jobs -l"
a jb=jobs
a e="exit"
a envsUpdate="s $linuxShellScripts/envs.sh;echo 'envs updated!'"
# a EnvsApplyNow="source /etc/profile.d/envs.sh"
a profileEdit="v /etc/profile"
a EnvsEdit="v /etc/profile.d/envs.sh"
a aliasesConfigEdit="v $aliasesConfig"
a aliasesJumperEdit="v $aliases_jumper"
a aliasEdit="aliasesConfigEdit"
# a aliasesEdit="v /etc/aliases"
a zrc="~/.zshrc"
a brc="~/.bashrc"
a sbrc="source ~/.bashrc"
a szrc="source ~/.zshrc"
a zshrcEdit="v ~/.zshrc"
a zre=zshrcEdit
a bashrcEdit="v ~/.bashrc"
a bre=bashrcEdit
a s="source"
# for linux virtual complete independent system
# a updateAliasNow="s /etc/aliases;echo '❤️the /etc/aliases was applied this session just now!'"
# for wsl
a dt="dict"
a le="less"
a tr_dt="trans"
a chx="chmod +x"
a wg="wget"
a vim_raw=vim
a v="sudo vim"
#默认vim以sudo(root权限打开)
a vim="sudo vim"
a hi="history"
a t=touch
a syslogCheck="sudo tail -f /var/log/syslog"
a faillogCheck="sudo tail -f /var/log/faillog"
# for debian_like:
a vimrcEditGlobal='v /etc/vim/vimrc;'
#😄with the basic alias definition of `alias` & `source`,these are optional configuration for you to config:

#s /etc/profile
#一般需要管理员权限(sudo)才可以更改该文件;`spf`
#s ~/.*rc
a sb="s ~/.bashrc"
a sz="s ~/.zshrc"
#😄zip/unzip/tar
#😄editor

#😄user management
a apr=apropos
# #for debian_like dist:
a apt="sudo apt"
a install="sudo apt install"

a cls=clear
