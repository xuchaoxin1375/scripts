@{
    RootModule = 'Tools.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'edfc2706-8431-43b4-91a4-d9ce76f52857'
    Author = 'cxxu'
    Description = '通用日常小工具:历史/版本/命令可用性/睡眠进度/vscode右键/仓库版本/conda源/北京时间'
    PowerShellVersion = '7.0'
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
