<#
.SYNOPSIS
    Exports a detailed report of users with enforced per-user MFA from Microsoft Entra ID.

.DESCRIPTION
    This script connects to Microsoft Graph API and generates a comprehensive CSV report
    containing users who have per-user Multi-Factor Authentication (MFA) enforced and their
    configured default authentication methods. Only users with MFAState = "enforced" are
    included in the output.

    Exported fields include: ObjectId, UserPrincipalName, DisplayName, MFAState,
    MFADefaultMethod, PrimarySMTP, Aliases, UserType, AccountEnabled, and CreatedDateTime.

    The script includes advanced features to handle large environments efficiently:
    - Batch processing to manage large user sets
    - Parallel processing with controlled concurrency (ThrottleLimit)
    - Automatic throttling controls to respect Microsoft Graph API rate limits
    - Exponential backoff retry logic for 429 (Too Many Requests) errors
    - Incremental CSV export to preserve progress in case of interruption
    - Comprehensive error handling with detailed logging

.PARAMETER OutputPath
    Specifies the path to the output CSV file. Must have a .csv extension.
    Default: MFAEnforcedUsers.csv in the script's directory ($PSScriptRoot)

.EXAMPLE
    .\Export-PerUserMFAUsers.ps1

    Connects to Microsoft Graph (prompts for authentication), retrieves all users,
    processes their MFA status in batches, and exports users with enforced MFA to
    MFAEnforcedUsers.csv in the script's directory.

.EXAMPLE
    .\Export-PerUserMFAUsers.ps1 -OutputPath "C:\Reports\MFA-Enforced-Users.csv"

    Exports the MFA report to a custom location. Only users with enforced per-user MFA
    will be included in the output file.

.EXAMPLE
    .\Export-PerUserMFAUsers.ps1 -OutputPath ".\Reports\MFAReport.csv"

    Exports the report to a relative path (Reports subdirectory under the script location).

