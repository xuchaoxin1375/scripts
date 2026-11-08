<#
.SYNOPSIS
把补全栈依赖按上游版本转存到 GitHub 仓库（默认 xuchaoxin1375/scripts-deps）。

.DESCRIPTION
按“解析版本 → 下载并校验 → 建 Release 并上传 → 更新 SOURCES.md”四步执行，只转存 Windows x86_64 产物。
默认取各上游最新 release；`argc-completions` 没有 release，取 main 分支快照并按提交日期打 tag。
tag 规则为 `<工具>-<上游 tag>`（如 `argc-v1.24.0`），快照为 `argc-completions-main-<yyyyMMdd>`。

每个 Release 附带 `LICENSE` 与 `SHA256SUMS`；上传前核对文件大小与 SHA-256，大小不符即中止。
已存在的 Release 与资产默认跳过，`-Force` 才重新上传同名资产。

完成后打印一段版本钉子，需要手动同步到 `PS/DevEnv/DevEnv.psm1` 的 `Get-CxxuDepsMirrorAsset`，
否则部署脚本仍会拉旧版本。

.PARAMETER Tool
只处理列出的工具，可选 `argc`、`yq`、`fzf`、`zoxide`、`argc-completions`。默认全部。

.PARAMETER Version
覆盖上游版本，键为工具名、值为 tag（如 `@{ argc = 'v1.24.1' }`）。默认查各上游最新 release。

.PARAMETER Owner
转存仓库的所有者，默认 `xuchaoxin1375`。

.PARAMETER Repo
转存仓库名，默认 `scripts-deps`。

.PARAMETER TokenFile
从文件读取 GitHub token；默认依次读 `GITHUB_TOKEN`、`GH_TOKEN`，再读该文件。
`-WhatIf` 不写远端时可以不带 token。

.PARAMETER Proxy
本次下载使用的代理；未指定时读取 `HTTPS_PROXY`、`HTTP_PROXY`、`ALL_PROXY`。

.PARAMETER NoProxy
强制直连，忽略 `-Proxy` 与代理环境变量。

.PARAMETER WorkDir
下载与打包的临时目录；默认系统临时目录下的 `cxxu-deps-mirror`，已下载且大小一致的文件会复用。

.PARAMETER SkipSources
只传 Release 资产，不更新仓库根目录的 `SOURCES.md`。

.PARAMETER Force
同名资产已存在时也重新上传。

.PARAMETER WhatIf
只打印计划，不下载、不建 Release、不改 `SOURCES.md`。

.EXAMPLE
Sync-GithubDepsMirror.ps1 -WhatIf

.EXAMPLE
Sync-GithubDepsMirror.ps1 -Tool argc,yq

.EXAMPLE
Sync-GithubDepsMirror.ps1 -Version @{ argc = 'v1.24.1' } -Proxy http://127.0.0.1:7897

