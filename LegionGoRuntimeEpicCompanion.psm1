# Legion Go Runtime Epic Companion module for Windows PowerShell 5.1.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$script:WindowsPowerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script:ThermalHelperPath = Join-Path -Path $PSScriptRoot -ChildPath 'Private\Invoke-LegionThermalModeElevated.ps1'
$script:SettingsDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'LegionGoRuntimeEpicCompanion'
$script:SettingsPath = Join-Path -Path $script:SettingsDirectory -ChildPath 'Settings.json'


function Get-DefaultEpicCompanionSetting {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        DefaultThermalProfile         = 'Balanced'
        UseLosslessScaling             = $true
        CloseLosslessScalingAfterGame  = $true
        LosslessScalingPathOverride    = ''
        GameStartTimeoutSeconds        = 300
        PollIntervalSeconds            = 2
        GameOverrides                  = [pscustomobject]@{}
    }
}

function Write-EpicCompanionSetting {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Setting)

    if (-not (Test-Path -LiteralPath $script:SettingsDirectory -PathType Container)) {
        New-Item -Path $script:SettingsDirectory -ItemType Directory -Force | Out-Null
    }

    $temporaryPath = Join-Path -Path $script:SettingsDirectory -ChildPath ("Settings.{0}.tmp" -f [guid]::NewGuid().ToString('N'))
    $backupPath = Join-Path -Path $script:SettingsDirectory -ChildPath ("Settings.{0}.bak" -f [guid]::NewGuid().ToString('N'))
    try {
        $Setting | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $temporaryPath -Encoding UTF8
        if (Test-Path -LiteralPath $script:SettingsPath -PathType Leaf) {
            [System.IO.File]::Replace($temporaryPath, $script:SettingsPath, $backupPath)
        }
        else {
            Move-Item -LiteralPath $temporaryPath -Destination $script:SettingsPath
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function ConvertTo-NormalizedEpicCompanionSetting {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Setting)

    $validProfiles = @('Quiet', 'Balanced', 'Performance')
    if ([string]$Setting.DefaultThermalProfile -notin $validProfiles) {
        throw 'DefaultThermalProfile must be Quiet, Balanced, or Performance.'
    }

    foreach ($booleanName in @('UseLosslessScaling', 'CloseLosslessScalingAfterGame')) {
        $value = $Setting.$booleanName
        if ($value -is [bool]) { continue }
        $parsedBoolean = $false
        if ($value -is [string] -and [bool]::TryParse($value, [ref]$parsedBoolean)) {
            $Setting.$booleanName = $parsedBoolean
            continue
        }
        throw ("{0} must be true or false." -f $booleanName)
    }

    foreach ($range in @(
        @{ Name = 'GameStartTimeoutSeconds'; Minimum = 30; Maximum = 3600 },
        @{ Name = 'PollIntervalSeconds'; Minimum = 1; Maximum = 30 }
    )) {
        $parsedInteger = 0
        if (-not [int]::TryParse([string]$Setting.($range.Name), [ref]$parsedInteger) -or
            $parsedInteger -lt $range.Minimum -or $parsedInteger -gt $range.Maximum) {
            throw ("{0} must be an integer from {1} through {2}." -f $range.Name, $range.Minimum, $range.Maximum)
        }
        $Setting.($range.Name) = $parsedInteger
    }

    $Setting.LosslessScalingPathOverride = [string]$Setting.LosslessScalingPathOverride
    if ($null -eq $Setting.GameOverrides) {
        $Setting.GameOverrides = [pscustomobject]@{}
    }
    elseif ($Setting.GameOverrides -is [string] -or $Setting.GameOverrides -is [System.Array] -or
        $Setting.GameOverrides.GetType().IsValueType) {
        throw 'GameOverrides must be a JSON object.'
    }

    foreach ($property in @($Setting.GameOverrides.PSObject.Properties)) {
        $override = $property.Value
        if ($null -eq $override -or $override -is [string] -or $override -is [System.Array] -or
            $override.GetType().IsValueType) {
            throw ("GameOverrides.{0} must be a JSON object." -f $property.Name)
        }
        if ($override.PSObject.Properties['ThermalProfile'] -and
            [string]$override.ThermalProfile -notin $validProfiles) {
            throw ("GameOverrides.{0}.ThermalProfile must be Quiet, Balanced, or Performance." -f $property.Name)
        }
        if ($override.PSObject.Properties['UseLosslessScaling']) {
            $overrideBoolean = $override.UseLosslessScaling
            if ($overrideBoolean -isnot [bool]) {
                $parsedOverrideBoolean = $false
                if ($overrideBoolean -is [string] -and [bool]::TryParse($overrideBoolean, [ref]$parsedOverrideBoolean)) {
                    $override.UseLosslessScaling = $parsedOverrideBoolean
                }
                else {
                    throw ("GameOverrides.{0}.UseLosslessScaling must be true or false." -f $property.Name)
                }
            }
        }
        if ($override.PSObject.Properties['ProcessName']) {
            $normalizedProcessNames = [string[]]@(
                $override.ProcessName |
                    ForEach-Object { [string]$_ } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
            if (@($normalizedProcessNames).Count -gt 0) {
                $override.ProcessName = $normalizedProcessNames
            }
            else {
                $override.PSObject.Properties.Remove('ProcessName')
            }
        }
        if (-not $override.PSObject.Properties['ThermalProfile'] -and
            -not $override.PSObject.Properties['UseLosslessScaling'] -and
            -not $override.PSObject.Properties['ProcessName']) {
            throw ("GameOverrides.{0} must contain ThermalProfile, UseLosslessScaling, or ProcessName." -f $property.Name)
        }
    }

    return $Setting
}

function Get-EpicCompanionSetting {
    <#
    .SYNOPSIS
        Gets persistent Epic companion settings.
    #>
    [CmdletBinding()]
    param()

    $defaults = Get-DefaultEpicCompanionSetting
    if (-not (Test-Path -LiteralPath $script:SettingsPath -PathType Leaf)) {
        Write-EpicCompanionSetting -Setting $defaults
        return $defaults
    }

    try {
        $setting = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop

        foreach ($defaultProperty in $defaults.PSObject.Properties) {
            if (-not $setting.PSObject.Properties[$defaultProperty.Name]) {
                $setting | Add-Member -MemberType NoteProperty -Name $defaultProperty.Name -Value $defaultProperty.Value
            }
        }

        return ConvertTo-NormalizedEpicCompanionSetting -Setting $setting
    }
    catch {
        throw ("Unable to read Epic companion settings at '{0}': {1}" -f $script:SettingsPath, $_.Exception.Message)
    }
}

function Set-EpicCompanionSetting {
    <#
    .SYNOPSIS
        Changes persistent Epic companion settings.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Quiet', 'Balanced', 'Performance')]
        [string]$DefaultThermalProfile,
        [bool]$UseLosslessScaling,
        [bool]$CloseLosslessScalingAfterGame,
        [string]$LosslessScalingPathOverride,
        [ValidateRange(30, 3600)]
        [int]$GameStartTimeoutSeconds,
        [ValidateRange(1, 30)]
        [int]$PollIntervalSeconds
    )

    $setting = Get-EpicCompanionSetting
    foreach ($propertyName in @('DefaultThermalProfile', 'UseLosslessScaling', 'CloseLosslessScalingAfterGame', 'LosslessScalingPathOverride', 'GameStartTimeoutSeconds', 'PollIntervalSeconds')) {
        if ($PSBoundParameters.ContainsKey($propertyName)) {
            $setting.$propertyName = $PSBoundParameters[$propertyName]
        }
    }
    Write-EpicCompanionSetting -Setting $setting
    Get-EpicCompanionSetting
}

function Get-EpicGameProfile {
    <#
    .SYNOPSIS
        Gets saved per-game Epic profiles.

    .DESCRIPTION
        Returns saved thermal and process-name overrides from Settings.json.
        Supply an App ID to return one profile.
    #>
    [CmdletBinding()]
    param([string]$AppId)

    $setting = Get-EpicCompanionSetting
    $profiles = @(
        foreach ($property in @($setting.GameOverrides.PSObject.Properties)) {
            $value = $property.Value
            $profileProcessNames = [string[]]@()
            if ($value.PSObject.Properties['ProcessName']) {
                $profileProcessNames = [string[]]@($value.ProcessName)
            }
            [pscustomobject]@{
                AppId          = [string]$property.Name
                ThermalProfile      = if ($value.PSObject.Properties['ThermalProfile']) { [string]$value.ThermalProfile } else { $null }
                UseLosslessScaling  = if ($value.PSObject.Properties['UseLosslessScaling']) { [bool]$value.UseLosslessScaling } else { $null }
                ProcessName          = $profileProcessNames
            }
        }
    )
    if ($AppId) { $profiles = @($profiles | Where-Object AppId -EQ $AppId) }
    $profiles | Sort-Object AppId
}

function Set-EpicGameProfile {
    <#
    .SYNOPSIS
        Creates or updates a saved profile for one Epic game.

    .DESCRIPTION
        Stores a per-game thermal profile and optional process-name overrides. Only
        explicitly supplied properties are changed, so adding a process override does
        not replace an existing thermal profile.

    .PARAMETER AppId
        Stable Epic AppName/AppId to configure.

    .PARAMETER ThermalProfile
        Saved thermal profile: Quiet, Balanced, or Performance.

    .PARAMETER ProcessName
        Optional process filename(s) used when the manifest LaunchExecutable is only a
        bootstrapper or otherwise unsuitable for session detection. Names may be supplied
        with or without the .exe extension.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AppId,
        [ValidateSet('Quiet', 'Balanced', 'Performance')][string]$ThermalProfile,
        [Nullable[bool]]$UseLosslessScaling,
        [string[]]$ProcessName
    )

    if (-not ($PSBoundParameters.ContainsKey('ThermalProfile') -or
        $PSBoundParameters.ContainsKey('UseLosslessScaling') -or
        $PSBoundParameters.ContainsKey('ProcessName'))) {
        throw 'Specify at least one profile value: ThermalProfile, UseLosslessScaling, or ProcessName.'
    }

    $setting = Get-EpicCompanionSetting
    $existingProperty = $setting.GameOverrides.PSObject.Properties[$AppId]
    $profile = if ($existingProperty) { $existingProperty.Value } else { [pscustomobject]@{} }

    if ($PSBoundParameters.ContainsKey('ThermalProfile')) {
        if ($profile.PSObject.Properties['ThermalProfile']) { $profile.ThermalProfile = $ThermalProfile }
        else { $profile | Add-Member -MemberType NoteProperty -Name ThermalProfile -Value $ThermalProfile }
    }
    if ($PSBoundParameters.ContainsKey('UseLosslessScaling')) {
        if ($profile.PSObject.Properties['UseLosslessScaling']) { $profile.UseLosslessScaling = [bool]$UseLosslessScaling }
        else { $profile | Add-Member -MemberType NoteProperty -Name UseLosslessScaling -Value ([bool]$UseLosslessScaling) }
    }
    if ($PSBoundParameters.ContainsKey('ProcessName')) {
        $normalizedProcessNames = [string[]]@(
            $ProcessName |
                ForEach-Object { [string]$_ } |
                Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
        )
        if (@($normalizedProcessNames).Count -gt 0) {
            if ($profile.PSObject.Properties['ProcessName']) { $profile.ProcessName = $normalizedProcessNames }
            else { $profile | Add-Member -MemberType NoteProperty -Name ProcessName -Value $normalizedProcessNames }
        }
        elseif ($profile.PSObject.Properties['ProcessName']) {
            $profile.PSObject.Properties.Remove('ProcessName')
        }
    }

    if (-not $profile.PSObject.Properties['ThermalProfile'] -and
        -not $profile.PSObject.Properties['UseLosslessScaling'] -and
        -not $profile.PSObject.Properties['ProcessName']) {
        throw 'A saved game profile must contain ThermalProfile, UseLosslessScaling, or at least one ProcessName.'
    }

    if ($existingProperty) { $setting.GameOverrides.$AppId = $profile }
    else { $setting.GameOverrides | Add-Member -MemberType NoteProperty -Name $AppId -Value $profile }

    Write-EpicCompanionSetting -Setting $setting
    Get-EpicGameProfile -AppId $AppId
}