.NOTES
    Author:         Benjamin Wolfe
    Version:        2.0
    DateCreated:    2025-01-01
    LastModified:   2025-12-29

    Requirements:
    - PowerShell 7.0 or later (for ForEach-Object -Parallel support)
    - Microsoft.Graph.Authentication module
    - Microsoft.Graph.Users module

    Required Permissions:
    - User.Read.All (Read all users' full profiles)
    - Policy.Read.AuthenticationMethod (Read authentication method policies)
    - UserAuthenticationMethod.Read.All (Read users' authentication methods)

    Performance Considerations:
    - Batch size: 20 users per batch (configurable on line 121)
    - Parallel throttle limit: 10 concurrent operations (configurable on line 149)
    - Inter-batch delay: 10 seconds (configurable on line 338)
    - Per-user random delay: 200-500ms

    Filtering:
    - Only users with PerUserMfaState = "enforced" are included in the report
    - Error entries are still captured to help track processing issues

    The script uses the Microsoft Graph Beta endpoint for accessing per-user MFA
    state and authentication preferences. This may change as the API evolves.

.LINK
    https://learn.microsoft.com/en-us/graph/api/authentication-list-requirements

.LINK
    https://learn.microsoft.com/en-us/graph/api/authenticationmethods-list
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Path to the output CSV file")]
    [ValidatePattern('\.csv$')]
    [string]$OutputPath = "$PSScriptRoot\MFAEnforcedUsers.csv"
)

#region Initialization and Setup

# Connect to Microsoft Graph with the required scopes
# These scopes enable access to user information and authentication settings
Connect-MgGraph -Scopes "User.Read.All", "Policy.Read.AuthenticationMethod", "UserAuthenticationMethod.Read.All" -nowelcome

# Create the output directory if it doesn't exist
# This ensures the export location is available before processing
$outputDirectory = Split-Path -Path $OutputPath -Parent
if (-not (Test-Path -Path $outputDirectory)) {
    New-Item -Path $outputDirectory -ItemType Directory -Force | Out-Null
}

#endregion

#region User Data Retrieval

# Define the user properties we want to retrieve
# These properties provide essential user identity information
$Properties = @(
    'Id',                 # Unique identifier (GUID) for the user
    'DisplayName',        # User's full name
    'UserPrincipalName',  # Primary email/login
    'UserType',           # Member, Guest, etc.
    'Mail',               # Primary email address
    'ProxyAddresses',     # All email aliases
    'AccountEnabled',     # Whether the account is active
    'CreatedDateTime'     # When the account was created
)

# Retrieve all users with the specified properties
# This gets the baseline user information before checking MFA status
[array]$Users = Get-MgUser -All -Property $Properties | Select-Object $Properties

# Verify that users were successfully retrieved
# Exit gracefully if no users were found
if (-not $Users) {
    Write-Host "No users found. Exiting script." -ForegroundColor Red
    return
}

#endregion

#region Batch Processing Setup

# Initialise variables for processing
$totalUsers = $Users.Count
$batchSize = 20  # Process users in small batches to avoid throttling
$processedCount = 0

# Create a generic list to store the report data
# Using a generic list for better performance with large datasets
$Report = [System.Collections.Generic.List[Object]]::new()

Write-Host "Processing $totalUsers users in small batches of $batchSize with throttling controls..." -ForegroundColor Cyan

#endregion

#region Main Processing Loop

# Process users in batches to manage API load and avoid throttling
# This loop takes chunks of users and processes them before moving to the next chunk
for ($i = 0; $i -lt $totalUsers; $i += $batchSize) {
    # Get the current batch of users
    $userBatch = $Users | Select-Object -Skip $i -First $batchSize
    $batchCount = $userBatch.Count

    Write-Host "Processing batch $([math]::Floor($i/$batchSize) + 1) with $batchCount users..." -ForegroundColor Yellow

    # Create a thread-safe collection for this batch
    # ConcurrentBag allows multiple threads to safely add items
    $batchReport = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()

    # Set throttle limit for parallel processing
    # This controls how many parallel operations run simultaneously
    $ThrottleLimit = 10  # Limit parallel processes to reduce API pressure

    #region Parallel User Processing

    # Process the current batch with controlled parallelism
    # Each user is processed in a separate thread, but limited by ThrottleLimit
    $userBatch | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
        # Import necessary modules in the parallel runspace
        # Each parallel thread needs its own module imports
        Import-Module Microsoft.Graph.Authentication
        Import-Module Microsoft.Graph.Users

        $User = $_
        $batchReport = $using:batchReport

        #region Helper Function - Retry Logic

        # Define a retry function for Graph API calls
        # This handles rate limiting (429 errors) with exponential backoff
        function Invoke-GraphRequestWithRetry {
            [CmdletBinding()]
            param (
                [Parameter(Mandatory = $true)]
                [string]$Uri,

                [Parameter(Mandatory = $false)]
                [string]$Method = "GET",

                [Parameter(Mandatory = $false)]
                [int]$MaxRetries = 5
            )

            $retryCount = 0
            $success = $false
            $result = $null

            while (-not $success -and $retryCount -lt $MaxRetries) {
                try {
                    # Attempt to make the Graph API request
                    $result = Invoke-MgGraphRequest -Uri $Uri -Method $Method
                    $success = $true
                }
                catch {
                    # Handle rate limiting (HTTP 429 - Too Many Requests)
                    if ($_.Exception.Response -and $_.Exception.Response.StatusCode.value__ -eq 429) {
                        $retryCount++
                        # Exponential backoff with jitter: 2^retry + random(0-1000ms)
                        # This helps prevent all retries happening simultaneously
                        $delay = [math]::Pow(2, $retryCount) + (Get-Random -Minimum 200 -Maximum 1000)

                        # Check for Retry-After header from the API
                        # This is the recommended wait time from Microsoft
                        $retryAfter = $null
                        try {
                            $retryAfter = $_.Exception.Response.Headers["Retry-After"]
                        } catch {
                            # Header might not exist, continue with calculated delay
                        }

                        # Use Retry-After header if available, otherwise use calculated delay
                        if ($retryAfter) {
                            $delay = [int]$retryAfter * 1000  # Convert to milliseconds
                        }

                        Write-Warning "TooManyRequests error for $Uri. Waiting $delay ms before retry $retryCount of $MaxRetries..."
                        Start-Sleep -Milliseconds $delay
                    }
                    else {
                        # For errors other than rate limiting, throw the exception
                        throw $_
                    }
                }
            }

            # If all retries failed, throw an exception
            if (-not $success) {
                throw "Failed after $MaxRetries retries"
            }

            return $result
        }

        #endregion

        #region Process Individual User

        try {
            # Add delay between processing different users
            # This helps smooth out the API request pattern
            Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 500)

            # Get MFA requirements status for the user
            # This tells us if MFA is enforced for this user
            $MFAStateUri = "https://graph.microsoft.com/beta/users/$($User.Id)/authentication/requirements"
            $Data = Invoke-GraphRequestWithRetry -Uri $MFAStateUri

            # Add delay between API calls for the same user
            # This further reduces the risk of throttling
            Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 500)

            # Get the user's preferred MFA method
            # This shows which authentication method the user has set as default
            $DefaultMFAUri = "https://graph.microsoft.com/beta/users/$($User.Id)/authentication/signInPreferences"
            $DefaultMFAMethod = Invoke-GraphRequestWithRetry -Uri $DefaultMFAUri

            # Convert the API's method code to a human-readable format
            if ($DefaultMFAMethod.userPreferredMethodForSecondaryAuthentication) {
                $MFAMethod = $DefaultMFAMethod.userPreferredMethodForSecondaryAuthentication
                Switch ($MFAMethod) {
                    "push" { $MFAMethod = "Microsoft authenticator app" }
                    "oath" { $MFAMethod = "Authenticator app or hardware token" }
                    "voiceMobile" { $MFAMethod = "Mobile phone" }
                    "voiceAlternateMobile" { $MFAMethod = "Alternate mobile phone" }
                    "voiceOffice" { $MFAMethod = "Office phone" }
                    "sms" { $MFAMethod = "SMS" }
                    Default { $MFAMethod = "Unknown method" }
                }
            }
            else {
                $MFAMethod = "Not Enabled"
            }

            # Extract email aliases from ProxyAddresses
            # ProxyAddresses contains all email addresses, we filter to just get the SMTP ones
            $Aliases = ($User.ProxyAddresses | Where-Object { $_ -clike "smtp*" } | ForEach-Object { $_ -replace "smtp:", "" }) -join ', '

            # Create a report entry for this user
            # This contains all the user and MFA information we want to report
            $ReportLine = [PSCustomObject][ordered]@{
                ObjectId          = $User.Id
                UserPrincipalName = $User.UserPrincipalName
                DisplayName       = $User.DisplayName
                MFAState          = $Data.PerUserMfaState
                MFADefaultMethod  = $MFAMethod
                PrimarySMTP       = $User.Mail
                Aliases           = $Aliases
                UserType          = $User.UserType
                AccountEnabled    = $User.AccountEnabled
                CreatedDateTime   = $User.CreatedDateTime
            }

            # Only add users with enforced MFA to the report
            if ($Data.PerUserMfaState -eq "enforced") {
                $batchReport.Add($ReportLine)
            }
        }
        catch {
            # Handle and log any errors during processing
            Write-Warning "Error processing user $($User.UserPrincipalName): $_"

            # Create an error entry for the report
            # This ensures the user appears in the report even if there was an error
            $ReportLine = [PSCustomObject][ordered]@{
                ObjectId          = $User.Id
                UserPrincipalName = $User.UserPrincipalName
                DisplayName       = $User.DisplayName
                MFAState          = "Error"
                MFADefaultMethod  = "Error: $_"
                PrimarySMTP       = $User.Mail
                Aliases           = ($User.ProxyAddresses | Where-Object { $_ -clike "smtp*" } | ForEach-Object { $_ -replace "smtp:", "" }) -join ', '
                UserType          = $User.UserType
                AccountEnabled    = $User.AccountEnabled
                CreatedDateTime   = $User.CreatedDateTime
            }

            # Add the error entry to the report
            $batchReport.Add($ReportLine)
        }

        #endregion
    }

    #endregion

    #region Batch Completion and Export

    # Add all results from this batch to the main report
    $Report.AddRange($batchReport)

    # Update the count of processed users
    $processedCount += $batchCount

    # Show a progress bar to indicate completion percentage
    Write-Progress -Activity "Processing User Batches" -Status "Processed $processedCount of $totalUsers users" -PercentComplete (($processedCount / $totalUsers) * 100)

    # Write to CSV file after each batch
    # This provides incremental backup in case of script interruption
    if ($Report.Count -gt 0) {
        $Report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding utf8 -Force
    }

    # Add a delay between batches to further reduce throttling risk
    if ($i + $batchSize -lt $totalUsers) {
        $delaySeconds = 10
        Write-Host "Waiting $delaySeconds seconds before processing next batch..." -ForegroundColor Cyan
        Start-Sleep -Seconds $delaySeconds
    }

    #endregion
}

#endregion

#region Final Export and Completion

# Mark the progress bar as complete
Write-Progress -Activity "Processing User Batches" -Completed

# Export the final complete report to CSV
$Report | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding utf8
Write-Host "Entra per-user MFA Report is in $OutputPath" -ForegroundColor Cyan

#endregion
