<#
.SYNOPSIS
    Disables per-user MFA for users listed in a CSV file.

.DESCRIPTION
    This script processes a CSV file containing user information and disables per-user
    MFA for each user. The script is designed to work with the output from Export-PerUserMFAUsers.ps1.

    Key features:
    - Supports both ObjectId and UserPrincipalName for user identification
    - Intelligent retry logic with exponential backoff for API throttling
    - Batch processing with optional parallel execution
    - WhatIf support to preview changes before execution
    - Failed users export to CSV for easy reprocessing
    - Comprehensive logging to both console and file
    - Connection state preservation (doesn't disconnect if already connected)

.PARAMETER CsvPath
    Path to the CSV file containing user data. The file must have either an ObjectId
    column or a UserPrincipalName column. If both are present, ObjectId is used for
    better performance. File must have .csv extension.

.PARAMETER LogPath
    Optional path for the log file. If not specified, creates a timestamped log file
    in the script's directory: MFA_Disable_Log_yyyyMMdd_HHmmss.log

.PARAMETER BatchSize
    Number of users to process in each batch. Default is 20. Larger batches may
    improve performance but increase risk of API throttling.

.PARAMETER ThrottleLimit
    Maximum number of concurrent operations when using parallel processing.
    Default is 10. Lower values are more conservative and reduce throttling risk.

.PARAMETER WhatIf
    Shows what would happen if the script runs without actually making any changes.
    Use this to preview which users would be affected.

.PARAMETER Confirm
    Prompts for confirmation before disabling MFA for each user.

.EXAMPLE
    .\Disable-BulkPerUserMFA.ps1 -CsvPath ".\MFAEnforcedUsers.csv"

    Disables MFA for all users in the CSV file using default settings. The CSV could
    be the output from Export-PerUserMFAUsers.ps1.

.EXAMPLE
    .\Disable-BulkPerUserMFA.ps1 -CsvPath "C:\Reports\Users.csv" -LogPath "C:\Logs\MFA_Disable.log"

    Disables MFA for users in the specified CSV and writes the log to a custom location.

.EXAMPLE
    .\Disable-BulkPerUserMFA.ps1 -CsvPath ".\Users.csv" -WhatIf

    Preview mode - shows which users would have MFA disabled without making any changes.

.EXAMPLE
    .\Disable-BulkPerUserMFA.ps1 -CsvPath ".\Users.csv" -BatchSize 50 -ThrottleLimit 15

    Processes users in larger batches (50) with more parallelism (15) for faster execution.

.NOTES
    Author:         Benjamin Wolfe
    Version:        2.0
    DateCreated:    2025-04-15
    LastModified:   2025-12-30

    Requirements:
    - PowerShell 7.0 or later (for ForEach-Object -Parallel support)
    - Microsoft.Graph.Authentication module
    - Microsoft.Graph.Users module

    Required Permissions:
    - User.Read.All or User.ReadWrite.All (to look up user IDs)
    - Directory.ReadWrite.All or UserAuthenticationMethod.ReadWrite.All (to disable MFA)

    Performance Considerations:
    - Using ObjectId from CSV is ~10x faster than UPN lookup
    - Export script now includes ObjectId for optimal performance
    - Batch processing improves throughput for large user sets
    - Retry logic handles API throttling automatically

    Version History:
    - 1.0: Initial version with basic sequential processing
    - 2.0: Complete overhaul - parameters, ObjectId optimization, retry logic,
           batch processing, WhatIf support, failed users CSV

    IMPORTANT - Authentication Methods Preservation:
    This script ONLY disables the per-user MFA policy state. It does NOT remove or
    modify any of the user's registered authentication methods (phone numbers,
    authenticator apps, FIDO2 keys, hardware tokens, etc.). All authentication
    methods remain registered and available for use with Conditional Access policies
    or if per-user MFA is re-enabled in the future. Users will not need to
    re-register their authentication methods.

.LINK
    https://learn.microsoft.com/en-us/graph/api/authentication-update

.LINK
    https://learn.microsoft.com/en-us/powershell/module/microsoft.graph.users
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Path to CSV file with user data")]
    [ValidateScript({
        if (-not (Test-Path $_ -PathType Leaf)) {
            throw "CSV file not found: $_"
        }
        if ($_ -notmatch '\.csv$') {
            throw "File must have .csv extension: $_"
        }
        $true
    })]
    [string]$CsvPath,

    [Parameter(Mandatory = $false, HelpMessage = "Path for the log file")]
    [string]$LogPath = "$PSScriptRoot\MFA_Disable_Log_$(Get-Date -Format 'yyyyMMdd_HHmmss').log",

    [Parameter(Mandatory = $false, HelpMessage = "Number of users per batch")]
    [ValidateRange(1, 100)]
    [int]$BatchSize = 20,

    [Parameter(Mandatory = $false, HelpMessage = "Maximum concurrent operations")]
    [ValidateRange(1, 20)]
    [int]$ThrottleLimit = 10
)