function Remove-EpicGameProfile {
    <#
    .SYNOPSIS
        Removes a saved per-game Epic thermal profile.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)][string]$AppId)

    $setting = Get-EpicCompanionSetting
    if (-not $setting.GameOverrides.PSObject.Properties[$AppId]) { return }
    if ($PSCmdlet.ShouldProcess("Epic App ID $AppId", 'Remove saved game profile')) {
        $setting.GameOverrides.PSObject.Properties.Remove($AppId)
        Write-EpicCompanionSetting -Setting $setting
    }
}

function Get-ResolvedEpicThermalProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Game,
        [string]$ExplicitThermalProfile,
        [bool]$HasExplicitThermalProfile
    )

    if ($HasExplicitThermalProfile) {
        return [pscustomobject]@{ ThermalProfile = $ExplicitThermalProfile; Source = 'Explicit' }
    }

    $setting = Get-EpicCompanionSetting
    $overrideProperty = $setting.GameOverrides.PSObject.Properties[[string]$Game.AppId]
    if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['ThermalProfile']) {
        return [pscustomobject]@{ ThermalProfile = [string]$overrideProperty.Value.ThermalProfile; Source = 'Game' }
    }

    [pscustomobject]@{ ThermalProfile = [string]$setting.DefaultThermalProfile; Source = 'Global' }
}

