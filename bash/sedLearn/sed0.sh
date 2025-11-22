# sed -n '4,7p' text1
# sed -n -e '5,7p' -e '9,10p' text1
# from line 5,step with 7
# sed -n '5~7p' text1
# sed -n '/^And /p' coleridge.txt
sed -n  '/root/p' /etc/passwd
# sed -n '/^L1 /p' text1
# sed -n -e '/L72/,/L80/ p' text1
# sed -n --debug -e '/37834/, /30577/ p' text1
sed -n -r  -e '/L1.*/, /L2.*/ p' text1

sed -n "/Jane/, /贝爷/ p" data.txt

# nl 会给文本行prefix 行号,不建议使用在前头.
nl ILoveLinux|sed '3,5p' -n
nl ILoveLinux|sed '/linux/p' -n

sed '/apple/! s/hello/world/g' input.txt > output.txt

sed '25,27 s/L/wer/g' input.txt > output.txt
sed '22,/L89/ s/L/wer/g' input.txt > output.txt
sed '/L83/,/L89/ s/L/dd/g' input.txt > output.txt
nl input.txt |sed '/L83/,/L89/s/L/_d/g' > output.txt
cat input.txt |sed '/^b.*/Ip'  -rn|nl|tee output.txt
cat input.txt |sed '/[[:digit:]]/Ip'  -rn|nl|tee output.txt

# 替换install.zsh中的remote/repo源
cat input.txt |sed '/^remote/Ip'  -rn  |nl|tee output.txt
cat input.txt |sed '/(^remote)|(^repo)/Ip'  -rn  |nl|tee output.txt
cat input.txt |sed '/(^remote)|(^repo)/I s/^#*/#/ p'  -rn  |nl|tee output.txt

cat input.txt |sed '/(^#*remote)/I a\
REPO=${REPO:-mirrors/oh-my-zsh}\
 REMOTE=${REMOTE:-https://gitee.com/${REPO}.git}\
'  -rn  |nl|tee output.txt

sed '/(^#*remote)/I a\
REPO=${REPO:-mirrors/oh-my-zsh}\
 REMOTE=${REMOTE:-https://gitee.com/${REPO}.git}\
' input.txt -rn  |nl|tee output.txt

sed '/(^#*remote)/I  a\
REPO=${REPO:-mirrors/oh-my-zsh}\
REMOTE=${REMOTE:-https://gitee.com/${REPO}.git}\
' input.txt -r  |nl|tee output.txt
# {command}
seq 3 | sed -n '2{s/2/X/ ; p}'
seq 3 | sed -n '2s/2/X/ ; 2p'
seq 5 | sed -n '2,4{p;s/[0-9]/X/ ; p}'
# print lines number
sed -n '/L82/,/83/ {                                                                    [21:54:05]
=
p
}' input.txt
# append multiple lines
sed '/L93/ a\
test\
line2\
line3' input.txt