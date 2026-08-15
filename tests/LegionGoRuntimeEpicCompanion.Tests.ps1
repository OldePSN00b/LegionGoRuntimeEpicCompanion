$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\LegionGoRuntimeEpicCompanion.psd1'
Import-Module -Name $modulePath -Force

Describe 'Module contract' {
    It 'exports exactly the commands declared by the manifest' {
        $manifest = Test-ModuleManifest -Path $modulePath
        $actual = @(Get-Command -Module LegionGoRuntimeEpicCompanion -CommandType Function | Select-Object -ExpandProperty Name | Sort-Object)
        $expected = @($manifest.ExportedFunctions.Keys | Sort-Object)

        @(Compare-Object -ReferenceObject $expected -DifferenceObject $actual).Count | Should Be 0
    }

    It 'uses approved verbs for every exported command' {
        $approvedVerbs = @(Get-Verb | Select-Object -ExpandProperty Verb)
        $unapproved = @(
            Get-Command -Module LegionGoRuntimeEpicCompanion -CommandType Function |
                Where-Object { ($_.Name -split '-')[0] -notin $approvedVerbs }
        )

        $unapproved.Count | Should Be 0
    }
}

Describe 'Settings validation' {
    InModuleScope LegionGoRuntimeEpicCompanion {
        It 'normalizes Boolean strings and numeric values from legacy settings' {
            $setting = Get-DefaultEpicCompanionSetting
            $setting.UseLosslessScaling = 'false'
            $setting.GameStartTimeoutSeconds = '600'
            $setting.PollIntervalSeconds = '3'

            $result = ConvertTo-NormalizedEpicCompanionSetting -Setting $setting

            $result.UseLosslessScaling | Should Be $false
            $result.GameStartTimeoutSeconds | Should Be 600
            $result.PollIntervalSeconds | Should Be 3
        }

        It 'rejects invalid Boolean values instead of coercing them to true' {
            $setting = Get-DefaultEpicCompanionSetting
            $setting.UseLosslessScaling = 'not-a-boolean'

            { ConvertTo-NormalizedEpicCompanionSetting -Setting $setting } | Should Throw
        }

        It 'rejects invalid timeout ranges' {
            $setting = Get-DefaultEpicCompanionSetting
            $setting.GameStartTimeoutSeconds = 0

            { ConvertTo-NormalizedEpicCompanionSetting -Setting $setting } | Should Throw
        }

        It 'rejects malformed game override collections' {
            $setting = Get-DefaultEpicCompanionSetting
            $setting.GameOverrides = 'invalid'

            { ConvertTo-NormalizedEpicCompanionSetting -Setting $setting } | Should Throw
        }

        It 'rejects a persisted profile whose process override is empty' {
            $setting = Get-DefaultEpicCompanionSetting
            $setting.GameOverrides | Add-Member NoteProperty 'ExampleGame' ([pscustomobject]@{ ProcessName = @() })

            { ConvertTo-NormalizedEpicCompanionSetting -Setting $setting } | Should Throw
        }
    }
}

Describe 'Settings persistence' {
    InModuleScope LegionGoRuntimeEpicCompanion {
        It 'atomically replaces an existing settings file under Windows PowerShell 5.1' {
            $originalDirectory = $script:SettingsDirectory
            $originalPath = $script:SettingsPath
            $testDirectory = Join-Path -Path $TestDrive -ChildPath 'Settings'
            $script:SettingsDirectory = $testDirectory
            $script:SettingsPath = Join-Path -Path $testDirectory -ChildPath 'Settings.json'

            try {
                $setting = Get-DefaultEpicCompanionSetting
                Write-EpicCompanionSetting -Setting $setting
                $setting.DefaultThermalProfile = 'Performance'
                Write-EpicCompanionSetting -Setting $setting

                $saved = Get-Content -LiteralPath $script:SettingsPath -Raw | ConvertFrom-Json
                $saved.DefaultThermalProfile | Should Be 'Performance'
                @(Get-ChildItem -LiteralPath $testDirectory -Filter 'Settings.*.tmp').Count | Should Be 0
                @(Get-ChildItem -LiteralPath $testDirectory -Filter 'Settings.*.bak').Count | Should Be 0
            }
            finally {
                $script:SettingsDirectory = $originalDirectory
                $script:SettingsPath = $originalPath
            }
        }
    }
}

Describe 'Saved game profiles' {
    InModuleScope LegionGoRuntimeEpicCompanion {
        It 'rejects an empty saved profile' {
            { Set-EpicGameProfile -AppId 'ExampleGame' } | Should Throw
        }

        It 'rejects an empty process override as a new profile' {
            Mock Get-EpicCompanionSetting { Get-DefaultEpicCompanionSetting }

            { Set-EpicGameProfile -AppId 'ExampleGame' -ProcessName @() } | Should Throw
        }

        It 'keeps a single process override as a collection' {
            Mock Get-EpicCompanionSetting {
                $setting = Get-DefaultEpicCompanionSetting
                $setting.GameOverrides | Add-Member -MemberType NoteProperty -Name 'ExampleGame' -Value ([pscustomobject]@{
                    ProcessName = @('ExampleGame')
                })
                $setting
            }

            $profile = Get-EpicGameProfile -AppId 'ExampleGame'

            @($profile.ProcessName).Count | Should Be 1
            $profile.ProcessName[0] | Should Be 'ExampleGame'
        }
    }
}

