@{
    RootModule = 'Tools.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'edfc2706-8431-43b4-91a4-d9ce76f52857'
    Author = 'cxxu'
    Description = 'Everyday utilities: history/version/command probe/sleep progress/vscode ext/repo version/conda source/beijing time'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-PSConsoleHostHistory',
        'Get-CxxuPsModuleVersion',
        'Test-CommandAvailability',
        'Start-SleepWithProgress',
        'Set-OpenWithVscode',
        'Get-RepositoryVersion',
        'pow',
        'Get-MsysSourceScript',
        'Set-CondaSource',
        'Get-BeijingTime'
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
