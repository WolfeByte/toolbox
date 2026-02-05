<#
.SYNOPSIS
    Collects Microsoft Entra Connect configuration for PHS migration assessment.
    PII-FREE VERSION - No user-identifiable information is collected.

.DESCRIPTION
    This script gathers comprehensive Entra Connect configuration including sync settings,
    authentication methods, password hash sync status, password writeback configuration,
    TLS/FIPS compliance, sync errors, and custom sync rules to assess readiness for
    Password Hash Sync migration. All user-identifying information is excluded.

.PARAMETER OutputPath
    The folder path where assessment results will be saved.
    If not specified, the script will prompt for a location (default: C:\Temp\PHSAssessment).

.NOTES
    Author: Benjamin Wolfe
    Version: 2.2
    Run this script on the Entra Connect server with appropriate permissions.
    Requires: ADSync PowerShell module

    DATA COLLECTED: Sync configuration, connector status, error counts, policy settings
    DATA EXCLUDED: Names, usernames, email addresses, or any PII
#>

#Requires -Modules ADSync

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

#region Script Configuration
# Prompt for output path if not provided
if (-not $OutputPath) {
    $DefaultPath = "C:\Temp\PHSAssessment"
    $OutputPath = Read-Host "Enter output folder path (default: $DefaultPath)"
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = $DefaultPath
    }
}

if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ComputerName = $env:COMPUTERNAME
$ReportFile = Join-Path $OutputPath "EntraConnect_Config_$Timestamp.txt"

function Write-Section {
    param([string]$Title)
    $separator = "=" * 80
    "`n$separator" | Out-File $ReportFile -Append
    $Title | Out-File $ReportFile -Append
    $separator | Out-File $ReportFile -Append
}

function Write-SubSection {
    param([string]$Title)
    "`n--- $Title ---" | Out-File $ReportFile -Append
}
#endregion

#region Script Metadata
"PHS MIGRATION ASSESSMENT - ENTRA CONNECT CONFIGURATION" | Out-File $ReportFile
"Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $ReportFile -Append
"Server: $ComputerName" | Out-File $ReportFile -Append
"Script Version: 2.2" | Out-File $ReportFile -Append
#endregion

Write-Host "Starting Entra Connect configuration assessment..." -ForegroundColor Cyan

#region Entra Connect Version Information
Write-Section "ENTRA CONNECT VERSION INFORMATION"
Write-Host "Collecting Entra Connect version information..." -ForegroundColor Yellow

