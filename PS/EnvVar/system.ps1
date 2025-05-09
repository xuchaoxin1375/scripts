# System-related functions

## Environment Variables

function Publish-EnvVar
{
    <#
    .SYNOPSIS
    Notify the system about environment variable changes.

    .DESCRIPTION
    This function sends a broadcast message to notify all top-level windows that 
    the environment variables have changed. It uses the SendMessageTimeout function 
    from user32.dll to ensure that the message is sent within a specified timeout period.

    .EXAMPLE
    Publish-EnvVar
    #>
    if (-not ('Win32.NativeMethods' -as [Type]))
    {
        Add-Type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
public static extern IntPtr SendMessageTimeout(
    IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult
);
'@
    }

    $HWND_BROADCAST = [IntPtr] 0xffff
    $WM_SETTINGCHANGE = 0x1a
    $result = [UIntPtr]::Zero

    # Send broadcast message to notify about environment change
    [Win32.NativeMethods]::SendMessageTimeout($HWND_BROADCAST,
        $WM_SETTINGCHANGE,
        [UIntPtr]::Zero,
        'Environment',
        2,
        5000,
        [ref] $result
    ) | Out-Null
}

function Get-EnvVar
{
    <#
    .SYNOPSIS
    Retrieve an environment variable value.

    .DESCRIPTION
    This function retrieves the value of the specified environment variable 
    from the registry. It can fetch both user-specific and system-wide variables.

    .PARAMETER Name
    The name of the environment variable.

    .PARAMETER Global
    Switch to indicate if the environment variable is global (system-wide).

    .EXAMPLE
    Get-EnvVar -Name "Path"
    #>
    param(
        [string]$Name,
        [switch]$Global
    )

    # Determine the appropriate registry key to use based on the Global flag
    # User scope uses the HKCU hive, while global (system-wide) uses the HKLM hive
    $registerKey = if ($Global)
    {
        # HKLM hive is used for system-wide environment variables
        # This is the same key used by the system Configuration Manager
        # when setting environment variables through the System Properties
        # control panel
        Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    }
    else
    {
        # HKCU hive is used for user-specific environment variables
        Get-Item -Path 'HKCU:'
    }

    # Open the Environment sub-key off the selected registry key
    $envRegisterKey = $registerKey.OpenSubKey('Environment')

    # Retrieve the value of the specified environment variable
    # The DoNotExpandEnvironmentNames option is used to prevent the registry
    # from expanding any environment variables it finds in the value
    # This is necessary because environment variables can be nested (e.g. %PATH%)
    # and we want to return the raw, unexpanded value
    $registryValueOption = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
    $envRegisterKey.GetValue($Name, $null, $registryValueOption)
}

function Set-EnvVar
{
    <#
    .SYNOPSIS
    Set or remove an environment variable.

    .DESCRIPTION
    This function sets the specified environment variable in the registry. 
    If the value is null or empty, it removes the variable. It can target both 
    user-specific and system-wide variables.

    .PARAMETER Name
    The name of the environment variable.

    .PARAMETER Value
    The value to set for the environment variable.

    .PARAMETER Global
    Switch to indicate if the environment variable is global (system-wide).

    .EXAMPLE
    Set-EnvVar -Name "Path" -Value "C:\NewPath"
    #>
    param(
        [string]$Name,
        [string]$Value,
        [switch]$Global
    )

    $registerKey = if ($Global)
    {
        Get-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
    }
    else
    {
        Get-Item -Path 'HKCU:'
    }
    $envRegisterKey = $registerKey.OpenSubKey('Environment', $true)
    if ($null -eq $Value -or $Value -eq '')
    {
        if ($envRegisterKey.GetValue($Name))
        {
            # Delete the environment variable if the value is null or empty
            $envRegisterKey.DeleteValue($Name)
        }
    }
    else
    {
        $registryValueKind = if ($Value.Contains('%'))
        {
            [Microsoft.Win32.RegistryValueKind]::ExpandString
        }
        elseif ($envRegisterKey.GetValue($Name))
        {
            $envRegisterKey.GetValueKind($Name)
        }
        else
        {
            [Microsoft.Win32.RegistryValueKind]::String
        }
        # Set the environment variable with the appropriate value kind
        $envRegisterKey.SetValue($Name, $Value, $registryValueKind)
    }
    Publish-EnvVar
}

function Split-PathLikeEnvVar
{
    <#
    .SYNOPSIS
    Split a path-like environment variable.

    .DESCRIPTION
    This function splits a path-like environment variable into two parts: 
    the part matching specified patterns and the remainder.

    .PARAMETER Pattern
    Patterns to match against the path components.

    .PARAMETER Path
    The path-like environment variable to split.

    .EXAMPLE
    Split-PathLikeEnvVar -Pattern @("C:\Path1", "C:\Path2") -Path $env:Path
    #>
    param(
        [string[]]$Pattern,
        [string]$Path
    )

    if ($null -eq $Path -and $Path -eq '')
    {
        return $null, $null
    }
    else
    {
        $splitPattern = $Pattern.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
        $splitPath = $Path.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
        $inPath = @()
        foreach ($p in $splitPattern)
        {
            # Find and separate matching components from the path
            $inPath += $splitPath.Where({ $_ -like $p })
            $splitPath = $splitPath.Where({ $_ -notlike $p })
        }
        return ($inPath -join ';'), ($splitPath -join ';')
    }
}

