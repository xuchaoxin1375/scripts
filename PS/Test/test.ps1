#修改配置(图片从哪个站点移动到另一个站点)
$fromDomain = "motormeistershop.com"
$toDomain = "autofunktastisch.com"
$csv = "p37.csv"
$csvFullPath = "$Desktop\data_output\$fromDomain\$csv"
# 开始处理
$csvfrom = "$Desktop\data_output\$fromDomain\$csv"
$csvdest = "$Desktop\data_output\$toDomain\$csv"
Move-ItemImagesFromCsvPathFields -Path $csvFullPath -UseDomainNamePair $fromDomain, $toDomain  -IgnoreExtension # -Verbose

#移动csv
Move-Item $csvfrom $csvdest -V




#修改配置(图片从哪个站点移动到另一个站点)
$fromDomain = "motormeistershop.com"
$toDomain = "autofunktastisch.com"
$csv = "p44.csv"
$csvFullPath = "$Desktop\data_output\$fromDomain\$csv"
# 开始处理
$csvfrom = "$Desktop\data_output\$fromDomain\$csv"
$csvdest = "$Desktop\data_output\$toDomain\$csv"
Move-ItemImagesFromCsvPathFields -Path $csvFullPath -UseDomainNamePair $fromDomain, $toDomain  -ImgExtPattern '.webp' -Verbose # -IgnoreExtension

#移动csv
Move-Item $csvfrom $csvdest -V
