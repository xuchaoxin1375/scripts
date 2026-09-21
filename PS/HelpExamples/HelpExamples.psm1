# 注:此示例函数原名 Add-Extension,与 FileSystem 模块的同名真实函数冲突(自动加载命中不确定),
# 已改名为 Add-ExtensionExample;FileSystem\Add-Extension 为唯一正本
function Add-ExtensionExample
{
    param
    (

        [string]
        #Specifies the file name.
        $name,

        [string]
        #Specifies the file name extension. "Txt" is the default.
        $extension = 'txt'
    )

    $name = $name + '.' + $extension
    $name

    <#
        .SYNOPSIS

        Adds a file name extension to a supplied name.

        .DESCRIPTION

        Adds a file name extension to a supplied name. Takes any strings for the
        file name or extension.

        .INPUTS

        None. You cannot pipe objects to Add-Extension.

        .OUTPUTS

        System.String. Add-Extension returns a string with the extension or
        file name.

        .EXAMPLE

        PS> extension -name "File"
        File.txt

        .EXAMPLE

        PS> extension -name "File" -extension "doc"
        File.doc

        .EXAMPLE

        PS> extension "File" "doc"
        File.doc

        .LINK

        http://www.fabrikam.com/extension.html

        .LINK

        Set-Item
    #>  
}

function Operators_Comparison_pwsh
{
    help about_Comparison_Operators
}
function  Operators_Logical_pwsh
{
    help about_Logical_Operators
}