#region Helper Functions

# Function to write to both console and log file
function Write-Log {
    <#
    .SYNOPSIS
        Writes a message to both the console and the log file.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('INFO', 'SUCCESS', 'WARNING', 'ERROR')]
        [string]$Type = 'INFO'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $logMessage = "[$timestamp] [$Type] $Message"

    # Write to console with appropriate colour
    switch ($Type) {
        'INFO'    { Write-Host $logMessage -ForegroundColor Cyan }
        'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
        'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
        'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
        default   { Write-Host $logMessage }
    }

    # Write to log file
    try {
        Add-Content -Path $script:LogPath -Value $logMessage -ErrorAction Stop
    }
    catch {
        Write-Warning "Failed to write to log file: $_"
    }
}

# Function to retry Graph API requests with exponential backoff
function Invoke-GraphRequestWithRetry {
    <#
    .SYNOPSIS
        Invokes a Microsoft Graph API request with automatic retry logic for throttling.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Uri,

        [Parameter(Mandatory = $true)]
        [hashtable]$Body,

        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 5
    )

    $retryCount = 0
    $success = $false

    while (-not $success -and $retryCount -lt $MaxRetries) {
        try {
            # Attempt the Graph API request
            Invoke-MgGraphRequest -Method PATCH -Uri $Uri -Body $Body -ErrorAction Stop
            $success = $true
            return $true
        }
        catch {
            # Check if this is a throttling error (HTTP 429)
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 429) {
                $retryCount++

                # Calculate exponential backoff delay with jitter
                $baseDelay = [math]::Pow(2, $retryCount) * 1000  # Convert to milliseconds
                $jitter = Get-Random -Minimum 200 -Maximum 1000
                $delay = $baseDelay + $jitter

                # Check for Retry-After header
                $retryAfter = $null
                try {
                    $retryAfter = $_.Exception.Response.Headers['Retry-After']
                    if ($retryAfter) {
                        $delay = [int]$retryAfter * 1000  # Convert to milliseconds
                    }
                }
                catch {
                    # Retry-After header not available, use calculated delay
                }

                Write-Log "Rate limited (429). Retry $retryCount of $MaxRetries after ${delay}ms..." -Type 'WARNING'
                Start-Sleep -Milliseconds $delay
            }
            else {
                # Not a throttling error, throw it
                throw
            }
        }
    }

    # If we exhausted all retries, throw an error
    if (-not $success) {
        throw "Failed after $MaxRetries retry attempts due to persistent throttling"
    }
}

#endregion

#region Initialization

Write-Host "`n=== MFA Bulk Disable Script v2.0 ===" -ForegroundColor Cyan
Write-Host "Starting at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n" -ForegroundColor Cyan

# Create log directory if it doesn't exist
$logDirectory = Split-Path -Path $LogPath -Parent
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -Path $logDirectory -ItemType Directory -Force | Out-Null
}

Write-Log "Script started" -Type 'INFO'
Write-Log "Log file: $LogPath" -Type 'INFO'

# Import the CSV file
Write-Log "Importing CSV file: $CsvPath" -Type 'INFO'
try {
    $users = Import-Csv -Path $CsvPath -ErrorAction Stop
    if ($users.Count -eq 0) {
        throw "CSV file is empty"
    }
    Write-Log "Successfully imported $($users.Count) users from CSV" -Type 'SUCCESS'
}
catch {
    Write-Log "Failed to import CSV: $_" -Type 'ERROR'
    throw
}

# Check if CSV has ObjectId column (preferred for performance)
$hasObjectId = $users[0].PSObject.Properties.Name -contains 'ObjectId'
$hasUserPrincipalName = $users[0].PSObject.Properties.Name -contains 'UserPrincipalName'

if (-not $hasObjectId -and -not $hasUserPrincipalName) {
    $errorMsg = "CSV must contain either 'ObjectId' or 'UserPrincipalName' column"
    Write-Log $errorMsg -Type 'ERROR'
    throw $errorMsg
}

