@{
    RootModule = 'Shortcut.psm1'
    ModuleVersion = '1.0.4'
    GUID = '39a2ee47-ff86-4fe5-92a1-7d00a12648f7'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Shortcut'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-ShortcutLinkInfo',
        'New-Shortcut',
        'Get-ShortcutLinkInfoBasic',
        'getShortcutTargetPath',
        'Get-ShortcutTargetDir',
        'Set-Shortcut',
        'Set-ShortcutIcons',
        'Get-ShortcutPath'
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
