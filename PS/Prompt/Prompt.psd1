@{
    RootModule = 'Prompt.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'e53eaf28-3bea-4906-b4de-3d281c161600'
    Author = 'cxxu'
    Description = 'PowerShell prompt themes, segments and switching (Set-PsPrompt)'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'promptx',
        'prompt',
        'Set-PoshPrompt',
        'Enable-PoshGit',
        'Set-PsPromptStyle',
        'Write-UserHostname',
        'Write-Uptime',
        'Write-HostIp',
        'write-PermissoinLevel',
        'Write-Path',
        'Write-OSVersionInfo',
        'write-PsEnvMode',
        'write-PsMode',
        'Get-BatteryLevelCached',
        'Write-BatteryAndMemoryUse',
        'Write-Data',
        'Write-Time',
        'Write-ColorsPreivew',
        'PromptShort',
        'PromptShort2',
        'PromptDefault',
        'PromptSimple',
        'PromptBrilliant',
        'PromptBrilliant2',
        'PromptFast',
        'PromptBalance',
        'Get-GitInfo',
        'write-GitBasicInfo',
        'Get-PromptScriptBlock',
        'dm',
        'Set-PsPrompt',
        'Test-PromptDelay'
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
