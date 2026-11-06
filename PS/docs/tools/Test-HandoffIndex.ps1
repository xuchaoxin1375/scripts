<#
.SYNOPSIS
校验 Agent-Handoff 索引与归档是否一致。

.DESCRIPTION
只读检查，不改任何文件。检查项：
- 索引行格式统一（ID / 链接 / 效力 / 位置 / 日期 五列）
- ID 在索引内唯一，链接指向归档的对应锚点
- 效力取值合法（现行 / 已废止 / —），`已废止` 必须写指针
- 位置以 主题文档 / 索引 / 指针 开头；`主题文档` 的链接目标必须存在
- 索引 ID 集合与归档 `#### #N` 小节集合完全一致，归档小节正文非空
- 文档内本地链接目标存在
- 不再出现已退役的状态词（已沉淀 / 考古）

退出码：0 通过（警告不算失败）；1 有错误（或 `-Strict` 下有警告）；2 目录或文件缺失。
PowerShell 5.1 与 7 行为一致。

.PARAMETER DocsRoot
docs 目录。默认取脚本所在目录的上一级（脚本放在 docs/tools 下）。

.PARAMETER Strict
把警告也当失败。

.PARAMETER CheckSectionText
额外核对位置列「节」文本是否出现在归属文档中。属启发式检查，节名改写也会报，
默认关闭。

.EXAMPLE
pwsh -NoProfile -File PS/docs/tools/Test-HandoffIndex.ps1

.EXAMPLE
powershell -NoProfile -File PS/docs/tools/Test-HandoffIndex.ps1 -Strict
#>
[CmdletBinding()]
param(
    [string]$DocsRoot = '',
    [switch]$Strict,
    [switch]$CheckSectionText
)

$ErrorActionPreference = 'Stop'
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Add-Error([string]$message)
{
    $errors.Add($message)
}

function Add-Warning([string]$message)
{
    $warnings.Add($message)
}

