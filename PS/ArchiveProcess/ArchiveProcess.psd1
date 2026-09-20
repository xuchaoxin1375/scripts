@{
    RootModule = 'ArchiveProcess.psm1'
    ModuleVersion = '1.0.4'
    GUID = '4f848320-1223-45c0-acbc-25bddf3d1070'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: ArchiveProcess'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Compress-Tar',
        'Test-TarFile',
        'Compress-Lz4Package',
        'Expand-Lz4TarPackage',
        'Compress-ZstdPackage',
        'Compress-ZstdPackageDev',
        'Expand-ZstdTarPackage',
        'Expand-GzFile'
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