try {
    # Get Entra Connect installation info from registry
    $AADConnectPath = "HKLM:\SOFTWARE\Microsoft\Azure AD Connect"
    $AADSyncPath = "HKLM:\SOFTWARE\Microsoft\Microsoft Entra Connect"

    if (Test-Path $AADConnectPath) {
        $AADConnectReg = Get-ItemProperty -Path $AADConnectPath -ErrorAction SilentlyContinue
        "Azure AD Connect Registry Path: $AADConnectPath" | Out-File $ReportFile -Append
        if ($AADConnectReg.Version) {
            "Installed Version: $($AADConnectReg.Version)" | Out-File $ReportFile -Append
        }
    }

    if (Test-Path $AADSyncPath) {
        $EntraConnectReg = Get-ItemProperty -Path $AADSyncPath -ErrorAction SilentlyContinue
        "Entra Connect Registry Path: $AADSyncPath" | Out-File $ReportFile -Append
        if ($EntraConnectReg.Version) {
            "Installed Version: $($EntraConnectReg.Version)" | Out-File $ReportFile -Append
        }
    }

    # Get ADSync module version
    $ADSyncModule = Get-Module -Name ADSync -ListAvailable | Select-Object -First 1
    if ($ADSyncModule) {
        "ADSync Module Version: $($ADSyncModule.Version)" | Out-File $ReportFile -Append
        "ADSync Module Path: $($ADSyncModule.ModuleBase)" | Out-File $ReportFile -Append
    }

    # Get installed product version from WMI
    $AADConnectProduct = Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE '%Azure AD Connect%' OR Name LIKE '%Entra Connect%'" -ErrorAction SilentlyContinue
    if ($AADConnectProduct) {
        foreach ($Product in $AADConnectProduct) {
            "Installed Product: $($Product.Name)" | Out-File $ReportFile -Append
            "Product Version: $($Product.Version)" | Out-File $ReportFile -Append
        }
    }

    "`nNote: Ensure Entra Connect is on the latest supported version for full PHS feature availability." | Out-File $ReportFile -Append

} catch {
    "Error retrieving version information: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Auto-Upgrade Status
Write-Section "AUTO-UPGRADE STATUS"
Write-Host "Checking auto-upgrade configuration..." -ForegroundColor Yellow

try {
    # Use the dedicated cmdlet for auto-upgrade status
    $AutoUpgradeState = Get-ADSyncAutoUpgrade -ErrorAction SilentlyContinue

    "Auto-Upgrade State: $AutoUpgradeState" | Out-File $ReportFile -Append

    switch ($AutoUpgradeState) {
        "Enabled" {
            "STATUS: Auto-upgrade is ENABLED - server will automatically update" | Out-File $ReportFile -Append
        }
        "Suspended" {
            "STATUS: Auto-upgrade is SUSPENDED" | Out-File $ReportFile -Append

            # Try to get the suspension reason
            try {
                $SuspensionReason = Get-ADSyncAutoUpgrade -Detail -ErrorAction SilentlyContinue
                if ($SuspensionReason) {
                    "Details: $SuspensionReason" | Out-File $ReportFile -Append
                }
            } catch {}

            "WARNING: Review why auto-upgrade is suspended and consider enabling it" | Out-File $ReportFile -Append
        }
        "Disabled" {
            "STATUS: Auto-upgrade is DISABLED" | Out-File $ReportFile -Append
            "NOTE: Manual upgrades required - ensure a process is in place to stay current" | Out-File $ReportFile -Append
        }
        default {
            if ([string]::IsNullOrWhiteSpace($AutoUpgradeState)) {
                "STATUS: Auto-upgrade state could not be determined" | Out-File $ReportFile -Append
            } else {
                "STATUS: $AutoUpgradeState" | Out-File $ReportFile -Append
            }
        }
    }

} catch {
    "Error checking auto-upgrade status: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region ADSync Service Account
Write-Section "ADSYNC SERVICE ACCOUNT"
Write-Host "Checking ADSync service configuration..." -ForegroundColor Yellow

try {
    $ADSyncService = Get-CimInstance -ClassName Win32_Service -Filter "Name='ADSync'" -ErrorAction SilentlyContinue

    if ($ADSyncService) {
        "Service Name: $($ADSyncService.Name)" | Out-File $ReportFile -Append
        "Display Name: $($ADSyncService.DisplayName)" | Out-File $ReportFile -Append
        "Service Account: $($ADSyncService.StartName)" | Out-File $ReportFile -Append
        "Start Mode: $($ADSyncService.StartMode)" | Out-File $ReportFile -Append
        "Current State: $($ADSyncService.State)" | Out-File $ReportFile -Append

        # Check if using a managed service account (gMSA)
        if ($ADSyncService.StartName -match '\$$') {
            "`nNOTE: Service appears to be using a Group Managed Service Account (gMSA)" | Out-File $ReportFile -Append
            "This is the recommended configuration for security" | Out-File $ReportFile -Append
        } elseif ($ADSyncService.StartName -eq "NT SERVICE\ADSync") {
            "`nNOTE: Service is using the default virtual service account" | Out-File $ReportFile -Append
        } else {
            "`nNOTE: Service is using a standard user account" | Out-File $ReportFile -Append
            "Consider migrating to a gMSA for improved security" | Out-File $ReportFile -Append
        }

        if ($ADSyncService.State -ne "Running") {
            "`nWARNING: ADSync service is NOT running" | Out-File $ReportFile -Append
        }
    } else {
        "ADSync service not found on this server" | Out-File $ReportFile -Append
    }

} catch {
    "Error checking ADSync service: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region SQL Configuration
Write-Section "SQL DATABASE CONFIGURATION"
Write-Host "Checking SQL database configuration..." -ForegroundColor Yellow

try {
    $DatabaseType = "Unknown"
    $SqlServer = $null
    $SqlInstance = $null

    # Method 1: Check for LocalDB files (most reliable indicator of LocalDB)
    $LocalDBPath = "$env:ProgramFiles\Microsoft Azure AD Sync\Data\ADSync.mdf"
    $IsLocalDB = Test-Path $LocalDBPath

    if ($IsLocalDB) {
        $DatabaseType = "LocalDB"
        "Database Type: LocalDB (SQL Server Express LocalDB)" | Out-File $ReportFile -Append
        "Database Path: $LocalDBPath" | Out-File $ReportFile -Append

        # Get LocalDB file sizes
        $MdfFile = Get-Item $LocalDBPath -ErrorAction SilentlyContinue
        $LdfFile = Get-Item ($LocalDBPath -replace '\.mdf$', '.ldf') -ErrorAction SilentlyContinue

        if ($MdfFile) {
            $MdfSizeMB = [math]::Round($MdfFile.Length / 1MB, 2)
            "Database Size (MDF): $MdfSizeMB MB" | Out-File $ReportFile -Append

            # Check if approaching LocalDB limit (10GB)
            if ($MdfSizeMB -gt 8000) {
                "`nWARNING: Database is approaching the 10GB LocalDB limit" | Out-File $ReportFile -Append
            }
        }
        if ($LdfFile) {
            "Log Size (LDF): $([math]::Round($LdfFile.Length / 1MB, 2)) MB" | Out-File $ReportFile -Append
        }

        "`nNOTE: LocalDB has a 10GB size limit" | Out-File $ReportFile -Append
        "For environments with >100,000 objects, consider migrating to full SQL Server" | Out-File $ReportFile -Append

    } else {
        # Method 2: Check registry for SQL Server configuration
        $ADSyncRegPath = "HKLM:\SOFTWARE\Microsoft\Azure AD Connect"
        if (Test-Path $ADSyncRegPath) {
            $ADSyncReg = Get-ItemProperty -Path $ADSyncRegPath -ErrorAction SilentlyContinue
            $SqlServer = $ADSyncReg.SqlServer
            $SqlInstance = $ADSyncReg.SqlInstance
        }

        # Method 3: Check ADSync service command line for SQL info
        $ADSyncService = Get-CimInstance -ClassName Win32_Service -Filter "Name='ADSync'" -ErrorAction SilentlyContinue
        if ($ADSyncService.PathName -match "SQLServer=([^""]+)") {
            $SqlServer = $Matches[1]
        }

        if ($SqlServer) {
            "SQL Server: $SqlServer" | Out-File $ReportFile -Append
            if ($SqlInstance) {
                "SQL Instance: $SqlInstance" | Out-File $ReportFile -Append
            }

            # Determine if local or remote
            if ($SqlServer -eq $env:COMPUTERNAME -or $SqlServer -eq "localhost" -or $SqlServer -eq "." -or $SqlServer -eq "(local)") {
                $DatabaseType = "LocalSQL"
                "`nDatabase Type: Local SQL Server (full instance on this server)" | Out-File $ReportFile -Append
                "NOTE: Local full SQL Server provides better performance than LocalDB" | Out-File $ReportFile -Append
            } else {
                $DatabaseType = "RemoteSQL"
                "`nDatabase Type: Remote SQL Server" | Out-File $ReportFile -Append
                "NOTE: Remote SQL Server supports larger environments and high availability" | Out-File $ReportFile -Append
            }
        } else {
            # No SQL Server info found and no LocalDB - might still be LocalDB with different path
            "Database Type: Could not be determined" | Out-File $ReportFile -Append
            "NOTE: Default Entra Connect installation uses LocalDB" | Out-File $ReportFile -Append
        }
    }

} catch {
    "Error checking SQL configuration: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Export Deletion Threshold
Write-Section "EXPORT DELETION THRESHOLD"
Write-Host "Checking export deletion threshold..." -ForegroundColor Yellow

try {
    # Note: Get-ADSyncExportDeletionThreshold requires authentication prompt, so we avoid it
    # Instead, check GlobalSettings for deletion threshold parameters
    $GlobalSettings = Get-ADSyncGlobalSettings -ErrorAction SilentlyContinue

    if ($GlobalSettings) {
        $AllParams = $GlobalSettings.Parameters

        # Look for deletion threshold related parameters
        $ThresholdEnabled = $AllParams | Where-Object { $_.Name -match "DeletionThreshold.*Enabled|AccidentalDeletion.*Enabled" }
        $ThresholdCount = $AllParams | Where-Object { $_.Name -match "DeletionThreshold$|AccidentalDeletion(?!.*Enabled)" }

        if ($ThresholdEnabled) {
            "Accidental Deletion Prevention: $($ThresholdEnabled.Value)" | Out-File $ReportFile -Append
        }
        if ($ThresholdCount) {
            "Deletion Threshold: $($ThresholdCount.Value) objects" | Out-File $ReportFile -Append
        }

        if (-not $ThresholdEnabled -and -not $ThresholdCount) {
            # List all parameters containing relevant keywords for debugging
            $RelatedParams = $AllParams | Where-Object { $_.Name -match "Deletion|Threshold|Export" }
            if ($RelatedParams) {
                "Related configuration parameters found:" | Out-File $ReportFile -Append
                foreach ($Param in $RelatedParams) {
                    "  $($Param.Name): $($Param.Value)" | Out-File $ReportFile -Append
                }
            } else {
                "Deletion threshold configuration not found in GlobalSettings" | Out-File $ReportFile -Append
                "`nNOTE: Check deletion threshold status in the Entra Connect wizard" | Out-File $ReportFile -Append
                "Default is ENABLED with 500 object threshold" | Out-File $ReportFile -Append
            }
        }
    } else {
        "Unable to retrieve GlobalSettings" | Out-File $ReportFile -Append
    }

} catch {
    "Error checking deletion threshold: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Staging Mode Check
Write-Section "STAGING MODE STATUS"
Write-Host "Checking staging mode configuration..." -ForegroundColor Yellow

try {
    $GlobalSettings = Get-ADSyncGlobalSettings
    $StagingModeEnabled = ($GlobalSettings.Parameters | Where-Object { $_.Name -eq "Microsoft.Synchronize.StagingMode" }).Value

    "Staging Mode Enabled: $StagingModeEnabled" | Out-File $ReportFile -Append

    if ($StagingModeEnabled -eq "True") {
        "`nSTATUS: This server is in STAGING MODE" | Out-File $ReportFile -Append
        "IMPACT: This server does NOT export changes to Entra ID" | Out-File $ReportFile -Append
        "NOTE: Staging mode servers are typically standby servers for disaster recovery" | Out-File $ReportFile -Append
    } else {
        "`nSTATUS: This server is ACTIVE (not in staging mode)" | Out-File $ReportFile -Append
        "IMPACT: This server actively syncs and exports changes to Entra ID" | Out-File $ReportFile -Append
    }
} catch {
    "Error checking staging mode: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region AAD Company Features (PHS, PTA, SSO, Writeback)
Write-Section "ENTRA ID COMPANY FEATURES"
Write-Host "Retrieving Entra ID company features..." -ForegroundColor Yellow

try {
    $AADCompanyFeatures = Get-ADSyncAADCompanyFeature

    Write-SubSection "Authentication Features"
    "Password Hash Sync Enabled: $($AADCompanyFeatures.PasswordHashSync)" | Out-File $ReportFile -Append
    "Pass-Through Authentication Enabled: $($AADCompanyFeatures.PassThroughAuthentication)" | Out-File $ReportFile -Append
    "Seamless Single Sign-On Enabled: $($AADCompanyFeatures.SeamlessSingleSignOn)" | Out-File $ReportFile -Append

    Write-SubSection "Writeback Features"
    "Password Writeback Enabled: $($AADCompanyFeatures.PasswordWriteback)" | Out-File $ReportFile -Append
    "User Writeback Enabled: $($AADCompanyFeatures.UserWriteback)" | Out-File $ReportFile -Append
    "Device Writeback Enabled: $($AADCompanyFeatures.DeviceWriteback)" | Out-File $ReportFile -Append
    "Group Writeback Enabled: $($AADCompanyFeatures.UnifiedGroupWriteback)" | Out-File $ReportFile -Append

    Write-SubSection "Exchange Features"
    "Exchange Hybrid Writeback: $($AADCompanyFeatures.ExchangeHybridWriteback)" | Out-File $ReportFile -Append

    Write-SubSection "Other Features"
    "Directory Extension Attribute Sync: $($AADCompanyFeatures.DirSyncFeature)" | Out-File $ReportFile -Append

    # PHS-specific analysis
    "`n--- PHS Migration Analysis ---" | Out-File $ReportFile -Append

    if ($AADCompanyFeatures.PasswordHashSync -eq $true) {
        "STATUS: Password Hash Sync is ENABLED" | Out-File $ReportFile -Append
        "PHS is already active - verify passwords are syncing correctly per connector" | Out-File $ReportFile -Append
    } else {
        "STATUS: Password Hash Sync is DISABLED" | Out-File $ReportFile -Append
        "ACTION: Enable PHS in Entra Connect wizard before migration" | Out-File $ReportFile -Append
    }

    if ($AADCompanyFeatures.PassThroughAuthentication -eq $true) {
        "`nNOTE: Pass-Through Authentication is currently enabled" | Out-File $ReportFile -Append
        "This can be disabled after PHS migration is complete and verified" | Out-File $ReportFile -Append
    }

    if ($AADCompanyFeatures.PasswordWriteback -eq $true) {
        "`nNOTE: Password Writeback is enabled - required for SSPR in hybrid" | Out-File $ReportFile -Append
    } else {
        "`nWARNING: Password Writeback is NOT enabled" | Out-File $ReportFile -Append
        "Enable Password Writeback if you plan to use SSPR for synced users" | Out-File $ReportFile -Append
    }

} catch {
    "Error retrieving company features: $($_.Exception.Message)" | Out-File $ReportFile -Append
    "This may occur if not connected to Entra ID or permissions are insufficient." | Out-File $ReportFile -Append
}
#endregion

#region Sync Scheduler Configuration
Write-Section "SYNC SCHEDULER CONFIGURATION"
Write-Host "Collecting sync scheduler settings..." -ForegroundColor Yellow

try {
    $Scheduler = Get-ADSyncScheduler

    "Scheduler Enabled: $($Scheduler.SchedulerEnabled)" | Out-File $ReportFile -Append
    "Sync Cycle Enabled: $($Scheduler.SyncCycleEnabled)" | Out-File $ReportFile -Append
    "Sync Cycle Interval: $($Scheduler.CurrentlyEffectiveSyncCycleInterval)" | Out-File $ReportFile -Append
    "Maintenance Enabled: $($Scheduler.MaintenanceEnabled)" | Out-File $ReportFile -Append
    "Staging Mode Enabled: $($Scheduler.StagingModeEnabled)" | Out-File $ReportFile -Append
    "Next Sync Cycle Start: $($Scheduler.NextSyncCycleStartTimeInUTC) UTC" | Out-File $ReportFile -Append
    "Next Sync Policy Type: $($Scheduler.NextSyncCyclePolicyType)" | Out-File $ReportFile -Append
    "Last Sync Cycle: $($Scheduler.LastSyncCycleStartTimeInUTC) UTC" | Out-File $ReportFile -Append

    if ($Scheduler.SchedulerSuspended -eq $true) {
        "`nWARNING: Scheduler is currently SUSPENDED" | Out-File $ReportFile -Append
        "Reason: $($Scheduler.SchedulerSuspendReason)" | Out-File $ReportFile -Append
    }

} catch {
    "Error retrieving scheduler configuration: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Connector Configuration
Write-Section "CONNECTOR CONFIGURATION"
Write-Host "Collecting connector information..." -ForegroundColor Yellow

try {
    $Connectors = @(Get-ADSyncConnector)

    "Total Connectors: $($Connectors.Count)" | Out-File $ReportFile -Append

    foreach ($Connector in $Connectors) {
        Write-SubSection "Connector: $($Connector.Name)"

        "Connector Type: $($Connector.ConnectorTypeName)" | Out-File $ReportFile -Append
        "Connector ID: $($Connector.Identifier)" | Out-File $ReportFile -Append
        "Creation Time: $($Connector.CreationTime)" | Out-File $ReportFile -Append
        "Last Modification Time: $($Connector.LastModificationTime)" | Out-File $ReportFile -Append

        # Check for AD connector-specific settings
        if ($Connector.ConnectorTypeName -eq "AD") {
            # Try different methods to get Forest Name
            $ForestName = $null
            if ($Connector.ConnectivityParameters) {
                $ForestParam = $Connector.ConnectivityParameters | Where-Object { $_.Name -eq "forest-name" }
                if ($ForestParam) { $ForestName = $ForestParam.Value }
            }
            if (-not $ForestName -and $Connector.GlobalParameters) {
                $ForestParam = $Connector.GlobalParameters | Where-Object { $_.Name -eq "Connector.ForestName" }
                if ($ForestParam) { $ForestName = $ForestParam.Value }
            }
            # Use connector name as fallback (often matches forest name)
            if (-not $ForestName) { $ForestName = $Connector.Name }

            "Forest Name: $ForestName" | Out-File $ReportFile -Append

            # Get partition configuration
            $Partitions = @($Connector.Partitions)
            "Number of Partitions: $($Partitions.Count)" | Out-File $ReportFile -Append

            foreach ($Partition in $Partitions) {
                $PartitionDN = if ($Partition.DN) { $Partition.DN } elseif ($Partition.Name) { $Partition.Name } else { $Partition.Identifier }
                $PartitionSelected = if ($null -ne $Partition.Selected) { $Partition.Selected } else { "Unknown" }
                "  Partition DN: $PartitionDN" | Out-File $ReportFile -Append
                "  Partition Enabled: $PartitionSelected" | Out-File $ReportFile -Append
            }
        }

        # Check for Entra ID connector
        if ($Connector.ConnectorTypeName -eq "Extensible2") {
            # Try different methods to get Tenant Name
            $TenantName = $null
            if ($Connector.ConnectivityParameters) {
                $TenantParam = $Connector.ConnectivityParameters | Where-Object { $_.Name -match "domain|tenant" }
                if ($TenantParam) { $TenantName = $TenantParam.Value }
            }
            if (-not $TenantName -and $Connector.GlobalParameters) {
                $TenantParam = $Connector.GlobalParameters | Where-Object { $_.Name -match "DomainName|TenantName" }
                if ($TenantParam) { $TenantName = $TenantParam.Value }
            }
            # Extract from connector name if it contains .onmicrosoft.com
            if (-not $TenantName -and $Connector.Name -match "\.onmicrosoft\.com") {
                $TenantName = ($Connector.Name -split " - ")[0]
            }

            "Tenant Name: $TenantName" | Out-File $ReportFile -Append
        }
    }
} catch {
    "Error retrieving connector configuration: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Domain and OU Filtering
Write-Section "DOMAIN AND OU FILTERING"
Write-Host "Checking domain and OU filtering configuration..." -ForegroundColor Yellow

try {
    $ADConnectors = @(Get-ADSyncConnector | Where-Object { $_.ConnectorTypeName -eq "AD" })

    foreach ($Connector in $ADConnectors) {
        Write-SubSection "Connector: $($Connector.Name)"

        $Partitions = @($Connector.Partitions)

        if ($Partitions.Count -eq 0) {
            "No partitions configured for this connector" | Out-File $ReportFile -Append
            continue
        }

        foreach ($Partition in $Partitions) {
            # Get partition identifier - try multiple properties
            $PartitionDN = if ($Partition.DN) { $Partition.DN }
                          elseif ($Partition.Name) { $Partition.Name }
                          elseif ($Partition.Identifier) { $Partition.Identifier }
                          else { "Unknown" }

            # Check if partition is selected - handle null gracefully
            $IsSelected = $Partition.Selected
            if ($null -eq $IsSelected) {
                # If Selected property doesn't exist, assume it's selected (default behaviour)
                $IsSelected = $true
            }

            if ($IsSelected -eq $true) {
                "`nDomain: $PartitionDN" | Out-File $ReportFile -Append

                # Check for OU-level filtering
                $ContainerInclusionList = @()
                $ContainerExclusionList = @()

                if ($Partition.ConnectorPartitionScope) {
                    if ($Partition.ConnectorPartitionScope.ContainerInclusionList) {
                        $ContainerInclusionList = @($Partition.ConnectorPartitionScope.ContainerInclusionList)
                    }
                    if ($Partition.ConnectorPartitionScope.ContainerExclusionList) {
                        $ContainerExclusionList = @($Partition.ConnectorPartitionScope.ContainerExclusionList)
                    }
                }

                if ($ContainerInclusionList.Count -gt 0) {
                    "Filtering Type: INCLUSION list (only specified OUs are synced)" | Out-File $ReportFile -Append
                    "Included OUs: $($ContainerInclusionList.Count)" | Out-File $ReportFile -Append
                    foreach ($OU in $ContainerInclusionList) {
                        "  - $OU" | Out-File $ReportFile -Append
                    }
                } elseif ($ContainerExclusionList.Count -gt 0) {
                    "Filtering Type: EXCLUSION list (specified OUs are excluded)" | Out-File $ReportFile -Append
                    "Excluded OUs: $($ContainerExclusionList.Count)" | Out-File $ReportFile -Append
                    foreach ($OU in $ContainerExclusionList) {
                        "  - $OU" | Out-File $ReportFile -Append
                    }
                } else {
                    "Filtering Type: ALL OUs synced (no OU filtering configured)" | Out-File $ReportFile -Append
                }
            } else {
                "`nDomain: $PartitionDN - NOT SELECTED FOR SYNC" | Out-File $ReportFile -Append
            }
        }
    }

} catch {
    "Error checking OU filtering: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Password Sync Status Per Connector
Write-Section "PASSWORD SYNC STATUS PER CONNECTOR"
Write-Host "Checking password sync status per connector..." -ForegroundColor Yellow

try {
    $Connectors = @(Get-ADSyncConnector | Where-Object { $_.ConnectorTypeName -eq "AD" })

    foreach ($Connector in $Connectors) {
        Write-SubSection "Connector: $($Connector.Name)"

        try {
            $PasswordSyncConfig = Get-ADSyncAADPasswordSyncConfiguration -SourceConnector $Connector.Name

            "Password Sync Enabled: $($PasswordSyncConfig.Enabled)" | Out-File $ReportFile -Append

            if ($PasswordSyncConfig.Enabled -eq $true) {
                "STATUS: Password hashes ARE being synced from this connector" | Out-File $ReportFile -Append
            } else {
                "WARNING: Password hashes are NOT being synced from this connector" | Out-File $ReportFile -Append
                "ACTION: Enable password sync for this connector in Entra Connect wizard" | Out-File $ReportFile -Append
            }
        } catch {
            "Unable to retrieve password sync configuration for this connector" | Out-File $ReportFile -Append
            "Error: $($_.Exception.Message)" | Out-File $ReportFile -Append
        }

        # Get password sync state
        try {
            $PasswordSyncState = Get-ADSyncAADPasswordResetConfiguration -Connector $Connector.Name -ErrorAction SilentlyContinue
            if ($PasswordSyncState) {
                "Password Reset/Writeback Enabled: $($PasswordSyncState.Enabled)" | Out-File $ReportFile -Append
            }
        } catch {
            # Silently continue if this cmdlet doesn't exist or fails
        }
    }
} catch {
    "Error checking password sync status: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Password Hash Sync Heartbeat
Write-Section "PASSWORD HASH SYNC HEARTBEAT"
Write-Host "Checking PHS sync status and last sync time..." -ForegroundColor Yellow

try {
    $ADConnectors = @(Get-ADSyncConnector | Where-Object { $_.ConnectorTypeName -eq "AD" })

    foreach ($Connector in $ADConnectors) {
        Write-SubSection "Connector: $($Connector.Name)"

        # Method 1: Check run profile results for password sync operations
        try {
            $RunHistory = @(Get-ADSyncRunProfileResult -ConnectorId $Connector.Identifier -NumberRequested 20 -ErrorAction SilentlyContinue)

            # Look for password sync related runs
            $PasswordSyncRuns = @($RunHistory | Where-Object {
                $_.RunProfileName -match "Password" -or
                ($_.StepResults | Where-Object { $_.StepDescription -match "Password" })
            })

            if ($PasswordSyncRuns.Count -gt 0) {
                $LastPHSRun = $PasswordSyncRuns | Select-Object -First 1
                "Last PHS-related Run: $($LastPHSRun.StartDate)" | Out-File $ReportFile -Append
                "Run Profile: $($LastPHSRun.RunProfileName)" | Out-File $ReportFile -Append
                "Result: $($LastPHSRun.Result)" | Out-File $ReportFile -Append

                if ($LastPHSRun.StartDate) {
                    $TimeSinceRun = (Get-Date) - $LastPHSRun.StartDate
                    if ($TimeSinceRun.TotalHours -gt 2) {
                        "WARNING: Last PHS activity was more than 2 hours ago" | Out-File $ReportFile -Append
                    }
                }
            }
        } catch {
            # Silently continue to next method
        }

        # Method 2: Check Application Event Log for PHS events
        try {
            $PHSEvents = @(Get-WinEvent -FilterHashtable @{
                LogName = 'Application'
                ProviderName = 'Directory Synchronization'
                StartTime = (Get-Date).AddHours(-24)
            } -MaxEvents 10 -ErrorAction SilentlyContinue | Where-Object {
                $_.Message -match "password"
            })

            if ($PHSEvents.Count -gt 0) {
                $LastPHSEvent = $PHSEvents | Select-Object -First 1
                "Last PHS Event Log Entry: $($LastPHSEvent.TimeCreated)" | Out-File $ReportFile -Append
                "Event ID: $($LastPHSEvent.Id)" | Out-File $ReportFile -Append
            } else {
                "No PHS events found in last 24 hours (this may be normal)" | Out-File $ReportFile -Append
            }
        } catch {
            "Event log query not available or no PHS events found" | Out-File $ReportFile -Append
        }

        # Note about PHS monitoring
        "`nNOTE: For detailed PHS monitoring, check:" | Out-File $ReportFile -Append
        "  - Entra Connect Health portal (if Health Agent installed)" | Out-File $ReportFile -Append
        "  - Application Event Log for 'Directory Synchronization' events" | Out-File $ReportFile -Append
        "  - Synchronization Service Manager > Operations tab" | Out-File $ReportFile -Append
    }
} catch {
    "Error checking PHS heartbeat: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Connector Space Statistics
Write-Section "CONNECTOR SPACE STATISTICS"
Write-Host "Collecting connector space object counts..." -ForegroundColor Yellow

try {
    $Connectors = @(Get-ADSyncConnector)

    foreach ($Connector in $Connectors) {
        Write-SubSection "Connector: $($Connector.Name)"

        # Get statistics from the most recent run profile results
        try {
            $LastRun = Get-ADSyncRunProfileResult -ConnectorId $Connector.Identifier -NumberRequested 1 -ErrorAction SilentlyContinue

            if ($LastRun -and $LastRun.StepResults) {
                $StepStats = $LastRun.StepResults | Select-Object -First 1

                # Extract counts from step results if available
                if ($StepStats) {
                    "Last Run Profile: $($LastRun.RunProfileName)" | Out-File $ReportFile -Append
                    "Last Run Time: $($LastRun.StartDate)" | Out-File $ReportFile -Append

                    # Try to get object counts from the step
                    if ($null -ne $StepStats.StageAdd) {
                        "Objects Added (staged): $($StepStats.StageAdd)" | Out-File $ReportFile -Append
                    }
                    if ($null -ne $StepStats.StageUpdate) {
                        "Objects Updated (staged): $($StepStats.StageUpdate)" | Out-File $ReportFile -Append
                    }
                    if ($null -ne $StepStats.StageDelete) {
                        "Objects Deleted (staged): $($StepStats.StageDelete)" | Out-File $ReportFile -Append
                    }
                    if ($null -ne $StepStats.ExportAdd) {
                        "Objects Exported (adds): $($StepStats.ExportAdd)" | Out-File $ReportFile -Append
                    }
                    if ($null -ne $StepStats.ExportUpdate) {
                        "Objects Exported (updates): $($StepStats.ExportUpdate)" | Out-File $ReportFile -Append
                    }
                    if ($null -ne $StepStats.ExportDelete) {
                        "Objects Exported (deletes): $($StepStats.ExportDelete)" | Out-File $ReportFile -Append
                    }
                }
            } else {
                "No recent run profile data available" | Out-File $ReportFile -Append
            }
        } catch {
            "Unable to retrieve run profile statistics: $($_.Exception.Message)" | Out-File $ReportFile -Append
        }

        # Check for pending exports (errors)
        try {
            $ExportErrors = @(Get-ADSyncCSObject -ConnectorIdentifier $Connector.Identifier -ExportErrorsOnly -ErrorAction SilentlyContinue)
            if ($ExportErrors.Count -gt 0) {
                "Pending Export Errors: $($ExportErrors.Count)" | Out-File $ReportFile -Append
            } else {
                "Pending Export Errors: 0" | Out-File $ReportFile -Append
            }
        } catch {
            # Silently continue
        }
    }

    # Summary note
    Write-SubSection "Statistics Note"
    "For detailed object counts, use the Synchronization Service Manager" | Out-File $ReportFile -Append
    "or check the exported server configuration files" | Out-File $ReportFile -Append

} catch {
    "Error collecting connector statistics: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Sync Errors and Export Errors
Write-Section "SYNC ERRORS AND EXPORT ERRORS"
Write-Host "Collecting sync error information..." -ForegroundColor Yellow

try {
    # Get run history for error analysis
    $Connectors = @(Get-ADSyncConnector)

    foreach ($Connector in $Connectors) {
        Write-SubSection "Connector: $($Connector.Name)"

        try {
            # Get the most recent run profile results
            $RunHistory = @(Get-ADSyncRunProfileResult -ConnectorId $Connector.Identifier -NumberRequested 5)

            if ($RunHistory.Count -gt 0) {
                $TotalErrors = 0
                $ExportErrors = 0
                $ImportErrors = 0
                $SyncErrors = 0

                foreach ($Run in $RunHistory) {
                    foreach ($Step in $Run.StepResults) {
                        $TotalErrors += $Step.ConnectorConnectionInformationXml_count

                        # Check step type and count errors accordingly
                        if ($Step.StepResult -ne "success") {
                            switch -Wildcard ($Step.StepDescription) {
                                "*Export*" { $ExportErrors += 1 }
                                "*Import*" { $ImportErrors += 1 }
                                "*Sync*" { $SyncErrors += 1 }
                            }
                        }
                    }
                }

                "Last 5 Run Profiles Analysed" | Out-File $ReportFile -Append
                "Export Errors: $ExportErrors" | Out-File $ReportFile -Append
                "Import Errors: $ImportErrors" | Out-File $ReportFile -Append
                "Sync Errors: $SyncErrors" | Out-File $ReportFile -Append

                # Get last run status
                $LastRun = $RunHistory | Select-Object -First 1
                "Last Run Time: $($LastRun.StartDate)" | Out-File $ReportFile -Append
                "Last Run Result: $($LastRun.Result)" | Out-File $ReportFile -Append

            } else {
                "No run history available for this connector." | Out-File $ReportFile -Append
            }
        } catch {
            "Unable to retrieve run history: $($_.Exception.Message)" | Out-File $ReportFile -Append
        }
    }

    # Get connector space export errors
    Write-SubSection "Export Error Details"

    foreach ($Connector in $Connectors) {
        try {
            $CSExportErrors = @(Get-ADSyncCSObject -ConnectorIdentifier $Connector.Identifier -ExportErrorsOnly -ErrorAction SilentlyContinue)

            if ($CSExportErrors.Count -gt 0) {
                "Connector '$($Connector.Name)' has $($CSExportErrors.Count) pending export errors" | Out-File $ReportFile -Append

                # Group by error type for summary
                $ErrorGroups = $CSExportErrors | Group-Object -Property ExportErrorType
                foreach ($ErrorGroup in $ErrorGroups) {
                    "  - $($ErrorGroup.Name): $($ErrorGroup.Count) errors" | Out-File $ReportFile -Append
                }
            } else {
                "Connector '$($Connector.Name)': No pending export errors" | Out-File $ReportFile -Append
            }
        } catch {
            "Unable to check export errors for '$($Connector.Name)'" | Out-File $ReportFile -Append
        }
    }

} catch {
    "Error collecting sync error information: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Custom Sync Rules Affecting Passwords
Write-Section "CUSTOM SYNC RULES AFFECTING PASSWORDS"
Write-Host "Analysing custom sync rules..." -ForegroundColor Yellow

try {
    $AllRules = @(Get-ADSyncRule)

    "Total Sync Rules: $($AllRules.Count)" | Out-File $ReportFile -Append

    # Separate custom vs default rules
    $CustomRules = @($AllRules | Where-Object { $_.ImmutableTag -eq $null -or $_.ImmutableTag -eq "" })
    $DefaultRules = @($AllRules | Where-Object { $_.ImmutableTag -ne $null -and $_.ImmutableTag -ne "" })

    "Default (Microsoft) Rules: $($DefaultRules.Count)" | Out-File $ReportFile -Append
    "Custom Rules: $($CustomRules.Count)" | Out-File $ReportFile -Append

    # Check for rules that may affect password sync
    Write-SubSection "Rules Potentially Affecting Password Sync"

    $PasswordRelatedRules = @($AllRules | Where-Object {
        $_.AttributeFlowMappings | Where-Object {
            $_.Destination -match "password|pwdLastSet|userPassword|unicodePwd" -or
            $_.Source -match "password|pwdLastSet|userPassword|unicodePwd"
        }
    })

    if ($PasswordRelatedRules.Count -gt 0) {
        foreach ($Rule in $PasswordRelatedRules) {
            "Rule Name: $($Rule.Name)" | Out-File $ReportFile -Append
            "  Direction: $($Rule.Direction)" | Out-File $ReportFile -Append
            "  Precedence: $($Rule.Precedence)" | Out-File $ReportFile -Append
            "  Is Custom: $(if ($Rule.ImmutableTag) { 'No (Default)' } else { 'Yes (Custom)' })" | Out-File $ReportFile -Append
            "  Enabled: $($Rule.Disabled -eq $false)" | Out-File $ReportFile -Append
        }
    } else {
        "No custom rules found that directly affect password attributes." | Out-File $ReportFile -Append
    }

    # Check for rules that filter users (could exclude from password sync)
    Write-SubSection "Custom Rules with Scoping Filters"

    $ScopingRules = @($CustomRules | Where-Object { $_.ScopeFilter })

    if ($ScopingRules.Count -gt 0) {
        "Found $($ScopingRules.Count) custom rules with scoping filters" | Out-File $ReportFile -Append
        "WARNING: Scoping filters may exclude users from password sync" | Out-File $ReportFile -Append

        foreach ($Rule in $ScopingRules) {
            "  - $($Rule.Name) (Precedence: $($Rule.Precedence))" | Out-File $ReportFile -Append
        }
    } else {
        "No custom rules with scoping filters found." | Out-File $ReportFile -Append
    }

    # Check for disabled default rules
    Write-SubSection "Disabled Default Rules"

    $DisabledDefaultRules = @($DefaultRules | Where-Object { $_.Disabled -eq $true })

    if ($DisabledDefaultRules.Count -gt 0) {
        "Found $($DisabledDefaultRules.Count) disabled default rules" | Out-File $ReportFile -Append
        "WARNING: Disabled default rules may affect expected sync behaviour" | Out-File $ReportFile -Append

        foreach ($Rule in $DisabledDefaultRules) {
            "  - $($Rule.Name)" | Out-File $ReportFile -Append
        }
    } else {
        "No disabled default rules found." | Out-File $ReportFile -Append
    }

} catch {
    "Error analysing sync rules: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region FIPS Compliance Check
Write-Section "FIPS COMPLIANCE CHECK"
Write-Host "Checking FIPS compliance settings..." -ForegroundColor Yellow

try {
    # Check FIPS policy in registry
    $FIPSPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy"

    if (Test-Path $FIPSPath) {
        $FIPSPolicy = Get-ItemProperty -Path $FIPSPath
        $FIPSEnabled = $FIPSPolicy.Enabled

        "FIPS Algorithm Policy Enabled: $FIPSEnabled" | Out-File $ReportFile -Append

        if ($FIPSEnabled -eq 1) {
            "`nWARNING: FIPS mode is ENABLED" | Out-File $ReportFile -Append
            "IMPACT: Password Hash Sync requires MD5 which is not FIPS-compliant" | Out-File $ReportFile -Append
            "ACTION: PHS will NOT work with FIPS mode enabled" | Out-File $ReportFile -Append
            "RESOLUTION: Disable FIPS mode or use Pass-Through Authentication instead" | Out-File $ReportFile -Append
        } else {
            "STATUS: FIPS mode is disabled - compatible with PHS" | Out-File $ReportFile -Append
        }
    } else {
        "FIPS policy registry key not found - FIPS is likely disabled (default)" | Out-File $ReportFile -Append
        "STATUS: Compatible with PHS" | Out-File $ReportFile -Append
    }

    # Also check via .NET
    $FIPSEnforced = [System.Security.Cryptography.CryptoConfig]::AllowOnlyFipsAlgorithms
    "`n.NET FIPS Enforcement: $FIPSEnforced" | Out-File $ReportFile -Append

} catch {
    "Error checking FIPS compliance: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region TLS 1.2 Configuration
Write-Section "TLS 1.2 CONFIGURATION"
Write-Host "Checking TLS 1.2 configuration..." -ForegroundColor Yellow

try {
    $TLSIssues = @()

    # Check TLS 1.2 Client settings
    $TLS12ClientPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Client"

    Write-SubSection "TLS 1.2 Client Configuration"

    if (Test-Path $TLS12ClientPath) {
        $TLS12Client = Get-ItemProperty -Path $TLS12ClientPath -ErrorAction SilentlyContinue

        $ClientEnabled = $TLS12Client.Enabled
        $ClientDisabledByDefault = $TLS12Client.DisabledByDefault

        "TLS 1.2 Client Enabled: $(if ($ClientEnabled -eq 1) { 'Yes' } elseif ($ClientEnabled -eq 0) { 'No' } else { 'Not Set (Default)' })" | Out-File $ReportFile -Append
        "TLS 1.2 Client DisabledByDefault: $(if ($ClientDisabledByDefault -eq 1) { 'Yes (BAD)' } elseif ($ClientDisabledByDefault -eq 0) { 'No (Good)' } else { 'Not Set' })" | Out-File $ReportFile -Append

        if ($ClientEnabled -eq 0 -or $ClientDisabledByDefault -eq 1) {
            $TLSIssues += "TLS 1.2 Client is not properly enabled"
        }
    } else {
        "TLS 1.2 Client registry key not found - using system defaults" | Out-File $ReportFile -Append
    }

    # Check TLS 1.2 Server settings
    $TLS12ServerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2\Server"

    Write-SubSection "TLS 1.2 Server Configuration"

    if (Test-Path $TLS12ServerPath) {
        $TLS12Server = Get-ItemProperty -Path $TLS12ServerPath -ErrorAction SilentlyContinue

        $ServerEnabled = $TLS12Server.Enabled
        $ServerDisabledByDefault = $TLS12Server.DisabledByDefault

        "TLS 1.2 Server Enabled: $(if ($ServerEnabled -eq 1) { 'Yes' } elseif ($ServerEnabled -eq 0) { 'No' } else { 'Not Set (Default)' })" | Out-File $ReportFile -Append
        "TLS 1.2 Server DisabledByDefault: $(if ($ServerDisabledByDefault -eq 1) { 'Yes (BAD)' } elseif ($ServerDisabledByDefault -eq 0) { 'No (Good)' } else { 'Not Set' })" | Out-File $ReportFile -Append

        if ($ServerEnabled -eq 0 -or $ServerDisabledByDefault -eq 1) {
            $TLSIssues += "TLS 1.2 Server is not properly enabled"
        }
    } else {
        "TLS 1.2 Server registry key not found - using system defaults" | Out-File $ReportFile -Append
    }

    # Check .NET Framework TLS settings
    Write-SubSection ".NET Framework TLS Configuration"

    $DotNet4Path = "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319"
    $DotNet4WowPath = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\.NETFramework\v4.0.30319"

    if (Test-Path $DotNet4Path) {
        $DotNet4 = Get-ItemProperty -Path $DotNet4Path -ErrorAction SilentlyContinue
        "SchUseStrongCrypto (64-bit): $(if ($DotNet4.SchUseStrongCrypto -eq 1) { 'Enabled (Good)' } else { 'Not Set or Disabled' })" | Out-File $ReportFile -Append
        "SystemDefaultTlsVersions (64-bit): $(if ($DotNet4.SystemDefaultTlsVersions -eq 1) { 'Enabled (Good)' } else { 'Not Set or Disabled' })" | Out-File $ReportFile -Append

        if ($DotNet4.SchUseStrongCrypto -ne 1) {
            $TLSIssues += ".NET 64-bit SchUseStrongCrypto not enabled"
        }
    }

    if (Test-Path $DotNet4WowPath) {
        $DotNet4Wow = Get-ItemProperty -Path $DotNet4WowPath -ErrorAction SilentlyContinue
        "SchUseStrongCrypto (32-bit): $(if ($DotNet4Wow.SchUseStrongCrypto -eq 1) { 'Enabled (Good)' } else { 'Not Set or Disabled' })" | Out-File $ReportFile -Append
        "SystemDefaultTlsVersions (32-bit): $(if ($DotNet4Wow.SystemDefaultTlsVersions -eq 1) { 'Enabled (Good)' } else { 'Not Set or Disabled' })" | Out-File $ReportFile -Append

        if ($DotNet4Wow.SchUseStrongCrypto -ne 1) {
            $TLSIssues += ".NET 32-bit SchUseStrongCrypto not enabled"
        }
    }

    # Summary
    Write-SubSection "TLS Configuration Summary"

    if ($TLSIssues.Count -eq 0) {
        "STATUS: TLS 1.2 appears to be properly configured" | Out-File $ReportFile -Append
    } else {
        "WARNING: TLS configuration issues detected" | Out-File $ReportFile -Append
        foreach ($Issue in $TLSIssues) {
            "  - $Issue" | Out-File $ReportFile -Append
        }
        "`nACTION: Configure TLS 1.2 as required for Entra Connect" | Out-File $ReportFile -Append
        "See: https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/reference-connect-tls-enforcement" | Out-File $ReportFile -Append
    }

} catch {
    "Error checking TLS configuration: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Entra Connect Health Agent
Write-Section "ENTRA CONNECT HEALTH AGENT"
Write-Host "Checking Entra Connect Health agent status..." -ForegroundColor Yellow

try {
    # Check for Health Agent services - try multiple known service names
    $HealthServiceNames = @(
        "AzureADConnectHealthSyncInsights",
        "AzureADConnectHealthSyncMonitor",
        "Azure AD Connect Health Sync Insights",
        "Azure AD Connect Health Sync Monitor",
        "Microsoft Entra Connect Health Sync"
    )

    $HealthService = $null
    foreach ($ServiceName in $HealthServiceNames) {
        $HealthService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($HealthService) { break }
    }

    # Also try wildcard search for health-related services
    if (-not $HealthService) {
        $HealthService = Get-Service | Where-Object {
            $_.Name -match "Health" -and ($_.Name -match "Azure|Entra|AAD|Connect")
        } | Select-Object -First 1
    }

    if ($HealthService) {
        "Health Agent Service: Found" | Out-File $ReportFile -Append
        "Service Name: $($HealthService.Name)" | Out-File $ReportFile -Append
        "Display Name: $($HealthService.DisplayName)" | Out-File $ReportFile -Append
        "Status: $($HealthService.Status)" | Out-File $ReportFile -Append
        "Start Type: $($HealthService.StartType)" | Out-File $ReportFile -Append

        if ($HealthService.Status -ne "Running") {
            "`nWARNING: Health agent service is NOT running" | Out-File $ReportFile -Append
            "Cloud-based monitoring may not be functioning" | Out-File $ReportFile -Append
        } else {
            "`nSTATUS: Health agent is running - cloud monitoring active" | Out-File $ReportFile -Append
        }
    } else {
        # Check if Health Agent is installed via product list (may be installed but service not registered)
        $HealthProduct = Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE '%Health Agent%'" -ErrorAction SilentlyContinue

        if ($HealthProduct) {
            "Health Agent Product: INSTALLED" | Out-File $ReportFile -Append
            "Product Name: $($HealthProduct.Name)" | Out-File $ReportFile -Append
            "Product Version: $($HealthProduct.Version)" | Out-File $ReportFile -Append
            "`nNOTE: Health Agent is installed but service was not detected" | Out-File $ReportFile -Append
            "The agent may be configured differently or service may have a different name" | Out-File $ReportFile -Append
        } else {
            "Health Agent: NOT INSTALLED" | Out-File $ReportFile -Append
            "`nNOTE: Entra Connect Health agent does not appear to be installed" | Out-File $ReportFile -Append
            "Consider installing for cloud-based monitoring and alerts" | Out-File $ReportFile -Append
            "See: https://learn.microsoft.com/en-us/entra/identity/hybrid/connect/how-to-connect-health-agent-install" | Out-File $ReportFile -Append
        }
    }

    # Check for Health Agent installation in registry
    $HealthAgentPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Azure AD Connect Health Sync Agent",
        "HKLM:\SOFTWARE\Microsoft\Microsoft Entra Connect Health Sync Agent"
    )

    foreach ($HealthAgentPath in $HealthAgentPaths) {
        if (Test-Path $HealthAgentPath) {
            $HealthAgentReg = Get-ItemProperty -Path $HealthAgentPath -ErrorAction SilentlyContinue
            if ($HealthAgentReg.Version) {
                "Health Agent Version (registry): $($HealthAgentReg.Version)" | Out-File $ReportFile -Append
            }
            break
        }
    }

} catch {
    "Error checking Health agent: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Full Configuration Export
Write-Section "FULL CONFIGURATION EXPORT"
Write-Host "Exporting full Entra Connect server configuration..." -ForegroundColor Yellow

try {
    $ConfigExportPath = Join-Path $OutputPath "ServerConfig_$Timestamp"

    Get-ADSyncServerConfiguration -Path $ConfigExportPath

    "Full configuration exported to: $ConfigExportPath" | Out-File $ReportFile -Append
    "`nThis export can be used with Microsoft's AADConnectConfigDocumenter tool" | Out-File $ReportFile -Append
    "Download from: https://github.com/microsoft/AADConnectConfigDocumenter" | Out-File $ReportFile -Append

    # List what was exported
    $ExportedItems = @(Get-ChildItem -Path $ConfigExportPath -Recurse -File -ErrorAction SilentlyContinue)
    "Exported files: $($ExportedItems.Count)" | Out-File $ReportFile -Append

    # List the folders created
    $ExportedFolders = @(Get-ChildItem -Path $ConfigExportPath -Directory -ErrorAction SilentlyContinue)
    if ($ExportedFolders.Count -gt 0) {
        "`nExported folders:" | Out-File $ReportFile -Append
        foreach ($Folder in $ExportedFolders) {
            "  - $($Folder.Name)" | Out-File $ReportFile -Append
        }
    }

} catch {
    "Error exporting server configuration: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Critical Findings Summary
Write-Section "CRITICAL FINDINGS SUMMARY"

$CriticalFindings = @()
$Warnings = @()
$Info = @()

# Staging mode check
try {
    $GlobalSettings = Get-ADSyncGlobalSettings
    $StagingModeEnabled = ($GlobalSettings.Parameters | Where-Object { $_.Name -eq "Microsoft.Synchronize.StagingMode" }).Value
    if ($StagingModeEnabled -eq "True") {
        $Info += "Server is in STAGING MODE - not actively syncing"
    }
} catch {}

# PHS check
try {
    $AADCompanyFeatures = Get-ADSyncAADCompanyFeature
    if ($AADCompanyFeatures.PasswordHashSync -ne $true) {
        $CriticalFindings += "Password Hash Sync is NOT ENABLED"
    }
    if ($AADCompanyFeatures.PasswordWriteback -ne $true) {
        $Warnings += "Password Writeback is NOT ENABLED (required for SSPR)"
    }
} catch {}

# FIPS check
try {
    $FIPSPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy"
    if (Test-Path $FIPSPath) {
        $FIPSPolicy = Get-ItemProperty -Path $FIPSPath
        if ($FIPSPolicy.Enabled -eq 1) {
            $CriticalFindings += "FIPS mode is ENABLED - incompatible with PHS"
        }
    }
} catch {}

# TLS check
try {
    $DotNet4Path = "HKLM:\SOFTWARE\Microsoft\.NETFramework\v4.0.30319"
    if (Test-Path $DotNet4Path) {
        $DotNet4 = Get-ItemProperty -Path $DotNet4Path -ErrorAction SilentlyContinue
        if ($DotNet4.SchUseStrongCrypto -ne 1) {
            $Warnings += "TLS 1.2 .NET strong crypto not explicitly enabled"
        }
    }
} catch {}

# Scheduler check
try {
    $Scheduler = Get-ADSyncScheduler
    if ($Scheduler.SchedulerSuspended -eq $true) {
        $Warnings += "Sync scheduler is currently SUSPENDED"
    }
} catch {}

# Deletion threshold check - removed as Get-ADSyncExportDeletionThreshold requires credentials prompt
# Check is performed in the main Export Deletion Threshold section using GlobalSettings

# Auto-upgrade check
try {
    $AutoUpgradeState = Get-ADSyncAutoUpgrade -ErrorAction SilentlyContinue
    if ($AutoUpgradeState -eq "Suspended") {
        $Warnings += "Auto-upgrade is SUSPENDED"
    } elseif ($AutoUpgradeState -eq "Disabled") {
        $Info += "Auto-upgrade is DISABLED - manual upgrades required"
    }
} catch {}

# ADSync service check
try {
    $ADSyncService = Get-Service -Name "ADSync" -ErrorAction SilentlyContinue
    if ($ADSyncService -and $ADSyncService.Status -ne "Running") {
        $CriticalFindings += "ADSync service is NOT running"
    }
} catch {}

# Health agent check
try {
    $HealthServiceNames = @("AzureADConnectHealthSyncInsights", "AzureADConnectHealthSyncMonitor")
    $HealthService = $null
    foreach ($ServiceName in $HealthServiceNames) {
        $HealthService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($HealthService) { break }
    }
    if (-not $HealthService) {
        # Check via wildcard
        $HealthService = Get-Service | Where-Object {
            $_.Name -match "Health" -and ($_.Name -match "Azure|Entra|AAD|Connect")
        } | Select-Object -First 1
    }

    if (-not $HealthService) {
        # Check if installed but service not found
        $HealthProduct = Get-CimInstance -ClassName Win32_Product -Filter "Name LIKE '%Health Agent%'" -ErrorAction SilentlyContinue
        if (-not $HealthProduct) {
            $Info += "Entra Connect Health agent is not installed"
        }
    } elseif ($HealthService.Status -ne "Running") {
        $Warnings += "Entra Connect Health agent is not running"
    }
} catch {}

# Output findings
if ($CriticalFindings.Count -gt 0) {
    "`n[CRITICAL - Must resolve before PHS migration]" | Out-File $ReportFile -Append
    $Priority = 1
    foreach ($Finding in $CriticalFindings) {
        "  $Priority. $Finding" | Out-File $ReportFile -Append
        $Priority++
    }
}

if ($Warnings.Count -gt 0) {
    "`n[WARNING - Review before PHS migration]" | Out-File $ReportFile -Append
    foreach ($Warning in $Warnings) {
        "  - $Warning" | Out-File $ReportFile -Append
    }
}

if ($Info.Count -gt 0) {
    "`n[INFO]" | Out-File $ReportFile -Append
    foreach ($Item in $Info) {
        "  - $Item" | Out-File $ReportFile -Append
    }
}

if ($CriticalFindings.Count -eq 0 -and $Warnings.Count -eq 0) {
    "No critical findings or warnings identified." | Out-File $ReportFile -Append
    "Entra Connect configuration appears ready for PHS migration." | Out-File $ReportFile -Append
}
#endregion

#region Script Completion
Write-Host "`nAssessment complete. Report saved to: $ReportFile" -ForegroundColor Green
Write-Host "This report contains NO personally identifiable information (PII)." -ForegroundColor Cyan
Write-Host "Only configuration settings and aggregate statistics have been collected." -ForegroundColor Cyan
#endregion
