$controlPanelMS = 'control /name Microsoft.'
<# 
when you maintain the following list,Using no wrap line to check the items is recommended to count it
#>
$ControlPanelApplets = [ordered]@{
    'User Accounts'                            = 'netplwiz'
    'Programs and Features'                    = 'appwiz'
    
    'Add a Printer wizard'                     = 'rundll32.exe shell32.dll,SHHelpShortcuts_RunDLL AddPrinter'
    'Screen Saver Settings'                    = 'rundll32.exe shell32.dll,Control_RunDLL desk.cpl,,1'
    'Set Program Access and Computer Defaults' = 'rundll32.exe shell32.dll,Control_RunDLL appwiz.cpl,,3' #和直接用appwiz并不相通,win10之后的系统这里会打开系统设置里的应用管理界面
    'Desktop Icon Settings'                    = 'rundll32.exe shell32.dll,Control_RunDLL desk.cpl,,0'
    
    'Network Connections'                      = 'control.exe ncpa.cpl'
    'Network Setup Wizard'                     = 'control.exe netsetup.cpl'
    'ODBC Data Source Administrator'           = 'control.exe odbccp32.cpl'
    
    'Color and Appearance'                     = 'explorer shell:::{ED834ED6-4B5A-4bfe-8F11-A626DCB6A921} -Microsoft.Personalization\pageColorization'
    'Desktop Background'                       = 'explorer shell:::{ED834ED6-4B5A-4bfe-8F11-A626DCB6A921} -Microsoft.Personalization\pageWallpaper'
    'Notification Area Icons'                  = 'explorer shell:::{05d7b0f4-2121-4eff-bf6b-ed3f69b894d9}'
    'Personalization'                          = 'explorer shell:::{ED834ED6-4B5A-4bfe-8F11-A626DCB6A921}'
    'System Icons'                             = 'explorer shell:::{05d7b0f4-2121-4eff-bf6b-ed3f69b894d9} \SystemIcons,,0'
    'Add a Device wizard'                      = "$env:windir\System32\DevicePairingWizard.exe"
    'Add Hardware wizard'                      = "$env:windir\System32\hdwwiz.exe"
    'System Properties'                        = "$env:windir\System32\SystemPropertiesComputerName.exe"
    'Windows Features'                         = "$env:windir\System32\OptionalFeatures.exe"
    'Windows To Go'                            = "$env:windir\System32\pwcreator.exe"
    'Work Folders'                             = "$env:windir\System32\WorkFolders.exe"
    'Performance Options'                      = "$env:windir\system32\SystemPropertiesPerformance.exe"
    'Presentation Settings'                    = "$env:windir\system32\PresentationSettings.exe"
    'Windows Defender Antivirus'               = "$env:ProgramFiles\Windows Defender\MSASCui.exe"
    
    'Administrative Tools'                     = "${controlPanelMS}AdministrativeTools"
    'AutoPlay'                                 = "${controlPanelMS}AutoPlay"
    'Backup and Restore'                       = "${controlPanelMS}BackupAndRestoreCenter"
    'BitLocker Drive Encryption'               = "${controlPanelMS}BitLockerDriveEncryption"
    'Color Management'                         = "${controlPanelMS}ColorManagement"
    'Credential Manager'                       = "${controlPanelMS}CredentialManager"
    'Date and Time'                            = "${controlPanelMS}DateAndTime"
    'Default Programs'                         = "${controlPanelMS}DefaultPrograms"
    'Device Manager'                           = "${controlPanelMS}DeviceManager"
    'Devices and Printers'                     = "${controlPanelMS}DevicesAndPrinters"
    'Ease of Access Center'                    = "${controlPanelMS}EaseOfAccessCenter"
    'File Explorer Options'                    = "${controlPanelMS}FolderOptions"
    'File History'                             = "${controlPanelMS}FileHistory"
    'Fonts'                                    = "${controlPanelMS}Fonts"
    'Game Controllers'                         = "${controlPanelMS}GameControllers"
    'Get Programs'                             = "${controlPanelMS}GetPrograms"
    'HomeGroup'                                = "${controlPanelMS}HomeGroup"
    'Indexing Options'                         = "${controlPanelMS}IndexingOptions"
    'Infrared'                                 = "${controlPanelMS}Infrared"
    'Internet Properties'                      = "${controlPanelMS}InternetOptions"
    'iSCSI Initiator'                          = "${controlPanelMS}iSCSIInitiator"
    'Keyboard'                                 = "${controlPanelMS}Keyboard"
    'Language'                                 = "${controlPanelMS}Language"
    'Mouse Properties'                         = "${controlPanelMS}Mouse"
    'Network and Sharing Center'               = "${controlPanelMS}NetworkAndSharingCenter"
    'Netwokr Advanced Sharing settings'        = "${controlPanelMS}NetworkAndSharingCenter /page Advanced"
    'Offline Files'                            = "${controlPanelMS}OfflineFiles"
    'Phone and Modem'                          = "${controlPanelMS}PhoneAndModem"
    'Power Options'                            = "${controlPanelMS}PowerOptions"
    # 'Programs and Features'                    = "${controlPanelMS}ProgramsAndFeatures"
    'Recovery'                                 = "${controlPanelMS}Recovery"
    'Region'                                   = "${controlPanelMS}RegionAndLanguage"
    'RemoteApp and Desktop Connections'        = "${controlPanelMS}RemoteAppAndDesktopConnections"
    'Scanners and Cameras'                     = "${controlPanelMS}ScannersAndCameras"
    'Security and Maintenance'                 = "${controlPanelMS}ActionCenter"
    'Set Associations'                         = "${controlPanelMS}DefaultPrograms /page pageFileAssoc"
    'Set Default Programs'                     = "${controlPanelMS}DefaultPrograms /page pageDefaultProgram"
    'Sound'                                    = "${controlPanelMS}Sound"
    'Speech Recognition'                       = "${controlPanelMS}SpeechRecognition"
    'Storage Spaces'                           = "${controlPanelMS}StorageSpaces"
    'Sync Center'                              = "${controlPanelMS}SyncCenter"
    'System'                                   = "${controlPanelMS}System"
    'Windows Defender Firewall'                = "${controlPanelMS}WindowsFirewall"
    'Windows Mobility Center'                  = "${controlPanelMS}MobilityCenter"
    'Tablet PC Settings'                       = "${controlPanelMS}TabletPCSettings"
    'Text to Speech'                           = "${controlPanelMS}TextToSpeech"
    'User Accounts Changes'                    = "${controlPanelMS}UserAccounts"
}


