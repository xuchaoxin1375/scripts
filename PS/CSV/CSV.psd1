@{
    RootModule = 'CSV.psm1'
    ModuleVersion = '1.0.4'
    GUID = 'ec209d9e-b173-4ee7-951c-f6ee628e8a3f'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: CSV'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Get-CsvTailRowsArchived',
        'Get-CsvPreview',
        'Get-CsvTailRows',
        'Get-CsvTailRowsGUI',
        'Export-NewCSVFile',
        'Export-CsvSplitFiles',
        'Export-NewCSVFilesFromSKU',
        'Export-NewCSvFromRange',
        'Get-CsvRowsByPercentage'
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
