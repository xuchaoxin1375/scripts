@{
    RootModule = 'PsDebug.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'c1847d23-b3b2-4e8d-9c32-0ea18e49a103'
    Author = 'cxxu'
    Description = 'PowerShell 内省/诊断/调试辅助:管道/源码/权限/日志'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Head',
        'Tail',
        'Get-TypeCxxu',
        'Get-ParametersList',
        'Test-SudoAvailability',
        'Get-PathType',
        'Set-Owner',
        'Grant-PermissionToPath',
        'Get-PipelineInput',
        'Get-SourceCode',
        'Confirm-UserContinue',
        'Write-PsDebugLog',
        'Start-CodeSSh'
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
