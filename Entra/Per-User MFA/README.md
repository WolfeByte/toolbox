# Per-User MFA Management Scripts

PowerShell toolkit for managing per-user Multi-Factor Authentication (MFA) in Microsoft Entra ID. Export users with enforced per-user MFA and bulk disable the policy when migrating to Conditional Access.

---

## Overview

Scripts for managing per-user MFA at scale:

1. **Export-PerUserMFA.ps1** - Exports all users who are set to enforced for per-user MFA to CSV
2. **Disable-PerUserMFA.ps1** - Bulk disables per-user MFA from CSV input

**Key Benefits:**
- Migrate from legacy per-user MFA to Conditional Access policies
- Manage thousands of users with batch/parallel processing
- WhatIf support, retry logic, and comprehensive error handling
- Parallel processing with intelligent API throttling
- Detailed logging and audit trails

**IMPORTANT**: Disabling per-user MFA does NOT remove registered authentication methods (phone numbers, authenticator apps, FIDO2 keys, hardware tokens). All methods remain available for use with Conditional Access policies.

---

## Quick Start

```powershell
# Export users with enforced per-user MFA
.\Export-PerUserMFA.ps1 -OutputPath ".\EnforcedMFAUsers.csv"

# Preview changes with WhatIf
.\Disable-PerUserMFA.ps1 -CsvPath ".\EnforcedMFAUsers.csv" -WhatIf

# Execute disable operation
.\Disable-PerUserMFA.ps1 -CsvPath ".\EnforcedMFAUsers.csv"

# Review results in log file (MFA_Disable_Log_*.log) and failed users CSV if present
```

---

## Requirements

**PowerShell Version:** 7.0 or later (for `ForEach-Object -Parallel` support)

```powershell
# Check version
$PSVersionTable.PSVersion

# Install required modules
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser
Install-Module Microsoft.Graph.Users -Scope CurrentUser
```

**Required Permissions:**

| Permission | Type | Purpose |
|------------|------|---------|
| `User.Read.All` | Delegated/Application | Read user profiles |
| `UserAuthenticationMethod.Read.All` | Delegated/Application | Read authentication methods |
| `UserAuthenticationMethod.ReadWrite.All` | Delegated/Application | Modify MFA state |
| `Policy.Read.AuthenticationMethod` | Delegated/Application | Read authentication policies |
| `Policy.ReadWrite.AuthenticationMethod` | Delegated/Application | Write authentication policies |

**Note**: These permissions require admin consent in most tenants.

---

## Export-PerUserMFA.ps1

Exports users with **enforced** per-user MFA to CSV.

**Features:**
- Filters for `PerUserMfaState = "enforced"` only
- Includes ObjectId for optimal Disable script performance
- Batch processing (default: 20 users per batch)
- Parallel processing (default: 10 concurrent operations)
- Incremental CSV export (progress preserved on interruption)
- Intelligent API throttling with exponential backoff

**Usage:**

```powershell
# Basic usage (exports CSV file to the running script directory)
.\Export-PerUserMFA.ps1

# Custom output path
.\Export-PerUserMFA.ps1 -OutputPath "C:\Reports\MFAEnforcedUsers.csv"
```

**Parameters:**

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `OutputPath` | No | `$PSScriptRoot\MFAEnforcedUsers.csv` | CSV output path |

**CSV Output Columns:**

| Column | Description |
|--------|-------------|
| `ObjectId` | User's unique GUID |
| `UserPrincipalName` | Primary email/login |
| `DisplayName` | User's full name |
| `MFAState` | Per-user MFA state (enforced) |
| `MFADefaultMethod` | Preferred MFA method |
| `PrimarySMTP` | Primary email address |
| `Aliases` | All email aliases |
| `UserType` | Member or Guest |
| `AccountEnabled` | Account status |
| `CreatedDateTime` | Account creation date |

**MFA Method Translations:**

| API Value | Description |
|-----------|-------------|
| `push` | Microsoft authenticator app |
| `oath` | Authenticator app or hardware token |
| `voiceMobile` | Mobile phone |
| `voiceAlternateMobile` | Alternate mobile phone |
| `voiceOffice` | Office phone |
| `sms` | SMS |
| `(empty)` | Not Enabled |

---

## Disable-PerUserMFA.ps1

Bulk disables per-user MFA for users in a CSV file.

**Features:**
- WhatIf/Confirm support for safe testing
- ObjectId optimisation (~10x faster than UPN lookup)
- Intelligent retry logic with exponential backoff
- Batch/parallel processing
- Failed users CSV export for reprocessing
- Connection state preservation
- Comprehensive logging with colour-coded output

**Usage:**

```powershell
# Basic usage
.\Disable-PerUserMFA.ps1 -CsvPath ".\EnforcedMFAUsers.csv"

# Test with WhatIf
.\Disable-PerUserMFA.ps1 -CsvPath ".\Users.csv" -WhatIf

# Performance tuning
.\Disable-PerUserMFA.ps1 -CsvPath ".\Users.csv" -BatchSize 50 -ThrottleLimit 15
```

