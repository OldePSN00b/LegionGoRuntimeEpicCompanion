# LegionGoRuntime Epic Companion Agent Guide

## Scope

These instructions apply to the entire repository.

LegionGoRuntimeEpicCompanion is a Windows PowerShell companion for
LegionGoRuntime. It discovers installed Epic titles, resolves launcher and
per-game settings, applies a temporary Legion thermal profile, invokes Epic's
native launch URI, monitors the game session, and restores Balanced afterward.

Steam is the mature launcher-companion reference. Keep Steam, Epic, and future
companions consistent in UI/UX, menu structure, terminology, settings layout,
command naming, output style, and behavior wherever launcher-specific
differences do not prevent it.

## PowerShell compatibility and commands

- Support Windows PowerShell 5.1 only. Do not introduce syntax, modules, APIs,
  or behaviors that require PowerShell 6+ or PowerShell 7+.
- Use only approved PowerShell verbs. Validate new command names against
  `Get-Verb`.
- Test relevant code with `Set-StrictMode -Version Latest` enabled.
- PowerShell may unwrap a single-item result. Wrap potential single-object
  collections in `@()` before reading `.Count`.
- Preserve public command names, parameters, accepted inputs, output shapes,
  and behavior unless an API change is explicitly approved.
- Keep the manifest `FunctionsToExport` list and `Export-ModuleMember` list
  explicit and synchronized.

## Output and interactive UI

- Use `Write-Output` for normal informational and logging output.
- Use `Write-Host` and `Read-Host` for interactive menus, prompts, status
  displays, and other UI text so menu output does not pollute pipeline results.
- Keep menu structure, labels, selection behavior, terminology, and profile
  summaries aligned with the Steam companion wherever practical.

## Launcher and session behavior

- The launcher wrapper is dual-mode: no arguments open the interactive UI;
  App ID or game name performs a direct non-interactive launch; an optional
  thermal profile supplies a one-session override.
- Do not accept or forward arbitrary game arguments. Epic remains responsible
  for launching and configuring games.
- The companion's responsibility is: resolve game, resolve profile, apply the
  thermal/TDP state, invoke Epic's native launcher URI, identify and monitor the
  game session, and restore Balanced.
- Keep Epic Games Launcher and game processes unelevated. Elevate only the
  short-lived LegionGoRuntime thermal helper.
- Apply thermal changes through LegionGoRuntime. Do not duplicate Lenovo WMI
  write logic in this repository.
- Exclude matching processes that existed before launch. Do not adopt Epic
  helpers, EOS installers, overlays, prerequisite installers, or unrelated
  processes as the game session.
- Preserve launch timeout and candidate-stability handling. Process-name
  overrides must remain available for games whose manifest executable is not a
  reliable session anchor.
- Restore Balanced in cleanup after every session in which a non-Balanced mode
  was successfully applied, including launch failures and timeouts.
- If this companion starts Lossless Scaling, close only that instance when the
  configured cleanup behavior requires it. Never close a pre-existing instance.

## Epic discovery

- Discover installed games from Epic `.item` manifests and launch them through
  Epic's native protocol URI.
- Treat Epic `AppName`/`AppId` as the stable settings key.
- Preserve launcher-specific filtering for incomplete installs, Unreal Engine
  components, and non-launchable addons.
- Do not pass manifest `LaunchCommand` or arbitrary game arguments directly to
  a game executable.
- Collapse duplicate manifests deliberately by stable App ID and prefer a
  usable installed record.

## Settings and data safety

- Store settings under
  `%LOCALAPPDATA%\LegionGoRuntimeEpicCompanion\Settings.json`.
- Write settings atomically through a same-directory temporary file and clean
  up temporary and backup files.
- Validate and normalize persisted values before use. Reject malformed settings
  and empty game profiles with actionable errors instead of silently coercing
  them.
- Preserve backward compatibility when adding settings. Add missing properties
  from defaults without discarding existing user profiles.
- Keep explicit one-session values, saved per-game values, and global defaults
  distinct, with resolution order: explicit, game, global.

## Documentation, versions, and tests

- Update `README.md` and `CHANGELOG.md` for every user-visible change. Create
  `CHANGELOG.md` if it is not yet present when the next user-visible change is
  made.
- Follow semantic versioning and keep the manifest version and release notes
  current.
- Add Windows PowerShell 5.1-compatible Pester regression coverage for changes.
  Use syntax supported by the bundled Pester 3.4 where practical.
- Prioritize coverage for module exports, approved verbs, atomic settings
  writes, settings normalization, single-object `.Count` behavior, duplicate
  manifests, process-name collections, pre-existing process exclusion, launch
  timeout/stability behavior, Lossless Scaling lifecycle, and Balanced restore.
- Run applicable tests and validate module import with `powershell.exe`, not
  only `pwsh.exe`, before handoff.

## Change discipline

- Keep changes scoped to the requested behavior and preserve unrelated user
  edits.
- Do not commit generated settings, logs, manifests copied from a local Epic
  installation, or machine-specific paths.
- Report tests actually run and any launcher, Lossless Scaling, elevation, or
  real-hardware behavior that could not be exercised.
