
# Write-Output 'loading jumper!'
# path jump serials:
function blogs_math_
{
    param (
        
    )
    Set-Location $blogs\neep\math
}
function c_cpp_{
    Set-Location $repos\c_cpp_consoleapps
}
function share_
{
    Set-Location $share_home
    
}
function home_config_
{
    Set-Location "$home\.config\"
}
function PrincipleOfCompilers
{
    Set-Location $books\PrinciplesOfCompilers
}
function vpnTools_
{
    param (
    )
    Set-Location $exes\vpntools
}
function exes_
{
    param (
        
    )
    Set-Location $exes
}
function sedLearn_
{
    Set-Location $sedLearn
}
function linuxShellScripts_
{
    Set-Location $env:scripts\linuxShellScripts
}
function slideProjs_
{
    Set-Location $blogs\slidevProjects
}


function os_codes_
{
    Set-Location $repos\os_codes
}
function os_
{
    Set-Location $env:neep\408\os_materials
}


function cpp_consoleApps_
{
    Set-Location "$cpp\consoleapps"
}
function neovim_fix
{
    Remove-Item -Verbose $AppDataLocal\nvim-data
}
function compressed_
{
    Set-Location $Downloads\compressed
}
function programs_
{
    Set-Location $downloads\programs
}
function formula_
{
    Set-Location $math\miscellaneous\Formula
}
function dcs_Idm
{
    Set-Location $Downloads\documents
}
function latex_
{
    Set-Location $latex_materials  
}
function fonts_
{
    Set-Location $fonts
}
function ccser_
{
    Set-Location $repos\ccser
}
function graduation_
{
    Set-Location $graduationDesign
}
function graduation_blogs_
{
    Set-Location $blogs\python\graduationDesign
}
function blogs_
{

    Set-Location $repos/blogs    
}
function blogs_408_
{
    Set-Location "$blogs\neep\408\"
}
function books_408_
{

    Set-Location $neep\408    
}




function cp_
{
    Set-Location $cp
}
function cp86_
{
    Set-Location $cp86
}
function webLearn_
{
    param (
        $isOpen
    )
    Set-Location $repos\web\webLearn
    if ($isOpen -eq 'c')
    {
        c 
    }
}
function localAppData_
{
    param (
        
    )
    Set-Location $env:LOCALAPPDATA
}

function DjangoPjs_
{
    param (
    )
    Set-Location 'C:\repos\PythonLearn\DjangoProjects'
    
}
function ELA_backendProj_
{
    param (
        
    )
    Set-Location $repos\ela\backend\
}
function pythonLearn_
{
    Set-Location $pythonLearn
}

function english_
{
    param (
        
    )
    Set-Location $blogs\courses\english
}
function dp_
{
	
    Set-Location $dp
}
function winTools_
{
    Set-Location $exes
}
function web_
{
    Set-Location $repos\web
}

function DjangoProjects_
{
    param (
    )
    Set-Location $DjangoProjects
    
}


function tester_psFunctions
{
    Set-Location $PS\tester
}
function PS_
{
    Set-Location $PS
}
function Basic_
{
    Set-Location $PS\Basic
}

function videos_
{
    param (
        
    )
    Set-Location $videos
}
function profileEdit_
{
    code $profile
}


function miniprograms_
{
    Set-Location $repos/miniprograms
}

function modulesEdit_
{
    PS_
    code .
}
function dingtalkFiles_
{
    # Set-Location $dingtalkFiles
    Write-Output "配置下$dingtalkFiles变量"
}


function scripts_
{
    param (
        $toCode = ''
    )
    Set-Location $repos\scripts
    if ($toCode -eq '')
    {

    }
    else
    {
        c .
    }
}

function hitomishimatani_
{
    Set-Location $music\hitomishimatani
}

function startMenuPrograms_
{
    Set-Location $startMenuPrograms
}
function startMenu_common_
{
    Set-Location $startMenu
}
function startMenu_user_
{
    Set-Location $userStartMenu
}
function music_
{
    param (
        
    )
    Set-Location $music 
}
<# #  jump to your frequently used folder(path)
 #>
function wechatFiles_
{
    Set-Location $wechatFiles
}
function qqFiles_
{
    Set-Location $qqFiles
}
function configs_ { Set-Location $configs }
function pictures_
{
    param (
    )
    Set-Location $pictures
    
}

function exes_
{
    param (

    )
    Set-Location $exes

}
function books_
{
    param (
        
    )
    Set-Location $books
}


function downloads_
{
    param (
        
    )
    Set-Location $Downloads
    
}
function dcs_Idm
{
    Set-Location $downloads\documents
}
function repos_ { Set-Location -Path $repos }
# function usersByCxxu_ { Set-Location -Path $usersByCxxu }

function desktop_ { Set-Location ~/desktop }
function documents_
{
    param (
        
    )
    Set-Location $Documents    
}