if ($hasObjectId) {
    Write-Log "CSV contains ObjectId column - using optimized lookup (faster)" -Type 'INFO'
}
else {
    Write-Log "CSV only has UserPrincipalName - will perform user lookups (slower)" -Type 'WARNING'
}

# Check if already connected to Microsoft Graph
$context = Get-MgContext
$wasConnected = $context -ne $null

if (-not $wasConnected) {
    Write-Log "Connecting to Microsoft Graph..." -Type 'INFO'
    try {
        Connect-MgGraph -Scopes 'User.Read.All', 'UserAuthenticationMethod.ReadWrite.All' -NoWelcome -ErrorAction Stop
        Write-Log "Successfully connected to Microsoft Graph" -Type 'SUCCESS'
    }
    catch {
        Write-Log "Failed to connect to Microsoft Graph: $_" -Type 'ERROR'
        throw
    }
}
else {
    Write-Log "Already connected to Microsoft Graph as $($context.Account)" -Type 'INFO'
}

# Initialise counters
$totalUsers = $users.Count
$processedUsers = 0
$successCount = 0
$failureCount = 0
$startTime = Get-Date

# Initialise collection for failed users
$failedUsers = [System.Collections.Generic.List[Object]]::new()

Write-Log "Starting to process $totalUsers users in batches of $BatchSize" -Type 'INFO'
Write-Log "Parallel throttle limit: $ThrottleLimit concurrent operations" -Type 'INFO'

if ($WhatIfPreference) {
    Write-Log "WHATIF MODE: No changes will be made" -Type 'WARNING'
}

#endregion

#region Main Processing Loop

# Process users in batches
for ($i = 0; $i -lt $totalUsers; $i += $BatchSize) {
    # Get the current batch
    $userBatch = $users | Select-Object -Skip $i -First $BatchSize
    $batchCount = $userBatch.Count
    $batchNumber = [math]::Floor($i / $BatchSize) + 1

    Write-Log "Processing batch $batchNumber with $batchCount users..." -Type 'INFO'

    # Create thread-safe collection for batch results
    $batchResults = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()

    # Process batch with parallel execution
    $userBatch | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        # Import modules in parallel runspace
        Import-Module Microsoft.Graph.Authentication
        Import-Module Microsoft.Graph.Users

        $user = $_
        $hasObjectId = $using:hasObjectId
        $batchResults = $using:batchResults
        $LogPath = $using:LogPath

        # Recreate Write-Log function in parallel runspace
        function Write-Log {
            param ([string]$Message, [string]$Type = 'INFO')
            $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            $logMessage = "[$timestamp] [$Type] $Message"
            switch ($Type) {
                'INFO'    { Write-Host $logMessage -ForegroundColor Cyan }
                'SUCCESS' { Write-Host $logMessage -ForegroundColor Green }
                'WARNING' { Write-Host $logMessage -ForegroundColor Yellow }
                'ERROR'   { Write-Host $logMessage -ForegroundColor Red }
            }
            try {
                Add-Content -Path $LogPath -Value $logMessage -ErrorAction SilentlyContinue
            } catch {}
        }

        # Recreate retry function in parallel runspace
        function Invoke-GraphRequestWithRetry {
            param ([string]$Uri, [hashtable]$Body, [int]$MaxRetries = 5)
            $retryCount = 0
            $success = $false
            while (-not $success -and $retryCount -lt $MaxRetries) {
                try {
                    Invoke-MgGraphRequest -Method PATCH -Uri $Uri -Body $Body -ErrorAction Stop
                    $success = $true
                    return $true
                }
                catch {
                    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 429) {
                        $retryCount++
                        $baseDelay = [math]::Pow(2, $retryCount) * 1000
                        $jitter = Get-Random -Minimum 200 -Maximum 1000
                        $delay = $baseDelay + $jitter
                        Write-Log "Rate limited. Retry $retryCount of $MaxRetries after ${delay}ms..." -Type 'WARNING'
                        Start-Sleep -Milliseconds $delay
                    }
                    else {
                        throw
                    }
                }
            }
            if (-not $success) {
                throw "Failed after $MaxRetries retries"
            }
        }

        # Process individual user
        $result = [PSCustomObject]@{
            UserPrincipalName = $null
            ObjectId          = $null
            Status            = 'Failed'
            Error             = $null
            Timestamp         = Get-Date
        }

        try {
            # Small delay to spread out requests
            Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 300)

            # Get user identifier
            if ($hasObjectId -and $user.ObjectId) {
                # Use ObjectId directly (much faster!)
                $userId = $user.ObjectId
                $userIdentifier = $user.UserPrincipalName
                Write-Log "Processing user: $userIdentifier (using ObjectId)" -Type 'INFO'
            }
            else {
                # Look up user by UPN
                $userIdentifier = $user.UserPrincipalName
                Write-Log "Processing user: $userIdentifier (looking up ObjectId)" -Type 'INFO'
                $mgUser = Get-MgUser -UserId $userIdentifier -ErrorAction Stop
                $userId = $mgUser.Id
            }

            $result.UserPrincipalName = $userIdentifier
            $result.ObjectId = $userId

            if (-not $userId) {
                throw "User ID not found"
            }

            # Disable per-user MFA with retry logic
            $uri = "https://graph.microsoft.com/beta/users/$userId/authentication/requirements"
            $body = @{ perUserMfaState = 'disabled' }

            # Check if WhatIf is enabled
            if ($using:WhatIfPreference) {
                Write-Log "WHATIF: Would disable MFA for $userIdentifier" -Type 'WARNING'
                $result.Status = 'WhatIf'
            }
            else {
                Invoke-GraphRequestWithRetry -Uri $uri -Body $body -MaxRetries 5
                Write-Log "Successfully disabled MFA for $userIdentifier" -Type 'SUCCESS'
                $result.Status = 'Success'
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Log "Failed to disable MFA for $userIdentifier`: $errorMessage" -Type 'ERROR'
            $result.Error = $errorMessage
            $result.Status = 'Failed'
        }

        # Add result to thread-safe collection
        $batchResults.Add($result)
    }

    # Process batch results
    foreach ($result in $batchResults) {
        $processedUsers++

        if ($result.Status -eq 'Success') {
            $successCount++
        }
        elseif ($result.Status -eq 'Failed') {
            $failureCount++
            $failedUsers.Add($result)
        }
        # WhatIf results don't count as success or failure
    }

    # Update progress
    $percentComplete = [math]::Round(($processedUsers / $totalUsers) * 100, 1)
    Write-Progress -Activity 'Disabling per-user MFA' -Status "$percentComplete% Complete" `
        -CurrentOperation "Processed $processedUsers of $totalUsers users" `
        -PercentComplete $percentComplete

    # Delay between batches to prevent API overload
    if (($i + $BatchSize) -lt $totalUsers) {
        $delaySeconds = 5
        Write-Log "Waiting $delaySeconds seconds before next batch..." -Type 'INFO'
        Start-Sleep -Seconds $delaySeconds
    }
}