function Get-EpicManifestPath {
    <#
    .SYNOPSIS
        Discovers Epic Games Launcher manifest folders.

    .DESCRIPTION
        Checks the Epic Games Launcher registry AppDataPath and the standard
        ProgramData location. Duplicate paths are removed before output.
        This function is private to the module.
    #>
    [CmdletBinding()]
    param()

    $candidatePaths = New-Object System.Collections.Generic.List[string]
    $registryPaths = @(
        'HKLM:\SOFTWARE\WOW6432Node\Epic Games\EpicGamesLauncher',
        'HKLM:\SOFTWARE\Epic Games\EpicGamesLauncher'
    )

    foreach ($registryPath in $registryPaths) {
        if (-not (Test-Path -LiteralPath $registryPath)) { continue }

        $properties = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if (-not $properties) { continue }

        $appDataProperty = $properties.PSObject.Properties['AppDataPath']
        if (-not $appDataProperty) { continue }

        $appDataPath = [string]$appDataProperty.Value
        if ([string]::IsNullOrWhiteSpace($appDataPath)) { continue }

        if ((Split-Path -Path $appDataPath -Leaf) -ieq 'Manifests') {
            $candidatePaths.Add($appDataPath)
        }
        elseif ((Split-Path -Path $appDataPath -Leaf) -ieq 'Data') {
            $candidatePaths.Add((Join-Path -Path $appDataPath -ChildPath 'Manifests'))
        }
        else {
            $candidatePaths.Add((Join-Path -Path $appDataPath -ChildPath 'Data\Manifests'))
            $candidatePaths.Add((Join-Path -Path $appDataPath -ChildPath 'Manifests'))
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($env:ProgramData)) {
        $candidatePaths.Add(
            (Join-Path -Path $env:ProgramData -ChildPath 'Epic\EpicGamesLauncher\Data\Manifests')
        )
    }

    $candidatePaths |
        Where-Object { Test-Path -LiteralPath $_ -PathType Container } |
        Select-Object -Unique
}

function ConvertFrom-EpicGameManifest {
    <#
    .SYNOPSIS
        Converts one Epic .item manifest into a discovery object.

    .DESCRIPTION
        Parses the JSON manifest, excludes incomplete installs, Unreal Engine
        components, and non-launchable addons, and returns a normalized game object.
        This function is private to the module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.IO.FileInfo]$Manifest,

        [switch]$IncludeMissingInstallPath
    )

    $content = Get-Content -LiteralPath $Manifest.FullName -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($content)) { return }

    try {
        $item = $content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return
    }

    $appNameProperty = $item.PSObject.Properties['AppName']
    $installLocationProperty = $item.PSObject.Properties['InstallLocation']
    if (-not $appNameProperty -or -not $installLocationProperty) { return }

    $appName = [string]$appNameProperty.Value
    $installLocation = [string]$installLocationProperty.Value
    if ([string]::IsNullOrWhiteSpace($appName) -or [string]::IsNullOrWhiteSpace($installLocation)) { return }

    if ($appName -like 'UE_*') { return }

    $incompleteProperty = $item.PSObject.Properties['bIsIncompleteInstall']
    if ($incompleteProperty -and [bool]$incompleteProperty.Value) { return }

    $categories = @()
    $categoryProperty = $item.PSObject.Properties['AppCategories']
    if ($categoryProperty -and $null -ne $categoryProperty.Value) {
        $categories = @($categoryProperty.Value | ForEach-Object { [string]$_ })
    }

    if ($categories -contains 'addons' -and $categories -notcontains 'addons/launchable') {
        return
    }

    if (-not $IncludeMissingInstallPath -and
        -not (Test-Path -LiteralPath $installLocation -PathType Container)) {
        return
    }

    $displayName = $appName
    $displayNameProperty = $item.PSObject.Properties['DisplayName']
    if ($displayNameProperty -and -not [string]::IsNullOrWhiteSpace([string]$displayNameProperty.Value)) {
        $displayName = [string]$displayNameProperty.Value
    }

    $launchExecutable = ''
    $launchExecutableProperty = $item.PSObject.Properties['LaunchExecutable']
    if ($launchExecutableProperty) {
        $launchExecutable = [string]$launchExecutableProperty.Value
    }

    $launchPath = $null
    if (-not [string]::IsNullOrWhiteSpace($launchExecutable)) {
        $launchPath = Join-Path -Path $installLocation -ChildPath $launchExecutable
    }

    $catalogNamespace = ''
    $catalogNamespaceProperty = $item.PSObject.Properties['CatalogNamespace']
    if ($catalogNamespaceProperty) {
        $catalogNamespace = [string]$catalogNamespaceProperty.Value
    }

    $catalogItemId = ''
    $catalogItemProperty = $item.PSObject.Properties['CatalogItemId']
    if ($catalogItemProperty) {
        $catalogItemId = [string]$catalogItemProperty.Value
    }

    $mainGameAppName = ''
    $mainGameProperty = $item.PSObject.Properties['MainGameAppName']
    if ($mainGameProperty) {
        $mainGameAppName = [string]$mainGameProperty.Value
    }

    $launchCommand = ''
    $launchCommandProperty = $item.PSObject.Properties['LaunchCommand']
    if ($launchCommandProperty) {
        $launchCommand = [string]$launchCommandProperty.Value
    }

    $launchIdentifier = $appName
    if (-not [string]::IsNullOrWhiteSpace($catalogNamespace) -and
        -not [string]::IsNullOrWhiteSpace($catalogItemId)) {
        $launchIdentifier = '{0}%3A{1}%3A{2}' -f $catalogNamespace, $catalogItemId, $appName
    }

    [pscustomobject]@{
        Name              = $displayName
        AppId             = $appName
        AppName           = $appName
        CatalogNamespace  = $catalogNamespace
        CatalogItemId     = $catalogItemId
        MainGameAppName   = $mainGameAppName
        InstallPath       = $installLocation
        LaunchExecutable  = $launchExecutable
        LaunchPath        = $launchPath
        LaunchCommand     = $launchCommand
        LaunchUri         = 'com.epicgames.launcher://apps/{0}?action=launch&silent=true' -f $launchIdentifier
        AppCategories     = $categories
        Manifest          = $Manifest.FullName
    }
}

function Get-EpicInstalledGame {
    <#
    .SYNOPSIS
        Gets games currently installed through Epic Games Launcher.

    .DESCRIPTION
        Parses Epic Games Launcher .item manifests and returns each installed game's
        display name, stable AppName identifier, catalog identifiers, installation
        path, launch executable, launch URI, categories, and source manifest.

        By default the function discovers the Epic manifest directory automatically.
        ManifestPath can be supplied for testing or nonstandard layouts.

    .PARAMETER Name
        Filters results using a case-insensitive wildcard match against the game name.

    .PARAMETER AppId
        Filters results to one Epic AppName identifier.

    .PARAMETER ManifestPath
        Optional Epic manifest directory to scan instead of automatic discovery.

    .PARAMETER IncludeMissingInstallPath
        Includes manifest records whose InstallLocation no longer exists.

    .OUTPUTS
        PSCustomObject for each installed Epic game.

    .EXAMPLE
        Get-EpicInstalledGame

    .EXAMPLE
        Get-EpicInstalledGame -Name 'Alan Wake'

    .EXAMPLE
        Get-EpicInstalledGame -AppId 'Fortnite'
    #>
    [CmdletBinding()]
    param(
        [string]$Name,
        [string]$AppId,
        [string[]]$ManifestPath,
        [switch]$IncludeMissingInstallPath
    )

    $manifestPaths = @()
    if ($ManifestPath) {
        $manifestPaths = @($ManifestPath)
    }
    else {
        $manifestPaths = @(Get-EpicManifestPath)
    }

    $games = foreach ($path in $manifestPaths) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) { continue }

        foreach ($manifest in (Get-ChildItem -LiteralPath $path -Filter '*.item' -File -ErrorAction SilentlyContinue)) {
            ConvertFrom-EpicGameManifest -Manifest $manifest -IncludeMissingInstallPath:$IncludeMissingInstallPath
        }
    }

    # AppName is Epic's stable local application identifier. Collapse duplicate
    # manifests by AppName while preferring an entry whose launch executable exists.
    $games = @(
        $games |
            Sort-Object AppId, Manifest |
            Group-Object AppId |
            ForEach-Object {
                $_.Group |
                    Sort-Object @{ Expression = { if ($_.LaunchPath -and (Test-Path -LiteralPath $_.LaunchPath -PathType Leaf)) { 0 } else { 1 } } }, Manifest |
                    Select-Object -First 1
            }
    )

    if ($AppId) { $games = $games | Where-Object AppId -EQ $AppId }
    if ($Name) { $games = $games | Where-Object Name -Like "*$Name*" }

    $games | Sort-Object Name, AppId
}

