[toc]

## 说明

- 此模块内包含了其他关于部署powershell模块的脚本文件等内容

- 关于快速部署此模块集(及其所在仓库),这里创建的专用脚本文件为`Deploy-CxxuPsModules.ps1`

- 用户使用方法:

  - 运行一下命令行进行部署

    ```powershell
    
    Set-ExecutionPolicy Bypass -Scope CurrentUser -Force
    $mirror = 'https://github.moeyy.xyz'
    $url1 = 'https://gitee.com/xuchaoxin1375/scripts/raw/main/PS/Deploy/Deploy-CxxuPsModules.psm1'
    $url2 = "$mirror/https://raw.githubusercontent.com/xuchaoxin1375/scripts/refs/heads/main/PS/Deploy/deploy.psm1"
    $urls = @($url1, $url2)
    $code = Read-Host "Enter the code [0..$($urls.Count-1)]"
    $code = $code -as [int]
    $scripts = Invoke-RestMethod $urls[$code]
    
    $scripts | Invoke-Expression
    
    $GitAvailability = Get-Command git -ErrorAction SilentlyContinue
    if ($GitAvailability)
    {
        #装有Git的用户使用此方案(可以指定参数)
        Deploy-CxxuPsModules -RepoPath # C:/temp/scripts -Verbose
        
    }
    else
    {
        
        #没有Git的用户使用此方案(可以进一步指定参数)
        Deploy-CxxuPsModules -Mode FromPackage -Verbose
    }
    ```

    