<#
.SYNOPSIS
    Starts the Legion Go Runtime Epic Companion interactively or launches one Epic game directly.

.DESCRIPTION
    With no game selection parameters, opens the interactive Epic companion menu.
    With -AppId or -Name, launches the selected Epic game through the normal Epic
    session flow. -ThermalProfile can override the resolved thermal profile for that
    session only; otherwise saved per-game and global settings are used.

    Epic remains responsible for the game's launch behavior and arguments.

.PARAMETER AppId
    Stable Epic AppName/AppId to launch directly.

.PARAMETER Name
    Installed Epic game name to resolve for direct launch. Wildcards are supported;
    the selection must resolve to exactly one installed title.

.PARAMETER ThermalProfile
    Optional one-session thermal override: Quiet, Balanced, or Performance.

.EXAMPLE
    .\Start-LegionGoRuntimeEpicCompanion.ps1

.EXAMPLE
    .\Start-LegionGoRuntimeEpicCompanion.ps1 -AppId '4256d7c7170f4326a1a861d0b30f1af7'

.EXAMPLE
    .\Start-LegionGoRuntimeEpicCompanion.ps1 -Name 'Foretales' -ThermalProfile Performance
#>
[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory, ParameterSetName = 'ByAppId')]
    [string]$AppId,

    [Parameter(Mandatory, ParameterSetName = 'ByName')]
    [string]$Name,

    [Parameter(ParameterSetName = 'ByAppId')]
    [Parameter(ParameterSetName = 'ByName')]
    [Alias('TDProfile')]
    [ValidateSet('Quiet', 'Balanced', 'Performance')]
    [string]$ThermalProfile
)

$modulePath = Join-Path -Path $PSScriptRoot -ChildPath 'LegionGoRuntimeEpicCompanion.psd1'
Import-Module -Name $modulePath -Force

if ($PSCmdlet.ParameterSetName -eq 'Interactive') {
    Show-LegionGoRuntimeEpicCompanion
    return
}

$sessionParameters = @{}
if ($PSBoundParameters.ContainsKey('ThermalProfile')) {
    $sessionParameters.ThermalProfile = $ThermalProfile
}

if ($PSCmdlet.ParameterSetName -eq 'ByAppId') {
    Start-EpicGame -AppId $AppId @sessionParameters
}
else {
    Start-EpicGame -Name $Name @sessionParameters
}
