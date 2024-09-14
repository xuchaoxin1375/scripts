# 在这里构造类似函数的别名
echo "update param aliases done!"
# --------under-----------

w(){
    whereis $1|tr ' ' '\n'
}
hit(){
    history|tail -$1
}
help_bash(){
    bash -c "help $1"
}
alias help="help_bash"
psh(){
    # ps -ef|grep '.*CMD$|pattern'
    #如果要查看命令字段的隐含启动参数,可以用ps -f参数
    echo $1
    # ps -ef f|{head -1;grep "$1"}
    ps -ef f| head -1
    ps -ef f|grep -v "grep"|grep "$1"
    echo "❤️"
}
white_remove(){
    cat $1 |sed 's/\s\+/ /g'|tr '\n' ' '
}
gcc_d(){
    ls $1
    echo $1.out
    gcc $1 -o $1.out
    ./$1.out
}
chr() {
    [ "$1" -lt 256 ] || return 1
    printf "\\$(printf '%03o' "$1")"
}
examples(){
    eg $1;
    cheat $1;
    tldr $1;
}
# sbrc(){
#     s brc
# }
# szrc(){
#     s zrc
# }
alias egs=examples
ord() {
    LC_CTYPE=C printf '%d' "'$1"
}
dl(){
    # 启动dictd服务来提供离线词典
    # sudo dictd
    pattern="dictd"
    if pgrep -x $pattern > /dev/null
    then
        echo "$pattern is Running"
        
    else
        echo "$pattern Stopped,try to start $pattern"
        sudo dictd
        sleep 1
        ps u -C "dictd"
    fi
    dict $1|less
}
tl(){
    trans $1|less
}

ty(){
    type $(which $1)
}



man() {
    # LESS_TERMCAP_md=$'\e[01;31m' \
    # LESS_TERMCAP_me=$'\e[0m' \
    # LESS_TERMCAP_se=$'\e[0m' \
    # LESS_TERMCAP_so=$'\e[45;93m' \
    # LESS_TERMCAP_ue=$'\e[0m' \
    # LESS_TERMCAP_us=$'\e[01;32m' \
    export LESS_TERMCAP_mb=$'\e[1;32m'
    export LESS_TERMCAP_md=$'\e[01;31m'
    export LESS_TERMCAP_me=$'\e[0m'
    export LESS_TERMCAP_se=$'\e[0m'
    export LESS_TERMCAP_so=$'\e[45;93m'
    export LESS_TERMCAP_ue=$'\e[0m'
    export LESS_TERMCAP_us=$'\e[01;32m'
    command man "$@"
}
# a m=mann

a append="tee -a"
a override="tee"
deleteUser(){
    sudo pkill -KILL -u $1
    sudo deluser --remove-home $1
}
deleteLinuxUser(){
    sudo pkill -KILL -u $1
    sudo userdel --remove $1
}