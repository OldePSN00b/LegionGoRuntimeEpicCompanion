# Changelog

## 1.0.0 - 2026-08-16

- Normalized the public API with the Steam companion around
  `Start-EpicCompanion` and `Start-EpicGameSession`.
- Removed the legacy `Show-LegionGoRuntimeEpicCompanion` and `Start-EpicGame`
  commands rather than retaining compatibility aliases.
- Added pipeline `Game` selection to `Start-EpicGameSession`, matching Steam's
  AppId, Name, pipeline, thermal, process, Lossless Scaling, timeout, polling,
  and stability parameter surface.

## 0.9.0 - 2026-08-15

- Added `Start-EpicGameSession` as the Steam-family session command while
  preserving `Start-EpicGame` for backward compatibility.
- Added persisted `GameStartTimeoutSeconds` and `PollIntervalSeconds` settings
  with Steam-compatible defaults and validation.
- Fixed the interactive Settings menu so option 4 views profiles and option 5
  removes profiles.
- Added an explicit interactive library refresh action.
- Added clear mixed-source profile labels for partial per-game overrides.
- Started Lossless Scaling minimized to match Steam behavior.
- Standardized non-interactive informational output on `Write-Output` while
  retaining `Write-Host` and `Read-Host` for interactive UI.
- Strengthened persisted-settings validation and normalization.
- Rejected persisted or newly created profiles whose only value is an empty
  process-name override.
- Added a Windows PowerShell 5.1-compatible Pester regression suite covering
  module exports, approved verbs, settings, atomic writes, profile collections,
  interactive profile actions, refresh, and thermal elevation.

## 0.8.0

- Added Lossless Scaling global defaults, per-game overrides, one-session
  overrides, automatic discovery, lifecycle cleanup, and interactive UI status.
