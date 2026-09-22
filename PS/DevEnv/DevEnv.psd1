@{
    RootModule = 'DevEnv.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'd417f649-d5ce-48ce-82f7-e980051d43a0'
    Author = 'cxxu'
    Description = 'Language toolchains and editors setup: Python/conda/C++/editors/completion'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Install-BasicSoftwares',
        'Deploy-Python',
        'Deploy-CppVscodeThere',
        'Deploy-PipConfig',
        'Deploy-UvConfig',
        'Deploy-AndroidStudio_depends',
        'Deploy-Typora',
        'Deploy-GitConfig',
        'Deploy-VsCodeSettings_depends',
        'Deploy-WtSettings',
        'Deploy-MiniforgeConfig',
        'Deploy-CompletionStack'
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
