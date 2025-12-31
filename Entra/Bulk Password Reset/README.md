# Reset-Passwords.ps1

![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-blue) ![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-SDK-00BCF2) ![Entra](https://img.shields.io/badge/Microsoft-Entra_ID-0078D4)

Bulk password reset for Entra ID group members with automatic logging and reporting.

## Overview

If you've ever needed to reset passwords for a group of users, you know how tedious it gets clicking through the portal one by one. Manual password resets are time-consuming, error-prone, and nearly impossible to track properly.

This script automates the entire process. Point it at an Entra ID group, and it'll reset passwords for all members, generate temporary credentials based on their initials, force them to change passwords on next login, and give you both a detailed log file and a CSV export for your records.

With this script you can:
* **Reset passwords in bulk** for all members of an Entra ID group
* **Generate temporary passwords** automatically (user initials + custom suffix)
* **Track everything** with timestamped logs and CSV exports
* **Force password changes** on next sign-in for security
* **Preview changes** with WhatIf support before making changes

## Features

* Microsoft Graph API integration with automatic authentication
* Generates temporary passwords using first and last initial pattern
* Forces password change on next sign-in for all users
* Comprehensive logging to both file and console with colour-coded output
* CSV export with full results (successes, failures, new passwords)
* Progress tracking for large groups
* Error handling for missing user data
* Support for WhatIf and Confirm parameters

## Prerequisites

* **PowerShell**: 5.1 or higher
* **Required Modules**:
  - Microsoft.Graph (minimum version 2.5.0) - `Install-Module Microsoft.Graph`
* **Required Permissions**:
  - User.Read.All
  - GroupMember.Read.All
  - User.ReadWrite.All

## Usage

### Basic Example

```powershell
.\Reset-Passwords.ps1 -TenantId "12345678-1234-1234-1234-123456789012" -GroupId "87654321-4321-4321-4321-210987654321"
```

This will reset passwords for all members in the specified group and create logs in `.\logs\PasswordReset_[timestamp].[log/csv]`

### Custom Log Location

```powershell
.\Reset-Passwords.ps1 -TenantId "12345678-1234-1234-1234-123456789012" -GroupId "87654321-4321-4321-4321-210987654321" -LogPath "D:\MyLogs\Reset"
```

Logs will be saved to `D:\MyLogs\Reset.log` and `D:\MyLogs\Reset.csv`

### Custom Password Suffix

```powershell
.\Reset-Passwords.ps1 -TenantId "12345678-1234-1234-1234-123456789012" -GroupId "87654321-4321-4321-4321-210987654321" -PasswordSuffix ".Welcome2025"
```

Changes the password suffix from the default `.Mecca25` to `.Welcome2025`

### Preview Mode (WhatIf)

```powershell
.\Reset-Passwords.ps1 -TenantId "12345678-1234-1234-1234-123456789012" -GroupId "87654321-4321-4321-4321-210987654321" -WhatIf
```

Shows what would happen without actually resetting any passwords.

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| TenantId | string | Yes | - | The Entra Tenant ID where the changes will be made |
| GroupId | string | Yes | - | The Object ID of the Entra group containing the users |
| PasswordSuffix | string | No | `.Mecca25` | The suffix for the temporary password (combined with user's initials) |
| LogPath | string | No | `.\logs\PasswordReset_[timestamp]` | Base path for log files (without extension). Both .log and .csv files are created |

## How It Works

1. **Authenticates** to Microsoft Graph with the specified tenant
2. **Retrieves** all members from the specified Entra ID group
3. **Fetches** full user details for each member
4. **Generates** temporary passwords using pattern: `[FirstInitial][LastInitial][Suffix]`
   - Example: John Smith with default suffix → `js.Mecca25`
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
2025-12-31 14:30:30 - Password reset successful - User: john.smith@contoso.com - Password: js.Mecca25
```

### CSV Report (.csv)
Structured data for all processed users:
```csv
Timestamp,UserPrincipalName,DisplayName,Status,ErrorMessage,NewPassword,WhatIfMode
2025-12-31 14:30:30,john.smith@contoso.com,John Smith,Success,,js.Mecca25,False
```

## Notes

* This script makes privileged modifications to user accounts - review carefully before running
* Temporary passwords are logged in plain text for administrator distribution to users
* Users without both GivenName and Surname will be skipped with a warning
* The script automatically installs the Microsoft.Graph module if not present
* Graph API connection is reused if already authenticated to the same tenant

## Security Considerations

* Passwords are stored in plain text in both log and CSV files - protect these files appropriately
* The password pattern is predictable (user initials + suffix) - ensure it meets your security requirements
* Users are forced to change passwords on first login, making the temporary nature explicit
* Log files should be securely stored and deleted after passwords have been distributed

---

**Author**: Benjamin Wolfe
**Last Updated**: December 31, 2025
