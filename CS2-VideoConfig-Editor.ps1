<#
.PARAMETER -FilePath
    Specifies the full path to the "cs2_video.txt" file.
    Defaults to "C:\Program Files (x86)\Steam\userdata\2421650\730\local\cfg\cs2_video.txt".
    You should change "2421650" to your Steam3ID or Steam friend code.

.PARAMETER -Preset
    Allows for automated resolution changes without user interaction.
    Accepts:
    - Numbers 1-9 for predefined resolutions (grouped by aspect ratio).
    - Resolution format string like "1920x1080", "1280x960", etc.
    - Named presets (case-insensitive, e.g., "1920x1080").

.PARAMETER -AspectRatioMode
    Used in conjunction with -Preset when setting a custom resolution or when
    the script cannot automatically determine the aspect ratio for a preset.
    Accepts: "4:3" (or "0"), "16:9" (or "1"), "16:10" (or "2").

.PARAMETER -Silent
    A switch parameter that, when present, suppresses all output except errors.
    Ideal for automation scripts. Returns proper exit codes (0 = success, 1 = failure).

.EXAMPLE
    .\CS2-VideoConfig-Editor.ps1 -Preset "1" -Silent
    .\CS2-VideoConfig-Editor.ps1 -Preset "1920x1080" -Silent
    .\CS2-VideoConfig-Editor.ps1 -FilePath "C:\Custom\Path\cs2_video.txt" -Preset "1280x960" -Silent
    .\CS2-VideoConfig-Editor.ps1 -Preset "1920x1080"
    .\CS2-VideoConfig-Editor.ps1 -Preset "1280x720" -AspectRatioMode "16:9" -Silent
#>
param(
    [string]$FilePath = "C:\Program Files (x86)\Steam\userdata\2421650\730\local\cfg\cs2_video.txt",
    [string]$Preset = "",
    [string]$AspectRatioMode = "", # New parameter for automation mode
    [switch]$Silent
)

# Define common resolutions and their aspect ratios
$Resolutions = @(
    @{ Width = "1024"; Height = "768"; Display = "1024x768"; Ratio = "4:3"; Mode = "0" },
    @{ Width = "1152"; Height = "864"; Display = "1152x864"; Ratio = "4:3"; Mode = "0" },
    @{ Width = "1280"; Height = "960"; Display = "1280x960"; Ratio = "4:3"; Mode = "0" },
    @{ Width = "1440"; Height = "1080"; Display = "1440x1080"; Ratio = "4:3"; Mode = "0" },
    @{ Width = "1280"; Height = "1024"; Display = "1280x1024"; Ratio = "5:4"; Mode = "0" }, # 5:4 handled as 4:3 in game
    @{ Width = "1920"; Height = "1080"; Display = "1920x1080"; Ratio = "16:9"; Mode = "1" },
    @{ Width = "2560"; Height = "1440"; Display = "2560x1440"; Ratio = "16:9"; Mode = "1" },
    @{ Width = "3840"; Height = "2160"; Display = "3840x2160"; Ratio = "16:9"; Mode = "1" },
    @{ Width = "1280"; Height = "720"; Display = "1280x720"; Ratio = "16:9"; Mode = "1" },
    @{ Width = "1600"; Height = "900"; Display = "1600x900"; Ratio = "16:9"; Mode = "1" },
    @{ Width = "1440"; Height = "900"; Display = "1440x900"; Ratio = "16:10"; Mode = "2" },
    @{ Width = "1680"; Height = "1050"; Display = "1680x1050"; Ratio = "16:10"; Mode = "2" },
    @{ Width = "1920"; Height = "1200"; Display = "1920x1200"; Ratio = "16:10"; Mode = "2" }
) | Sort-Object Ratio, Width

