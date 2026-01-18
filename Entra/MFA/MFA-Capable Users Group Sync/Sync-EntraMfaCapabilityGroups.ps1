<#
.SYNOPSIS
    Manages Entra group memberships for users based on their MFA capability.

.DESCRIPTION
    This script manages Entra group memberships for users based on their MFA capability (registered or not).
    It categorises users into two predefined groups: 'MFA-capable' and 'MFA-non-capable'.
    Users are added to or removed from these groups based on their current MFA registration status.
    This can help to drive MFA registration campaigns or enforce policies based on MFA capability, such as block access policies for non-MFA-capable users.

    The script performs the following operations:
    1. Retrieves all users in the tenant and filters out guests.
    2. Retrieves the MFA registration details and current group membership of the two groups 'MFA-capable' & 'MFA-non-capable'.
    3. Categorises users based on the boolean value in the IsMfaCapable property.
    4. Updates memberships of the predefined groups for MFA-capable and MFA-non-capable users.
    5. Removes users from the opposite group if their MFA status has changed.
    6. Uses parallel processing to handle a large number of users as quickly as possible.
    7. Implements error handling to avoid redundant group additions and removals.
    8. Provides enhanced visual output with colours and detailed progress information.

.EXAMPLE
    .\Sync-EntraMfaCapabilityGroups.ps1

    Runs the script to synchronise all users into the appropriate MFA capability groups.

.NOTES
    Author: Benjamin Wolfe
    Date: August 15, 2024
    Version: 1.0

    Configuration:
    - You can adjust the number of parallel jobs by changing the $maxParallelJobs variable (default: 20, tested up to 50).
    - Group IDs are configured in the script variables: $mfaCapableGroupId and $mfaNonCapableGroupId
    - Log file is created at: $PSScriptRoot\AuthenticationReport_Log.txt
#>

# Import necessary modules
#region Module Management
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users
Import-Module Microsoft.Graph.Groups
Import-Module Microsoft.Graph.Reports

# Log file path
$logPath = "$PSScriptRoot\AuthenticationReport_Log.txt"

# Predefined Group IDs
$mfaCapableGroupId = "c003270a-88c1-4f80-83ca-107fb9a05071"  # This is the group ID for your 'MFA-capable' group
$mfaNonCapableGroupId = "1ce56375-42cd-43db-98bf-7c626939246c"  # This is the group ID for your 'MFA-non-capable' group
#endregion Module Management

# Number of parallel jobs to run
$maxParallelJobs = 20 # You can change this value but the higher the number, the more resources it will consume. Tested with 50.

# Function to write to both console and log file with colour
#region Helper Functions
function Write-ColourLog {
    param(
        [string]$Message,
        [string]$Colour = "White"
    )
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "{0}: {1}" -f $timestamp, $Message
    Write-Host $logMessage -ForegroundColor $Colour
    Add-Content -Path $logPath -Value $logMessage
}

# Function to display a progress bar
function Show-ProgressBar {
    param(
        [int]$PercentComplete,
        [string]$Status
    )
    Write-Progress -Activity "Processing Users" -Status $Status -PercentComplete $PercentComplete
}

# Connect to Microsoft Graph with updated scopes
Connect-MgGraph -Scopes @(
    "User.Read.All",
    "Group.ReadWrite.All",
    "UserAuthenticationMethod.Read.All",
    "AuditLog.Read.All"
) -NoWelcome

