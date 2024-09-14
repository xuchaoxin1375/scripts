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

nl ILoveLinux|sed '3,5p' -n
nl ILoveLinux|sed '/linux/p' -n