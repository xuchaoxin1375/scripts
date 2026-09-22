@{
    RootModule = 'BTCN.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'eb9c5aff-3b43-4427-8fd4-d6f0b792c199'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: BTCN'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-BatchSiteDBCreateLines',
        'Get-BatchSiteBuilderLines',
        'Get-BatchSiteBuilderLinesFromTable',
        'Start-BatchSitesBuild',
        'Remove-LineInFile',
        'Write-Highlighted',
        'Get-CRLFChecker',
        'Convert-CRLF',
        'Deploy-BatchSiteBTOnline'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('CxxuPsModules')
            ProjectUri = 'https://github.com/xuchaoxin1375/scripts'
        }
    }
}
