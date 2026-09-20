@{
    RootModule = 'SSH.psm1'
    ModuleVersion = '1.0.4'
    GUID = '93a30c37-caa2-44a3-9b18-d5133bda955f'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: SSH'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Enable-SSHPubkeyAuthentication',
        'Get-SSHPubKeysAdderScripts',
        'Get-SSHPubKeysPushScripts',
        'Set-SSHServerInit',
        'Set-SSHClientInit',
        'Get-SSHPreRunPubkeyVarsScript',
        'New-SSHKeyPairs',
        'Deploy-SSHVersionWin32Zip',
        'Set-SSHDefaultShell'
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
