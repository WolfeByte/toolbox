#Requires -Version 5.1
<#
.SYNOPSIS
Performs a mass password reset of users in an Entra ID group.

.DESCRIPTION
This script automates the process of resetting passwords for multiple users within an Entra ID group.
It retrieves the members of the specified group, generates a temporary password for each user based on
their first and last initials combined with a predefined suffix, resets their password in Entra, and
requires them to change their password at their next login.

The script outputs both a log file (.log) and a CSV report (.csv) in the same location.

.PARAMETER TenantId
The Entra Tenant ID where the changes will be made.

.PARAMETER GroupId
The Object ID of the Entra group containing the users.

.PARAMETER PasswordSuffix
The suffix for the temporary password. Default is ".Mecca25".

.PARAMETER LogPath
Optional. Base path for log files (without extension).
If not specified, creates a 'logs' folder in the current directory and uses timestamp-based naming.
Both .log and .csv files will be created with this base name.

.NOTES
Prerequisites:
* PowerShell 5.1 or higher
* Microsoft.Graph PowerShell module (minimum version 2.5.0)
* Required Graph API permissions:
  - User.Read.All
  - GroupMember.Read.All
  - User.ReadWrite.All

    Author: Benjamin Wolfe
    Date: December 31, 2025
.EXAMPLE
.\Reset-Passwords.ps1 -TenantId "12345678-1234-1234-1234-123456789012" -GroupId "87654321-4321-4321-4321-210987654321"
Runs the script with default logging to .\logs\PasswordReset_[timestamp].[log/csv]

.EXAMPLE
.\Reset-Passwords.ps1 -TenantId "12345678-1234-1234-1234-123456789012" -GroupId "87654321-4321-4321-4321-210987654321" -LogPath "D:\MyLogs\Reset"
Runs the script with logging to D:\MyLogs\Reset.log and D:\MyLogs\Reset.csv
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GroupId,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$PasswordSuffix = ".Mecca25",

    [Parameter(Mandatory = $false)]
    [string]$LogPath
)

# Set default log paths based on current directory if not specified
if (-not $LogPath) {
    $currentPath = Get-Location
    $defaultFolder = Join-Path -Path $currentPath -ChildPath "logs"
    if (-not (Test-Path $defaultFolder)) {
        New-Item -ItemType Directory -Path $defaultFolder | Out-Null
    }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $LogPath = Join-Path -Path $defaultFolder -ChildPath "PasswordReset_$timestamp"
}

# Define log file paths
$LogFilePath = "$LogPath.log"
$CSVPath = "$LogPath.csv"

# Ensure the directory exists
$logDir = Split-Path $LogPath -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

# Function to write to log file and console
#region Helper Functions
function Write-Log {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$UserPrincipalName,

        [Parameter(Mandatory = $false)]
        [string]$Password,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Severity = 'Info'
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "$Timestamp - $Message"

    if ($UserPrincipalName) {
        $LogEntry += " - User: $UserPrincipalName"
    }

    if ($Password) {
        $LogEntry += " - Password: $Password"
    }

    Add-Content -Path $LogFilePath -Value $LogEntry

    switch ($Severity) {
        'Warning' { Write-Host $LogEntry -ForegroundColour Yellow }
        'Error' { Write-Host $LogEntry -ForegroundColour Red }
        default { Write-Host $LogEntry }
    }
}

# Function to generate temporary password
function New-TemporaryPassword {
    param (
        [string]$GivenName,
        [string]$Surname,
        [string]$Suffix
    )

    try {
        $initials = ($GivenName[0] + $Surname[0]).ToLower()
        return $initials + $Suffix
    } catch {
        throw "Failed to generate password: $($_.Exception.Message)"
    }
}

# Write initial log entry
Write-Log "Script started - Using log path: $LogPath"

# Check for required module
if (-not (Get-Module -ListAvailable Microsoft.Graph)) {
    Write-Host "Installing Microsoft.Graph module..."
#endregion Helper Functions
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
}

# Initialize CSV report array
#region Main Execution
$reportData = @()

