@{
    RootModule = 'backup.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'd182d545-4779-453f-9be1-29ed789acfe0'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: backup'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Backup-ScoopApps',
        'Backup-Shortcuts',
        'Deploy-Shortcuts',
        'Backup-UserConfig',
        'Backup-CppVscode',
        'Backup-PicgoConfig',
        'Backup-TyporaConf',
        'Backup-VsCodeSettings',
        'Backup-GitConfig',
        'Backup-WtSettings',
        'Backup-PwshProfile',
        'Backup-EnvsRegistry',
        'Backup-EnvsByPwsh',
        'Backup-Links'
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
