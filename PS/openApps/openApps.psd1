@{
    RootModule = 'openApps.psm1'
    ModuleVersion = '1.0.4'
    GUID = '5fd59d6a-f208-4b6a-ac8b-9442892573e5'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: openApps'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Set-DefaultAppForExtension',
        'set-PsScriptDefaultRunner',
        'typora_home',
        'qq_run',
        'clash_run',
        'run_silently',
        'qq',
        'Start-ProcessSilentlyFromShortcut',
        'hostsEdit',
        'anaconda',
        'condaPrompt',
        'wireSharkPortable',
        'ept',
        'wtAs',
        'NetSpeed',
        'msys2'
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
