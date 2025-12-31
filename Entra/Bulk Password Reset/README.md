# Reset-PasswordsByGroup.ps1

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue) ![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-SDK-00BCF2) ![Entra](https://img.shields.io/badge/Microsoft-Entra_ID-0078D4)

Perform a bulk password reset for users in a specifci Entra ID group.

## Overview

Point the script at an Entra ID group and it will reset passwords for all group members, generate temporary passwords based on each user’s initials, and enforce a password change at next sign-in. It also produces a detailed log file and a CSV export for record keeping. This is useful for new user onboarding and temporary password distribution.

With this script you can:
* **Reset passwords in bulk** for all members of an Entra ID group
* **Generate temporary passwords** automatically (user initials + custom suffix)
* **Track everything** with timestamped logs and CSV exports
* **Force password changes** on next sign-in for security
* **Preview changes** with WhatIf support before making changes

## Prerequisites

* **PowerShell**: 7.1 or higher
* **Required Modules**:
  - Microsoft.Graph.Users
* **Required Permissions**:
  - GroupMember.Read.All
  - User-PasswordProfile.ReadWrite.All

## Usage

### Basic Example

```powershell
.\Reset-PasswordsByGroup.ps1 -GroupId "87654321-4321-4321-4321-210987654321"
```

This will reset passwords for all members in the specified group and create logs in `.\logs\PasswordReset_[timestamp].[log/csv]`

### Custom Log Location

```powershell
.\Reset-PasswordsByGroup.ps1 -GroupId "87654321-4321-4321-4321-210987654321" -LogPath "C:\MyLogs\Reset"
```

Logs will be saved to `C:\MyLogs\Reset.log` and `C:\MyLogs\Reset.csv`

### Custom Password Suffix

```powershell
.\Reset-PasswordsByGroup.ps1 -GroupId "87654321-4321-4321-4321-210987654321" -PasswordSuffix ".Contoso2025"
```

Changes the password suffix from the default `.Welcome25` to `.Contoso2025`

### Preview Mode (WhatIf)

```powershell
.\Reset-PasswordsByGroup.ps1 -GroupId "87654321-4321-4321-4321-210987654321" -WhatIf
```

Shows what would happen without actually resetting any passwords.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| GroupId | string | Yes | - | The Object ID of the Entra group containing the users |
| PasswordSuffix | string | No | `.Welcome25` | The suffix for the temporary password (combined with user's initials) |
| LogPath | string | No | `.\logs\PasswordReset_[timestamp]` | Base path for log files (without extension). Both .log and .csv files are created |

## How It Works

1. **Authenticates** to Microsoft Graph
2. **Retrieves** all members from the specified Entra ID group
3. **Fetches** full user details for each member
4. **Generates** temporary passwords using pattern: `[FirstInitial][LastInitial][Suffix]`
   - Example: John Smith with default suffix → `js.Welcome25`
5. **Resets** each user's password and forces change on next sign-in
6. **Logs** all operations to both console and file
7. **Exports** complete results to CSV for record keeping

## Output Files

The script creates two files:

### Log File (.log)
Timestamped entries of all operations:
```
2025-12-31 14:30:15 - Script started - Using log path: .\logs\PasswordReset_20251231_143015
2025-12-31 14:30:20 - Successfully authenticated to Microsoft Graph
2025-12-31 14:30:25 - Retrieving group members...
2025-12-31 14:30:28 - Found 15 members in group.
2025-12-31 14:30:30 - Password reset successful - User: john.smith@contoso.com - Password: js.Contoso25
```

### CSV Report (.csv)
Structured data for all processed users:
```csv
Timestamp,UserPrincipalName,DisplayName,Status,ErrorMessage,NewPassword,WhatIfMode
2025-12-31 14:30:30,john.smith@contoso.com,John Smith,Success,,js.Contoso25,False
```

## Notes

* This script makes privileged modifications to user accounts - review carefully before running
* Temporary passwords are logged in plain text for distribution to users
* Users without both GivenName and Surname will be skipped with a warning
* The script automatically installs the Microsoft.Graph.Users module if not present
* Graph API connection is reused if already authenticated

## Security Considerations

* Passwords are stored in plain text in both log and CSV files - protect these files appropriately
* The password pattern is predictable (user initials + suffix) - ensure it meets your security requirements
* Users are forced to change passwords on first login, making the temporary nature explicit

---

**Author**: Benjamin Wolfe
**Last Updated**: December 31, 2025