try {
    Write-ColourLog "Script started. Fetching MFA registration details for all users..." -Colour Cyan

    # Fetch MFA registration details only for non-guest users
    $mfaUsers = Get-MgBetaReportAuthenticationMethodUserRegistrationDetail -Filter "UserType eq 'Member'" -All
#endregion Helper Functions
    Write-ColourLog ("MFA registration details fetched. Total users: " + $mfaUsers.Count) -Colour Green

    Write-ColourLog "Fetching all users from Entra..." -Colour Cyan
    $allUsers = Get-MgUser -Filter "UserType eq 'Member'" -All -Select "Id,UserPrincipalName"
#region Main Execution
    Write-ColourLog ("All users fetched. Total users (excluding guests): " + $allUsers.Count) -Colour Green

    # Create a hashtable for quick lookup of MFA status
    $mfaStatus = @{}
    foreach ($user in $mfaUsers) {
        $mfaStatus[$user.Id] = $user.IsMfaCapable
    }

    # Create a combined list of all users with their MFA status
    $users = $allUsers | ForEach-Object {
        [PSCustomObject]@{
            Id = $_.Id
            UserPrincipalName = $_.UserPrincipalName
            IsMfaCapable = if ($mfaStatus.ContainsKey($_.Id)) { $mfaStatus[$_.Id] } else { $false }
        }
    }

    Write-ColourLog ("Combined user list created. Total users: " + $users.Count) -Colour Green

    # Fetch current members of both groups
    Write-ColourLog "Fetching current group members..." -Colour Cyan
    $mfaCapableGroupMembers = @(Get-MgGroupMember -GroupId $mfaCapableGroupId -All).Id
    $mfaNonCapableGroupMembers = @(Get-MgGroupMember -GroupId $mfaNonCapableGroupId -All).Id
    Write-ColourLog "Group members fetched. MFA Capable: $($mfaCapableGroupMembers.Count), MFA Non-Capable: $($mfaNonCapableGroupMembers.Count)" -Colour Green

    $totalUsers = $users.Count

    # Create a thread-safe variable to track progress
    $progress = [hashtable]::Synchronized(@{
        ProcessedUsers = 0
        MfaCapableAdded = 0
        MfaNonCapableAdded = 0
        MfaCapableRemoved = 0
        MfaNonCapableRemoved = 0
        AlreadyInCorrectGroup = 0
        ErrorCount = 0
    })

    Write-ColourLog "Starting user processing..." -Colour Yellow

    # Process users in parallel
    $users | ForEach-Object -ThrottleLimit $maxParallelJobs -Parallel {
        # Import modules and variables into the parallel scope
        Import-Module Microsoft.Graph.Groups

        $mfaCapableGroupId = $using:mfaCapableGroupId
        $mfaNonCapableGroupId = $using:mfaNonCapableGroupId
        $progress = $using:progress
        $mfaCapableGroupMembers = $using:mfaCapableGroupMembers
        $mfaNonCapableGroupMembers = $using:mfaNonCapableGroupMembers

        $addToGroupId = if ($_.IsMfaCapable) { $mfaCapableGroupId } else { $mfaNonCapableGroupId }
        $removeFromGroupId = if ($_.IsMfaCapable) { $mfaNonCapableGroupId } else { $mfaCapableGroupId }

        $inCorrectGroup = ($_.IsMfaCapable -and $_.Id -in $mfaCapableGroupMembers) -or
                          (-not $_.IsMfaCapable -and $_.Id -in $mfaNonCapableGroupMembers)
        $inWrongGroup = ($_.IsMfaCapable -and $_.Id -in $mfaNonCapableGroupMembers) -or
                        (-not $_.IsMfaCapable -and $_.Id -in $mfaCapableGroupMembers)

        if (-not $inCorrectGroup) {
            try {
                New-MgGroupMember -GroupId $addToGroupId -DirectoryObjectId $_.Id -ErrorAction Stop
                if ($_.IsMfaCapable) {
                    $progress.MfaCapableAdded++
                } else {
                    $progress.MfaNonCapableAdded++
                }
            }
            catch {
                if ($_.Exception.Message -like "*One or more added object references already exist*") {
                    $progress.AlreadyInCorrectGroup++
                }
                else {
                    $progress.ErrorCount++
                    Write-Host "Error adding user $($_.UserPrincipalName) to group: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        else {
            $progress.AlreadyInCorrectGroup++
        }

        if ($inWrongGroup) {
            try {
                Remove-MgGroupMemberByRef -GroupId $removeFromGroupId -DirectoryObjectId $_.Id -ErrorAction Stop
                if ($_.IsMfaCapable) {
                    $progress.MfaNonCapableRemoved++
                } else {
                    $progress.MfaCapableRemoved++
                }
            }
            catch {
                $progress.ErrorCount++
                Write-Host "Error removing user $($_.UserPrincipalName) from group: $($_.Exception.Message)" -ForegroundColor Red
            }
        }

        $progress.ProcessedUsers++

        # Update progress every 100 users
        if ($progress.ProcessedUsers % 100 -eq 0) {
            $percentComplete = [math]::Round(($progress.ProcessedUsers / $using:totalUsers) * 100, 2)
            $status = "Processed $($progress.ProcessedUsers) / $using:totalUsers users"
            Write-Progress -Activity "Processing Users" -Status $status -PercentComplete $percentComplete
        }
    }

    # Clear the progress bar
    Write-Progress -Activity "Processing Users" -Completed

    # Fetch group names
    $mfaCapableGroupName = (Get-MgGroup -GroupId $mfaCapableGroupId).DisplayName
    $mfaNonCapableGroupName = (Get-MgGroup -GroupId $mfaNonCapableGroupId).DisplayName

    Write-ColourLog "`nScript completed. User categorization and group membership updates finished." -Colour Green
    Write-ColourLog "`nFinal Results:" -Colour Cyan
    Write-ColourLog "MFA Capable Group: '$mfaCapableGroupName'" -Colour Yellow
    Write-ColourLog "  - Users added:    $($progress.MfaCapableAdded)" -Colour Green
    Write-ColourLog "  - Users removed:  $($progress.MfaCapableRemoved)" -Colour Magenta
    Write-ColourLog "MFA Non-Capable Group: '$mfaNonCapableGroupName'" -Colour Yellow
    Write-ColourLog "  - Users added:    $($progress.MfaNonCapableAdded)" -Colour Green
    Write-ColourLog "  - Users removed:  $($progress.MfaNonCapableRemoved)" -Colour Magenta
    Write-ColourLog "Users already in correct groups: $($progress.AlreadyInCorrectGroup)" -Colour Cyan
    Write-ColourLog "Total users processed: $($progress.ProcessedUsers)" -Colour White
    Write-ColourLog "Errors encountered: $($progress.ErrorCount)" -Colour Red

    # Calculate and display percentages
    $totalChanges = $progress.MfaCapableAdded + $progress.MfaNonCapableAdded + $progress.MfaCapableRemoved + $progress.MfaNonCapableRemoved
    $changePercentage = [math]::Round(($totalChanges / $totalUsers) * 100, 2)
    Write-ColourLog "`nSummary:" -Colour Cyan
    Write-ColourLog "Percentage of users with group changes: $changePercentage%" -Colour Yellow
    Write-ColourLog "Percentage of users already in correct groups: $([math]::Round(($progress.AlreadyInCorrectGroup / $totalUsers) * 100, 2))%" -Colour Yellow
}
catch {
    # Catch errors
    Write-ColourLog ("An error occurred: " + $_.Exception.Message) -Colour Red
}
finally {
    Disconnect-MgGraph
    Write-ColourLog "Disconnected from Microsoft Graph. Script execution finished." -Colour Cyan
}
#endregion Main Execution
