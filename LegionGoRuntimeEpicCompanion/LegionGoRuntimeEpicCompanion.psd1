@{
    RootModule        = 'LegionGoRuntimeEpicCompanion.psm1'
    ModuleVersion     = '0.8.0'
    GUID              = '3dc3bfe6-467c-4d0e-a1bd-1ea3c29a20ce'
    Author            = '0ldePSN00b'
    CompanyName       = 'Independent'
    Copyright         = '(c) 2026 0ldePSN00b. All rights reserved.'
    Description       = 'Companion module for Legion Go Runtime that discovers and launches Epic Games Launcher titles with persistent thermal profiles and optional per-game process detection overrides.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-EpicCompanionSetting',
        'Set-EpicCompanionSetting',
        'Get-EpicGameProfile',
        'Set-EpicGameProfile',
        'Remove-EpicGameProfile',
        'Get-EpicInstalledGame',
        'Trace-EpicGameLaunch',
        'Start-EpicGame',
        'Show-LegionGoRuntimeEpicCompanion',
        'Start-EpicCompanion'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('EpicGames', 'LegionGo', 'LegionGoRuntime', 'EpicCompanion', 'Gaming')
            ProjectUri   = ''
            ReleaseNotes = 'Adds Lossless Scaling parity: global defaults, per-game overrides, one-session override, auto-detection, lifecycle cleanup, and Steam-consistent UI.'
        }
    }
}
