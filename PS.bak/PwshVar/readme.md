- 配置常量字符串在strings.conf中进行

- 可以使用`rvpa "xxx*"`的方式动态解析,但是C盘的许多目录需要管理员权限访问

  - 例如,'C:\Program Files',windowsApp目录

  - 如果直接是用`ls`去列举其中的子目录和文件,会导致无法显示内容

    - ```powershell
      
      PS[BAT:76%][MEM:39.91% (12.65/31.70)GB][19:37:11]
      # [C:\Program Files\WindowsApps]
       ls
      Get-ChildItem: Access to the path 'C:\Program Files\WindowsApps' is denied.
      
      ```

      

  - 切换到管理员shell,才可以看到内容