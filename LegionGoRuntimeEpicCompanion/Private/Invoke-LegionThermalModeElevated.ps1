<#
.SYNOPSIS
    Applies a Legion thermal mode from an elevated Windows PowerShell 5.1 process.

.DESCRIPTION
    Private helper for LegionGoRuntimeEpicCompanion. The helper imports
    LegionGoRuntime and calls Set-LegionThermalMode. It is launched with RunAs so
    only the Lenovo WMI thermal write is elevated; Epic and the game are not.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Quiet', 'Balanced', 'Performance')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'

try {
    Import-Module LegionGoRuntime -ErrorAction Stop
    $result = Set-LegionThermalMode -ModeName $Mode
    if (-not $result.Success) {
        throw ("LegionGoRuntime reported that {0} mode was not applied. Actual mode: {1}." -f $Mode, $result.ActualName)
    }
    Write-Output ("Legion thermal mode set to {0}." -f $Mode)
}
catch {
    Write-Error ("Failed to set Legion thermal mode to {0}: {1}" -f $Mode, $_.Exception.Message)
    exit 1
}
