## abstract

- The repository is used to save scripts created in my daily life
- The main language of scripts is powershell.The path of the powershell scripts locates in the PS

## 详情

- 中文[readme_zh.md](readme_zh.md)

## 移除git中的二进制或缓存文件

从 Git 存储库中删除所有 `.exe` 文件的缓存记录。

### powershell方案

我们可以利用powershell处理这个任务

```powershell
ls *.exe -Recurse |%{git rm --cached $_.FullName -r}
```

它首先使用 `ls` 命令列出所有 `.exe` 文件，并通过 `-Recurse` 参数递归地搜索子目录。然后，使用管道 (`|`) 将结果传递给一个脚本块 `{}`，该脚本块遍历 (`%{...%}`) 每一个文件路径，并执行 `git rm --cached` 命令来从 Git 缓存中删除这些文件，但不删除实际文件系统中的文件。

### bash方案

在 Linux 或 macOS 的 Bash shell 中，可以这样做：

```bash
find . -name "*.exe" -type f -exec git rm --cached {} \;
```

这个命令的工作方式如下：
- `find .` 命令从当前目录开始递归地查找文件。
- `-name "*.exe"` 指定只查找扩展名为 `.exe` 的文件。
- `-type f` 确保只找到文件而不是目录。
- `-exec` 允许执行外部命令，这里的命令是 `git rm --cached {} \;`，其中 `{}` 是 find 命令找到的每个文件的占位符。
- `\;` 表示结束 `-exec` 后面的命令。

请注意，在执行上述命令之前，请确保你是在一个 Git 工作树中，并且你有权限执行 `git rm` 命令。如果你不确定这些 `.exe` 文件是否应该被移除出 Git 跟踪，最好先检查一下它们是什么以及为何存在于你的项目中。另外，如果你不想立即提交这些更改，你可以稍后再手动添加并提交这些文件。

### 演示示例

```powershell
PS> ls *.exe -Recurse |%{git rm --cached $_.FullName -r}
rm 'Cpp/stars_printer/2.exe'
rm 'Cpp/stars_printer/a.exe'
rm 'Cpp/a.exe'
rm 'Cpp/StarsPrinter.exe'
 
```

### 步骤总结👺

* 在 `.gitignore`文件中写好规则(如果之前疏忽了,将不需要或不适合的东西提交上去了,就添加对应的排除规则)
* 扫描出需要移除提交的文件,然后传递给 `git rm --cached` 进行撤销提交
* 最后根据需要是否要删除这些仓库中不需要提交的文件(通常可以不删除,否则运行起来重新生成,而且新的规则下它们不会再被提交,就可以了)
* 如果确实要删除,那么仍然可以用类似的方法

  * ```powershell
    
    PS🌙[BAT:94%][MEM:51.14% (4.01/7.85)GB][2:53:09]
    # [cxxu@CXXUREDMIBOOK][<W:192.168.1.46>][Win 11 专业版@10.0.26100.1297][C:\repos\scripts]{Git:main}
    PS> ls *.exe -Recurse |%{rm $_}  
    ```
