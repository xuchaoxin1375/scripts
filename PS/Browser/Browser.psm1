
function edge_favoriates
{
    https3w_start 'chrome://favorites/'
}
function googleSearch
{
    https3w_start 'https://www.google.com.hk/webhp?hl=en&as_q=&as_epq=&as_oq=&as_eq=&as_nlo=&as_nhi=&lr=&cr=countryUS&as_qdr=all&as_sitesearch=&as_occt=any&safe=images&as_filetype=&tbs='
}
function csdn_writer
{
    param (
    )
    https3w_start 'https://mp.csdn.net/mp_blog/manage/article?spm=1011.2124.3001.5298'
}
function https_open
{
    param (
        $domain
    )
    $url = "www.$domain"
    Start-Process $url
    Write-Output "try to open https url:🎶 $url"
}
