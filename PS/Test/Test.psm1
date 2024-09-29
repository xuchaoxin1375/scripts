# 定义一个自定义类型
class MyCustomObject
{
    [string]$Name
    [int]$Age
    [string]$City
}

function Get-MyCustomData
{
    [OutputType([MyCustomObject[]])]
    [CmdletBinding()]
    param()

    # 创建一些示例数据
    $obj1 = [MyCustomObject]@{
        Name = 'Alice'
        Age  = 30
        City = 'New York'
    }
    $obj2 = [MyCustomObject]@{
        Name = 'Bob'
        Age  = 25
        City = 'London'
    }

    # 返回对象数组
    return @($obj1, $obj2)
}

function Get-SumOfNumbers
{
    <# 
    .SYNOPSIS
    最简单的这次管道符的powershell函数示例
    #>
    <# 
 .EXAMPLE
    PS> 1,2,3|Get-SumOfNumbers
6
    #>
    [CmdletBinding()] #对于管道符函数不是必须的,但是如果用上的话,需要注意:在使用 CmdletBinding 的情况下，process 块应使用您为管道输入定义的参数变量，而不是 $_ 或 $PSItem
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [int[]]$Numbers
    )

    begin
    { 
        $retValue = 0 
        # Write-Host "Numbers: $Numbers" 如果是管道符用法,这个阶段无法读取$Numbers参数
    }

    process
    {
        foreach ($n in $Numbers)
        {
            $retValue += $n
        }
    }

    end { $retValue }
}


function Get-SumOfNumbersTestPipeLine
{
    <# 
    .SYNOPSIS
    最简单的这次管道符的powershell函数示例
    这里不是使用prcess块,来试验处理数组管道符传递参数时的错误情形
    #>
    <# 
 .EXAMPLE
PS> 1,2,3|Get-SumOfNumbersTestPipeLine
3
    #>
    [CmdletBinding()] #对于管道符函数不是必须的
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [int[]]$Numbers
    )

    
    $retValue = 0 
    # Write-Host "Numbers: $Numbers" 如果是管道符用法,这个阶段无法读取$Numbers参数
    

    foreach ($n in $Numbers)
    {
        $retValue += $n
    }
    

    return $retValue 
}
function Get-Numbers
{
    <# 
    .SYNOPSIS
    演示SupportsPaging特性的方法,打印0~100的整数,并且支持跳过前若干个(跳过的最大数量不超过100)
    .DESCRIPTION
    对于更进一步的处理,可以使用|select -First/Last等通用方式处理
    .LINK
    
    https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions_cmdletbindingattribute?view=powershell-7.4#supportspaging
    .LINK
    https://learn.microsoft.com/zh-cn/dotnet/api/system.management.automation.pagingparameters?view=powershellsdk-7.3.0#properties
    #>
    [CmdletBinding(SupportsPaging)]
    param()

    # 确定要显示数据范围:第一个数据和和最后一个数据
    #其中FirstNumber应该是考虑到用户是否使用Skip参数,如果没有指定-skip参数,那么$PSCmdlet.PagingParameters.Skip默认取值为0
    # 和默认值100进行比较,也就是说如果用户使用Skip参数
    # 下面使用min()函数是为了防止用户指定的Skip参数值大于100,造成溢出边界的安全措施
    $FirstNumber = [Math]::Min($PSCmdlet.PagingParameters.Skip, 100)
    # 类似的,$PSCmdlet.PagingParameters.First 表示用户通过-First参数传入的数值,并且对于没有指定-First参数的情况做了默认处理,也就是取MaxValue(尽可能多的输出),本例子为了防止溢出,使用min()函数,当用户指定-First的数值超过100,就取100
    $LastNumber = [Math]::Min($PSCmdlet.PagingParameters.First +
        $FirstNumber - 1, 100)

    if ($PSCmdlet.PagingParameters.IncludeTotalCount)
    {
        $TotalCountAccuracy = 1.0
        $TotalCount = $PSCmdlet.PagingParameters.NewTotalCount(100,
            $TotalCountAccuracy)
        Write-Output $TotalCount
    }
    $FirstNumber .. $LastNumber | Write-Output
}

