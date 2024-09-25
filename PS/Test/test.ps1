$modules = Get-Module -ListAvailable | Where-Object -Property HelpInfoUri

$Destination = 'C:\PsHelpx' #指定你想要的下载目录即可
New-Item -ItemType Directory -Path $Destination -Verbose -Force

$modules.Name | ForEach-Object -Parallel {
    # param($Destination)
    $Destination = $using:Destination
    #这里可以指定verbose观察输出，也可以不使用-Verbose详情，检查下载目录即可
    Save-Help -Verbose -Module $_ -DestinationPath $Destination -UICulture en-us -ErrorAction SilentlyContinue
} -ThrottleLimit 64 