function Add-Path
{
    <#
    .SYNOPSIS
    Add directories to the path environment variable.

    .DESCRIPTION
    This function adds specified directories to the path environment variable 
    for both future sessions and the current session. It can target both 
    user-specific and system-wide variables.

    .PARAMETER Path
    The directories to add to the path.

    .PARAMETER TargetEnvVar
    The environment variable to modify, defaults to "PATH".

    .PARAMETER Global
    Switch to indicate if the path modification is global (system-wide).

    .PARAMETER Force
    Force the addition even if the path already exists.

    .PARAMETER Quiet
    Suppress output messages.

    .EXAMPLE
    Add-Path -Path @("C:\NewDir") -Global
    #>
    param(
        [string[]]$Path,
        [string]$TargetEnvVar = 'PATH',
        [switch]$Global,
        [switch]$Force,
        [switch]$Quiet
    )

    # Future sessions
    $inPath, $strippedPath = Split-PathLikeEnvVar $Path (Get-EnvVar -Name $TargetEnvVar -Global:$Global)
    if (!$inPath -or $Force)
    {
        if (!$Quiet)
        {
            $Path | ForEach-Object {
                Write-Host "Adding $(friendly_path $_) to $(if ($Global) {'global'} else {'your'}) path."
            }
        }
        # Add path for future sessions
        Set-EnvVar -Name $TargetEnvVar -Value ((@($Path) + $strippedPath) -join ';') -Global:$Global
    }
    # Current session
    $inPath, $strippedPath = Split-PathLikeEnvVar $Path $env:PATH
    if (!$inPath -or $Force)
    {
        # Add path for the current session
        $env:PATH = (@($Path) + $strippedPath) -join ';'
    }
}

function Remove-Path
{
    <#
    .SYNOPSIS
    Remove directories from the path environment variable.

    .DESCRIPTION
    This function removes specified directories from the path environment variable 
    for both future sessions and the current session. It can target both 
    user-specific and system-wide variables.

    .PARAMETER Path
    The directories to remove from the path.

    .PARAMETER TargetEnvVar
    The environment variable to modify, defaults to "PATH".

    .PARAMETER Global
    Switch to indicate if the path modification is global (system-wide).

    .PARAMETER Quiet
    Suppress output messages.

    .PARAMETER PassThru
    Return the removed paths.

    .EXAMPLE
    Remove-Path -Path @("C:\OldDir") -Global
    #>
    param(
        [string[]]$Path,
        [string]$TargetEnvVar = 'PATH',
        [switch]$Global,
        [switch]$Quiet,
        [switch]$PassThru
    )

    # Future sessions
    $inPath, $strippedPath = Split-PathLikeEnvVar $Path (Get-EnvVar -Name $TargetEnvVar -Global:$Global)
    if ($inPath)
    {
        if (!$Quiet)
        {
            $Path | ForEach-Object {
                Write-Host "Removing $(friendly_path $_) from $(if ($Global) {'global'} else {'your'}) path."
            }
        }
        # Remove path for future sessions
        Set-EnvVar -Name $TargetEnvVar -Value $strippedPath -Global:$Global
    }
    # Current session
    $inSessionPath, $strippedPath = Split-PathLikeEnvVar $Path $env:PATH
    if ($inSessionPath)
    {
        # Remove path for the current session
        $env:PATH = $strippedPath
    }
    if ($PassThru)
    {
        return $inPath
    }
}

## Deprecated functions

function env($name, $global, $val)
{
    <#
    .SYNOPSIS
    Deprecated: Set or get an environment variable.

    .DESCRIPTION
    This function is deprecated. Use Set-EnvVar to set an environment variable 
    and Get-EnvVar to get an environment variable.

    .PARAMETER name
    The name of the environment variable.

    .PARAMETER global
    Switch to indicate if the environment variable is global (system-wide).

    .PARAMETER val
    The value to set for the environment variable.

    .EXAMPLE
    env "Path" $true "C:\NewPath"
    #>
    if ($PSBoundParameters.ContainsKey('val'))
    {
        Show-DeprecatedWarning $MyInvocation 'Set-EnvVar'
        Set-EnvVar -Name $name -Value $val -Global:$global
    }
    else
    {
        Show-DeprecatedWarning $MyInvocation 'Get-EnvVar'
        Get-EnvVar -Name $name -Global:$global
    }
}

function strip_path($orig_path, $dir)
{
    <#
    .SYNOPSIS
    Deprecated: Strip directories from a path.

    .DESCRIPTION
    This function is deprecated. Use Split-PathLikeEnvVar instead.

    .PARAMETER orig_path
    The original path.

    .PARAMETER dir
    The directory to strip from the path.

    .EXAMPLE
    strip_path $env:Path "C:\OldDir"
    #>
    Show-DeprecatedWarning $MyInvocation 'Split-PathLikeEnvVar'
    Split-PathLikeEnvVar -Pattern @($dir) -Path $orig_path
}

function add_first_in_path($dir, $global)
{
    <#
    .SYNOPSIS
    Deprecated: Add a directory to the beginning of the path.

    .DESCRIPTION
    This function is deprecated. Use Add-Path with the -Force switch instead.

    .PARAMETER dir
    The directory to add.

    .PARAMETER global
    Switch to indicate if the path modification is global (system-wide).

    .EXAMPLE
    add_first_in_path "C:\NewDir" $true
    #>
    Show-DeprecatedWarning $MyInvocation 'Add-Path'
    Add-Path -Path $dir -Global:$global -Force
}

function remove_from_path($dir, $global)
{
    <#
    .SYNOPSIS
    Deprecated: Remove a directory from the path.

    .DESCRIPTION
    This function is deprecated. Use Remove-Path instead.

    .PARAMETER dir
    The directory to remove.

    .PARAMETER global
    Switch to indicate if the path modification is global (system-wide).

    .EXAMPLE
    remove_from_path "C:\OldDir" $true
    #>
    Show-DeprecatedWarning $MyInvocation 'Remove-Path'
    Remove-Path -Path $dir -Global:$global
}