**Parameters:**

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `CsvPath` | Yes | - | Path to CSV file (.csv extension required) |
| `LogPath` | No | `$PSScriptRoot\MFA_Disable_Log_<timestamp>.log` | Log file path |
| `BatchSize` | No | `20` | Users per batch (range: 1-100) |
| `ThrottleLimit` | No | `10` | Concurrent operations (range: 1-20) |
| `WhatIf` | No | `False` | Preview changes without executing |
| `Confirm` | No | `False` | Prompt for confirmation |

**CSV Requirements:**
- Must contain **either** `ObjectId` **or** `UserPrincipalName` column
- Must have `.csv` extension
- Using the export script CSV output is recommended (includes ObjectId for ~10x performance boost)

**Failed Users Handling:**
If processing fails for any users, a CSV is automatically created:
- Filename: `MFA_Disable_Failed_<timestamp>.csv`
- Contains: UserPrincipalName, ObjectId, Error, Timestamp
- Reprocess with: `.\Disable-PerUserMFA.ps1 -CsvPath ".\MFA_Disable_Failed_*.csv"`

---

## Migration Workflow

**Scenario**: Migrating from per-user MFA to Conditional Access policies

```powershell
# 1. Export current enforced users (create backup)
.\Export-PerUserMFA.ps1 -OutputPath ".\MFAEnforcedUsers.csv"

# 2. Implement Conditional Access policies
# 3. Test Conditional Access with pilot group

# 4. Preview disable operation
.\Disable-PerUserMFA.ps1 -CsvPath ".\MFAEnforcedUsers.csv" -WhatIf

# 5. Execute disable (consider phased approach for large deployments)
.\Disable-PerUserMFA.ps1 -CsvPath ".\MFAEnforcedUsers.csv"

# 6. Verify users can authenticate via Conditional Access
# 7. Review logs and address any failed users
```

---

## Performance Guide

**Expected Processing Times:**

| User Count | Export Time | Disable Time | Notes |
|------------|-------------|--------------|-------|
| < 100 | 1-2 min | 1-2 min | Minimal parallel benefit |
| 100-1,000 | 5-15 min | 3-8 min | ObjectId optimisation noticeable |
| 1,000-10,000 | 30-90 min | 15-45 min | Batch processing essential |
| 10,000+ | 1-3 hours | 45min-2hours | Run during off-peak hours |

**Performance Tuning:**

```powershell
# Conservative (slower, safer for throttled environments)
.\Disable-PerUserMFA.ps1 -CsvPath ".\Users.csv" -BatchSize 10 -ThrottleLimit 5

# Aggressive (faster, higher API load)
.\Disable-PerUserMFA.ps1 -CsvPath ".\Users.csv" -BatchSize 50 -ThrottleLimit 15
```

**Export Script Tuning** (edit directly in script):
- Batch Size (line 121): Default 20 - increase for speed, decrease if throttled
- Throttle Limit (line 149): Default 10 - increase for parallelism, decrease if throttled
- Inter-Batch Delay (line 338): Default 10 seconds - increase if experiencing throttling

---

## Troubleshooting

### Rate Limiting
**Error**: Repeated HTTP 429 errors despite retry logic

**Solution**:
1. Reduce batch size and throttle limit: `-BatchSize 10 -ThrottleLimit 5`
2. Run during off-peak hours
3. For Export script, edit lines 121 and 149 to reduce values
4. Check Microsoft Graph API status: [status.cloud.microsoft](https://status.cloud.microsoft)

### CSV Format Issues
**Error**: "CSV must contain either 'ObjectId' or 'UserPrincipalName' column"

**Solution**:
1. Verify CSV has required columns (case-sensitive headers)
2. Test CSV format: `Import-Csv ".\file.csv" | Format-Table`
3. Use Export script output for guaranteed compatibility

---

## Related Resources

**Microsoft Documentation:**
- [Per-User MFA in Entra ID](https://learn.microsoft.com/en-us/entra/identity/authentication/howto-mfa-userstates)
- [Microsoft Graph API - Authentication](https://learn.microsoft.com/en-us/graph/api/authentication-update)
- [Conditional Access Documentation](https://learn.microsoft.com/en-us/entra/identity/conditional-access/)
- [Migrate to Conditional Access](https://learn.microsoft.com/en-us/entra/identity/conditional-access/howto-conditional-access-policy-all-users-mfa)

**PowerShell Resources:**
- [PowerShell 7+ Download](https://github.com/PowerShell/PowerShell/releases)
- [Microsoft Graph PowerShell SDK](https://learn.microsoft.com/en-us/powershell/microsoftgraph/)

---

## Support

Before requesting support:
1. Review the [Troubleshooting](#troubleshooting) section
2. Verify all [Requirements](#requirements) are met
3. Check [Microsoft Graph API status](https://status.cloud.microsoft)
4. Review inline script comments for additional details

---

## Licence

These scripts are provided as-is without warranty. Use at your own risk. Always test in a non-production environment first.

---