function Get-EpicProcessSnapshot {
    <#
    .SYNOPSIS
        Captures a lightweight Win32_Process snapshot.

    .DESCRIPTION
        Returns process identity, parent PID, executable path, command line, and
        creation time for launch tracing. Access to ExecutablePath or CommandLine
        can be denied for individual processes; those fields are left blank.
        This function is private to the module.
    #>
    [CmdletBinding()]
    param()

    Get-CimInstance -ClassName Win32_Process -ErrorAction Stop | ForEach-Object {
        $creationDate = $null
        if ($_.CreationDate) {
            try { $creationDate = [Management.ManagementDateTimeConverter]::ToDateTime([string]$_.CreationDate) }
            catch { $creationDate = $null }
        }

        [pscustomobject]@{
            ProcessName     = [string]$_.Name
            ProcessId       = [int]$_.ProcessId
            ParentProcessId = [int]$_.ParentProcessId
            ExecutablePath  = [string]$_.ExecutablePath
            CommandLine     = [string]$_.CommandLine
            CreationTime    = $creationDate
        }
    }
}

function Get-EpicCompanionSteamLibraryPath {
    [CmdletBinding()]
    param()

    $steamRoots = New-Object System.Collections.Generic.List[string]
    foreach ($registryPath in @('HKCU:\Software\Valve\Steam','HKLM:\Software\WOW6432Node\Valve\Steam','HKLM:\Software\Valve\Steam')) {
        if (-not (Test-Path -LiteralPath $registryPath)) { continue }
        $properties = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if (-not $properties) { continue }
        foreach ($propertyName in @('SteamPath','InstallPath')) {
            $property = $properties.PSObject.Properties[$propertyName]
            if ($property -and (Test-Path -LiteralPath ([string]$property.Value) -PathType Container)) {
                $steamRoots.Add([string]$property.Value)
            }
        }
    }
    foreach ($defaultRoot in @((Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Steam'),(Join-Path -Path $env:ProgramFiles -ChildPath 'Steam'))) {
        if (Test-Path -LiteralPath $defaultRoot -PathType Container) { $steamRoots.Add($defaultRoot) }
    }
    $libraries = New-Object System.Collections.Generic.List[string]
    foreach ($steamRoot in ($steamRoots | Select-Object -Unique)) {
        $libraries.Add($steamRoot)
        $libraryFile = Join-Path -Path $steamRoot -ChildPath 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path -LiteralPath $libraryFile -PathType Leaf)) { continue }
        foreach ($line in (Get-Content -LiteralPath $libraryFile -ErrorAction SilentlyContinue)) {
            if ($line -match '^\s*"path"\s+"(?<Path>.+)"\s*$') {
                $path = $Matches.Path -replace '\\\\','\'
                if (Test-Path -LiteralPath $path -PathType Container) { $libraries.Add($path) }
            }
        }
    }
    $libraries | Select-Object -Unique
}

function Get-EpicLosslessScalingPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][psobject]$Setting)

    if ($Setting.LosslessScalingPathOverride) {
        if (Test-Path -LiteralPath $Setting.LosslessScalingPathOverride -PathType Leaf) { return $Setting.LosslessScalingPathOverride }
        throw "The Lossless Scaling override does not exist: $($Setting.LosslessScalingPathOverride)"
    }
    foreach ($registryPath in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 993090',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 993090',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 993090'
    )) {
        if (-not (Test-Path -LiteralPath $registryPath)) { continue }
        $properties = Get-ItemProperty -LiteralPath $registryPath -ErrorAction SilentlyContinue
        if ($properties.DisplayIcon) {
            $path = ($properties.DisplayIcon -replace ',\d+$','').Trim('"')
            if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
        }
    }
    foreach ($library in (Get-EpicCompanionSteamLibraryPath)) {
        foreach ($fileName in @('LosslessScaling.exe','Lossless Scaling.exe')) {
            $candidate = Join-Path -Path $library -ChildPath "steamapps\common\Lossless Scaling\$fileName"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    return $null
}

function Set-ElevatedEpicLegionThermalMode {
    <#
    .SYNOPSIS
        Applies one Legion thermal mode from an elevated helper process.

    .DESCRIPTION
        Only the thermal-mode write is elevated. Epic Games Launcher and the game
        continue to run in the original user context. This function is private to
        the module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Quiet', 'Balanced', 'Performance')]
        [string]$Mode
    )

    if (-not (Test-Path -LiteralPath $script:WindowsPowerShellPath -PathType Leaf)) {
        throw "Windows PowerShell 5.1 was not found: $script:WindowsPowerShellPath"
    }

    if (-not (Test-Path -LiteralPath $script:ThermalHelperPath -PathType Leaf)) {
        throw "Thermal helper was not found: $script:ThermalHelperPath"
    }

    Write-Output ("Requesting {0} thermal mode..." -f $Mode)
    $process = Start-Process -FilePath $script:WindowsPowerShellPath -Verb RunAs -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"{0}"' -f $script:ThermalHelperPath),
        '-Mode', $Mode
    ) -WindowStyle Hidden -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "The elevated thermal helper failed to set $Mode mode. Exit code: $($process.ExitCode)"
    }
}