.NOTES
只做原样转存，不修改二进制；上游版权与许可证随各 Release 的 LICENSE 一并保留。
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
param(
    [ValidateSet('argc', 'yq', 'fzf', 'zoxide', 'argc-completions')]
    [string[]]$Tool = @('argc', 'yq', 'fzf', 'zoxide', 'argc-completions'),
    [hashtable]$Version = @{},
    [string]$Owner = 'xuchaoxin1375',
    [string]$Repo = 'scripts-deps',
    [string]$TokenFile = (Join-Path (Join-Path $env:TEMP 'opencode') 'gh_token.txt'),
    [string]$Proxy = '',
    [switch]$NoProxy,
    [string]$WorkDir = (Join-Path (Join-Path $env:TEMP 'opencode') 'deps-mirror'),
    [switch]$SkipSources,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

$catalog = @(
    [pscustomobject]@{
        Tool = 'argc'; Repo = 'sigoden/argc'
        AssetPattern = '^argc-v?{ver}-x86_64-pc-windows-msvc\.zip$'
        Licenses = @('LICENSE-APACHE', 'LICENSE-MIT')
    }
    [pscustomobject]@{
        Tool = 'yq'; Repo = 'mikefarah/yq'
        AssetPattern = '^(yq_windows_amd64\.exe|checksums)$'
        Licenses = @('LICENSE')
    }
    [pscustomobject]@{
        Tool = 'fzf'; Repo = 'junegunn/fzf'
        AssetPattern = '^(fzf-{ver}-windows_amd64\.zip|fzf_{ver}_checksums\.txt)$'
        Licenses = @('LICENSE')
    }
    [pscustomobject]@{
        Tool = 'zoxide'; Repo = 'ajeetdsouza/zoxide'
        AssetPattern = '^zoxide-{ver}-x86_64-pc-windows-msvc\.zip$'
        Licenses = @('LICENSE')
    }
)

function Get-ProxyUrl
{
    if ($NoProxy) { return '' }
    if (-not [string]::IsNullOrWhiteSpace($Proxy)) { return $Proxy.Trim() }
    foreach ($name in @('HTTPS_PROXY', 'https_proxy', 'HTTP_PROXY', 'http_proxy', 'ALL_PROXY', 'all_proxy'))
    {
        $value = [Environment]::GetEnvironmentVariable($name)
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value.Trim() }
    }
    return ''
}

$proxyUrl = Get-ProxyUrl
if ($proxyUrl) { Write-Host ("代理：{0}" -f $proxyUrl) }

$token = ''
foreach ($name in @('GITHUB_TOKEN', 'GH_TOKEN'))
{
    $value = [Environment]::GetEnvironmentVariable($name)
    if (-not [string]::IsNullOrWhiteSpace($value)) { $token = $value.Trim(); break }
}
if (-not $token -and (Test-Path -LiteralPath $TokenFile))
{
    $token = (Get-Content -LiteralPath $TokenFile -Raw).Trim()
}
if (-not $token -and -not $WhatIfPreference)
{
    throw "未找到 GitHub token：请设置 `$env:GITHUB_TOKEN，或写入 $TokenFile"
}

$apiHeaders = @{
    Accept                 = 'application/vnd.github+json'
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent'           = 'cxxu-deps-mirror'
}
if ($token) { $apiHeaders.Authorization = "Bearer $token" }

function Invoke-Api
{
    param([string]$Method, [string]$Uri, $Body, [switch]$AllowNotFound)
    $p = @{ Method = $Method; Uri = $Uri; Headers = $apiHeaders; TimeoutSec = 60 }
    if ($proxyUrl) { $p.Proxy = $proxyUrl }
    if ($null -ne $Body)
    {
        $p.ContentType = 'application/json; charset=utf-8'
        $p.Body = ($Body | ConvertTo-Json -Depth 5 -Compress)
    }
    try { return Invoke-RestMethod @p }
    catch
    {
        if ($AllowNotFound -and $_.Exception.Response -and [int]$_.Exception.Response.StatusCode -eq 404) { return $null }
        throw
    }
}

function Save-File
{
    param([string]$Uri, [string]$OutFile, [hashtable]$Headers = @{})
    $p = @{ Uri = $Uri; OutFile = $OutFile; Headers = $Headers; TimeoutSec = 600 }
    if ($proxyUrl) { $p.Proxy = $proxyUrl }
    Invoke-WebRequest @p | Out-Null
}

if (-not (Test-Path -LiteralPath $WorkDir)) { New-Item -ItemType Directory -Path $WorkDir -Force | Out-Null }
$stamp = (Get-Date).ToString('yyyy-MM-dd')
$manifest = @()
$pins = @()
$failed = @()