Describe 'Steam-family session command' {
    InModuleScope LegionGoRuntimeEpicCompanion {
        It 'forwards only explicitly bound values to Start-EpicGame' {
            Mock Start-EpicGame { }

            Start-EpicGameSession -AppId 'ExampleGame' -ThermalProfile Quiet

            Assert-MockCalled Start-EpicGame -Times 1 -Exactly -ParameterFilter {
                $AppId -eq 'ExampleGame' -and
                $ThermalProfile -eq 'Quiet' -and
                -not $PSBoundParameters.ContainsKey('LaunchTimeoutSeconds') -and
                -not $PSBoundParameters.ContainsKey('PollIntervalMilliseconds')
            }
        }
    }
}

Describe 'Interactive settings actions' {
    InModuleScope LegionGoRuntimeEpicCompanion {
        function New-TestEpicSetting {
            $setting = Get-DefaultEpicCompanionSetting
            $setting.GameOverrides | Add-Member -MemberType NoteProperty -Name 'ExampleGame' -Value ([pscustomobject]@{
                ThermalProfile = 'Performance'
            })
            $setting
        }

        It 'uses option 4 to view profiles without removing one' {
            $script:answers = @('s', '4', '', '6', 'q')
            Mock Read-Host {
                $answer = $script:answers[0]
                $script:answers = @($script:answers | Select-Object -Skip 1)
                $answer
            }
            Mock Clear-Host { }
            Mock Write-Host { }
            Mock Get-EpicInstalledGame { [pscustomobject]@{ Name = 'Example'; AppId = 'ExampleGame'; LaunchExecutable = 'Example.exe' } }
            Mock Get-EpicCompanionSetting { New-TestEpicSetting }
            Mock Get-EpicGameProfile { [pscustomobject]@{ AppId = 'ExampleGame'; ThermalProfile = 'Performance'; UseLosslessScaling = $null; ProcessName = @() } }
            Mock Remove-EpicGameProfile { }

            Show-LegionGoRuntimeEpicCompanion

            Assert-MockCalled Remove-EpicGameProfile -Times 0 -Exactly
        }

        It 'uses option 5 to remove the selected profile' {
            $script:answers = @('s', '5', '1', '6', 'q')
            Mock Read-Host {
                $answer = $script:answers[0]
                $script:answers = @($script:answers | Select-Object -Skip 1)
                $answer
            }
            Mock Clear-Host { }
            Mock Write-Host { }
            Mock Get-EpicInstalledGame { [pscustomobject]@{ Name = 'Example'; AppId = 'ExampleGame'; LaunchExecutable = 'Example.exe' } }
            Mock Get-EpicCompanionSetting { New-TestEpicSetting }
            Mock Get-EpicGameProfile { [pscustomobject]@{ AppId = 'ExampleGame'; ThermalProfile = 'Performance'; UseLosslessScaling = $null; ProcessName = @() } }
            Mock Remove-EpicGameProfile { }

            Show-LegionGoRuntimeEpicCompanion

            Assert-MockCalled Remove-EpicGameProfile -Times 1 -Exactly -ParameterFilter { $AppId -eq 'ExampleGame' }
        }

        It 'rescans the Epic library when R is selected' {
            $script:answers = @('r', 'q')
            Mock Read-Host {
                $answer = $script:answers[0]
                $script:answers = @($script:answers | Select-Object -Skip 1)
                $answer
            }
            Mock Clear-Host { }
            Mock Write-Host { }
            Mock Start-Sleep { }
            Mock Get-EpicInstalledGame { [pscustomobject]@{ Name = 'Example'; AppId = 'ExampleGame'; LaunchExecutable = 'Example.exe' } }

            Show-LegionGoRuntimeEpicCompanion

            Assert-MockCalled Get-EpicInstalledGame -Times 2 -Exactly -Scope It
        }
    }
}

Describe 'Thermal helper launch behavior' {
    InModuleScope LegionGoRuntimeEpicCompanion {
        It 'hides the elevated PowerShell console and disables profile loading' {
            Mock Test-Path { $true }
            Mock Start-Process { [pscustomobject]@{ ExitCode = 0 } }

            Set-ElevatedEpicLegionThermalMode -Mode Performance

            Assert-MockCalled Start-Process -Times 1 -Exactly -ParameterFilter {
                $Verb -eq 'RunAs' -and
                $WindowStyle -eq 'Hidden' -and
                $Wait -and
                $PassThru -and
                $ArgumentList -contains '-NoProfile'
            }
        }
    }
}
