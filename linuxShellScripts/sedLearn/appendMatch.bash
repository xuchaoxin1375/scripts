# cat install.sh |sed '/(^remote)|(^repo)/I s/^#*/#/ '  -r  > output.sh

# sed '/^#*remote/Ia\
# 1REPO\
# 2REMOTE
# ' output.sh  |tee output.txt

# sed '/^#*remote/I a\
# REPO=${REPO:-mirrors/oh-my-zsh}\
# REMOTE=${REMOTE:-https://gitee.com/${REPO}.git}\
# ' input.txt -r  |nl|tee output.txt

# seq 3 | sed '2a\
# hello\
# world
# 3s/./X/'

# 替换遇到问题,可以基于已有的解决方案,控制变量,双向替换,看到底是那一步分出现问题
# seq 3 | sed '2a\
# REPO=${REPO:-mirrors/oh-my-zsh}\
# REMOTE=${REMOTE:-https://gitee.com/${REPO}.git}
# 3s/./X/'

# 说明用于替换的字符串ok
# cat install.sh | sed '2a\
# aaREPO=${REPO:-mirrors/oh-my-zsh}\
# bbREMOTE=${REMOTE:-https://gitee.com/${REPO}.git}
# 3s/./X@@/'

#说明文本源文件ok

# 能够匹配到行! p;-n
# cat install.sh|sed '/^remote/I p'  -rn  > output.sh
# 成功在合适位置插入简单多行内容
# cat install.sh|sed '/^remote/I a\
# aa\
# bb
# '  -r  > output.sh

#成功替换复杂内容
# cat install.sh|sed '/^remote/I a\
# aaREPO=${REPO:-mirrors/oh-my-zsh}\
# bbREMOTE=${REMOTE:-https://gitee.com/${REPO}.git}
# '  -r  > output.sh

# cat install.sh |sed '/(^remote)|(^repo)/I s/^#*/#/ '  -r  > output.sh

# cat output.sh|sed '/^#*remote/I a\
# REPO=${REPO:-mirrors/oh-my-zsh}\
# REMOTE=${REMOTE:-https://gitee.com/${REPO}.git}
# '  -r  > output.txt
# 调试完毕

#开始整合...
# cat install.sh |sed '/(^remote)|(^repo)/I s/^#*/#/ ;
# /^#*remote/I a\
# REPO=${REPO:-mirrors/oh-my-zsh}\
# REMOTE=${REMOTE:-https://gitee.com/${REPO}.git} ' -r >output.txt
#整合完毕

# path=$desktop/install.sh
# cat $path |sed '/(^remote)|(^repo)/I s/^#*/#/ ;
# /^#*remote/I a\
# REPO=${REPO:-mirrors/oh-my-zsh}\
# REMOTE=${REMOTE:-https://gitee.com/${REPO}.git} ' -r >gitee_install.sh

# path=$desktop/installR.sh
# path=~/install.sh
# sed '/(^remote)|(^repo)/I s/^#*/#/ ;
# /^#*remote/I a\
# REPO=${REPO:-mirrors/oh-my-zsh}\
# REMOTE=${REMOTE:-https://gitee.com/${REPO}.git} ' -r  -iE $path

bash
echo "here is bash!"
cd ~
path=.zshrc

sed '/(^plugins)/ s/^#*/#/;
/^#*plugins/ a\
plugins=(\
    git\
    zsh-syntax-highlighting\
    zsh-autosuggestions\
    # 注意,sed命令的后续不能换行\
)' -r -iE $path

source .zshrc
cd - 
