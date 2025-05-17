

$a = 0..9
Write-Output 'You can also use looping constructs, such as ForEach, For, and While loops,
to refer to the elements in an array. '
foreach ($element in $a)
{
    $element
}
for ($i = 0; $i -le ($a.length - 1); $i += 2)
{
    $a[$i]
}
while ($i -lt 4)
{
    $a[$i]
    $i++
}
Write-Output 'app'
Write-Host