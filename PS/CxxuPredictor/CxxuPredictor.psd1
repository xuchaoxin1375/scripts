@{
    # 无 RootModule(故意外置):dll 活件在 $HOME/.cxxu/bin,由 loader 按哈希同步后按路径装载;
    # 按名 Import-Module CxxuPredictor 只装出空壳(不注册 predictor),必须走 Register-PsUxLazyLoad
    # 5.1 Tab-only 构建在 ps51/CxxuPredictor.dll(netstandard2.0,仅 CompleteCommand,
    # 由 CxxuTab 按字节装载;不注册 predictor)
    ModuleVersion = '1.0.5'
    GUID = '8a9a22d5-7b99-4ce4-8daf-d717be17fc68'
    Author = 'cxxu'
    Description = 'Cxxu predictors: command-name fuzzy + strict wildcard on cached names, plus static argc-completions flag hints at the first argument position'
    PowerShellVersion = '7.5'
    FunctionsToExport = @(
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
