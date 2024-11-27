powershell.exe { 
    
    $zh = 'zh-hans-cn'
    $en='en-US'
    $lang=$en
    
    $l = Get-WinUserLanguageList; 
    $Lang = $l | Where-Object { $_.languageTag -match $lang }
    $LangTips = $Lang.inputMethodTips
    # 具体的输入法
    $sogou_keyboard = $LangTips | Where-Object { $_ -like '*e7ea*' }
    $en_us_keyboard = $LangTips | Where-Object { $_ -like '*0409:00000409*' }
    $wetype_keyboard = $LangTips | Where-Object { $_ -like '*86598FB9*' }
    $IME = $en_us_keyboard

    Write-Output "IME:$IME"

    $LangTips.remove($IME)
    Write-Output $l

    Set-WinUserLanguageList -LanguageList $l -Force -Verbose
}