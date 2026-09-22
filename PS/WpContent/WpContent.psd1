@{
    RootModule = 'WpContent.psm1'
    ModuleVersion = '1.0.4'
    GUID = '2fe8b447-04fd-461b-9947-bdee9af4538a'
    Author = 'cxxu'
    Description = 'WordPress content: images/shopify scrape/SQL batch'
    PowerShellVersion = '5.1' # B档兼容集:5.1 可用(其余模块保持 7.0)
    FunctionsToExport = @(
        'Move-ItemImagesFromCsvPathFields',
        'Get-WpImages',
        'Import-WpSqlBatch',
        'Get-XXXShopifyProductJsonUrlArchived',
        'Get-ShopifyProductJsonUrl',
        'Get-WpSitesLocalImagesCount'
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
