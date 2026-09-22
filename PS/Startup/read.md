* ```powershell
  #尝试重定向输出到日志文件,但这在powershell似乎无法做到,我们用start-job虽然隐藏了输出,却无法重定向到文件
  # 如果想要接受start-job启动的任务返回结果,使用Receive-Job -Id $job.id,其中$job是Start-job 赋值的对象
  #然而这里调用的vbs没有输出结果,因此是空白的输出,就不需要定向到日志文件中
  #有些软件,例如alist server输出内容无法使用 >,2>等重定向阻止输出到标准输出终端(不知道cmd能不能做到)
  ```

```bash

#检查alist挂载配置了多少个存储(将结果输出到日志文件,否则会阻碍下一步任务,或者放在其他脚本里)
# $scriptBlock = {
#     $alist_home = 'c:\exes\alist'
#     Set-Location $alist_home
#     C:\exes\alist\alist.exe storage list 
# }
# $job = Start-Job -ScriptBlock $scriptBlock
# Receive-Job -Id $job.id

# Stop-Job -Name $job.name

# 查看所有正在运行的后台任务
# Get-Job

# 等待后台任务完成（如果需要）
# Wait-Job $job
```

### alist

* ```
  #后台(不打印日志到前台)启动alist服务
  # $scriptBlock = {
  #     # $alist_home = 'c:\exes\alist'
  #     # Set-Location $alist_home
  #     # # (vbs免弹出窗口,同时也不会由信息输出,所以可以不用后台执行)
  #     # "$alist_home\startup.vbs" | Invoke-Expression
  #     # 当窗口退出后,如下写法会停止alist服务,因此下面的写法不可用
  #     # "$alist_home\alist.exe server" | Invoke-Expression
  # }
  # Start-Job -ScriptBlock $scriptBlock
  ```