# Connect to Microsoft Graph
try {
    $context = Get-MgContext
    if (-not $context) {
        Connect-MgGraph -Scopes User.Read.All, GroupMember.Read.All, User.ReadWrite.All -TenantId $TenantId
    } elseif ($context.TenantId -ne $TenantId) {
        Disconnect-MgGraph
        Connect-MgGraph -Scopes User.Read.All, GroupMember.Read.All, User.ReadWrite.All -TenantId $TenantId
    }
    Write-Log "Successfully authenticated to Microsoft Graph"
} catch {
    Write-Log "Authentication failed: $($_.Exception.Message)" -Severity Error
    exit 1
}

# Get group members
try {
    Write-Log "Retrieving group members..."
    $groupMembers = Get-MgGroupMember -GroupId $GroupId -All

    if ($groupMembers) {
        Write-Log "Found $($groupMembers.Count) members in group."

        # Get full user details for each member
        $users = @()
        foreach ($member in $groupMembers) {
            try {
                $user = Get-MgUser -UserId $member.Id
                if ($user) {
                    $users += $user
                }
            } catch {
                Write-Log "Failed to get user details for member ID $($member.Id)" -Severity Warning
            }
        }
    } else {
        Write-Log "No members found in group" -Severity Warning
        exit 0
    }
} catch {
    Write-Log "Error retrieving group members: $($_.Exception.Message)" -Severity Error
    exit 1
}

# Process each user
$total = $users.Count
$current = 0
$successCount = 0
$failureCount = 0

foreach ($user in $users) {
    $current++
    Write-Progress -Activity "Resetting user passwords" -Status "Processing $current of $total" -PercentComplete (($current / $total) * 100)

    $reportEntry = [PSCustomObject]@{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        UserPrincipalName = $user.UserPrincipalName
        DisplayName = $user.DisplayName
        Status = "Not Processed"
        ErrorMessage = ""
        NewPassword = ""
        WhatIfMode = $WhatIfPreference
    }

    try {
        if (-not $user.GivenName -or -not $user.Surname) {
            Write-Log "Missing first or last name" -UserPrincipalName $user.UserPrincipalName -Severity Warning
            $reportEntry.Status = "Failed"
            $reportEntry.ErrorMessage = "Missing first or last name"
            $failureCount++
            continue
        }

        $newPassword = New-TemporaryPassword -GivenName $user.GivenName -Surname $user.Surname -Suffix $PasswordSuffix

        if ($PSCmdlet.ShouldProcess($user.UserPrincipalName, "Reset Password")) {
            $passwordProfile = @{
                "passwordProfile" = @{
                    "password" = $newPassword
                    "forceChangePasswordNextSignIn" = $true
                }
            }

            Update-MgUser -UserId $user.Id -BodyParameter $passwordProfile

            $reportEntry.Status = "Success"
            $reportEntry.NewPassword = $newPassword
            Write-Log "Password reset successful" -UserPrincipalName $user.UserPrincipalName -Password $newPassword
            $successCount++
        }
    } catch {
        $reportEntry.Status = "Failed"
        $reportEntry.ErrorMessage = $_.Exception.Message
        Write-Log "Failed to reset password: $($_.Exception.Message)" -UserPrincipalName $user.UserPrincipalName -Severity Error
        $failureCount++
    }

    $reportData += $reportEntry
}

Write-Progress -Activity "Resetting user passwords" -Completed

# Export CSV report
try {
    $reportData | Export-Csv -Path $CSVPath -NoTypeInformation
    Write-Log "CSV report exported to $CSVPath"
} catch {
    Write-Log "Failed to export CSV report: $($_.Exception.Message)" -Severity Error
}

# Log summary and cleanup
Write-Log "Password reset process completed. Success: $successCount, Failures: $failureCount"

try {
    Disconnect-MgGraph
    Write-Log "Successfully disconnected from Microsoft Graph"
} catch {
    Write-Log "Failed to disconnect from Microsoft Graph: $($_.Exception.Message)" -Severity Warning
}

exit 0
#endregion Main Execution
