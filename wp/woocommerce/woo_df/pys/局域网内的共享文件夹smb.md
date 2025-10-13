创建共享目录(权限只读,共享路径为`C:\share\df\LocoySpider`)

用户名和密码分别为`reader`,`readonly`
注意管理员权限powershell窗口运行🎈

```powershell
Deploy-SmbSharing -Path C:\share\df\ -ShareName df -Permission Read -SmbUser reader -SmbUserkey readonly
```
```powershell
Deploy-SmbSharing -Path C:\shareTemp -ShareName dfc -Permission change -SmbUser shareTemp -SmbUserkey 1
```

链接

```powershell
# [Administrator@CXXUDESK][~\Desktop][09:21:20][UP:0.56Days]
net use R: \\cxxudesk\df /p:yes /savecred
命令成功完成。

# net use S: \\cxxudesk\dfc

```

删除

```powershell
# [Administrator@CXXUDESK][~\Desktop][09:21:25][UP:0.56Days]
net use /del R:
R: 已经删除。
```