function Trace-EpicGameLaunch {
    <#
    .SYNOPSIS
        Launches one Epic title and reports processes created by the launch.

    .DESCRIPTION
        Diagnostic command for learning Epic launch behavior before session tracking
        is implemented. The command resolves exactly one installed Epic game, takes
        a process snapshot, launches the game's Epic protocol URI, then samples new
        processes during an observation window.

        No Legion Go thermal settings are changed.

        New processes are returned once, with simple hints showing whether the
        process matches the manifest LaunchExecutable or is descended from a process
        created during this trace.

    .PARAMETER Name
        Selects an installed Epic game by display name. Wildcards are supported by
        Get-EpicInstalledGame. The result must resolve to exactly one title.

    .PARAMETER AppId
        Selects one installed Epic game by its stable Epic AppName identifier.

    .PARAMETER ObservationSeconds
        Number of seconds to observe for new processes after launch. Default: 20.

    .PARAMETER PollIntervalMilliseconds
        Delay between process snapshots. Default: 500 milliseconds.

    .PARAMETER PassThruGame
        Emits the resolved game object before process-trace results.

    .OUTPUTS
        PSCustomObject records describing processes first seen after launch.

    .EXAMPLE
        Trace-EpicGameLaunch -Name 'Foretales'

    .EXAMPLE
        Trace-EpicGameLaunch -AppId '4256d7c7170f4326a1a861d0b30f1af7' -ObservationSeconds 30
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByAppId')]
        [string]$AppId,

        [ValidateRange(1, 300)]
        [int]$ObservationSeconds = 20,

        [ValidateRange(100, 5000)]
        [int]$PollIntervalMilliseconds = 500,

        [switch]$PassThruGame
    )

    [object[]]$games = @(
        if ($PSCmdlet.ParameterSetName -eq 'ByAppId') {
            Get-EpicInstalledGame -AppId $AppId
        }
        else {
            Get-EpicInstalledGame -Name $Name
        }
    )

    if (@($games).Count -eq 0) {
        throw 'No installed Epic game matched the requested selection.'
    }

    if (@($games).Count -gt 1) {
        $matchedNames = ($games | ForEach-Object { $_.Name }) -join ', '
        throw ("The selection matched more than one Epic game: {0}. Use -AppId or a more specific -Name." -f $matchedNames)
    }

    $game = $games[0]
    if ([string]::IsNullOrWhiteSpace([string]$game.LaunchUri)) {
        throw ("Epic game '{0}' does not have a launch URI." -f $game.Name)
    }

    $launchExecutableName = ''
    if (-not [string]::IsNullOrWhiteSpace([string]$game.LaunchExecutable)) {
        $launchExecutableName = [System.IO.Path]::GetFileName([string]$game.LaunchExecutable)
    }

    Write-Output ("Tracing Epic launch for: {0}" -f $game.Name)
    Write-Output ("Launch URI: {0}" -f $game.LaunchUri)
    Write-Output ("Observation window: {0} seconds" -f $ObservationSeconds)
    Write-Output 'No Legion Go thermal settings will be changed.'

    $before = @(Get-EpicProcessSnapshot)
    $knownProcessIds = @{}
    foreach ($process in $before) {
        $knownProcessIds[[int]$process.ProcessId] = $true
    }

    if ($PassThruGame) {
        $game
    }

    Start-Process -FilePath ([string]$game.LaunchUri) -ErrorAction Stop
    $traceStart = Get-Date
    $deadline = $traceStart.AddSeconds($ObservationSeconds)
    $createdProcessIds = @{}

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds $PollIntervalMilliseconds

        $snapshot = @(Get-EpicProcessSnapshot)
        foreach ($process in $snapshot) {
            $processId = [int]$process.ProcessId
            if ($knownProcessIds.ContainsKey($processId)) { continue }

            $knownProcessIds[$processId] = $true
            $createdProcessIds[$processId] = $true

            $matchType = 'NewProcess'
            if (-not [string]::IsNullOrWhiteSpace($launchExecutableName) -and
                [string]$process.ProcessName -ieq $launchExecutableName) {
                $matchType = 'ManifestLaunchExecutable'
            }
            elseif ($createdProcessIds.ContainsKey([int]$process.ParentProcessId)) {
                $matchType = 'ChildOfNewProcess'
            }

            [pscustomobject]@{
                GameName          = $game.Name
                AppId             = $game.AppId
                MatchType         = $matchType
                ProcessName       = $process.ProcessName
                ProcessId         = $process.ProcessId
                ParentProcessId   = $process.ParentProcessId
                ExecutablePath    = $process.ExecutablePath
                CommandLine       = $process.CommandLine
                CreationTime      = $process.CreationTime
                SecondsAfterLaunch = [math]::Round(((Get-Date) - $traceStart).TotalSeconds, 2)
            }
        }
    }
}


