@{
    RootModule = 'Development.psm1'
    ModuleVersion = '1.0.4'
    GUID = '9da0acaf-e999-4080-94a1-d058a57c6585'
    Author = 'cxxu'
    Description = 'Cxxu PowerShell module: Development'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'EggNew',
        'dj_start_proj',
        'env_django2',
        'env_django4',
        'pmg',
        'sqlmigrate',
        'showmigrations',
        'pmgmk',
        'pmgmi',
        'Django_env_Home',
        'runserver_jango',
        'startapp',
        'cxxuAli_update_alias_envs_vimrc',
        'CxxuAli',
        'rootAli',
        'removeLF',
        'removeSpace',
        'removeSpaceLF',
        'navicat_reset_try',
        'tomcat_restart',
        'wmqtt',
        'Add-PythonAliasPy'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('CxxuPsModules')
            ProjectUri = 'https://github.com/xuchaoxin1375/scripts'
        }
    }
}
