# Cxxu PS 模块集的 PSScriptAnalyzer 配置
# 用法: Invoke-ScriptAnalyzer -Path PS/<模块>/ -Settings PS/PSScriptAnalyzerSettings.psd1
# Error 必须清零;Warning 允许“已接受偏差”(见下),其余应修或在规范文档登记。
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # prompt 渲染必须用 Write-Host(颜色/NoNewline 是刚需),全仓库有意为之。
        'PSAvoidUsingWriteHost',
        # 本模块集仅支持 PS7(各 manifest PowerShellVersion = 7.0),无 BOM 的 UTF-8 即正确编码;
        # 加 BOM 会造成全仓库换行级 diff,收益为负。
        'PSUseBOMForUnicodeEncodedFile'
    )
    Rules        = @{}
}
