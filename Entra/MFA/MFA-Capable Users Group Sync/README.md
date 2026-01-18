# Sync-EntraMfaCapabilityGroups.ps1

![PowerShell](https://img.shields.io/badge/PowerShell-7.1-blue) ![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-SDK-00BCF2) ![Entra](https://img.shields.io/badge/Microsoft-Entra_ID-0078D4)

Automatically categorise and manage Entra ID users into groups based on their MFA capability status.

## Overview

Entra does not support building dynamic group rules based on a user’s MFA registration status, which can be determined using the IsMfaCapable property. This property returns a boolean value.

This script reads the IsMfaCapable value, categorises users accordingly, and automatically manages group membership. Users who are MFA enabled, meaning they have a registered MFA method, are added to an MFA-capable group, while users without MFA are placed in an MFA-non-capable group.

The script is designed for large-scale environments and uses parallel processing to handle thousands of users. It can be run on a schedule to mimic the behaviour of a dynamic group, which can then be used to build Conditional Access policies, such as blocking users who are not yet registered for MFA. Once a user registers an MFA method, they are automatically moved to the appropriate group the next time the script runs.

## What It Does

This script will:

* **Retrieve all member users** from your Entra tenant (excluding guests)
* **Check MFA capability** for each user using the `IsMfaCapable` property
* **Automatically categorise users** into two predefined groups:
  - MFA-capable users → Added to the 'MFA-capable' group
  - MFA-non-capable users → Added to the 'MFA-non-capable' group
* **Keep groups in sync** by removing users from the opposite group when their status changes
* **Process users in parallel** for fast execution in large tenants (configurable up to 50 parallel jobs)
* **Provide detailed logging** with colour-coded console output and a persistent log file
* **Show real-time progress** with percentage completion and processing statistics

## Features

* **Parallel processing** - Handles large user bases efficiently with configurable throttle limits (default: 20, tested up to 50)
* **Intelligent error handling** - Gracefully manages duplicate adds and API errors without stopping execution
* **Detailed progress tracking** - Real-time console output shows processing status, additions, removals, and errors
* **Comprehensive logging** - All operations logged to `AuthenticationReport_Log.txt` with timestamps
* **Smart categorisation** - Uses Entra ID's native `IsMfaCapable` property for accurate status detection
* **Automatic cleanup** - Removes users from incorrect groups when their MFA status changes
* **Thread-safe operations** - Uses synchronised hashtables for accurate parallel statistics tracking

## Prerequisites

* **PowerShell**: 7.x or higher recommended
* **Required Modules**:
  - Microsoft.Graph.Authentication - `Install-Module Microsoft.Graph.Authentication`
  - Microsoft.Graph.Users - `Install-Module Microsoft.Graph.Users`
  - Microsoft.Graph.Groups - `Install-Module Microsoft.Graph.Groups`
  - Microsoft.Graph.Reports - `Install-Module Microsoft.Graph.Reports`
  - Microsoft.Graph - `Install-Module Microsoft.Graph`
* **Required Graph API Permissions**:
  - `User.Read.All` - Read all user profiles
  - `Group.ReadWrite.All` - Read and write group memberships
  - `UserAuthenticationMethod.Read.All` - Read user authentication methods and MFA status
  - `AuditLog.Read.All` - Read audit logs and authentication reports

## Configuration

Before running the script, you'll need to configure two group IDs:

1. Open the script in your editor
2. Update these variables with your group IDs (lines 46-47):
   ```powershell
   $mfaCapableGroupId = "your-mfa-capable-group-id-here"
   $mfaNonCapableGroupId = "your-mfa-non-capable-group-id-here"
   ```
3. Optionally adjust the parallel processing limit (line 51):
   ```powershell
   $maxParallelJobs = 20  # Increase for faster processing, tested up to 50
   ```

## Usage

### Basic Example

```powershell
.\Sync-EntraMfaCapabilityGroups.ps1
```

The script will:
1. Connect to Microsoft Graph (you'll be prompted to sign in)
2. Retrieve all member users and their MFA capability status
3. Process users in parallel batches
4. Display colour-coded progress and statistics
5. Save detailed logs to `AuthenticationReport_Log.txt` in the script directory

### What to Expect

When you run the script, you'll see real-time output showing:
- Total users fetched from Entra ID
- Processing progress (updated every 100 users)
- Final statistics including:
  - Users added to each group
  - Users removed from each group
  - Users already in the correct groups
  - Any errors encountered
  - Percentage of users that required changes

## Notes

- **Review before running** - This script makes bulk group membership changes. Test in a non-production environment first.
- **Schedule it** - Run this script on a schedule (daily/weekly) to keep groups automatically in sync with MFA status changes.
- **Performance** - The default 20 parallel jobs works well for most environments. Increase carefully if you have a very large tenant.
- **Logging** - Check the log file if you need to audit what changes were made.

---
