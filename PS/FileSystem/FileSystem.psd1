@{
    RootModule = 'FileSystem.psm1'
    ModuleVersion = '1.0.4'
    GUID = '62949e73-dd5d-416a-bc20-bec551e97a34'
    Author = 'cxxu'
    Description = 'File and directory measurement and helpers'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Add-Extension',
        'Get-NonEmptySubdirectories',
        'Remove-EmptyDirectories',
        'Get-PsIOItemInfo',
        'Get-Size',
        'Get-ItemSizeSorted',
        'Get-ChildItemNameQuatation',
        'Test-DirectoryEmpty'
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