function Start-EpicGame {
    <#
    .SYNOPSIS
        Launches and monitors one installed Epic Games Launcher title.

    .DESCRIPTION
        Resolves exactly one installed Epic game, snapshots any already-running
        instances of the manifest LaunchExecutable, invokes the Epic protocol URI,
        and waits for a new matching process to appear.

        A newly detected process must remain alive for StabilitySeconds before it
        becomes the session process. Epic launcher helpers, EOS installers, overlays,
        and unrelated processes are never adopted as the game session.

        Before launch, an optional Quiet, Balanced, or Performance thermal profile
        is applied through a small elevated helper. Epic and the game remain
        unelevated. After the session process is established, the command waits for
        that PID to exit and restores Balanced when a non-Balanced profile was
        applied. The completed session is returned as a summary object.

    .PARAMETER Name
        Selects an installed Epic game by display name. Wildcards are supported by
        Get-EpicInstalledGame. The result must resolve to exactly one title.

    .PARAMETER AppId
        Selects one installed Epic game by its stable Epic AppName identifier.

    .PARAMETER ThermalProfile
        Optional thermal profile override for this launch: Quiet, Balanced, or Performance.
        TDProfile is provided as a shorter alias. When omitted, a saved per-game
        profile is used, then the global default, then Balanced.

    .PARAMETER ProcessName
        Optional one-session process filename override. When omitted, a saved per-game
        ProcessName override is used; otherwise the manifest LaunchExecutable is used.

    .PARAMETER LaunchTimeoutSeconds
        Maximum time to wait for a new game process after invoking Epic.
        When omitted, uses the persisted GameStartTimeoutSeconds setting.

    .PARAMETER PollIntervalMilliseconds
        Optional one-session delay between process checks. When omitted, uses
        the persisted PollIntervalSeconds setting.

    .PARAMETER StabilitySeconds
        Time a candidate game PID must remain alive before launch is accepted.
        Default: 2 seconds.

    .OUTPUTS
        PSCustomObject describing the completed Epic game session.

    .EXAMPLE
        Start-EpicGame -Name 'Foretales' -ThermalProfile Performance

    .EXAMPLE
        Start-EpicGame -AppId '487bfeacfebe4d2a921b0b1478ad6625' -LaunchTimeoutSeconds 90
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByAppId')]
        [string]$AppId,

        [Alias('TDProfile')]
        [ValidateSet('Quiet', 'Balanced', 'Performance')]
        [string]$ThermalProfile,

        [string[]]$ProcessName,

        [Nullable[bool]]$UseLosslessScaling,

        [ValidateRange(5, 3600)]
        [int]$LaunchTimeoutSeconds,

        [ValidateRange(100, 5000)]
        [int]$PollIntervalMilliseconds,

        [ValidateRange(0, 10)]
        [int]$StabilitySeconds = 2
    )

    [object[]]$games = @(
        if ($PSCmdlet.ParameterSetName -eq 'ByAppId') {
            Get-EpicInstalledGame -AppId $AppId
        }
        else {
            Get-EpicInstalledGame -Name $Name
        }
    )

    if (@($games).Count -eq 0) {
        throw 'No installed Epic game matched the requested selection.'
    }

    if (@($games).Count -gt 1) {
        $matchedNames = ($games | ForEach-Object { $_.Name }) -join ', '
        throw ("The selection matched more than one Epic game: {0}. Use -AppId or a more specific -Name." -f $matchedNames)
    }

    $game = $games[0]
    if ([string]::IsNullOrWhiteSpace([string]$game.LaunchUri)) {
        throw ("Epic game '{0}' does not have a launch URI." -f $game.Name)
    }

    if ([string]::IsNullOrWhiteSpace([string]$game.LaunchExecutable)) {
        throw ("Epic game '{0}' does not define LaunchExecutable in its manifest." -f $game.Name)
    }

    $manifestExecutableName = [System.IO.Path]::GetFileName([string]$game.LaunchExecutable)
    if ([string]::IsNullOrWhiteSpace($manifestExecutableName)) {
        throw ("Epic game '{0}' has an invalid LaunchExecutable value: {1}" -f $game.Name, $game.LaunchExecutable)
    }

    $setting = Get-EpicCompanionSetting
    $effectiveLaunchTimeoutSeconds = if ($PSBoundParameters.ContainsKey('LaunchTimeoutSeconds')) { $LaunchTimeoutSeconds } else { [int]$setting.GameStartTimeoutSeconds }
    $effectivePollIntervalMilliseconds = if ($PSBoundParameters.ContainsKey('PollIntervalMilliseconds')) { $PollIntervalMilliseconds } else { [int]$setting.PollIntervalSeconds * 1000 }
    $overrideProperty = $setting.GameOverrides.PSObject.Properties[[string]$game.AppId]
    $hasExplicitProcessName = $PSBoundParameters.ContainsKey('ProcessName')
    [string[]]$resolvedProcessNames = @(
        if ($hasExplicitProcessName) {
            $ProcessName
        }
        elseif ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['ProcessName'] -and $overrideProperty.Value.ProcessName) {
            $overrideProperty.Value.ProcessName
        }
        else {
            $manifestExecutableName
        }
    ) | ForEach-Object {
        $name = [System.IO.Path]::GetFileName([string]$_)
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            if ([System.IO.Path]::GetExtension($name)) { $name } else { "$name.exe" }
        }
    }
    $resolvedProcessNames = [string[]]@($resolvedProcessNames | Select-Object -Unique)
    if (@($resolvedProcessNames).Count -eq 0) {
        throw ("Epic game '{0}' does not have a usable session process name." -f $game.Name)
    }
    $processNameSource = if ($hasExplicitProcessName) { 'Explicit' } elseif ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['ProcessName'] -and $overrideProperty.Value.ProcessName) { 'Game' } else { 'Manifest' }

    $hasExplicitThermalProfile = $PSBoundParameters.ContainsKey('ThermalProfile')
    $resolvedProfile = Get-ResolvedEpicThermalProfile -Game $game -ExplicitThermalProfile $ThermalProfile -HasExplicitThermalProfile $hasExplicitThermalProfile
    $effectiveThermalProfile = [string]$resolvedProfile.ThermalProfile
    $thermalProfileSource = [string]$resolvedProfile.Source

    $hasExplicitLosslessScaling = $PSBoundParameters.ContainsKey('UseLosslessScaling')
    if ($hasExplicitLosslessScaling) {
        $effectiveUseLosslessScaling = [bool]$UseLosslessScaling
        $losslessScalingSource = 'Explicit'
    }
    elseif ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['UseLosslessScaling']) {
        $effectiveUseLosslessScaling = [bool]$overrideProperty.Value.UseLosslessScaling
        $losslessScalingSource = 'Game'
    }
    else {
        $effectiveUseLosslessScaling = [bool]$setting.UseLosslessScaling
        $losslessScalingSource = 'Global'
    }

    # Capture only existing instances of the expected manifest executable. A process
    # that existed before this command can never become this launch session's anchor.
    $existingProcessIds = @{}
    foreach ($process in @(Get-EpicProcessSnapshot)) {
        if (@($resolvedProcessNames | Where-Object { [string]$process.ProcessName -ieq $_ }).Count -gt 0) {
            $existingProcessIds[[int]$process.ProcessId] = $true
        }
    }

    Write-Output ("Thermal profile for this session: {0} ({1})" -f $effectiveThermalProfile, $thermalProfileSource)
    Write-Output ("Lossless Scaling for this session: {0} ({1})" -f $(if ($effectiveUseLosslessScaling) { 'On' } else { 'Off' }), $losslessScalingSource)
    Write-Output ("Launching Epic game: {0}" -f $game.Name)
    Write-Output ("Session process: {0} ({1})" -f ($resolvedProcessNames -join ", "), $processNameSource)
    Write-Output ("Launch timeout: {0} seconds" -f $effectiveLaunchTimeoutSeconds)

    $thermalModeChanged = $false
    $losslessScalingWasRunning = $false
    $losslessScalingStartedProcess = $null
    $sessionResult = $null

    try {
        if ($effectiveThermalProfile -ne 'Balanced') {
            Set-ElevatedEpicLegionThermalMode -Mode $effectiveThermalProfile
            $thermalModeChanged = $true
        }
        else {
            Write-Output 'Balanced is the baseline; no pre-launch thermal mode change is required.'
        }

        if ($effectiveUseLosslessScaling) {
            $losslessScalingWasRunning = [bool](Get-Process -Name 'LosslessScaling' -ErrorAction SilentlyContinue)
            if (-not $losslessScalingWasRunning) {
                $losslessScalingPath = Get-EpicLosslessScalingPath -Setting $setting
                if (-not $losslessScalingPath) { throw 'Lossless Scaling could not be located.' }
                Write-Output ("Starting Lossless Scaling: {0}" -f $losslessScalingPath)
                $losslessScalingStartedProcess = Start-Process -FilePath $losslessScalingPath -ArgumentList '-StartMinimized' -PassThru -ErrorAction Stop
            }
            else {
                Write-Output 'Lossless Scaling is already running.'
            }
        }
        else {
            Write-Output 'Lossless Scaling is disabled for this launch.'
        }

        $launchRequestedAt = Get-Date
        Start-Process -FilePath ([string]$game.LaunchUri) -ErrorAction Stop

        $deadline = $launchRequestedAt.AddSeconds($effectiveLaunchTimeoutSeconds)
        $rejectedCandidateIds = @{}
        $sessionProcess = $null

        while ((Get-Date) -lt $deadline -and $null -eq $sessionProcess) {
            Start-Sleep -Milliseconds $effectivePollIntervalMilliseconds

            $candidates = @(
                Get-EpicProcessSnapshot |
                    Where-Object {
                        [string]$_.ProcessName -in $resolvedProcessNames -and
                        -not $existingProcessIds.ContainsKey([int]$_.ProcessId) -and
                        -not $rejectedCandidateIds.ContainsKey([int]$_.ProcessId)
                    }
            )

            foreach ($candidate in $candidates) {
                $candidateId = [int]$candidate.ProcessId

                if ($StabilitySeconds -gt 0) {
                    Start-Sleep -Seconds $StabilitySeconds
                    $stillRunning = Get-Process -Id $candidateId -ErrorAction SilentlyContinue
                    if ($null -eq $stillRunning) {
                        $rejectedCandidateIds[$candidateId] = $true
                        continue
                    }
                }

                $sessionProcess = $candidate
                break
            }
        }

        if ($null -eq $sessionProcess) {
            throw ("Epic accepted the launch request for '{0}', but no new session process ({1}) was detected within {2} seconds. The game may be updating, installing prerequisites, waiting for user interaction, or require a ProcessName override." -f $game.Name, ($resolvedProcessNames -join ', '), $effectiveLaunchTimeoutSeconds)
        }

        $sessionProcessId = [int]$sessionProcess.ProcessId
        $sessionStartedAt = Get-Date
        $secondsToDetect = [math]::Round(($sessionStartedAt - $launchRequestedAt).TotalSeconds, 2)

        Write-Output ("Game session detected: {0} (PID {1}) after {2} seconds." -f $sessionProcess.ProcessName, $sessionProcessId, $secondsToDetect)
        Write-Output 'Monitoring game session. Close the game normally to complete this command.'

        while ($null -ne (Get-Process -Id $sessionProcessId -ErrorAction SilentlyContinue)) {
            Start-Sleep -Milliseconds $effectivePollIntervalMilliseconds
        }

        $sessionEndedAt = Get-Date
        $duration = $sessionEndedAt - $sessionStartedAt
        Write-Output ("Game session ended: {0} (PID {1})." -f $sessionProcess.ProcessName, $sessionProcessId)

        $sessionResult = [pscustomobject]@{
            GameName             = $game.Name
            AppId                = $game.AppId
            ThermalProfile       = $effectiveThermalProfile
            ThermalProfileSource = $thermalProfileSource
            UseLosslessScaling   = $effectiveUseLosslessScaling
            LosslessScalingSource = $losslessScalingSource
            ProcessName          = $sessionProcess.ProcessName
            ProcessNameSource    = $processNameSource
            ProcessId            = $sessionProcessId
            ExecutablePath       = $sessionProcess.ExecutablePath
            LaunchUri            = $game.LaunchUri
            LaunchRequestedAt    = $launchRequestedAt
            SessionStartedAt     = $sessionStartedAt
            SessionEndedAt       = $sessionEndedAt
            SecondsToDetection   = $secondsToDetect
            Duration             = $duration
            DurationSeconds      = [math]::Round($duration.TotalSeconds, 2)
            LaunchTimeoutSeconds = $effectiveLaunchTimeoutSeconds
            StabilitySeconds     = $StabilitySeconds
        }
    }
    finally {
        if ($effectiveUseLosslessScaling -and $setting.CloseLosslessScalingAfterGame -and $losslessScalingStartedProcess -and -not $losslessScalingWasRunning) {
            Write-Output 'Closing Lossless Scaling...'
            Get-Process -Id $losslessScalingStartedProcess.Id -ErrorAction SilentlyContinue | Stop-Process -ErrorAction SilentlyContinue
        }
        if ($thermalModeChanged) {
            try {
                Set-ElevatedEpicLegionThermalMode -Mode Balanced
                Write-Output 'Balanced thermal mode restored.'
            }
            catch {
                Write-Warning ("Failed to restore Balanced mode: {0}" -f $_.Exception.Message)
            }
        }
    }

    if ($null -ne $sessionResult) {
        $sessionResult
    }
}