foreach ($entry in @($catalog | Where-Object { $Tool -contains $_.Tool }))
{
    Write-Host ("== {0}" -f $entry.Tool)
    $upstreamTag = $Version[$entry.Tool]
    if (-not $upstreamTag)
    {
        $latest = Invoke-Api -Method GET -Uri "https://api.github.com/repos/$($entry.Repo)/releases/latest"
        $upstreamTag = $latest.tag_name
    }
    $ver = $upstreamTag -replace '^v', ''
    $tag = "$($entry.Tool)-$upstreamTag"
    $pattern = $entry.AssetPattern -replace '\{ver\}', [regex]::Escape($ver)
    Write-Host ("   上游版本 {0}；本仓库 tag {1}" -f $upstreamTag, $tag)

    $release = Invoke-Api -Method GET -Uri "https://api.github.com/repos/$($entry.Repo)/releases/tags/$upstreamTag" -AllowNotFound
    if (-not $release) { Write-Warning ("{0}：上游没有 tag {1}" -f $entry.Tool, $upstreamTag); $failed += $entry.Tool; continue }
    $assets = @($release.assets | Where-Object { $_.name -match $pattern })
    if (-not $assets.Count) { Write-Warning ("{0}：上游未匹配到资产 {1}" -f $entry.Tool, $pattern); $failed += $entry.Tool; continue }

    if ($WhatIfPreference)
    {
        Write-Host ("   计划：创建 Release {0} 并上传 {1}" -f $tag, (($assets | ForEach-Object { $_.name }) -join '、'))
        continue
    }

    $files = @()
    foreach ($asset in $assets)
    {
        $out = Join-Path $WorkDir $asset.name
        if (-not (Test-Path -LiteralPath $out) -or (Get-Item -LiteralPath $out).Length -ne $asset.size)
        {
            Write-Host ("   下载 {0}（{1:N2} MB）" -f $asset.name, ($asset.size / 1MB))
            Save-File -Uri $asset.url -OutFile $out -Headers @{ Authorization = "Bearer $token"; Accept = 'application/octet-stream'; 'User-Agent' = 'cxxu-deps-mirror' }
        }
        $actual = (Get-Item -LiteralPath $out).Length
        if ($actual -ne $asset.size) { throw ("{0} 大小不符：{1} != {2}" -f $asset.name, $actual, $asset.size) }
        $files += [pscustomobject]@{
            Name = $asset.name; Path = $out; Size = $actual
            Sha256 = (Get-FileHash -LiteralPath $out -Algorithm SHA256).Hash.ToLowerInvariant()
            SourceUrl = $asset.browser_download_url
        }
    }

    foreach ($lic in $entry.Licenses)
    {
        $licPath = Join-Path $WorkDir ("lic-{0}-{1}" -f $entry.Tool, $lic)
        $licUrl = "https://raw.githubusercontent.com/$($entry.Repo)/$upstreamTag/$lic"
        try
        {
            # 已下载过的许可证直接复用，避免网络抖动让本次 SOURCES.md 少一行
            if (-not (Test-Path -LiteralPath $licPath) -or (Get-Item -LiteralPath $licPath).Length -eq 0)
            {
                Save-File -Uri $licUrl -OutFile $licPath
            }
            $files += [pscustomobject]@{
                Name = $lic; Path = $licPath; Size = (Get-Item -LiteralPath $licPath).Length
                Sha256 = (Get-FileHash -LiteralPath $licPath -Algorithm SHA256).Hash.ToLowerInvariant()
                SourceUrl = $licUrl
            }
        }
        catch { Write-Warning ("{0}：{1} 下载失败：{2}" -f $entry.Tool, $lic, $_.Exception.Message) }
    }

    $sumText = (($files | ForEach-Object { "$($_.Sha256)  $($_.Name)" }) -join "`n") + "`n"
    $sumPath = Join-Path $WorkDir ("SHA256SUMS-" + $entry.Tool)
    [IO.File]::WriteAllText($sumPath, $sumText, [Text.UTF8Encoding]::new($false))
    $files += [pscustomobject]@{
        Name = 'SHA256SUMS'; Path = $sumPath; Size = (Get-Item -LiteralPath $sumPath).Length
        Sha256 = (Get-FileHash -LiteralPath $sumPath -Algorithm SHA256).Hash.ToLowerInvariant(); SourceUrl = ''
    }

    if ($PSCmdlet.ShouldProcess("$Owner/$Repo", ("创建 Release {0} 并上传 {1} 个资产" -f $tag, $files.Count)))
    {
        $existing = Invoke-Api -Method GET -Uri "https://api.github.com/repos/$Owner/$Repo/releases/tags/$tag" -AllowNotFound
        if ($existing) { $releaseInfo = $existing; Write-Host "   Release 已存在" }
        else
        {
            $body = @"
上游仓库：https://github.com/$($entry.Repo)
上游版本：$upstreamTag
转存时间：$stamp
平台：Windows x86_64

本 Release 仅做原样转存，未修改二进制。许可证见资产中的 LICENSE 文件，校验见 SHA256SUMS。
"@
            $releaseInfo = Invoke-Api -Method POST -Uri "https://api.github.com/repos/$Owner/$Repo/releases" -Body @{
                tag_name = $tag; name = "$($entry.Tool) $upstreamTag (Windows x86_64)"; body = $body
                draft = $false; prerelease = $false; make_latest = 'false'
            }
            Write-Host ("   已建 Release：{0}" -f $releaseInfo.html_url)
        }

        $existingNames = @($releaseInfo.assets | ForEach-Object { $_.name })
        foreach ($file in $files)
        {
            if (($existingNames -contains $file.Name) -and -not $Force)
            {
                Write-Host ("   已存在，跳过：{0}" -f $file.Name)
                continue
            }
            $uploadUri = "https://uploads.github.com/repos/$Owner/$Repo/releases/$($releaseInfo.id)/assets?name=$([uri]::EscapeDataString($file.Name))"
            $p = @{
                Method = 'POST'; Uri = $uploadUri; Headers = $apiHeaders
                ContentType = 'application/octet-stream'; InFile = $file.Path; TimeoutSec = 600
            }
            if ($proxyUrl) { $p.Proxy = $proxyUrl }
            Invoke-RestMethod @p | Out-Null
            Write-Host ("   已上传：{0}（{1:N2} MB）" -f $file.Name, ($file.Size / 1MB))
        }
    }
    else
    {
        Write-Host ("   计划：创建 Release {0} 并上传 {1} 个资产" -f $tag, $files.Count)
    }

    foreach ($file in $files)
    {
        $manifest += [pscustomobject]@{
            Tool = $entry.Tool; Repo = $entry.Repo; UpstreamTag = $upstreamTag; Tag = $tag
            Name = $file.Name; Size = $file.Size; Sha256 = $file.Sha256
        }
    }
    $pins += [pscustomobject]@{ Tool = $entry.Tool; Tag = $tag; Assets = ($files | Where-Object { $_.Name -match '\.(zip|exe|msi|tar\.gz)$' } | ForEach-Object { $_.Name }) }
}

