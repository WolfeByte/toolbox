# ExportUserTypeCount.ps1

![PowerShell](https://img.shields.io/badge/PowerShell-7.1+-blue) ![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-SDK-00BCF2) ![Entra](https://img.shields.io/badge/Microsoft-Entra_ID-0078D4) ![Exchange](https://img.shields.io/badge/Exchange-Online-0078D4)

Export a breakdown of user account types across Entra ID and Exchange Online, with a calculated licensable human account count for IGA sizing.

## Overview

When sizing an IGA product, vendors typically licence based on human identities — but Entra ID surfaces Exchange resource accounts (shared mailboxes, rooms, equipment) as regular user objects, making it hard to determine your true user count without digging into Exchange.

This script pulls all Entra user objects and all Exchange Online mailboxes, correlates them, and produces a summary that separates human accounts from Exchange resource accounts. The final output is a licensable human account count that you can hand directly to a vendor.

With this script you can:
* **Count all Entra user objects** broken down by Member, Guest, and account enabled state
* **Identify Exchange resource accounts** (shared mailboxes, rooms, equipment) that inflate the Entra user count
* **Calculate a true licensable human account count** by subtracting resource accounts from the total
* **Exclude Exchange system mailboxes** (e.g. DiscoverySearchMailbox) that have no Entra identity at all
* **Export results** to a formatted HTML report and CSV files for sharing with vendors or stakeholders

## Prerequisites

* **PowerShell**: 7.1 or higher
* **Required Modules**:
  - Microsoft.Graph.Users
  - ExchangeOnlineManagement
* **Required Permissions**:
  - Entra ID: `Global Reader`
  - Exchange Online: `View-Only Organization Management` (role group)

## Usage

### Default (Console + CSV + HTML)

```powershell
.\ExportUserTypeCount.ps1
```

Runs the full report and writes all output files to the current directory.

### Console Only

```powershell
.\ExportUserTypeCount.ps1 -Output Console
```

### HTML Report Only

```powershell
.\ExportUserTypeCount.ps1 -Output HTML
```

### CSV Files Only

```powershell
.\ExportUserTypeCount.ps1 -Output CSV
```

## Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| Output | string | No | `All` | Controls output destinations. Valid values: `Console`, `CSV`, `HTML`, `All` |

## How It Works

1. **Authenticates** to Microsoft Graph with delegated permissions
2. **Retrieves** all Entra user objects including `UserType` and `AccountEnabled` state
3. **Authenticates** to Exchange Online with delegated permissions
4. **Retrieves** all mailboxes with `RecipientTypeDetails` and `ExternalDirectoryObjectId`
5. **Filters out** Exchange system mailboxes with no corresponding Entra identity (e.g. `DiscoverySearchMailbox`)
6. **Correlates** each mailbox back to its Entra user object via `ExternalDirectoryObjectId`
7. **Buckets** mailboxes into `UserMailbox`, `SharedMailbox`, `RoomMailbox`, `EquipmentMailbox`, and `Other / Linked`
8. **Calculates** the licensable human count as Members + Guests minus all Exchange resource accounts
9. **Outputs** results to the terminal, CSV files, and/or an HTML report

## Output Files

All files are written to the directory the script is run from, with the current date appended to the filename.

### HTML Report
A single-page formatted report containing all three summary sections.
```
TenantUserSummary_20250421.html
```

### Entra CSV
Entra user type breakdown with totals and licensable count appended.
```
EntraUserSummary_20250421.csv
```

### Exchange CSV
Exchange resource account breakdown with totals.
```
ExchangeMailboxSummary_20250421.csv
```

## Output Structure

The report is broken into three sections:

**Tenant User Account Summary** — all Entra user objects by type and enabled state.

| Type | Total | Enabled | Disabled |
|------|-------|---------|----------|
| Regular Users (Member) | 41 | 40 | 1 |
| Guest Users | 1 | 1 | 0 |
| **Total Human Accounts** | **42** | **41** | **1** |

**Exchange Resource Accounts** — non-human accounts created by Exchange, excluded from licensing.

| Type | Total | Enabled | Disabled |
|------|-------|---------|----------|
| SharedMailbox | 1 | 0 | 1 |
| RoomMailbox | 6 | 6 | 0 |
| EquipmentMailbox | 0 | 0 | 0 |
| **Total Resource Accounts** | **7** | **6** | **1** |

**Licensable Human Accounts** — the true count to provide to an IGA vendor for sizing.

| Type | Total | Enabled | Disabled |
|------|-------|---------|----------|
| Licensable Human Accounts | **35** | **35** | **0** |

## Notes

* Both authentication prompts (Graph and Exchange Online) will appear when the script runs — the same account can be used for both
* Exchange system mailboxes without an `ExternalDirectoryObjectId` are excluded entirely and reported in the console output
* Any mailbox types outside the four standard resource types are captured in an `Other / Linked` bucket rather than silently dropped
* The script reuses existing Graph and Exchange Online sessions if already connected

---

**Author**: Benjamin Wolfe
**Last Updated**: April 2026
