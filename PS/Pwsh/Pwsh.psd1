@{
    RootModule = 'Pwsh.psm1'
    ModuleVersion = '1.0.4'
    GUID = '7a6243f2-bed4-47b7-a4fe-49bb87a7e2f4'
    Author = 'cxxu'
    Description = 'General PowerShell utilities: modules, profiles, processes helpers'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Confirm-ModuleInstalled',
        'Set-PsExtension',
        'Add-CxxuPsModuleToProfile',
        'Add-CxxuPsModuleToEnvVar',
        'Head',
        'Tail',
        'Get-TypeCxxu',
        'Get-ParametersList',
        'New-ModuleByCxxu',
        'Test-SudoAvailability',
        'Import-ModuleForce',
        'ipmof',
        'Get-PathType',
        'Get-PsProfilesPath',
        'Remove-PsProfiles',
        'Confirm-PsVersion',
        'Install-ScoopByLocalProxy',
        'Set-Owner',
        'Grant-PermissionToPath',
        'Get-PipelineInput',
        'Get-SourceCode',
        'Operators_Comparison_pwsh',
        'Operators_Logical_pwsh',
        'Update-PowerShellLegacy',
        'Get-LatestPowerShellDownloadUrl',
        'Update-PowerShell',
        'Confirm-UserContinue',
        'Write-PsDebugLog',
        'Start-CodeSSh',
        'Remove-RobocopyMirEmpty',
        'Copy-Robocopy',
        'Sync-ModuleManifest'
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
