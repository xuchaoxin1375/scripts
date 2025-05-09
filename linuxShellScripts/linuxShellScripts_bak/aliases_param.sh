# 在这里构造类似函数的别名
echo "update param aliases done!"
help_bash(){
    bash -c "help $1"
}
alias help="help_bash"



a append="tee -a" 
a override="tee"
