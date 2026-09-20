<#
Json 模块:JSON 数据文件的读写与校验(从 Tools.psm1 迁入)。
init 热路径(Confirm-DataJson)与 prompt 缓存都依赖本模块，保持精简以降低首次解析成本。
#>

function Update-DataJsonLastWriteTime
{
    param (
        $DataJson = $DataJson
    )
    Update-Json -Key LastWriteTime -Value (Get-Date) -DataJson $DataJson
}

function Update-Json
{
    <# 
    .SYNOPSIS
    提供创建/修改/删除JSON文件中的配置项目的功能
    #>
    [CmdletBinding()]
    param (
        [string]$Key,
        [string]$Value,
        [switch]$Remove,
        [string][Alias('DataJson')]$Path = $DataJson
    )
    
    # 如果配置文件不存在，创建一个空的JSON文件
    if (-not (Test-Path $Path))
    {
        Write-Verbose "Configuration file '$Path' does not exist. Creating a new one."
        $emptyConfig = @{}
        $emptyConfig | ConvertTo-Json -Depth 32 | Set-Content $Path
    }

    # 读取配置文件
    $config = Get-Content $Path | ConvertFrom-Json

    if ($Remove)
    {
        if ($config.PSObject.Properties[$Key])
        {
            $config.PSObject.Properties.Remove($Key)
            Write-Verbose "Removed '$Key' from '$Path'"
        }
        else
        {
            Write-Verbose "Key '$Key' does not exist in '$Path'"
        }
    }
    else
    {
        # 检查键是否存在，并动态添加新键
        if (-not $config.PSObject.Properties[$Key])
        {
            $config | Add-Member -MemberType NoteProperty -Name $Key -Value $Value
        }
        else
        {
            $config.$Key = $Value
        }
        Write-Verbose "Updated '$Key' to '$Value' in '$Path'"
    }

    # 保存配置文件
    $config | ConvertTo-Json -Depth 32 | Set-Content $Path
}

function Confirm-DataJson
{
    <#
    .SYNOPSIS
    如果不存在默认的DataJson文件，就创建一个；如果文件损坏则备份后重建。
    .NOTES
    从 Startup.psm1 迁入：init 热路径与 prompt 缓存都依赖它，与 Get-Json/Update-Json 同模块。
    无递归设计——校验失败直接重建，不再自调用(曾经因此死循环)。
    #>
    param(
        $DataJson = $DataJson
    )
    # 守卫:$DataJson为空(未先执行Update-PwshVars时)直接定默认值,避免Test-Path/Get-Content抛错后无脑递归
    if ([string]::IsNullOrWhiteSpace($DataJson))
    {
        $DataJson = Join-Path $HOME 'Data.json'
    }
    $defaultContent = @{
        ConnectionName = '' ;
        IpPrompt       = ''
    }
    try
    {
        if (!(Test-Path -LiteralPath $DataJson))
        {
            $parent = Split-Path $DataJson -Parent
            if ($parent -and !(Test-Path -LiteralPath $parent))
            {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            $defaultContent | ConvertTo-Json | Set-Content -LiteralPath $DataJson -Encoding utf8
            return $DataJson
        }
        $jsonContent = Get-Content -LiteralPath $DataJson -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($jsonContent)) { throw 'Empty DataJson file.' }
        $null = $jsonContent | ConvertFrom-Json -ErrorAction Stop
        Write-Verbose 'The JSON file is valid.'
        return $DataJson
    }
    catch
    {
        Write-Warning "DataJson无效($DataJson): $_. 正在重建."
        try
        {
            $bak = "$DataJson.bak.$((Get-Date).ToString('yyyy-MM-dd--HH-mm-ss'))"
            Move-Item -LiteralPath $DataJson -Destination $bak -Force -ErrorAction SilentlyContinue
            $defaultContent | ConvertTo-Json | Set-Content -LiteralPath $DataJson -Encoding utf8 -ErrorAction Stop
        }
        catch
        {
            Write-Error "重建DataJson失败: $_"
        }
        return $DataJson
    }
}

function Get-Json
{
    <#
.SYNOPSIS
    Reads a specific property from a JSON string or JSON file. If no property is specified, returns the entire JSON object.
    调用powershell中的ConvertFrom-Json cmdlet处理

.DESCRIPTION
    This function reads a JSON string or JSON file and extracts the value of a specified property. If no property is specified, it returns the entire JSON object.

.PARAMETER JsonInput
    The JSON string or the path to the JSON file.

.PARAMETER Property
    The path to the property whose value needs to be extracted, using dot notation for nested properties.
.EXAMPLE
从多行字符串(符合json格式)中提取JSON属性
#从文件中读取并通过管道符传递时需要使用-Raw选项,否则无法解析json
PS> cat "$home/Data.json" -Raw |Get-Json

ConnectionName IpPrompt
-------- --------
         xxx
 
PS> cat $DataJson -Raw |Get-Json -property IpPrompt
xxx

.EXAMPLE
    Get-Json -JsonInput '{"name": "John", "age": 30}' -Property "name"

    This command extracts the value of the "name" property from the provided JSON string.

.EXAMPLE
    Get-Json -JsonInput "data.json" -Property "user.address.city"

    This command extracts the value of the nested "city" property from the provided JSON file.

.EXAMPLE
    Get-Json -JsonInput '{"name": "John", "age": 30}'

    This command returns the entire JSON object.

.NOTES
    Author: Your Name
    Date: YYYY-MM-DD
#>

    [CmdletBinding()]
    param (
        [Parameter(   ValueFromPipeline = $true)]
        [Alias('DataJson', 'JsonFile', 'Path', 'File')]$JsonInput = $DataJson,

        [Parameter(Position = 0)]
        [string][Alias('Property')]$Key
    )

    process
    {
    # 读取JSON内容

    $jsonContent = if (Test-Path $JsonInput)
    {
        Get-Content -Path $JsonInput -Raw | ConvertFrom-Json
    }
    else
    {
        $JsonInput | ConvertFrom-Json
    }
    # Write-Host $jsonContent

     

    # 如果没有指定属性，则返回整个JSON对象
    if (-not $Key)
    {
        return $jsonContent
    }

    # 提取指定属性的值
    try
    {
        # TODO
        $KeyValue = $jsonContent | Select-Object -ExpandProperty $Key
        # Write-Verbose $KeyValue
        return $KeyValue
    }
    catch
    {
        Write-Error "Failed to extract the property value for '$Key'."
    }
    }
}

function Get-JsonItemCompleter
{
    param(
        $commandName, 
        $parameterName,
        $wordToComplete,
        $commandAst,
        $fakeBoundParameters
        # $cursorPosition
    )
    if ($fakeBoundParameters.containskey('JsonInput'))
    {
        $Json = $fakeBoundParameters['JsonInput']
    
    }
    else
    {
        $Json = $DataJson
    }
    $res = Get-Content $Json | ConvertFrom-Json
    $Names = $res | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    $Names = $Names | Where-Object { $_ -like "$wordToComplete*" }
    foreach ($name in $Names)
    {
        $value = $res | Select-Object $name | Format-List | Out-String
        # $value = Get-Json -JsonInput $Json $name |Out-String
        if (! $value)
        {
            $value = 'Error:Nested property expand failed'
        }

        [System.Management.Automation.CompletionResult]::new($name, $name, 'ParameterValue', $value.ToString())
    }
}
