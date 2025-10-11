[toc]



## 配置本地网站

### 配置小皮

- 数据使用5.7或8.0

- 修改`my.ini`文件

  (小皮->(软件)**设置**->文件位置->MYSQL->mysql版本,目录下大概如下

  ```bash
  #⚡️[Administrator@CXXUDESK][C:\phpstudy_pro\Extensions\MySQL5.7.26][16:13:52][UP:1.17Days]
  PS> ls
  
      Directory: C:\phpstudy_pro\Extensions\MySQL5.7.26
  
  Mode                 LastWriteTime         Length Name
  ----                 -------------         ------ ----
  d----            2025/3/5    10:54                bin
  d----           2025/5/19     8:41                data
  d----            2025/3/5    10:54                share
  -a---           2019/6/13     9:31          17987 COPYING
  -a---           2025/4/22    10:15           1134 my.ini
  -a---           2019/6/13     9:31           2478 README
  ```

  此时弹出资源管理器,请将该目录记住(复制地址栏中的地址备用,地址类似于:`C:\phpstudy_pro\Extensions\MySQL5.7.26`)

  将以下内容添加到`my.ini`文件中的`[mysqld]`一节下面,保存修改

  ```sql
  sql_mode="NO_ZERO_IN_DATE,NO_ZERO_DATE"
  ```

  然后重启mysql服务(可在小皮工具箱首页**重启mysql**)

### 将mysql命令工具添加到环境变量

打开powershell 或pwsh (可以从开始菜单中搜索powershell打开)

打开文本编辑器(记事本或者vscode),新建空文本文件,复制粘贴并修改下面的必要内容

```powershell
$mysql_bin="    C:\phpstudy_pro\Extensions\MySQL5.7.26     ".trim()+"\bin" # 字符串替换为你之前复制的值
$newPath = [Environment]::GetEnvironmentVariable('Path', 'User') + ";$mysql_bin"
[Environment]::SetEnvironmentVariable('Path', $newPath, 'User')

# 弹出一个新的powershell窗口
powershell.exe
```

编辑完毕后在powershell中粘贴执行

#### 检查mysql命令行

现在,在弹出的新的powershell窗口中,(或者你也可以手动打开全新的powershell),复制粘贴执行以下命令

```powershell
gcm mysql
```

如果结果类似下面,则配置成功

```powershell
PS> gcm mysql

CommandType     Name                                               Version    Source
-----------     ----                                               -------    ------
Application     mysql.exe                                          5.7.26.0   C:\phpstudy_pro\Extensions\MySQL5.…

```



### 导入数据库

#### 命令行方案(powershell)

如果部署过本文提供的[powershell模块](https://gitee.com/xuchaoxin1375/scripts),则可以通过命令行方式来导入数据库

```powershell
Import-MysqlFile 
```

或者通过命令行启动一个专门的GUI窗口来填写

```powershell
shcm Import-MysqlFile 
```

用例:

```powershell
$sql_file="  C:\sites\wp_sites\base_sqls\7.us.sql  ".trim() #将引号中的内容替换为sql文件的路径
#将这里的7.us替换为你要在本地创建的数据库的名字,数据库的密码统一固定
Import-MysqlFile -SqlFilePath $sql_file -DatabaseName "7.us" -MySqlUser root -key 15a58524d3bd2e49  -verbose  


```