if (-not $DocsRoot)
{
    $DocsRoot = Split-Path -Parent $PSScriptRoot
}
$DocsRoot = $DocsRoot.TrimEnd('\', '/')
if (-not (Test-Path -LiteralPath $DocsRoot))
{
    Write-Host "[错误] docs 目录不存在：$DocsRoot" -ForegroundColor Red
    exit 2
}

$handoffPath = Join-Path $DocsRoot 'Agent-Handoff.md'
$archivePath = Join-Path $DocsRoot 'archive\agent-handoff-history.md'
foreach ($p in @($handoffPath, $archivePath))
{
    if (-not (Test-Path -LiteralPath $p))
    {
        Write-Host "[错误] 缺少文件：$p" -ForegroundColor Red
        exit 2
    }
}

$linkPattern = '\[[^\]]*\]\(([^)]+)\)'
$pointerPattern = '^→\s*#(\d+)$'
$effects = @('现行', '已废止', '—')

$rows = New-Object System.Collections.Generic.List[object]
$handoffLines = [IO.File]::ReadAllLines($handoffPath)
for ($i = 0; $i -lt $handoffLines.Count; $i++)
{
    $line = $handoffLines[$i]
    $lineNo = $i + 1
    if ($line -match '^\s*\|\s*\[#\d+\]')
    {
        # 按未转义的竖线切列（\| 属于单元格内容）
        $cells = [regex]::Split($line.Trim(), '(?<!\\)\|')
        if ($cells.Count -ne 7)
        {
            Add-Error "索引行列数不符（第 $lineNo 行）：期望 5 列，实际 $($cells.Count - 2) 列；竖线请写成 \|"
            continue
        }
        $idCell = $cells[1].Trim()
        if ($idCell -notmatch '^\[#(\d+)\]\(([^)]+)\)$')
        {
            Add-Error "索引行 ID 列格式不符（第 $lineNo 行）：$idCell"
            continue
        }
        $rows.Add([pscustomobject]@{
                Id     = [int]$matches[1]
                Link   = $matches[2]
                Title  = ($cells[2].Trim() -replace '\\\|', '|')
                Effect = $cells[3].Trim()
                Place  = $cells[4].Trim()
                Date   = $cells[5].Trim()
                LineNo = $lineNo
            })
    }
}

if ($rows.Count -eq 0)
{
    Add-Error '没有解析到任何索引行（表头或格式可能已改）'
}

# ID 唯一
$seen = @{}
foreach ($r in $rows)
{
    if ($seen.ContainsKey($r.Id))
    {
        Add-Error "ID 重复：#$($r.Id)（第 $($seen[$r.Id]) 行与第 $($r.LineNo) 行）"
    }
    else
    {
        $seen[$r.Id] = $r.LineNo
    }
}

# 逐行校验
foreach ($r in $rows)
{
    $expectLink = "archive/agent-handoff-history.md#$($r.Id)"
    if ($r.Link -ne $expectLink)
    {
        Add-Error "#$($r.Id) 链接应为 $expectLink，实际 $($r.Link)"
    }

    if ($effects -notcontains $r.Effect)
    {
        Add-Error "#$($r.Id) 效力取值非法：$($r.Effect)（只允许 现行 / 已废止 / —）"
    }

    switch ($r.Effect)
    {
        '现行'
        {
            if ($r.Place -match $pointerPattern)
            {
                Add-Error "#$($r.Id) 效力为现行，位置却是指针：$($r.Place)"
            }
        }
        '已废止'
        {
            if ($r.Place -notmatch $pointerPattern)
            {
                Add-Error "#$($r.Id) 效力为已废止，位置必须写指针（→ #N），实际：$($r.Place)"
            }
            else
            {
                $target = [int]$matches[1]
                if (-not $seen.ContainsKey($target))
                {
                    Add-Error "#$($r.Id) 指向不存在的条目：#$target"
                }
            }
        }
    }

    if ($r.Place -notmatch '^(主题文档：|索引|→\s*#\d+)')
    {
        Add-Error "#$($r.Id) 位置须以 主题文档 / 索引 / 指针 开头，实际：$($r.Place)"
    }

    if ($r.Place -match '^主题文档：')
    {
        if ($r.Place -notmatch $linkPattern)
        {
            Add-Error "#$($r.Id) 位置是主题文档但没有 Markdown 链接：$($r.Place)"
        }
        else
        {
            $target = ($matches[1] -replace '#.*$', '')
            $full = Join-Path $DocsRoot $target.Replace('/', '\')
            if (-not (Test-Path -LiteralPath $full))
            {
                Add-Error "#$($r.Id) 归属文档不存在：$target"
            }
            elseif ($CheckSectionText)
            {
                if ($r.Place -notmatch '「(.+)」\s*$')
                {
                    Add-Warning "#$($r.Id) 位置没有写「节」名：$($r.Place)"
                }
                else
                {
                    $section = $matches[1] -replace '\\\|', '|'
                    $text = [IO.File]::ReadAllText($full)
                    if (-not $text.Contains($section))
                    {
                        Add-Warning "#$($r.Id) 归属文档里找不到「$section」：$target"
                    }
                }
            }
        }
    }

    if ($r.Date -ne '—' -and $r.Date -notmatch '^\d{4}-\d{2}-\d{2}$')
    {
        Add-Warning "#$($r.Id) 最后验证日期格式异常：$($r.Date)"
    }

    if ($r.Title.Trim() -eq '')
    {
        Add-Error "#$($r.Id) 结论为空"
    }
}

# 文档内本地链接
foreach ($line in $handoffLines)
{
    foreach ($m in [regex]::Matches($line, $linkPattern))
    {
        $target = $m.Groups[1].Value
        if ($target -match '^(https?|mailto):' -or $target -match '^#')
        {
            continue
        }
        $rel = ($target -replace '#.*$', '')
        if ($rel -eq '')
        {
            continue
        }
        $full = Join-Path $DocsRoot $rel.Replace('/', '\')
        if (-not (Test-Path -LiteralPath $full))
        {
            Add-Error "链接目标不存在：$rel"
        }
    }
}

# 状态词退役检查（只查表格单元格，避免误伤正文里的同名字词）
$handoffText = [IO.File]::ReadAllText($handoffPath)
foreach ($word in @('已沉淀', '考古'))
{
    if ($handoffText -match ('\|\s*' + $word + '\s*\|'))
    {
        Add-Error "索引仍在使用已退役的取值「$word」，请改成 效力 × 位置 两维写法"
    }
}

# 归档小节
$archiveLines = [IO.File]::ReadAllLines($archivePath)
$archiveIds = New-Object System.Collections.Generic.List[int]
$archiveSeen = @{}
$current = -1
$bodyCount = 0
foreach ($line in $archiveLines)
{
    if ($line -match '^####\s+#(\d+)\s*$')
    {
        if ($current -gt 0 -and $bodyCount -eq 0)
        {
            Add-Error "归档小节 #$current 正文为空"
        }
        $current = [int]$matches[1]
        if ($archiveSeen.ContainsKey($current))
        {
            Add-Error "归档小节重复：#$current"
        }
        $archiveSeen[$current] = $true
        $archiveIds.Add($current)
        $bodyCount = 0
        continue
    }
    if ($current -gt 0 -and $line.Trim() -ne '')
    {
        $bodyCount++
    }
}
if ($current -gt 0 -and $bodyCount -eq 0)
{
    Add-Error "归档小节 #$current 正文为空"
}

for ($i = 1; $i -lt $archiveIds.Count; $i++)
{
    if ($archiveIds[$i] -le $archiveIds[$i - 1])
    {
        Add-Warning "归档小节编号未严格递增：#$($archiveIds[$i - 1]) → #$($archiveIds[$i])"
        break
    }
}

$tableIds = @($rows | ForEach-Object { $_.Id })
foreach ($id in $tableIds)
{
    if (-not $archiveSeen.ContainsKey($id))
    {
        Add-Error "索引有 #$id，归档缺对应小节（#### #$id）"
    }
}
foreach ($id in $archiveIds)
{
    if (-not $seen.ContainsKey($id))
    {
        Add-Error "归档有 #$id，索引缺对应行"
    }
}

# 输出
Write-Host "检查文件：$handoffPath"
Write-Host "检查文件：$archivePath"
foreach ($m in $errors)
{
    Write-Host "[错误] $m" -ForegroundColor Red
}
foreach ($m in $warnings)
{
    Write-Host "[警告] $m" -ForegroundColor Yellow
}

$failed = $errors.Count -gt 0 -or ($Strict -and $warnings.Count -gt 0)
if ($failed)
{
    Write-Host "结果：未通过（错误 $($errors.Count) 条，警告 $($warnings.Count) 条）" -ForegroundColor Red
    exit 1
}
Write-Host "结果：通过（索引 $($rows.Count) 行，归档 $($archiveIds.Count) 个小节，警告 $($warnings.Count) 条）" -ForegroundColor Green
exit 0
