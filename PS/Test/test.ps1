$ev1 = [PSCustomObject]@{
    Name  = 'k1'; 
    Value = 'v1'
}
$ev2 = [PSCustomObject]@{
    Name  = 'k2'; 
    Value = 'v2'
}
$es = @($ev1, $ev2)

$es | Format-EnvItemNumber -Debug
# $es | Format-DoubleColumn -Debug


