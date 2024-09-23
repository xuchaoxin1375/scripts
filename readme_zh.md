[toc]



## abstract

- 记录日常编写的脚本,函数
- 以powershell为主,将这些代码组成成相应的模块,支持灵活导入,配置简单

## 仓库重点:powershell



- 仓库重点是`powershell` 脚本,详情查看说明文档:
  -  [Scripts:PwshModuleByCxxu - GitCode](https://gitcode.com/xuchaoxin1375/Scripts/blob/main/PwshModuleByCxxu.md)
  -  [Gitee|PwshModuleByCxxu.md](https://gitee.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md)
  -  [Github|PwshModuleByCxxu.md](https://github.com/xuchaoxin1375/scripts/blob/main/PwshModuleByCxxu.md)
  
- 适配于powershell7的模块/函数/别名集合,对于windows powershell5.1仅提供有限的支持
  - 部分简单函数支持powershell5.1,但是用到新特性的powershell函数需要powershell7+
  - powershell模块集中如果存在powershell5.1不支持的语法或排版,就可能导致整个模块中定义的函数都无法被powershell5.1使用,这种情况下,你需要手动复制对应的函数(支持powershell5.1),然后存放到肚里的脚本文件或模块中以提供兼容,例如`scoop`国内加速版的部署相关函数
  - 这里在强调一下,强烈建议使用powershell7+以上的版本