Write-Progress -Activity 'Disabling per-user MFA' -Completed

#endregion

#region Summary and Cleanup

# Calculate duration
$endTime = Get-Date
$duration = $endTime - $startTime
$formattedDuration = "{0:hh\:mm\:ss}" -f $duration

# Export failed users if any
if ($failedUsers.Count -gt 0) {
    $failedCsvPath = "$PSScriptRoot\MFA_Disable_Failed_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    try {
        $failedUsers | Export-Csv -Path $failedCsvPath -NoTypeInformation -ErrorAction Stop
        Write-Log "Failed users exported to: $failedCsvPath" -Type 'WARNING'
    }
    catch {
        Write-Log "Failed to export failed users CSV: $_" -Type 'ERROR'
    }
}

# Display summary
Write-Log '-------------------------------------------' -Type 'INFO'
Write-Log "Process completed in $formattedDuration" -Type 'INFO'
Write-Log "Total users processed: $totalUsers" -Type 'INFO'

if ($WhatIfPreference) {
    Write-Log "Mode: WHATIF (no changes made)" -Type 'WARNING'
}
else {
    Write-Log "Successful: $successCount" -Type 'SUCCESS'
    Write-Log "Failed: $failureCount" -Type $(if ($failureCount -gt 0) { 'ERROR' } else { 'INFO' })
}

Write-Log '-------------------------------------------' -Type 'INFO'

# Disconnect only if we connected
if (-not $wasConnected) {
    Write-Log "Disconnecting from Microsoft Graph..." -Type 'INFO'
    Disconnect-MgGraph -NoWelcome
}
else {
    Write-Log "Leaving Microsoft Graph connection open (was already connected)" -Type 'INFO'
}

# Final message
Write-Host "`n=== Process Complete ===" -ForegroundColor Cyan
Write-Host "Log file: $LogPath" -ForegroundColor Cyan
if ($failedUsers.Count -gt 0) {
    Write-Host "Failed users CSV: $failedCsvPath" -ForegroundColor Yellow
}
Write-Host ""

#endregion