function Start-EpicGameSession {
    <#
    .SYNOPSIS
        Launches and monitors one installed Epic Games Launcher title.

    .DESCRIPTION
        Steam-family command name for Start-EpicGame. Start-EpicGame remains
        available for backward compatibility.
    #>
    [CmdletBinding(DefaultParameterSetName = 'ByName')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [string]$Name,

        [Parameter(Mandatory, ParameterSetName = 'ByAppId')]
        [string]$AppId,

        [Alias('TDProfile')]
        [ValidateSet('Quiet', 'Balanced', 'Performance')]
        [string]$ThermalProfile,

        [string[]]$ProcessName,
        [Nullable[bool]]$UseLosslessScaling,

        [ValidateRange(5, 3600)]
        [int]$LaunchTimeoutSeconds,

        [ValidateRange(100, 5000)]
        [int]$PollIntervalMilliseconds,

        [ValidateRange(0, 10)]
        [int]$StabilitySeconds
    )

    Start-EpicGame @PSBoundParameters
}


function Select-EpicThermalProfile {
    [CmdletBinding()]
    param(
        [string]$Title = 'Select thermal profile',
        [switch]$AllowInherit
    )

    while ($true) {
        Write-Host ''
        Write-Host $Title
        Write-Host '  [1] Quiet'
        Write-Host '  [2] Balanced'
        Write-Host '  [3] Performance'
        if ($AllowInherit) {
            Write-Host '  [4] Inherit global default (remove game override)'
        }
        Write-Host '  [B] Back'
        $selection = [string](Read-Host 'Selection')

        switch ($selection.Trim().ToUpperInvariant()) {
            '1' { return 'Quiet' }
            '2' { return 'Balanced' }
            '3' { return 'Performance' }
            '4' { if ($AllowInherit) { return '__INHERIT__' } }
            'B' { return $null }
        }

        Write-Host 'Invalid selection.'
    }
}

function Get-EpicInteractiveLibrary {
    [CmdletBinding()]
    param()

    $setting = Get-EpicCompanionSetting
    $games = @(Get-EpicInstalledGame)
    @(
        foreach ($game in $games) {
            $overrideProperty = $setting.GameOverrides.PSObject.Properties[[string]$game.AppId]
            if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['ThermalProfile']) {
                $profile = [string]$overrideProperty.Value.ThermalProfile
                $thermalSource = 'Game'
            }
            else {
                $profile = [string]$setting.DefaultThermalProfile
                $thermalSource = 'Global'
            }
            $useLosslessScaling = if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['UseLosslessScaling']) { [bool]$overrideProperty.Value.UseLosslessScaling } else { [bool]$setting.UseLosslessScaling }
            $losslessScalingSource = if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['UseLosslessScaling']) { 'Game' } else { 'Global' }

            [pscustomobject]@{
                Name                 = [string]$game.Name
                AppId                = [string]$game.AppId
                EffectiveProfile     = $profile
                ProfileSource        = $thermalSource
                UseLosslessScaling   = $useLosslessScaling
                LosslessScalingSource = $losslessScalingSource
                LaunchExecutable     = [string]$game.LaunchExecutable
            }
        }
    ) | Sort-Object Name
}