function Get-Upper
{
    <# 
    .SYNOPSIS
    将输入字符串转换为大写,简单演示管道符特性

    .DESCRIPTION
    在没有显式使用循环语句的情况下,对于管道传入的一个输入数组经过恰当的绑定,也能表现得像循环(或遍历可迭代元素)一样或类似的效果

    # 虽然在process块中不需要使用循环迭代接受管道符的参数(一般是容器类对象,如果是单个元素也可以正确处理,这些自动转换和处理和其他编程语言很不同)
    # 当以管道符的方式调用时,接受到的参数是个容器(比如数组)时,管道符会控制数据的传递,会以逐个元素的方式传递给管道符后的命令处理
    #声明参数为数组类型,比如[String[]]并能够兼容单个元素的情况(比如传入的参数是String对象)
    #>
    <# 
    .EXAMPLE
    普通方式调用
    PS🌙[BAT:73%][MEM:32.1% (10.18/31.71)GB][Win 11 Pro@24H2:10.0.26100.1742][17:05:19]
    # [cxxu@CXXUCOLORFUL][<W:192.168.1.154>][~\Desktop]
    PS> Get-Upper 'apple', 'banana'
    Initialization
    Processing: apple
    Processing: banana
    Finalizing
    ----------
    APPLE
    BANANA

    .EXAMPLE
    管道符方式调用
    PS🌙[BAT:73%][MEM:32.55% (10.32/31.71)GB][Win 11 Pro@24H2:10.0.26100.1742][17:09:20]
    # [cxxu@CXXUCOLORFUL][<W:192.168.1.154>][~\Desktop]
    PS> 'apple', 'banana' | Get-Upper
    Initialization
    Processing: apple
    Processing: banana
    Finalizing
    ----------
    APPLE
    BANANA
    #>
    param (
        # 将参数声明为支持作为管道的输入(并且是按值传递的管道符参数绑定)
        [Parameter( ValueFromPipeline)]
        [string[]]$InputData
    )
    
    begin
    {
        Write-Host 'Initialization'
        Write-Host '----------'
        $results = @()
    }
    
    process
    {
        # 虽然在process块中不需要使用循环迭代接受管道符的参数(一般是容器类对象,如果是单个元素也可以正确处理,这些自动转换和处理和其他编程语言很不同)
        # 当以管道符的方式调用时,接受到的参数是个容器(比如数组)时,管道符会控制数据的传递,会以逐个元素的方式传递给管道符后的命令处理
        #声明参数为数组类型,比如[String[]]并能够兼容单个元素的情况(比如传入的参数是String对象)
        foreach ($data in $InputData)
        {
            Write-Host "Processing: $data"
            $results += $data.ToUpper()

        }
        
        # Write-Host "Processing: $_"
        # $results += $_.ToUpper()
    }
    
    end
    {
        Write-Host 'Finalizing'
        Write-Host '----------'
        $results
    }
}


<#
.SYNOPSIS
    Counts the number of alphabetic characters in a given string or array of strings.

.DESCRIPTION
    This function takes a string or an array of strings and counts all the alphabetic characters (A-Z, a-z) in each string.
    It supports both pipeline input and direct parameter input.

.PARAMETER InputString
    The string or array of strings in which to count the alphabetic characters.

.EXAMPLE
    Measure-AlphabeticChars -InputString "Hello, World!"
    Output: 10

.EXAMPLE
    "Hello, World!" | Measure-AlphabeticChars
    Output: 10

.EXAMPLE
    Measure-AlphabeticChars -InputString @("Hello, World!", "PowerShell 7")
    Output: 10
            10

.EXAMPLE
    @("Hello, World!", "PowerShell 7") | Measure-AlphabeticChars
    Output: 10
            10

.NOTES
    Author: Your Name
    Date: Today's date
#>

function Measure-AlphabeticChars
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string[]]$InputString
    )

    process
    {
        foreach ($str in $InputString)
        {
            # Use regex to find all alphabetic characters and count them
            $ms = [regex]::Matches($str, '[a-zA-Z]')
            $ms.Count
        }
    }
}

# Example usage:
# Measure-AlphabeticChars -InputString "Hello, World!"
# "Hello, World!" | Measure-AlphabeticChars
# Measure-AlphabeticChars -InputString @("Hello, World!", "PowerShell 7")
# @("Hello, World!", "PowerShell 7") | Measure-AlphabeticChars