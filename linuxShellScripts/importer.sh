# ---该脚本作为管理脚本,用来总览各个自定义的模块和定义,配置说明查看readme.md----



# 取得并导入环境变量
echo "importer loading!"
# comment the second `scripts` line in real linux 
export scripts=~
#!/bin/bash
read -p "请输入msys2或wsl：" input
available_types="msys2,wsl"
t="wsl"#default
r=""
if [ "$input" = "msys2" ]; then
    echo "msys2"
    
elif [ "$input" = "wsl" ]; then
    echo "wsl"
    r="/mnt"
else
    echo `无效的输入,请在$available_types中选取`
fi


export scripts=$r/d/repos/scripts

export linuxShellScripts=$scripts/linuxShellScripts

alias importConfig="source $linuxShellScripts/importer.sh"
export ipc=$impoertConfig
source $linuxShellScripts/envs.sh

cd $linuxShellScripts
source removeBgc.sh
source aliases.sh
source aliases_jumper.sh
source aliases_param.sh
source shellSettings.sh
# 返回到执行此命令时的路径
cd - > \dev\null
echo "importer:update env & Aliases done!"