if ($Tool -contains 'argc-completions')
{
    Write-Host '== argc-completions'
    $commit = Invoke-Api -Method GET -Uri 'https://api.github.com/repos/sigoden/argc-completions/commits/main'
    $commitDate = ([datetime]$commit.commit.committer.date).ToString('yyyyMMdd')
    $tag = "argc-completions-main-$commitDate"
    $zipName = "argc-completions-main-$($commit.sha.Substring(0, 8)).zip"
    $zipPath = Join-Path $WorkDir $zipName
    $licPath = Join-Path $WorkDir 'lic-argc-completions-LICENSE'
    Write-Host ("   提交 {0}，tag {1}" -f $commit.sha.Substring(0, 8), $tag)
    if ($WhatIfPreference)
    {
        Write-Host ("   计划：创建 Release {0} 并上传 {1}、LICENSE、SHA256SUMS" -f $tag, $zipName)
    }
    else
    {
        try
        {
            if (-not (Test-Path -LiteralPath $zipPath))
            {
                Save-File -Uri 'https://codeload.github.com/sigoden/argc-completions/zip/refs/heads/main' -OutFile $zipPath
            }
            $files = @([pscustomobject]@{
                    Name = $zipName; Path = $zipPath; Size = (Get-Item -LiteralPath $zipPath).Length
                    Sha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    SourceUrl = 'https://github.com/sigoden/argc-completions/archive/refs/heads/main.zip'
                })
            try
            {
                Save-File -Uri 'https://raw.githubusercontent.com/sigoden/argc-completions/main/LICENSE' -OutFile $licPath
                $files += [pscustomobject]@{
                    Name = 'LICENSE'; Path = $licPath; Size = (Get-Item -LiteralPath $licPath).Length
                    Sha256 = (Get-FileHash -LiteralPath $licPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    SourceUrl = 'https://raw.githubusercontent.com/sigoden/argc-completions/main/LICENSE'
                }
            }
            catch { Write-Warning ("argc-completions：LICENSE 下载失败：{0}" -f $_.Exception.Message) }

            $sumPath = Join-Path $WorkDir 'SHA256SUMS-argc-completions'
            [IO.File]::WriteAllText($sumPath, ((($files | ForEach-Object { "$($_.Sha256)  $($_.Name)" }) -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
            $files += [pscustomobject]@{
                Name = 'SHA256SUMS'; Path = $sumPath; Size = (Get-Item -LiteralPath $sumPath).Length
                Sha256 = (Get-FileHash -LiteralPath $sumPath -Algorithm SHA256).Hash.ToLowerInvariant(); SourceUrl = ''
            }

            $existing = Invoke-Api -Method GET -Uri "https://api.github.com/repos/$Owner/$Repo/releases/tags/$tag" -AllowNotFound
            if ($existing) { $releaseInfo = $existing; Write-Host '   Release 已存在' }
            else
            {
                $releaseInfo = Invoke-Api -Method POST -Uri "https://api.github.com/repos/$Owner/$Repo/releases" -Body @{
                    tag_name = $tag; name = "argc-completions main @ $commitDate"
                    body = "上游仓库：https://github.com/sigoden/argc-completions`n提交：$($commit.sha)`n提交时间：$($commit.commit.committer.date)`n转存时间：$stamp`n`n分支快照，仅做原样转存。"
                    draft = $false; prerelease = $false; make_latest = 'false'
                }
                Write-Host ("   已建 Release：{0}" -f $releaseInfo.html_url)
            }
            $existingNames = @($releaseInfo.assets | ForEach-Object { $_.name })
            foreach ($file in $files)
            {
                if (($existingNames -contains $file.Name) -and -not $Force) { Write-Host ("   已存在，跳过：{0}" -f $file.Name); continue }
                $p = @{
                    Method = 'POST'; Uri = "https://uploads.github.com/repos/$Owner/$Repo/releases/$($releaseInfo.id)/assets?name=$([uri]::EscapeDataString($file.Name))"
                    Headers = $apiHeaders; ContentType = 'application/octet-stream'; InFile = $file.Path; TimeoutSec = 600
                }
                if ($proxyUrl) { $p.Proxy = $proxyUrl }
                Invoke-RestMethod @p | Out-Null
                Write-Host ("   已上传：{0}（{1:N2} MB）" -f $file.Name, ($file.Size / 1MB))
            }

            foreach ($file in $files)
            {
                $manifest += [pscustomobject]@{
                    Tool = 'argc-completions'; Repo = 'sigoden/argc-completions'; UpstreamTag = 'main'; Tag = $tag
                    Name = $file.Name; Size = $file.Size; Sha256 = $file.Sha256
                }
            }
            $pins += [pscustomobject]@{ Tool = 'argc-completions'; Tag = $tag; Assets = @($zipName) }
        }
        catch { Write-Warning ("argc-completions 处理失败：{0}" -f $_.Exception.Message); $failed += 'argc-completions' }
    }
}

if (-not $SkipSources -and $manifest.Count -gt 0 -and -not $PSBoundParameters.ContainsKey('Tool'))
{
    $md = New-Object Text.StringBuilder
    [void]$md.AppendLine('# 转存来源')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('本仓库按上游版本转存 `scripts` 仓库部署时会用到的二进制，未做修改。每个 Release 附带 `LICENSE` 与 `SHA256SUMS`。')
    [void]$md.AppendLine('')
    [void]$md.AppendLine("最近更新：$stamp")
    [void]$md.AppendLine('')
    [void]$md.AppendLine('| 工具 | 上游 | 上游版本 | 本仓库 Tag | 资产 | 大小 | SHA-256 |')
    [void]$md.AppendLine('|---|---|---|---|---|---|---|')
    foreach ($row in ($manifest | Sort-Object Tool, Name))
    {
        [void]$md.AppendLine(("| {0} | {1} | {2} | {3} | {4} | {5:N2} MB | {6} |" -f $row.Tool, $row.Repo, $row.UpstreamTag, $row.Tag, $row.Name, ($row.Size / 1MB), $row.Sha256))
    }
    [void]$md.AppendLine('')
    [void]$md.AppendLine('## 用法')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('```text')
    [void]$md.AppendLine("https://github.com/$Owner/$Repo/releases/download/<tag>/<asset>")
    [void]$md.AppendLine('```')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('## 说明')
    [void]$md.AppendLine('')
    [void]$md.AppendLine('- 仅转存 Windows x86_64 产物；其他平台请直接使用上游 Release。')
    [void]$md.AppendLine('- 版本固定，不自动跟随上游；需要新版本时新增 tag，旧版本保留可回滚。')
    [void]$md.AppendLine('- 二进制版权归上游作者所有，分发遵循各 Release 内 LICENSE。')

    if ($PSCmdlet.ShouldProcess("$Owner/$Repo", '更新 SOURCES.md'))
    {
        $bytes = [Text.Encoding]::UTF8.GetBytes($md.ToString())
        $existingFile = Invoke-Api -Method GET -Uri "https://api.github.com/repos/$Owner/$Repo/contents/SOURCES.md" -AllowNotFound
        $body = @{ message = "docs: 更新转存来源（$stamp）"; content = [Convert]::ToBase64String($bytes); branch = 'main' }
        if ($existingFile) { $body.sha = $existingFile.sha }
        $res = Invoke-Api -Method PUT -Uri "https://api.github.com/repos/$Owner/$Repo/contents/SOURCES.md" -Body $body
        Write-Host ("SOURCES.md 已更新：{0}" -f $res.content.html_url)
    }
}

if ($pins.Count -gt 0)
{
    Write-Host ''
    if ($PSBoundParameters.ContainsKey('Tool'))
    {
        Write-Host '按 -Tool 只处理了部分工具：未改 SOURCES.md，需要完整刷新时去掉 -Tool 再跑。'
    }
    Write-Host '把下面这段同步到 PS/DevEnv/DevEnv.psm1 的 Get-CxxuDepsMirrorAsset，部署脚本才会用新版本：'
    Write-Host ''
    foreach ($pin in $pins)
    {
        $asset = @($pin.Assets)[0]
        Write-Host ("        {0} = @{{ Tag = '{1}'; X64 = '{2}' }}" -f $pin.Tool, $pin.Tag, $asset)
    }
}

Write-Host ''
if ($failed.Count) { Write-Warning ("失败项：{0}" -f ($failed -join '、')); exit 1 }
Write-Host ("完成：{0} 个资产，共 {1:N2} MB" -f $manifest.Count, (($manifest | Measure-Object Size -Sum).Sum / 1MB))