# Add error handling for the entire script
try {
    function Get-AspectRatioModeFromRatio {
        param([string]$ratio)
        switch ($ratio.ToLower()) {
            "4:3" { return "0" }
            "5:4" { return "0" } # Game treats 5:4 as 4:3
            "16:9" { return "1" }
            "16:10" { return "2" }
            default { return $null }
        }
    }

    function Get-AspectRatioModeFromInput {
        param([bool]$Silent = $false)

        if ($Silent) { return $null } # Cannot prompt in silent mode

        Write-Host "Select Aspect Ratio Mode:" -ForegroundColor Yellow
        Write-Host "0. 4:3 (includes 5:4)" -ForegroundColor White
        Write-Host "1. 16:9" -ForegroundColor White
        Write-Host "2. 16:10" -ForegroundColor White
        Write-Host "X. Cancel" -ForegroundColor Red

        do {
            $aspectChoice = Read-Host "Enter your choice (0, 1, 2, or X)"
            switch ($aspectChoice.ToLower()) {
                "0" { return "0" }
                "1" { return "1" }
                "2" { return "2" }
                "x" { return $null } # User cancelled
                default { Write-Host "Invalid choice. Please enter 0, 1, 2, or X." -ForegroundColor Red }
            }
        } while ($true)
    }

    function Show-ResolutionMenu {
        Write-Host "`nCS2 Video Configuration Editor" -ForegroundColor Cyan
        Write-Host "================================" -ForegroundColor Cyan
        Write-Host "Select a resolution option:" -ForegroundColor Yellow

        $currentIdx = 1
        $ratioGroups = $Resolutions | Group-Object Ratio | Sort-Object Name

        foreach ($group in $ratioGroups) {
            $groupName = $group.Name
            $mode = Get-AspectRatioModeFromRatio $groupName
            Write-Host "`n--- $($groupName) Resolutions (Aspect Ratio Mode: $mode) ---" -ForegroundColor Green
            foreach ($res in $group.Group) {
                Write-Host "$($currentIdx). $($res.Display)" -ForegroundColor White
                $currentIdx++
            }
        }

        Write-Host "$($currentIdx). Custom resolution" -ForegroundColor White
        Write-Host "$($currentIdx+1). Exit" -ForegroundColor Red
        Write-Host ""
        return $currentIdx # Return the index for Custom resolution
    }

    function Get-ResolutionFromPreset {
        param([string]$presetString, [string]$explicitAspectRatioMode)

        $result = $null

        # Try to find in predefined resolutions by Display or by numeric index
        if ($presetString -match "^\d+$") { # Numeric preset (e.g., "1", "5")
            $index = [int]$presetString
            if ($index -ge 1 -and $index -le $Resolutions.Count) {
                $result = $Resolutions[$index - 1] # Adjust for 0-based array index
            }
        } elseif ($presetString -match "^(\d+)x(\d+)$") { # Resolution format (e.g., "1920x1080")
            $width = $matches[1]
            $height = $matches[2]
            $foundRes = $Resolutions | Where-Object { $_.Width -eq $width -and $_.Height -eq $height } | Select-Object -First 1
            if ($foundRes) {
                $result = $foundRes
            } else {
                # If not a predefined resolution, create a new object for it
                $result = @{ Width = $width; Height = $height; Display = "${width}x${height}" }
                # Attempt to determine ratio mode
                $calculatedMode = Get-AspectRatioModeFromRatio ((New-Object -TypeName System.Drawing.Size($width, $height)).GetAspectRatioString())
                if ($calculatedMode) {
                    $result.Mode = $calculatedMode
                } else {
                    $result.Mode = $null # Indicate unknown mode
                }
            }
        } else { # Named preset (e.g., "1024x768")
            $foundRes = $Resolutions | Where-Object { $_.Display -eq $presetString -or $_.Display -eq $presetString.ToLower() } | Select-Object -First 1
            if ($foundRes) {
                $result = $foundRes
            }
        }

        # Override or set AspectRatioMode if explicitly provided
        if ($explicitAspectRatioMode) {
            $mode = switch ($explicitAspectRatioMode.ToLower()) {
                "0" { "0" }
                "4:3" { "0" }
                "1" { "1" }
                "16:9" { "1" }
                "2" { "2" }
                "16:10" { "2" }
                default { $null }
            }
            if ($mode -ne $null) {
                if ($result -eq $null) {
                    # This case implies a custom resolution being passed only as string
                    # and the user providing a mode without the actual resolution format.
                    # This might be an invalid usage but handle defensively.
                    $result = @{ Mode = $mode }
                } else {
                    $result.Mode = $mode
                }
            } else {
                Write-Host "Warning: Invalid AspectRatioMode '$explicitAspectRatioMode' provided. Using auto-detection or prompting." -ForegroundColor Yellow
            }
        }

        return $result
    }

    # Helper function to calculate aspect ratio string for custom resolutions
    function Get-AspectRatioString {
        param([int]$width, [int]$height)

        $gcd = [System.Numerics.BigInteger]::GreatestCommonDivisor($width, $height)
        $ratioWidth = $width / $gcd
        $ratioHeight = $height / $gcd

        if ($ratioWidth -eq 4 -and $ratioHeight -eq 3) { return "4:3" }
        if ($ratioWidth -eq 5 -and $ratioHeight -eq 4) { return "5:4" }
        if ($ratioWidth -eq 16 -and $ratioHeight -eq 9) { return "16:9" }
        if ($ratioWidth -eq 16 -and $ratioHeight -eq 10) { return "16:10" }

        return "$($ratioWidth):$($ratioHeight)" # Return simplified ratio for others
    }

    function Get-ResolutionFromChoice {
        param([string]$choice, [int]$customResIndex, [bool]$Silent = $false)

        if ($choice -match "^\d+$") {
            $index = [int]$choice
            if ($index -ge 1 -and $index -le $Resolutions.Count) {
                return $Resolutions[$index - 1]
            } elseif ($index -eq $customResIndex) { # Custom resolution
                do {
                    $customRes = Read-Host "Enter custom resolution (format: WIDTHxHEIGHT, e.g., 1920x1080)"
                    if ($customRes -match "^(\d+)x(\d+)$") {
                        $width = $matches[1]
                        $height = $matches[2]
                        $resObj = @{ Width = $width; Height = $height; Display = "${width}x${height}" }

                        # Attempt to determine aspect ratio mode
                        $ratioString = Get-AspectRatioString $width $height
                        $detectedMode = Get-AspectRatioModeFromRatio $ratioString

                        if ($detectedMode) {
                            $resObj.Mode = $detectedMode
                            Write-Host "Detected aspect ratio: $($ratioString) (Mode: $($detectedMode))" -ForegroundColor DarkGray
                        } else {
                            Write-Host "Could not automatically determine aspect ratio mode for $($ratioString)." -ForegroundColor Yellow
                            $resObj.Mode = Get-AspectRatioModeFromInput -Silent $Silent
                            if ($resObj.Mode -eq $null) {
                                Write-Host "Custom resolution setup cancelled." -ForegroundColor Red
                                return "cancelled" # User cancelled aspect ratio choice
                            }
                        }
                        return $resObj
                    } else {
                        Write-Host "Invalid format! Please use WIDTHxHEIGHT format (e.g., 1920x1080)" -ForegroundColor Red
                    }
                } while ($true)
            } elseif ($index -eq ($customResIndex + 1)) { # Exit option
                return $null
            } else {
                Write-Host "Invalid choice! Please select a valid number from the menu." -ForegroundColor Red
                return "invalid"
            }
        } else {
            Write-Host "Invalid choice! Please enter a number." -ForegroundColor Red
            return "invalid"
        }
    }

    function Update-VideoConfig {
        param(
            [string]$FilePath,
            [string]$Width,
            [string]$Height,
            [string]$AspectRatioMode, # New parameter for aspect ratio mode
            [bool]$Silent = $false
        )

        try {
            # Check if file exists
            if (-not (Test-Path $FilePath)) {
                if (-not $Silent) {
                    Write-Host "Error: File not found at $FilePath" -ForegroundColor Red
                }
                return $false
            }

            # Read the file content
            $content = Get-Content $FilePath | Out-String # Read as single string to easily manipulate multiple lines
            $updatedContent = $content

            $widthUpdated = $false
            $heightUpdated = $aspectRatioModeUpdated = $false

            # --- Update Width ---
            if ($updatedContent -match '("setting\.defaultres"\s*)"(\d+)"') {
                $oldWidth = $matches[2]
                $updatedContent = $updatedContent -replace '("setting\.defaultres"\s*)"(\d+)"', "`$1`"$Width`""
                if (-not $Silent) {
                    Write-Host "Updated width: $oldWidth -> $Width" -ForegroundColor Green
                }
                $widthUpdated = $true
            } else {
                if (-not $Silent) {
                    Write-Host "Warning: Could not find 'setting.defaultres' line." -ForegroundColor Yellow
                }
            }

            # --- Update Height ---
            if ($updatedContent -match '("setting\.defaultresheight"\s*)"(\d+)"') {
                $oldHeight = $matches[2]
                $updatedContent = $updatedContent -replace '("setting\.defaultresheight"\s*)"(\d+)"', "`$1`"$Height`""
                if (-not $Silent) {
                    Write-Host "Updated height: $oldHeight -> $Height" -ForegroundColor Green
                }
                $heightUpdated = $true
            } else {
                if (-not $Silent) {
                    Write-Host "Warning: Could not find 'setting.defaultresheight' line." -ForegroundColor Yellow
                }
            }

            # --- Update or Add Aspect Ratio Mode ---
            if ($AspectRatioMode -ne $null) {
                if ($updatedContent -match '("setting\.aspectratiomode"\s*)"(\d+)"') {
                    $oldMode = $matches[2]
                    if ($oldMode -ne $AspectRatioMode) {
                        $updatedContent = $updatedContent -replace '("setting\.aspectratiomode"\s*)"(\d+)"', "`$1`"$AspectRatioMode`""
                        if (-not $Silent) {
                            Write-Host "Updated aspectratiomode: $oldMode -> $AspectRatioMode" -ForegroundColor Green
                        }
                        $aspectRatioModeUpdated = $true
                    } else {
                        if (-not $Silent) {
                            Write-Host "Aspect ratio mode already set to: $AspectRatioMode" -ForegroundColor DarkGray
                        }
                    }
                } else {
                    # If line not found, insert it before the last closing brace of the main block
                    # This targets the last "}" followed by whitespace or end of string, hopefully within the "video.cfg" block
                    if ($updatedContent -match '}\s*$') {
                        $updatedContent = $updatedContent -replace '}\s*$', "`t`"setting.aspectratiomode`"`t`"$AspectRatioMode`"`n}"
                        if (-not $Silent) {
                            Write-Host "Added 'setting.aspectratiomode' line." -ForegroundColor Green
                        }
                        $aspectRatioModeUpdated = $true
                    } else {
                         if (-not $Silent) {
                            Write-Host "Warning: Could not find suitable place to add 'setting.aspectratiomode' line." -ForegroundColor Yellow
                        }
                    }
                }
            } elseif (-not $Silent) {
                Write-Host "Warning: 'setting.aspectratiomode' not provided. Keeping current value if exists." -ForegroundColor Yellow
            }


            if ($widthUpdated -or $heightUpdated -or $aspectRatioModeUpdated) {
                # Write the updated content back to the file
                # Use [System.IO.File]::WriteAllText for simple string writing
                [System.IO.File]::WriteAllText($FilePath, $updatedContent, [System.Text.Encoding]::UTF8)
                if (-not $Silent) {
                    Write-Host "Configuration updated successfully!" -ForegroundColor Green
                }
                return $true
            } else {
                if (-not $Silent) {
                    Write-Host "No changes were made to the file. It might already be set to the desired values." -ForegroundColor Yellow
                }
                return $false
            }

        } catch {
            if (-not $Silent) {
                Write-Host "Error updating file: $($_.Exception.Message)" -ForegroundColor Red
            }
            return $false
        }
    }

    # Main script logic

    # Check if running in automation mode
    if ($Preset -ne "") {
        $resolution = Get-ResolutionFromPreset $Preset $AspectRatioMode

        if ($resolution -eq $null) {
            if (-not $Silent) {
                Write-Host "Error: Invalid preset '$Preset'" -ForegroundColor Red
                Write-Host "Valid presets: numeric index, resolution format like '1920x1080', or named presets." -ForegroundColor Yellow
            }
            exit 1
        }

        # If a resolution was found but its mode is unknown (e.g., custom resolution not in predefined list
        # and no AspectRatioMode param provided), prompt the user if not silent.
        if ($resolution.Mode -eq $null) {
            if ($Silent) {
                Write-Host "Error: Aspect ratio mode could not be determined for '$($resolution.Display)' in silent mode. Please provide -AspectRatioMode." -ForegroundColor Red
                exit 1
            } else {
                Write-Host "Aspect ratio mode could not be automatically determined for $($resolution.Display)." -ForegroundColor Yellow
                $resolution.Mode = Get-AspectRatioModeFromInput -Silent $Silent
                if ($resolution.Mode -eq $null) {
                    Write-Host "Operation cancelled." -ForegroundColor Red
                    exit 1
                }
            }
        }

        # Check if file exists
        if (-not (Test-Path $FilePath)) {
            if (-not $Silent) {
                Write-Host "Error: Configuration file not found!" -ForegroundColor Red
                Write-Host "Expected location: $FilePath" -ForegroundColor Yellow
            }
            exit 1
        }

        if (-not $Silent) {
            Write-Host "CS2 Video Configuration Editor - Automation Mode" -ForegroundColor Cyan
            Write-Host "Applying preset: $($resolution.Display) (Aspect Ratio Mode: $($resolution.Mode))" -ForegroundColor Cyan
        }

        $success = Update-VideoConfig -FilePath $FilePath `
                                     -Width $resolution.Width `
                                     -Height $resolution.Height `
                                     -AspectRatioMode $resolution.Mode `
                                     -Silent $Silent

        if ($success) {
            if (-not $Silent) {
                Write-Host "Resolution and Aspect Ratio successfully changed to $($resolution.Display) (Mode: $($resolution.Mode))" -ForegroundColor Green
                Write-Host "Note: You may need to restart CS2 for changes to take effect." -ForegroundColor Yellow
            }
            exit 0
        } else {
            if (-not $Silent) {
                Write-Host "Failed to update configuration." -ForegroundColor Red
            }
            exit 1
        }
    }

    # Interactive mode
    Write-Host "CS2 Video Configuration Editor" -ForegroundColor Cyan
    Write-Host "File path: $FilePath" -ForegroundColor Gray

    # Check if file exists
    if (-not (Test-Path $FilePath)) {
        Write-Host "`nError: Configuration file not found!" -ForegroundColor Red
        Write-Host "Expected location: $FilePath" -ForegroundColor Yellow
        Write-Host "Please make sure CS2 has been launched at least once and the file exists." -ForegroundColor Yellow
        Start-Sleep -Seconds 1
        exit 1
    }

    do {
        $customResOptionIndex = Show-ResolutionMenu
        $exitOptionIndex = $customResOptionIndex + 1

        $choice = Read-Host "Enter your choice (1-$($exitOptionIndex))"

        $resolution = Get-ResolutionFromChoice $choice $customResOptionIndex -Silent $Silent

        if ($resolution -eq $null) {
            Write-Host "Exiting..." -ForegroundColor Yellow
            break
        } elseif ($resolution -eq "invalid") {
            continue
        } elseif ($resolution -eq "cancelled") { # For custom resolution aspect ratio cancellation
            Write-Host "Returning to main menu." -ForegroundColor Yellow
            continue
        } else {
            if ($resolution.Mode -eq $null) { # This should ideally not happen for predefined, but for safety
                Write-Host "Could not determine aspect ratio mode for selected resolution." -ForegroundColor Red
                Write-Host "Please manually select it." -ForegroundColor Red
                $resolution.Mode = Get-AspectRatioModeFromInput -Silent $Silent
                if ($resolution.Mode -eq $null) {
                    Write-Host "Operation cancelled. Returning to main menu." -ForegroundColor Red
                    continue
                }
            }

            Write-Host "Applying resolution: $($resolution.Display) (Aspect Ratio Mode: $($resolution.Mode))" -ForegroundColor Cyan

            $success = Update-VideoConfig -FilePath $FilePath `
                                         -Width $resolution.Width `
                                         -Height $resolution.Height `
                                         -AspectRatioMode $resolution.Mode `
                                         -Silent $false

            if ($success) {
                Write-Host "Note: You may need to restart CS2 for changes to take effect." -ForegroundColor Yellow
            }

            Write-Host "Closing in 1 second..." -ForegroundColor Gray
            Start-Sleep -Seconds 1
            break
        }
    } while ($true)

} catch {
    if (-not $Silent) {
        Write-Host "`nAn unexpected error occurred: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "Stack trace: $($_.ScriptStackTrace)" -ForegroundColor Red
        Start-Sleep -Seconds 1
    }
    exit 1
} finally {
    # Exit.
}
