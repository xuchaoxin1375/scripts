function jsonValueSpec
{
    Write-Output '
    JSON的值只能是以下几种数据格式：

数字，包含浮点数和整数
字符串，需要包裹在双引号中
Bool值，true 或者 false
数组，需要包裹在方括号中 []
对象，需要包裹在大括号中 {}
Null
    '
}
function liveSite
{
    $value = '浙江省杭州市钱塘区白杨街道学正街18号浙江工商大学钱江湾生活区30幢602'
    Set-Clipboard $value
}
function schoolSite
{
    $value = '浙江省杭州市钱塘区下沙高教园区学正街18号'
    Set-Clipboard $value
}
function homeSite
{
    $value = '福建省莆田市秀屿区平海镇溪边村前黄19号'
    Set-Clipboard $value
}
function colorSpecification
{
    Write-Output 'https://developer.mozilla.org/en-US/docs/Web/CSS/color_value#:~:text=pioneer%20Eric%20Meyer.-, Specification, -Keyword'
    Write-Output '完整复制上述链接进行查看颜色规范'
    Write-Output
    '
    常用颜色:
    turquoise	#40e0d0
    yellowgreen	#9acd32
    '

}