function Start-ControlPanelApplet
{
    <# 
    .SYNOPSIS
    启动控制面板或常用设置页面

    .DESCRIPTION
    您可以一次性指定多个需要打开的页面(尽管通常一次打开一个就够了)
    在此函数外有一个自动完成功能，可以自动补全应用程序名称,用户输入前几个字母后,按下tab键进行补全,这可保证输入的名字是合法的
    有些名字补全后包含空格,会自动用引号括起来

    
    .NOTES
    被接受的合法程序名定义在了$ControlPanelApplets中,如果有必要,可以进行修改
    大多数可以通过<Name.cpl>直接启动的控制面板页面没有在上述列表中提及,例如appwiz.cpl;
    如果有需要,可以添加到列表中,本函数为
    1.设置或控制面板页面程序的长名称能够方便键入而创建
    2.许多面板虽然可以直接通过程序名字来启动,例如appwiz可以打开程序管理设置页面,
    但是我们并不容易直接想到windwos中的相应功能页面可以用wizapp,或者容易忘记
    而本函数通过定义一个字典,这样可以取一个更加友好的名字来代替缩写名字

    输入需要补全的关键字(不一定是程序名称的开头),补全功能会将包含改关键字的所有合法程序名作为后选项供您选择,通过tab键来切换候选
    当候选名称只有一个时,继续按tab不会发生变换
    .EXAMPLE
    #同时打开程序管理设置页面和声音设置页面
    PS> start-ControlPanelApplet -Name 'Set Program Access and Computer Defaults','Sound'
    .EXAMPLE
    打开程序和功能管理页面(等价于直接打输入appwiz)
    PS C:\Users\cxxu\Desktop> start-ControlPanelApplet 'Programs and Features'
    #>
    [CmdletBinding()]
    param
    (
        [string[]]
        $Name
    )

    foreach ($Applet in $Name)
    {
        $expression = $ControlPanelApplets.$Applet
        # Write-Host $expression -BackgroundColor Green
        cmd /c $expression
        # "'$expression'" | Invoke-Expression
    }
}
Register-ArgumentCompleter -CommandName Start-ControlPanelApplet -ParameterName Name -ScriptBlock {
    param ($CommandName, $ParameterName, $WordToComplete, $CommandAst, $FakeBoundParameter)

    $Keys = $ControlPanelApplets.Keys

    foreach ($Key in $Keys)
    {
        if ($Key -Match $WordToComplete)
        {
            [System.Management.Automation.CompletionResult]::new(
                "'$Key'",
                $Key,
                'ParameterValue',
                ($Key)
            )
        }
    }
}


