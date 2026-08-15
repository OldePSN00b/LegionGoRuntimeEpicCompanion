# Legion Go Runtime Epic Companion

Epic Games Launcher companion for `LegionGoRuntime`.

## Version 0.9.0 scope

Version 0.9.0 supports:

- installed Epic game discovery from `.item` manifests
- diagnostic launch/process tracing
- real Epic game launch and session monitoring
- Quiet, Balanced, and Performance thermal modes
- automatic Balanced restore after a non-Balanced session
- persistent global thermal default
- persistent per-game thermal overrides keyed by Epic `AppId`
- explicit one-session thermal overrides
- Steam-consistent search/settings/launch menu via `Show-LegionGoRuntimeEpicCompanion`
- optional Lossless Scaling startup and lifecycle cleanup
- persisted launch timeout and polling settings
- interactive installed-library refresh
- `Start-EpicGameSession` as the preferred Steam-family session command

Settings are stored for the current user at:

```text
%LOCALAPPDATA%\LegionGoRuntimeEpicCompanion\Settings.json
```

The settings file is written atomically to reduce the chance of corruption.

## Profile resolution order

`Start-EpicGameSession` and its compatibility command `Start-EpicGame` resolve
the effective thermal profile in this order:

1. explicit `-ThermalProfile` / `-TDProfile`
2. saved per-game profile
3. global default profile
4. `Balanced` as the initial default when settings are first created

The completed session object includes `ThermalProfileSource` with `Explicit`, `Game`, or `Global`.

## Settings commands

Show current settings:

```powershell
Get-EpicCompanionSetting
```

Change the global default:

```powershell
Set-EpicCompanionSetting -DefaultThermalProfile Performance
```

Change the persisted launch detection timing:

```powershell
Set-EpicCompanionSetting -GameStartTimeoutSeconds 300 -PollIntervalSeconds 2
```

The initial global default is `Balanced`.

## Per-game profiles

Use the stable Epic `AppId` returned by `Get-EpicInstalledGame`.

Save a profile:

```powershell
Set-EpicGameProfile -AppId '4256d7c7170f4326a1a861d0b30f1af7' -ThermalProfile Performance
```

List saved profiles:

```powershell
Get-EpicGameProfile
```

Get one saved profile:

```powershell
Get-EpicGameProfile -AppId '4256d7c7170f4326a1a861d0b30f1af7'
```

Remove a saved profile:

```powershell
Remove-EpicGameProfile -AppId '4256d7c7170f4326a1a861d0b30f1af7'
```

## Launch examples

Launch using saved/global profile resolution:

```powershell
Start-EpicGameSession -Name 'Foretales' | Format-List *
```

Override the saved settings for one launch only:

```powershell
Start-EpicGameSession -Name 'Foretales' -ThermalProfile Quiet | Format-List *
```

Existing instances of the manifest executable are excluded before launch. Epic launcher helpers, EOS installers, overlays, and unrelated processes are not adopted as the game session.

The default launch timeout is 300 seconds, the default polling interval is 2
seconds, and the default stability check is 2 seconds. `Start-EpicGame` remains
available for backward compatibility.

## Discovery

```powershell
Get-EpicInstalledGame |
    Format-Table Name, AppId, InstallPath, LaunchExecutable -AutoSize
```

Each discovered game includes:

- `Name`
- `AppId` / `AppName`
- `CatalogNamespace`
- `CatalogItemId`
- `MainGameAppName`
- `InstallPath`
- `LaunchExecutable`
- `LaunchPath`
- `LaunchCommand`
- `LaunchUri`
- `AppCategories`
- `Manifest`

## Diagnostic trace

`Trace-EpicGameLaunch` remains available for investigating unusual launch chains. It does not apply thermal settings.

```powershell
Trace-EpicGameLaunch -Name 'Foretales' -ObservationSeconds 30 |
    Format-List *
```

## Thermal behavior

Quiet and Performance are applied before launch through the Legion Go thermal helper. Epic and the game remain in the normal user context. After the monitored game process exits, Balanced is restored.

If the effective profile is already Balanced, no pre-launch thermal mode change is required.


## Interactive companion

Start the menu:

```powershell
Start-EpicCompanion
```

The library shows each installed Epic title with its effective thermal profile and source (`Game` or `Global`). From the menu you can:

- launch a game using its resolved profile
- set Quiet, Balanced, or Performance for one game
- remove a game override so it inherits the global default
- change the global default
- refresh installed-game discovery

The existing command-line functions remain available for scripting and diagnostics.

Use `R` from the main interactive menu to rescan Epic manifests.


## Interactive launcher

Use `Show-LegionGoRuntimeEpicCompanion`, or run `Start-LegionGoRuntimeEpicCompanion.ps1`. `Start-EpicCompanion` remains as a compatibility wrapper.


## Dual-mode launcher wrapper

`Start-LegionGoRuntimeEpicCompanion.ps1` follows the shared launcher-companion wrapper pattern:

```powershell
# Interactive
.\Start-LegionGoRuntimeEpicCompanion.ps1

# Direct launch using saved/global profile resolution
.\Start-LegionGoRuntimeEpicCompanion.ps1 -AppId '4256d7c7170f4326a1a861d0b30f1af7'

# Direct launch by installed game name with a one-session thermal override
.\Start-LegionGoRuntimeEpicCompanion.ps1 -Name 'Foretales' -ThermalProfile Performance
```

Epic remains responsible for game-specific launch arguments and behavior.


## Lossless Scaling

The global default is enabled, per-game profiles may override it, and
`Start-EpicGameSession -UseLosslessScaling $false` can override it for one
session. The module locates Lossless Scaling through its Steam uninstall
registration or Steam libraries, unless `LosslessScalingPathOverride` is
configured. Lossless Scaling is started minimized. If the companion starts it
and `CloseLosslessScalingAfterGame` is enabled, only that instance is closed
when the game ends; a pre-existing process is left running.

## Tests

The Pester suite supports Windows PowerShell 5.1 and Pester 3.4:

```powershell
Invoke-Pester .\tests
```