function Show-LegionGoRuntimeEpicCompanion {
    <#
    .SYNOPSIS
        Opens the interactive Epic Companion menu.
    #>
    [CmdletBinding()]
    param()

    [object[]]$games = @(Get-EpicInstalledGame)
    if (@($games).Count -eq 0) { throw 'No installed Epic games were found.' }

    while ($true) {
        Clear-Host
        Write-Host '=== Legion Go Runtime Epic Companion ==='
        Write-Host 'Type part of a game name to filter, A for all games, R to refresh, S for settings, or Q to quit.'
        $choice = Read-Host 'Selection'

        if ($choice -match '^(?i)q$') { return }
        if ($choice -match '^(?i)r$') {
            $games = @(Get-EpicInstalledGame)
            Write-Host ("Epic library refreshed. {0} installed game(s) found." -f @($games).Count)
            Start-Sleep -Seconds 1
            continue
        }
        if ($choice -match '^(?i)s$') {
            $returnToMain = $false
            while (-not $returnToMain) {
                $setting = Get-EpicCompanionSetting
                Clear-Host
                Write-Host '=== Epic Companion Settings ==='
                Write-Host "[1] Default thermal profile: $($setting.DefaultThermalProfile)"
                Write-Host "[2] Lossless Scaling enabled: $($setting.UseLosslessScaling)"
                Write-Host '[3] Configure a game profile'
                Write-Host '[4] View saved game profiles'
                Write-Host '[5] Remove a game profile'
                Write-Host '[6] Return'
                $settingsChoice = Read-Host 'Selection'

                switch ($settingsChoice) {
                    '1' {
                        Write-Host '[1] Quiet  [2] Balanced  [3] Performance'
                        $profileChoice = Read-Host 'Default thermal profile'
                        $profile = switch ($profileChoice) { '1' {'Quiet'} '2' {'Balanced'} '3' {'Performance'} default {$null} }
                        if ($profile) { Set-EpicCompanionSetting -DefaultThermalProfile $profile | Out-Null }
                    }
                    '2' { Set-EpicCompanionSetting -UseLosslessScaling (-not [bool]$setting.UseLosslessScaling) | Out-Null }
                    '3' {
                        $filter = Read-Host 'Enter part of the game name'
                        [object[]]$profileGames = @(Get-EpicInstalledGame -Name $filter)
                        if (@($profileGames).Count -eq 0) { Read-Host 'No matching games. Press Enter' | Out-Null; continue }
                        for ($i=0; $i -lt @($profileGames).Count; $i++) { Write-Host ('[{0}] {1} (App ID {2})' -f ($i+1),$profileGames[$i].Name,$profileGames[$i].AppId) }
                        $selection = 0
                        $value = Read-Host 'Game number'
                        if (-not [int]::TryParse($value,[ref]$selection) -or $selection -lt 1 -or $selection -gt @($profileGames).Count) { continue }
                        $selectedGame = $profileGames[$selection-1]
                        Write-Host '[1] Quiet  [2] Balanced  [3] Performance'
                        $thermalChoice = Read-Host 'Thermal profile'
                        $thermal = switch ($thermalChoice) { '1' {'Quiet'} '2' {'Balanced'} '3' {'Performance'} default {$null} }
                        if (-not $thermal) { continue }
                        $lsChoice = Read-Host 'Use Lossless Scaling for this game? (Y/N)'
                        $gameLs = $lsChoice -match '^(?i)y$'
                        Set-EpicGameProfile -AppId $selectedGame.AppId -ThermalProfile $thermal -UseLosslessScaling $gameLs | Out-Null
                    }
                    '4' {
                        [object[]]$profiles = @(Get-EpicGameProfile)
                        if (@($profiles).Count -eq 0) { Read-Host 'No saved game profiles. Press Enter' | Out-Null; continue }
                        Clear-Host
                        Write-Host '=== Saved Epic Game Profiles ==='
                        foreach ($profile in $profiles) {
                            $game = Get-EpicInstalledGame -AppId $profile.AppId | Select-Object -First 1
                            $name = if ($game) { $game.Name } else { 'Unknown game' }
                            Write-Host ('{0} (App ID {1})' -f $name,$profile.AppId)
                            Write-Host ('  Thermal profile: {0}' -f $(if ($profile.ThermalProfile) { $profile.ThermalProfile } else { '(inherits global default)' }))
                            $lsText = if ($null -eq $profile.UseLosslessScaling) { '(inherits global default)' } elseif ($profile.UseLosslessScaling) { 'On' } else { 'Off' }
                            Write-Host ('  Lossless Scaling: {0}' -f $lsText)
                            if (@($profile.ProcessName).Count -gt 0) {
                                Write-Host ('  Process override: {0}' -f ($profile.ProcessName -join ', '))
                            }
                            Write-Host ''
                        }
                        Read-Host 'Press Enter to return' | Out-Null
                    }
                    '5' {
                        [object[]]$profiles = @(Get-EpicGameProfile)
                        if (@($profiles).Count -eq 0) { Read-Host 'No saved game profiles. Press Enter' | Out-Null; continue }
                        for ($i=0; $i -lt @($profiles).Count; $i++) {
                            $game = Get-EpicInstalledGame -AppId $profiles[$i].AppId | Select-Object -First 1
                            $name = if ($game) { $game.Name } else { 'Unknown game' }
                            Write-Host ('[{0}] {1} (App ID {2})' -f ($i+1),$name,$profiles[$i].AppId)
                        }
                        $selection = 0
                        $value = Read-Host 'Profile number to remove'
                        if ([int]::TryParse($value,[ref]$selection) -and $selection -ge 1 -and $selection -le @($profiles).Count) {
                            Remove-EpicGameProfile -AppId $profiles[$selection-1].AppId -Confirm:$false
                        }
                    }
                    '6' { $returnToMain = $true }
                }
            }
            continue
        }

        [object[]]$matches = @(if ($choice -match '^(?i)a$' -or [string]::IsNullOrWhiteSpace($choice)) { $games } else { $games | Where-Object Name -Like "*$choice*" })
        if (@($matches).Count -eq 0) { Write-Host 'No matching games found.'; Read-Host 'Press Enter to continue' | Out-Null; continue }

        $setting = Get-EpicCompanionSetting
        for ($index=0; $index -lt @($matches).Count; $index++) {
            $overrideProperty = $setting.GameOverrides.PSObject.Properties[[string]$matches[$index].AppId]
            if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['ThermalProfile']) { $thermalProfile = [string]$overrideProperty.Value.ThermalProfile; $thermalSource = 'Game' } else { $thermalProfile = [string]$setting.DefaultThermalProfile; $thermalSource = 'Global' }
            if ($overrideProperty -and $overrideProperty.Value.PSObject.Properties['UseLosslessScaling']) { $useLs = [bool]$overrideProperty.Value.UseLosslessScaling; $lsSource = 'Game' } else { $useLs = [bool]$setting.UseLosslessScaling; $lsSource = 'Global' }
            $sourceText = if ($thermalSource -eq 'Game' -and $lsSource -eq 'Game') { 'Saved profile' } elseif ($thermalSource -eq 'Global' -and $lsSource -eq 'Global') { 'Global defaults' } else { 'Mixed sources' }
            $lsText = if ($useLs) { 'On' } else { 'Off' }
            Write-Host ('[{0}] {1} (App ID {2}) [Thermal: {3} | Lossless Scaling: {4} | {5}]' -f ($index+1),$matches[$index].Name,$matches[$index].AppId,$thermalProfile,$lsText,$sourceText)
        }

        $number = Read-Host 'Enter game number or press Enter to search again'
        if ([string]::IsNullOrWhiteSpace($number)) { continue }
        $selectedNumber = 0
        if (-not [int]::TryParse($number,[ref]$selectedNumber) -or $selectedNumber -lt 1 -or $selectedNumber -gt @($matches).Count) { Write-Host 'Invalid selection.'; Start-Sleep 1; continue }

        $selectedGame = $matches[$selectedNumber-1]
        $selectedProfile = Get-ResolvedEpicThermalProfile -Game $selectedGame -HasExplicitThermalProfile $false
        $selectedOverride = $setting.GameOverrides.PSObject.Properties[[string]$selectedGame.AppId]
        if ($selectedOverride -and $selectedOverride.Value.PSObject.Properties['UseLosslessScaling']) { $selectedUseLs = [bool]$selectedOverride.Value.UseLosslessScaling; $selectedLsSource = 'Game' } else { $selectedUseLs = [bool]$setting.UseLosslessScaling; $selectedLsSource = 'Global' }
        $selectedLsText = if ($selectedUseLs) { 'On' } else { 'Off' }
        Write-Host ''
        Write-Host ('Selected profile for {0}:' -f $selectedGame.Name)
        Write-Host ('  Thermal profile: {0} ({1})' -f $selectedProfile.ThermalProfile,$selectedProfile.Source)
        Write-Host ('  Lossless Scaling: {0} ({1})' -f $selectedLsText,$selectedLsSource)
        Write-Host ''
        Start-EpicGameSession -AppId $selectedGame.AppId
        Read-Host 'Press Enter to return to the launcher' | Out-Null
    }
}

function Start-EpicCompanion {
    <#
    .SYNOPSIS
        Compatibility wrapper for Show-LegionGoRuntimeEpicCompanion.
    #>
    [CmdletBinding()]
    param()

    Show-LegionGoRuntimeEpicCompanion
}

Export-ModuleMember -Function @(
    'Get-EpicCompanionSetting',
    'Set-EpicCompanionSetting',
    'Get-EpicGameProfile',
    'Set-EpicGameProfile',
    'Remove-EpicGameProfile',
    'Get-EpicInstalledGame',
    'Trace-EpicGameLaunch',
    'Start-EpicGame',
    'Start-EpicGameSession',
    'Show-LegionGoRuntimeEpicCompanion',
    'Start-EpicCompanion'
)
