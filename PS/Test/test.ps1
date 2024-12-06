@"
powershell -noprofile -nologo -c "Invoke-RestMethod https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Tools/Tools.psm1 | Invoke-Expression ;rebootToOS "
pause

"@ > $home\desktop\rebootToOS.bat
