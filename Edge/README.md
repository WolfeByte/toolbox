# Create-EdgeProfile.ps1

![PowerShell](https://img.shields.io/badge/PowerShell-7.1-blue)

A simple PowerShell script for creating custom Microsoft Edge browser profiles.

## What It Does

This script creates a new Microsoft Edge browser profile with a custom name, automatically configures it to open the Entra admin centre on startup, and launches Edge with the new profile.

Perfect for managing multiple customer environments or projects, each with their own isolated Edge profile.

## What It Creates

- A new Edge profile directory in your local app data
- Custom preferences file configured with:
  - Startup URL set to https://entra.microsoft.com
  - Homepage configured
  - Auto-switch disabled for the profile

## Requirements

- PowerShell 7.0 or later
- Microsoft Edge browser installed

## Usage

Run the script without parameters to be prompted for a profile name:

```powershell
.\Create-EdgeProfile.ps1
```

Or specify a profile name directly:

```powershell
Create-EdgeProfile -profileName "Customer Project"
```

The script will automatically:
1. Sanitise the profile name (removing invalid characters)
2. Create the profile directory structure
3. Configure startup preferences
4. Launch Edge with the new profile

---

**Author**: Benjamin Wolfe
**Last Updated**: January 01, 2026
