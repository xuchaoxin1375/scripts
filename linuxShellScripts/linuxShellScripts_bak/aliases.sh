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


alias a="alias"
echo "the basic aliases updating!"

# a testOrder="echo ok!"
alias testAliasAvailability="echo 'alias avalible'!"
# pwd
##-----insert your new aliases below the delimiter-----

a updateAliasesNow="s $linuxShellScripts/importer.sh;echo '❤️aliases updated this session just now!'"
a au="updateAliasesNow"
a linuxVer="lsb_release -a;cat /etc/issue"
a linuxKernelVer="uname -a"

a append="tee -a"
a ls1="ls -1"
a lsa="ls a"
a lsl="ls l"
a lsla="ls la"
a e="exit"
a envsUpdate="s $linuxShellScripts/envs.sh;echo 'envs updated!'"
# a EnvsApplyNow="source /etc/profile.d/envs.sh"
a profileEdit="v /etc/profile"
a EnvsEdit="v /etc/profile.d/envs.sh"
a aliasesConfigEdit="v $aliasesConfig"
a aliasesJumperEdit="v $aliases_jumper"
a zshrcEdit="v ~/.zshrc"
a bashrcEdit="v ~/.bashrc"
a s="source"
# for linux virtual complete independent system
# a updateAliasNow="s /etc/aliases;echo '❤️the /etc/aliases was applied this session just now!'"
# for wsl

a wg="wget"
a v="sudo vim"
a vi="v"
# for debian_like:
a vimrcEditGlobal='v /etc/vim/vimrc;'
a aliasesEdit="v /etc/aliases"
#😄with the basic alias definition of `alias` & `source`,these are optional configuration for you to config:

#s /etc/profile
#一般需要管理员权限(sudo)才可以更改该文件;`spf`
a vpf="v /etc/profile"
a spf="s /etc/profile"
#s ~/.*rc
a sb="s ~/.bashrc"
a sz="s ~/.zshrc"
#😄zip/unzip/tar

a ta="tar xvf"
#😄editor

#😄user management

a Gr="group"
# #for debian_like dist:
a install="sudo apt install"

