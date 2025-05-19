function Deploy-Wp
{
    <# 
.SYNOPSIS
对宝塔自动部署本地已有的wordpress模板网站进行快速建站
每次可以建一个站,批量建站(可以配置一个列表,然后将脚本循环运行)
.DESCRIPTION
该脚本可以快速部署本地已有的wordpress模板网站,并自动配置数据库,域名,网站根目录以及伪静态等信息

这里有两个任务需要注意:
1.生成批量宝塔批量建站语句和对应数据库创建语句
    (后续需要手动配置伪静态和ssl证书绑定,其中伪静态也可以通过此脚本批量配置,
    但是证书的申请和绑定需要逐个手动操作,尤其是证书的申请难以自动化分配,这是唯一的遗憾)
2.解压网站根目录和数据库sql还原;并且自动配置权限,所有者配置,修改配置文件以及数据库中的url(域名)相关值

.PARAMETER Table
指定表格数据,可以是自动模式(默认),从文件读取,或者直接输入多行字符串
例如:
www.ustensilesparfaits.com	郑玮	3.fr
www.raumhorizont.com	郑玮	4.de


.PARAMETER SpiderTeam
指定你的采集队伍人员姓名及其对应映射的名字缩写或代号,文件可以手动指定,也可以配置到powershell环境
.PARAMETER Structure
指定你粘贴的表格型数据的各列含义,尤其是前两列Domain和User不要动,尤其是User,是翻译名字的关键,
后面我预设了TemplateDomain和DeployMode这两列,
这两个分别用来指定改站点的旧域名(本地模板使用的本地域名),以及部署模式(是重新打包站点根目录以及导出最新数据库部署,还是利用已有的备份数据进行部署)
第4列之后可以为空,但是前三列比较重要

上述4个预设的列是按照高度规范的模板站根目录和数据库命名才能够达到的最简单配置
如果你的本地模板站根目录和数据库名字不同,甚至不同模板的根目录不在同一级存放站点的总目录下,那么需要配置的参数就比较多了

本文的本地模板规范是:所有有模板统一放在一个总目录下`sites`下,其每一个子目录表示一个模板;
所有模板的数据库名字和根目录名字一样,并且采用的本地域名也是和根目录名字一样
例如我的第一套德国站模板,我将其根目录命名为1.de,同时本地域名和数据库名字也都是1.de;
这种设计大有好处,允许很多操作可批处理执行,而且是相对容易实现
.PARAMETER TableMode
指定表格数据输入方式,可以是自动模式(默认),从文件读取,或者直接输入多行字符串
.NOTES
约定:

配置路径建议(但不是必须)统一用`/`分隔,也就是正斜杠(slash),windows/linux都能识别正斜杠(反斜杠windows可以识别,linux不行)
路径(目录)末尾不要使用`/`结尾,这不利于我们手动拼接路径
对于powershell,双引号字符串具有差值计算功能,而单引号字符串不具有差值功能,不能随意替换,按需使用

# .NOTES
关于压缩和解压,这里推荐使用7z压缩,本地一般不会自带7z,你需要自己安装,可以到官网/联想应用商店下载安装包,或者通过scoop自动安装
如果实在不想要7z,这里也提供了zip方案来打包,但是体积可能是7z包的2到3倍,你需要传输更长时间
使用7z的好吃是压缩率高,一般服务器自带7z命令,7z命令行工具可以压缩和解压几乎所有常见压缩包,包括zip,唯一的问题是电脑或服务器不一定自带7z;
zip的优势则是通用性,尤其是一般设备都支持压缩/解压zip
# .Notes
补充说明:root用户执行此脚本引起的权限及其衍生问题(相关问题的解决方案(自动处理)已经包含在脚本中)
这里脚本默认使用的是root用户来执行操作,而由root用户操作的文件或目录权限可能对其他用户不友好,这潜在的可能引发许多问题
例如访问网站时遇到403(被拒绝访问);wordpress默认组件,比如ftp提示警告等等


为了这类问题,你有两类选择:
1.仍然使用root操作，但是操作完成后要将权限放宽(比如将网站根目录设置为755);
另外将网站目录所有者设置为web服务用户(比如宝塔创建的/www用户)
在wp-config.php中,根据需要你可以禁用ftp,添加define('FS_METHOD', 'direct');到合适位置(末尾附近)即可
2.尝试使用普通用户来操作,但是我没验证过是否能够有利于避免权限问题

参数:不是所有参数都是必要的,但是建议不要随意调整,尤其是参数相对顺序,尤其是存在前后引用顺序,例如参数B的默认取值引用了参数A的值,那么参数B如果放到参数A前面可能会引发错误的默认取值;除非你不用到参数B,那么参数B位置随意,甚至可以被删除!

其他:
推荐环境变量配置密码,简化调用和提高安全性

.TODO
==================
解决 链接关闭问题(等待太久就会出现链接关闭问题)
Performing the operation "scp -r C:\sites\wp_sites/1.de.7z root@$env:df_server1:/www/wwwroot" on target
"23.239.111.202".
[Y] Yes  [A] Yes to All  [N] No  [L] No to All  [S] Suspend  [?] Help (default is "Y"):
Connection closed by 23.239.111.202 port 22
C:\ProgramData\scoop\apps\openssh\current\scp.exe: Connection closed

=======================
数据库没有自动处理时手动操作如下

ssh登陆到服务器
# 创建数据库
mysql -u root -e 'CREATE DATABASE `dbname` ;' -p"YourPassword" #替换dbname为你的数据库名,YourPassword为你的数据库密码
# 导入数据库备份文件
mysql -u root dbname < /www/wwwroot/4.de.sql -p 

本地powershell执行(可以自行添加密码参数 -key)


#>
    [cmdletbinding(SupportsShouldProcess)]
    param(

        $Table = "$home/desktop/table.conf",
        [ValidateSet("Auto", "FromFile", "MultiLineString")]$TableMode = 'Auto',
        $Server = $env:DF_SERVER1,
        $MysqlUser = "rootx",
        $MysqlKey = "$env:df_mysqlkey",

        $Structure = "Domain,User,TemplateDomain,DeployMode",
        $StructureCore = "Domain,User",
        $SpiderTeam = $SpiderTeam,
        $RewriteRules = "$wp_migration/RewriteRules.LF.conf",
        [switch]$CheckParams,
        [switch]$DelayToRun
    )
    function Deploy-SiteToServer
    {
        <# 
.SYNOPSIS
部署本地wordpress模板网站到服务器
.DESCRIPTION

基于上述功能,迁移过程的基本逻辑:

[核心部分]
网站归属人员;$User
服务器站点正式域名;$Domain
本地模板站域名(本地旧域名);$TemplateDomain

[可以简化的部分]如果按照本文的方式组织本地模板,那么此脚本的方便程度达到最大化,否则你还需要配置下面几个关键参数

1.本地模板站目录:$SiteDir
2.本地模板站目录归档文件|压缩包路径(7z/zip文件,不存在时自动压缩生成):$SiteDirArchive
3.本地模板站数据库名字;$OldDbName
4.本地模板站数据库备份文件路径(sql文件,不存在时自动生成);$OldDbFile

=====================================================================
[一般不需要修改,但是你以修改的重要参数]
服务器站点总目录(作为上传文件的存放目录,宝塔下一般默认/www/wwwroot);$ServerSitesHome
    服务器站点根目录(自动构造);$ServerSiteRoot
    服务器端网站目录归档文件路径(自动构造):$ServerSiteDirArchive
    服务器端网站sql备份文件路径(自动构造):$ServerDbFile
服务器站点数据库名字(自动构造);$ServerDBName

[通信/传输工具和鉴权]这部分可以通过配置环境变量以及免密配置等操作省去填写,或者填写是一次性的,第一次使用需要配置,后面就可以不写

配置mysql命令行工具(path环境变量);
    ssh命令行工具一般自带不用配置
服务器ssh用户名密码/密钥免密
服务器mysql用户名密码/配置文件免密

------------------------------------------
[采集或建站人员字典]这也是一次性配置

在电脑某个路径下配置一个文件SpiderTeam.ps1,比如:
$SpiderTeam=C:\sites\wp_sites\SpiderTeam.ps1
内容格式举例:
$SiteOwnersDict = @{
    "郑玮"             = "zw"
    "李宇哲"            = "lyz"
    "徐超信"            = "xcx"
    DFTableStructure = "Domains,User"
}
return $SiteOwnersDict

# 我们可以通过命令行:
. $SpiderTeam #导入字典到命令行环境中

==========================================
[配置powershell模块]
运行此脚本需要安装powershell7和git并配置模块:(下面是一键部署,但是建议手动安装上述两个软件,自动部署会自定下载安装软件,但是速度不是那么稳定,主要用他来下载powershell的模块)

irm 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.ps1'|iex

此命令行在powershell7或者windows 自带的powershell(v5)中都可以执行

参数文档说明(可能有滞后,仅供参考)
.PARAMETER User
网站所有者,一般是宝塔创建的用户,比如lyz

.PARAMETER domain
网站域名,比如deportealegria.com

.PARAMETER TemplateDomain
旧网站域名,比如本地模板使用的本地域名(上传到服务器后需要执行域名更新,修正为正式域名),也可以是其他情况下需要被替换的域名,比如6.es, local.com
.PARAMETER MysqlUser
服务器数据库用户名,一般是root

.PARAMETER ServerUser
服务器服务器用户名,一般是root

.PARAMETER Server
服务器服务器IP地址,比如192.168.1.1,但是这里将服务器ip配置到系统环境变量,这样调用方便,也更加安全优雅;
如果必要,你可以手动指定

.PARAMETER MysqlKey
服务器数据库密码,一般是宝塔创建的数据库密码,这里默认读取配置在环境变量中的数据库密码;
如果必要,你可以手动指定

.PARAMETER ServerSitesHome
服务器服务器总的网站目录,一般是/www/wwwroot,这个目录由宝塔默认创建
.PARAMETER user_sites_home
服务器服务器用户网站目录,一般是/www/wwwroot/$User,比如/www/wwwroot/lyz
这个目录在$ServerSitesHome下添加一级用户名目录,用于区分不同的建站人员,便于管理
.Parameter ServerUserDomainDir
用户网站域名目录,格式为"$ServerUserSitesHome/$domain",比如"/www/wwwroot/lyz/pasoadeporte.com"

.PARAMETER ServerSiteRoot
用户网站根目录,格式为"$ServerUserDomainDir/wordpress",比如"/www/wwwroot/lyz/pasoadeporte.com/wordpress"

.PARAMETER ServerWpConfigFile
wordpress配置文件路径,格式为"$ServerSiteRoot/wp-config.php",比如"/www/wwwroot/lyz/pasoadeporte.com/wordpress/wp-config.php"

.PARAMETER ServerDBName
服务器数据库名称,格式为"$User_$domain",比如"lyz_pasoadeporte.com"
.PARAMETER DeployMode
控制网站备份文件(分为两部分:
1.网站根目录打包文件(一般是7z压缩包)
2.数据库文件(一般是sql文件)

是否重新生成并覆盖旧备份(尝试找到并删除旧备份文件,然后重新打包站点根目录,导出数据库文件)

备份文件的存放位置有默认设置值,你也可以在脚本中覆盖它们

.PARAMETER OldDBName
本地数据库文件名,默认风格是和"$TemplateDomain"相同,比如"6.es"


.PARAMETER OldDbFile
本地数据库文件路径,该路径是导出sql后要存放的文件路径,也是读取已有数据库文件的路径

默认格式为"$base_sqls/$OldDBName.sql",
其中$base_sqls是存放数据库备份文件(.sql)的目录;
比如$base_sqls="c:/sites/wp_sites/base_sqls"
比如"c:/sites/wp_sites/base_sqls/6.es.sql"

.PARAMETER ServerDBFile
服务器数据库文件路径,该路径是从本地上传到服务器的数据库存放的位置
(上传到服务器是因为服务器上执行服务器自己的sql文件会比较快)
默认格式为"$ServerUserSitesHome/$OldDBName.sql",
比如"/www/wwwroot/lyz/6.es.sql"

.PARAMETER SiteDir
本地网站根目录,默认风格是"$wp_sites/$TemplateDomain",比如"c:/sites/wp_sites/6.es"
.PARAMETER ArchiveSuffix
用7z压缩本地网站目录,名字可以考虑用日期+时间来区分;
默认使用已有的压缩包,不加后缀
这个选项可以在DeployMode不启用的情况下,额外打包一个带有后缀的站根目录压缩包

#根据需要解开这行注释,这使你可以重新打包当前站点,而且不覆盖已有的备份文件,得到最新版本的压缩包
$ArchiveSuffix=".$(Get-Date -Format yyMMdd-hh)" 

.PARAMETER SiteDirArchive
本地网站根目录压缩包路径,默认是一个7z文件,名字是本地站点根目录同名
格式为"$SiteDir$ArchiveSuffix.7z",比如"c:/sites/wp_sites/6.es.7z"

.PARAMETER base_sqls
数据库备份文件存放路径,格式为"$base_sqls/$OldDBName.sql",比如"c:/sites/wp_sites/base_sqls/6.es.sql"


.PARAMETER BashFileName
文件上传到服务器后,需要修改配置文件,修改数据库必要内容(url)等操作
默认脚本名字为:wp_deploy.sh
注意这个脚本不应该包含CRLF,而应该处理为LF作为换行符
这里通过创建bash脚本,推送到服务器上,让服务器执行,可以减少不必要的麻烦

.PARAMETER BashScriptFile
控制本地生成的bash脚本存放的位置路径
默认格式为"$env:TEMP/$BashFileName",即存放到环境变量指定的临时文件目录Temp中
例如: C:\Users\Administrator\AppData\Local\Temp\wp_deploy.ps1

#>
        [CmdletBinding(SupportsShouldProcess)]
        param(


            #建站信息配置(服务器站点信息);这个部分有3个变量必须要要注意
            [alias('SiteOwner')]$User = "  lyz  ".trim(),

            [alias('FormalDomain', 'NewDomain')]$Domain = @"           

   DeporteAlegria.com  

"@,
            [alias("LocalDomain", "OldDomain", "Template")]$TemplateDomain = "    ".trim(),

            # 次要信息
  
            [alias('SSHUser')]$ServerUser = "root",
            $Server = $Server,
    
            # 本地模板网站根目录备份和导出
            # 🎈
            $SiteDir = "$wp_sites/$TemplateDomain",

            $ArchiveSuffix = "", 
            # $ArchiveSuffix=".$(Get-Date -Format yyMMdd-hh)" ,
            $ArchiveFormat = "7z",
            # 🎈
            $SiteDirArchive = "${SiteDir}${ArchiveSuffix}.${ArchiveFormat}",
   
            $SiteDirArchiveName = (Split-Path $SiteDirArchive -Leaf),
            $SiteArchiveBaseName = (Split-Path $SiteDirArchive -LeafBase),

            # 🎈
            [alias('LocalDBName')]$OldDBName = $TemplateDomain,
            # 🎈
            [alias('LocalDBFile')]$OldDbFile = "$base_sqls/$OldDBName.sql",
            # 配置目录体积界限(单位MB),超出这个范围的怀疑目录有问题
            $MinSize = 10,
            $MaxSize = 500,
            # 服务器网站目录和配置文件相关配置
            $ServerSitesHome = '/www/wwwroot',

            #格式例如: /www/wwwroot/lyz/pasoadeporte.com
            $ServerUserSitesHome = "$ServerSitesHome/$User",
        
            $ServerDBFile = "$ServerSitesHome/$OldDBName.sql",
            $ServerSiteDirArchive = "$ServerSitesHome/$SiteDirArchiveName",
            $ServerUserDomainDir = "$ServerUserSitesHome/$domain",

            # 下面的路径是根据7z的解压行为特点,自动构造的,一般不需要修改(压缩包将作为解压后的目录名,要更改名字,你根据此名来更改(mv))
            $ServerSitePack = "${ServerUserDomainDir}/SitePack",
            $ServerSiteDirExpanded = "${ServerSitePack}/$SiteArchiveBaseName",
            # 服务器数据库名称
            $ServerDBName = "${User}_${domain}",

            #格式例如: /www/wwwroot/lyz/pasoadeporte.com/wordpress
            $ServerSiteRoot = "$ServerUserDomainDir/wordpress",

            $ServerWpConfigFile = "$ServerSiteRoot/wp-config.php",
    

            #本地模板网站数据库信息;移除现有的版本(sql文件和7z压缩包),重新导出配套文件(部署最新版本)
            [validateset('Override', 'Lazy')]$DeployMode = 'Lazy',

    
    
            # 生成的bash脚本(要推送到服务器执行)
            $BashFileName = 'wp_deploy.sh',
            $BashScriptFile = "$env:TEMP/$BashFileName",

            # $SpiderTeam = $SpiderTeam,
            [switch]$CheckParams
        )

        $domain = $domain.ToLower().replace("www.", "") # .replace(".com", "").trim() + ".com"
        Write-Verbose "Params Check Mode is: $CheckParams" -Verbose

        if($CheckParams)
        {
            Write-Verbose "请检查如下关键目录是否配置正确(如果不正确,请回头修改参数;对于不存在的文件,脚本将尝试创建或生成!):" -Verbose

     

            Write-Host "网站归属人员: $User"
            Write-Host "网站域名: $Domain"
            Write-Host "本地模板站点域名(本地旧域名): $TemplateDomain"

            Write-Host "本地站点目录: $SiteDir"
            Write-Host "站点归档文件(压缩包)路径: $SiteDirArchive"
            Write-Host "本地模板数据库名称: $OldDBName"
            Write-Host "本地模板数据库备份sql文件路径: $OldDbFile"

            Write-Host "-----自动构造可自定义的重要参数------"
            Write-Host "服务器站点总目录: $ServerSitesHome"
            Write-Host "服务器站点根目录(例如域名目录domain.com的子目录wordpress): $ServerSiteRoot"
            Write-Host "服务器站点归档文件路径: $ServerSiteDirArchive"
            Write-Host "服务器数据库备份文件sql文件路径: $ServerDBFile"
        
            Write-Host "服务器数据库名称: $ServerDBName"

            Write-Host "-----通信鉴权组------"

            Write-Host "服务器服务器地址: $Server"
            Write-Host "MySQL密钥: $MysqlKey"
            Write-Host "服务器站点主目录: $ServerSitesHome"
            Write-Host "用户站点主目录: $ServerUserSitesHome"
            Write-Host "用户站点域名目录: $ServerUserDomainDir"
            Write-Host "站点(wp)配置文件路径: $ServerWpConfigFile"

            Write-Host "------备份和bash脚本文件上传位置组"

        
            Write-Host "站点归档文件名: $SiteDirArchiveName"
            Write-Host "站点归档文件基名: $SiteArchiveBaseName"
            Write-Host "站点归档解压后的默认名": $ServerSiteDirExpanded
        
            Write-Host "生成的Bash脚本文件名: $BashFileName"
            Write-Host "生成的Bash脚本文件路径: $BashScriptFile"
        }

        Pause

        # ====================================

        #处理备份文件(保险期间,下面的语句执行前,确保旧文件不再使用,或者做好了必要备份)
        if($DeployMode -eq 'Override')
        {
            # 移除旧文件
            Remove-Item $OldDbFile -ErrorAction SilentlyContinue -Verbose -Confirm
            Remove-Item $SiteDirArchive -ErrorAction SilentlyContinue -Verbose -Confirm
        
        }
        # 如果对应的备份文件不存在,则尝试重新生成
        if(!(Test-Path $SiteDirArchive))
        {
            #打包压缩本地网站目录(最新版本);使用7z打包压缩率高,上传服务器的速度快(要求你本地安装了7-zip,可以用scoop安装或其他方式安装)
            Write-Warning "${SiteDirArchive} does not exist,try to generate it..."
            if($ArchiveFormat -eq "7z")
            {

     
                if(Get-Command 7z -ErrorAction SilentlyContinue)
                {
                    # 判断该目录是否存在,以及初步判断该目录体积是否像一个正常的wp站,尤其是不是一个空站,
                    # 或者存在不必要的文件导致目录体积过大,应该暂时离开,进行排查
                    if(Test-Path $SiteDir)
                    {
                        Get-ChildItem $SiteDir | Select-Object fullname | Out-String | Write-Verbose 

                        # $size = Get-ItemSizeSorted $SiteDir
                        $list = Get-ChildItem $SiteDir | Select-Object -ExpandProperty fullname
                        Write-Host $list 
                        $sizeReportDetail = $size | Out-String
                        Write-Verbose "SiteDir size: $sizeReportDetail" -Verbose
                        $size = (Get-Size $siteDir -Unit MB).size
                        # Write-Host "SiteDir size: $($size|Out-String)"

                        if($size -gt $MaxSize -or $size -lt $MinSize)
                        {
                            Write-Error "SiteDir size is too large or too small, please check it first!"
                            exit
                
                        }
                        7z a -t7z $SiteDirArchive $SiteDir
                    }
                }
                else
                {
                    Write-Warning "7z(7-zip) command not found, please install 7-zip and add it to PATH"
                    if($PSCmdlet.ShouldProcess($SiteDir, "Generate zip archive"))
                    {
                        $ArchiveFormat = "zip"
                    }
                    else
                    {
                        exit
                    }
                }   
            }
            # 如果7z命令不存在,且用户愿意换用zip,则尝试使用zip打包压缩本地网站目录(默认使用powershell自带的Compress-Archive,有一定局限性,但是一般够用)
            if($ArchiveFormat -eq "zip")
            {
                Compress-Archive -Path $SiteDir -DestinationPath $SiteDirArchive -Force 
            
            }
    
        }if (!(Test-Path $OldDbFile))
        {
            #导出本地网站的对应数据库
            Write-Warning "${OldDbFile} does not exist,try to export it..." 
            New-Item -type directory -Path $base_sqls -Force -ErrorAction SilentlyContinue -Verbose
            Export-MysqlFile -DatabaseName $OldDBName -server localhost -MySqlUser $MysqlUser -key $MysqlKey -SqlFilePath $OldDbFile
        }


        #将网站文件包上传到服务器
        Push-ByScp -Server $Server -User $ServerUser -Source $SiteDirArchive -DestinationPath $ServerSitesHome -Confirm
        # 将数据库备份文件上传到服务器
        Push-ByScp -Server $Server -User $ServerUser -Source $OldDbFile -DestinationPath $ServerSitesHome -Confirm

        # 解压网站文件包到服务器对应目录的命令行构造(不会立即执行!)
        if($ArchiveFormat -eq "7z")
        {

            $ExpandArchiveCmd = "7z x $ServerSiteDirArchive -o${ServerUserDomainDir}/SitePack -y"
            # 解压后的目录标记为:$ServerSiteDirExpanded
        }
        else
        {
            # 这里使用unzip解压zip,7z可用的话也可以解压zip
            $ExpandArchiveCmd = "unzip $ServerSiteDirArchive -d $ServerUserDomainDir/SitePack"
        }
        Write-Verbose "ExpandArchiveCmd: $ExpandArchiveCmd will be executed on server"

        # 通过ssh远程执行命令行(推荐放到bash脚本中执行)
        # ssh $ServerUser@$Server "7z x $ServerSiteDirArchive -o$ServerUserDomainDir -y"

        # =========================

        # 定义bash脚本
        $bash_script = @"

# 解压网站根目录到合适的位置(在服务器调用7z执行命令;目录不存在时,7z会自动创建)
if [ -d "$ServerSiteDirExpanded" ]; then
    echo "The directory already exists: [$ServerSiteDirExpanded]"
    echo "The size of the directory is: [`$(du -sh $ServerSiteDirExpanded)]"
    echo "update/Remove this directory and continue to expand the archive...?(y/n)"
    read -r response
    # 注意将bash中创建并引用的变量前dollar符号使用`转义(这里是powershell变量,bash变量的引用符号会被powershell解释掉,这不是我们想要的)
    # 从powershell中引用的变量则应该表留dollar符号
    echo "You choose: [`$response]"

    if [ "`$response" = "y" ]; then
        rm -r "$ServerSiteDirExpanded"
        echo "Directory removed, continue to expand the archive..."
        $ExpandArchiveCmd
    else
        echo "Use the exist directory directly!"
        # exit 1 #debug todo
    fi
 
else
    echo "The directory does not exist, continue to expand the archive..."
    $ExpandArchiveCmd
fi

# 删除旧的根目录(可能会遇到.user.ini文件标记导致无法删除,暂时不用此方案)
# rm -rf $ServerSiteRoot
# 判断站点根目录是否事先存在
if [ -d "$ServerSiteRoot" ]; then
    echo "The directory already exists: [$ServerSiteRoot]"
    echo "Try to remove this directory try its best..."
    # 忽略删除输出消息
    rm -rf "$ServerSiteRoot" > /dev/null 2>&1
    # 确保目标目录存在(如果已经存在mkdir也不会报错)
    mkdir diry/dirz -p -v

    echo "Try to move the expanded directory to the root directory..."
    mv "$ServerSiteDirExpanded"/* $ServerSiteRoot -f 

    # 网站根目录(比如wordpress)若已经存在(比如宝塔事先建好,那么你可以尝试尽可能移除或清空此目录内容,
    # 有的内部文件无法直接删除,导致原根目录无法删除),你可考虑将解压的内容移动到网站根目录)
    # 检查目录是否为空,如果非空则移动其中内容,否则删除空目录,以便重新解压 if [ -z "`$(ls -A "$DIR")" ]; then
    # if [ -z "`$(ls -A $ServerSiteDirExpanded)" ]; then
    #     echo "Warning: Directory is empty: [$ServerSiteDirExpanded]"
    #     rm -r "$ServerSiteDirExpanded" 
    # else
    # 移动现有非空站点根目录到指定位置(并重命名为wordpress)
    # fi 
else
    # 站点根目录事先不存在,直接将原站点解压目录移动(更名)为站点根目录
    # 移动站点根目录到指定位置(并重命名为wordpress)
    mv $ServerSiteDirExpanded $ServerSiteRoot -f
fi



# 将wp-config.php文件中的数据库信息修改为正式数据库的信息
sed -ri "s/(define\(\s*'DB_NAME',\s*')[^']+('\s*\))/\1$ServerDBName\2/"  $ServerWpConfigFile

# 清理临时目录🎈
rm -r ${ServerUserDomainDir}/SitePack

# 将上传到服务器的sql备份文件导入服务器的数据库中🎈
echo "Importing database backup file to server...🎈"
mysql -u$MysqlUser -p$MysqlKey -h localhost $ServerDBName < $ServerDBFile
"@ + @'

#配置强制使用https

# sed -ri "/\/\*\* Sets up WordPress vars and included files. \*/i \

sed -ri "/\/\* That's all, stop editing! Happy publishing. \*/i \
define('FORCE_SSL_ADMIN', true);\n\
if (\$_SERVER['HTTP_X_FORWARDED_PROTO'] == 'https') {\n\
\$_SERVER['HTTPS'] = 'on';\n\
}\n"
'@ + " $ServerWpConfigFile " + @"


# linux递归地更改: 将指定目录权限设置为755;更改目录所有者

chmod 755 $ServerUserDomainDir
chown www:www $ServerUserDomainDir

chmod -R 755 $ServerSiteRoot
chown -R www:www $ServerSiteRoot
"@

        # 转为LF风格shell文件
        $bash_script = $bash_script -replace "`r`n", "`n"


        $bash_script | Set-Content -NoNewline $BashScriptFile
        # Get-CRLFChecker -Path $BashScriptFile
        Write-Host "请检查bash脚本:`n=============================================="
        # Write-Host $bash_script 
        $bash_script | Get-ContentNL -AsString
        Write-Host "===================================================="
        if(!$PSCmdlet.ShouldProcess($BashScriptFile, "Continue?"))
        {
            exit
        }
        #将本地备份的数据库导入到服务器对应的数据库中(耗时比较久,可以考虑使用navicat来加速,或者寻找更高效的方法,比如上传sql文件到服务器,然后让服务器自己导入,写入上述bash脚本片段中)
        # Import-MysqlFile -server $Server -MySqlUser $MysqlUser -DatabaseName $ServerDBName -SqlFilePath $OldDbFile

        #推送伪静态配置文件到服务器
        Push-ByScp -Server $Server -User $ServerUser -Source $RewriteRules -DestinationPath "/www/server/panel/vhost/rewrite/$domain.conf" -Verbose -Confirm

        #将脚本推送到服务器去执行(每轮执行自动更新,无需确认)
        Push-ByScp -Server $Server -User $ServerUser -Source $BashScriptFile -DestinationPath $ServerSitesHome -Confirm:$false

        ssh $ServerUser@$Server "bash $ServerSitesHome/$BashFileName" 

        #修改服务器中对应数据库中域名为正式域名(url/domain)
        Update-WpUrl -server $Server -MySqlUser $MysqlUser -key $MysqlKey -OldDomain $TemplateDomain -NewDomain $domain -DatabaseName $ServerDBName -Verbose -Start3w -protocol "https" -Confirm:$false

        # 通过ssh 直接执行bash脚本(不推荐,复制语句容易出问题)
        # $bash_script | ssh $ServerUser@$Server "bash -s"
    }
    function Start-Deploysites
    {
        <# 
    .SYNOPSIS
     批量部署网站到服务器(调度现有命令)
    #>
        param (
        
        )
        # 导入字典
        $SiteOwnersDict = . $SpiderTeam 
        Write-Verbose "Check SiteOwnerDict availibility" -Verbose
        Write-Verbose $SiteOwnersDict -Verbose
        # Pause
        # $Dict = $SiteOwnersDict.GetEnumerator()
        # $Dict
        # Write-Host "[$($Dict|Out-String)]" -ForegroundColor Cyan

        # 伪静态配置内容检查
        if(Test-Path $RewriteRules)
        {
            Get-CRLFChecker $RewriteRules
        
        }
        else
        {
            Write-Warning "RewriteRules file does not exist: [$RewriteRules], please check it first!"
            Pause
        }
        $res = Get-DomainUserDictFromTable -Table $Table -Structure $Structure -SiteOwnersDict $SiteOwnersDict -Verbose:$false
        # write-host $res
        Get-DictView -Dicts $res 
        # Pause
        # return $res

        Start-BatchSitesBuild -server $Server -MySqlUser $MySqlUser -MySqlkey $MysqlKey -Table $Table -TableMode $TableMode -Structure $StructureCore -SiteOwnersDict $SiteOwnersDict -SiteRoot "wordpress" -ToClipboard -Verbose:$false
    
        foreach($item in @($res))
        {
            $DeployMode = $item.DeployMode
            Write-Host "sturcture:[$structure]" -ForegroundColor Cyan
            if(!$DeployMode)
            {
                $DeployMode = 'Lazy'
            }
            Write-Verbose "DeployMode: [$DeployMode]" -Verbose
            # if($PSCmdlet.ShouldProcess($item.Domain, "Deploy to server"))
            # {
            # }
            Deploy-SiteToServer -User $item.User -domain $item.Domain -TemplateDomain $item.TemplateDomain -DeployMode $DeployMode -CheckParams:$checkParams
        }
    }
    # 是否立即执行脚本
    if(!$DelayToRun)
    {
        start-Deploysites
    }
}