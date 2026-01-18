<#
.SYNOPSIS
    Creates a new Microsoft Edge browser profile with custom settings.

.DESCRIPTION
    Creates a new Microsoft Edge profile with a custom name, configures it to open
    the Entra admin centre on startup, and launches Edge with the new profile.

.PARAMETER profileName
    The name for the new Edge profile. If not provided, you'll be prompted to enter one.

.EXAMPLE
    Create-EdgeProfile -profileName "Customer Project"
    Creates a new Edge profile named "Customer Project".

.EXAMPLE
    Create-EdgeProfile
    Prompts for a profile name, then creates the profile.

.NOTES
    Author: Benjamin Wolfe
    Date: January 01, 2026
    Version: 1.0
#>

function Create-EdgeProfile {
    param(
        [string]$profileName
    )

    if (-not $profileName) {
        $profileName = Read-Host "Enter profile name"
    }

    # Sanitise name
    $safeName = ($profileName -replace '[\\/:*?"<>|]', '_')

    # Define paths
    $edgeUserDataPath = Join-Path -Path $env:LOCALAPPDATA -ChildPath "Microsoft\Edge\User Data"
    $newProfilePath = Join-Path -Path $edgeUserDataPath -ChildPath "Profile_$safeName"
    $preferencesPath = Join-Path -Path $newProfilePath -ChildPath "Preferences"

    try {
        # Create directory if needed
        if (-not (Test-Path $newProfilePath)) {
            New-Item -ItemType Directory -Path $newProfilePath -Force | Out-Null
        }

        # Create basic Preferences file if missing
        if (-not (Test-Path $preferencesPath)) {
            '{}' | Out-File -Encoding utf8 -FilePath $preferencesPath
        }

        # Load existing or initialise Preferences as hashtable
        $prefsJson = Get-Content $preferencesPath -Raw
        $prefs = @{}

        if ($prefsJson -and $prefsJson.Trim() -ne '{}') {
            try {
                $prefs = ConvertFrom-Json $prefsJson -AsHashtable
            } catch {
                Write-Warning "Preferences file exists but could not be parsed. Starting fresh."
                $prefs = @{}
            }
        }

        # Ensure 'browser' and 'profile' keys exist
        if (-not $prefs.ContainsKey("browser")) { $prefs["browser"] = @{} }
        if (-not $prefs.browser.ContainsKey("startup")) { $prefs.browser["startup"] = @{} }

        $prefs.browser.startup["is_homepage"] = $true
        $prefs.browser.startup["restore_on_startup"] = 4
        $prefs.browser.startup["startup_urls"] = @("https://entra.microsoft.com")

        if (-not $prefs.ContainsKey("profile")) { $prefs["profile"] = @{} }
        $prefs.profile["auto_switch"] = $false


        # Save Preferences
        $prefs | ConvertTo-Json -Depth 10 | Out-File -FilePath $preferencesPath -Encoding UTF8

        # Launch Edge
        $edgePath = (Get-Command "msedge.exe" -ErrorAction SilentlyContinue)?.Source

        if (-not $edgePath) {
            $edgePath = "$env:ProgramFiles (x86)\Microsoft\Edge\Application\msedge.exe"
            if (-not (Test-Path $edgePath)) {
                $edgePath = "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
            }

            if (-not (Test-Path $edgePath)) {
                Write-Error "Microsoft Edge executable not found. Checked PATH and standard install locations."
                return
            }
        }


        Start-Process -FilePath $edgePath -ArgumentList "--user-data-dir=`"$newProfilePath`""

    } catch {
        Write-Error "Error creating profile or setting preferences: $_"
    }
}

# Usage: Just run it without parameters and you'll be prompted
Create-EdgeProfile
