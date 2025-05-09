

# 以管理员权限打开一个shell窗口,保证防火墙能够顺利配置
# 创建一个正则表达式对象
$path_raw = 'reg query HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\edgeupdate /v ImagePath' | Invoke-Expression
$regex = [regex] '"(.*)"'
# 对字符串执行匹配并获取所有匹配项
$all_matches = $regex.Matches($path_raw)
$edge_updater_path = $all_matches[-1].Value -replace '"', ''

Write-Host $edge_updater_path
#通常这个路径是:"C:\Program Files (x86)\Microsoft\EdgeUpdate\MicrosoftEdgeUpdate.exe"

#设置接下来要操作的防火墙规则名字
$deu="Disable Edge Updates"

#修改防火墙需要管理员权限,因此在此操作之前,以管理员权限打开一个shell窗口(如果已经处于管理员窗口,则直接执行下面的语句)
netsh advfirewall firewall add rule name=$deu dir=out action=block program=$edge_updater_path

#将禁止edge update的规则禁用,就是恢复edge update
$deu = "Disable Edge Updates"
netsh advfirewall firewall set rule name=$deu new enable=no

#检查防火墙规则
netsh advfirewall firewall show rule name=$deu
<# 
PS>netsh advfirewall firewall show rule name=$deu

Rule Name:                            Disable Edge Updates
----------------------------------------------------------------------
Enabled:                              Yes
Direction:                            Out
Profiles:                             Domain,Private,Public
Grouping:
LocalIP:                              Any
RemoteIP:                             Any
Protocol:                             Any
Edge traversal:                       No
Action:                               Block
Ok.
 #>

#也可以通过移除禁止edge update的规则
netsh advfirewall firewall delete rule name=$deu
<# 
PS>netsh advfirewall firewall delete rule name=$deu

Deleted 1 rule(s).
Ok.
 #>

write-host 'run '+'edge://settings/help' +' in edge'



# # 输出所有匹配项
# foreach ($match in $all_matches)
# {
#     Write-Host $match.Value
# }