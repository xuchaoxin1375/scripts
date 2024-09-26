## abstract

- The repository is used to save scripts created in my daily life
- The main language of scripts is powershell.The path of the powershell scripts locates in the PS

## 详情

- 中文[readme_zh.md](readme_zh.md)

## 移除git中的二进制或缓存文件

利用powershell处理

```powershell
PS> ls *.exe -Recurse |%{git rm --cached $_.FullName -r}
rm 'Cpp/stars_printer/2.exe'
rm 'Cpp/stars_printer/a.exe'
rm 'Cpp/a.exe'
rm 'Cpp/StarsPrinter.exe'
 
```

* 在 `.gitignore`文件中写好规则(如果之前疏忽了,将不需要的东西提价上去了,就添加对应的排除规则)
* 然后先扫描出需要移除提交的文件,然后传递给 `git rm --cached` 进行撤销提交
* 最后根据需要是否要删除这些仓库中不需要提交的文件(通常可以不删除,否则运行起来重新生成,而且新的规则小它们不会在被提交,就可以了)
* 如果确实要删除,那么仍然可以用类似的方法
* ```powershell

  PS🌙[BAT:94%][MEM:51.14% (4.01/7.85)GB][2:53:09]
  # [cxxu@CXXUREDMIBOOK][<W:192.168.1.46>][Win 11 专业版@10.0.26100.1297][C:\repos\scripts]{Git:main}
  PS> ls *.exe -Recurse |%{rm $_}  
  ```
