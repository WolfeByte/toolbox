<#
.SYNOPSIS
    Collects Microsoft Entra password and authentication configuration for PHS migration assessment.
    PII-FREE VERSION - No user-identifiable information is collected.

.DESCRIPTION
    This script gathers Entra ID configuration including password policies, sync settings,
    password protection policies (Smart Lockout, Banned Passwords), authentication methods,
    Staged Rollout configuration, SSPR settings, Identity Protection policies, Conditional
    Access summary, and PTA agent inventory to assess current state for PHS migration.
    All user-identifying information is excluded.

.PARAMETER OutputPath
    The folder where the assessment report will be saved.
    If not specified, you will be prompted to enter a path.
    Default suggestion: C:\Temp\PHSAssessment

.EXAMPLE
    .\Get-EntraPHSReadiness.ps1
    Runs the script and prompts for the output folder location.

.EXAMPLE
    .\Get-EntraPHSReadiness.ps1 -OutputPath "C:\Temp\PHSAssessment"
    Runs the script and saves the report to the specified folder.

.NOTES
    Author: Benjamin Wolfe
    Requires: Microsoft.Graph.Beta modules and Global Reader permissions minimum
    Run this script on a machine with internet connectivity.

    DATA COLLECTED: Policy settings, domain configuration, aggregate statistics only
    DATA EXCLUDED: Names, usernames, email addresses, or any PII

    IMPORTANT: Uses Microsoft.Graph.Beta modules to access properties not available in v1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

#Requires -Modules Microsoft.Graph.Beta.Identity.DirectoryManagement, Microsoft.Graph.Beta.Users

#region Script Configuration
# Prompt for output path if not provided
if (-not $OutputPath) {
    $DefaultPath = "C:\Temp\PHSAssessment"
    $OutputPath = Read-Host "Enter output folder path (press Enter for default: $DefaultPath)"
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = $DefaultPath
    }
}

if (-not (Test-Path $OutputPath)) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    Write-Host "Created output folder: $OutputPath" -ForegroundColor Green
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ReportFile = Join-Path $OutputPath "Entra_Assessment_$Timestamp.txt"

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
"PHS MIGRATION ASSESSMENT - ENTRA ID CONFIGURATION" | Out-File $ReportFile
"Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $ReportFile -Append
"Script Version: 2.0" | Out-File $ReportFile -Append
#endregion

#region Graph Connection
Write-Host "Connecting to Microsoft Graph (Beta endpoints)..." -ForegroundColor Cyan

# Define required scopes
$RequiredScopes = @(
    "Organization.Read.All",
    "User.Read.All",
    "Domain.Read.All",
    "Policy.Read.All",
    "Directory.Read.All",
    "IdentityRiskyUser.Read.All",
    "IdentityRiskEvent.Read.All",
    "Device.Read.All",
    "Application.Read.All"
)

Connect-MgGraph -Scopes $RequiredScopes -NoWelcome
#endregion

Write-Host "Starting Entra ID configuration assessment..." -ForegroundColor Cyan
Write-Host "This process may take several minutes depending on tenant size..." -ForegroundColor Yellow

#region Organisation Information
Write-Section "ORGANISATION INFORMATION"
Write-Host "Collecting organisation information..." -ForegroundColor Yellow

$Org = Get-MgBetaOrganization
"Tenant ID: $($Org.Id)" | Out-File $ReportFile -Append
"Display Name: $($Org.DisplayName)" | Out-File $ReportFile -Append
$VerifiedDomains = $Org.VerifiedDomains | Where-Object {$_.IsVerified -eq $true}
"Number of Verified Domains: $($VerifiedDomains.Count)" | Out-File $ReportFile -Append

# Find primary domain
$PrimaryDomain = $VerifiedDomains | Where-Object {$_.IsInitial -eq $true}
if ($PrimaryDomain) {
    "Primary (Initial) Domain: $($PrimaryDomain.Name)" | Out-File $ReportFile -Append
}
#endregion

#region License Availability (P1/P2)
Write-Section "ENTRA ID LICENSE AVAILABILITY"
Write-Host "Checking Entra ID license availability..." -ForegroundColor Yellow

try {
    $SubscribedSkus = Get-MgBetaSubscribedSku -All

    # Define P1 and P2 SKU part numbers
    $P1Skus = @("AAD_PREMIUM", "EMSPREMIUM", "ENTERPRISEPACK", "ENTERPRISEPREMIUM", "ENTERPRISEPREMIUM_NOPSTNCONF", "SPE_E3", "SPE_E5", "SPE_F1", "IDENTITY_THREAT_PROTECTION")
    $P2Skus = @("AAD_PREMIUM_P2", "EMSPREMIUM_E5", "IDENTITY_THREAT_PROTECTION", "SPE_E5")

    $HasP1 = $false
    $HasP2 = $false
    $P1LicenseCount = 0
    $P2LicenseCount = 0

    foreach ($Sku in $SubscribedSkus) {
        if ($Sku.ServicePlans | Where-Object { $_.ServicePlanName -match "AAD_PREMIUM" -and $_.ProvisioningStatus -eq "Success" }) {
            $HasP1 = $true
            $P1LicenseCount += ($Sku.PrepaidUnits.Enabled - $Sku.ConsumedUnits)
        }
        if ($Sku.ServicePlans | Where-Object { $_.ServicePlanName -match "AAD_PREMIUM_P2" -and $_.ProvisioningStatus -eq "Success" }) {
            $HasP2 = $true
            $P2LicenseCount += ($Sku.PrepaidUnits.Enabled - $Sku.ConsumedUnits)
        }
    }

    "Entra ID P1 Available: $HasP1" | Out-File $ReportFile -Append
    "Entra ID P2 Available: $HasP2" | Out-File $ReportFile -Append

    Write-SubSection "License Impact on PHS Features"

    if ($HasP2) {
        "STATUS: P2 licenses available - All PHS features supported" | Out-File $ReportFile -Append
        "  - Identity Protection (leaked credentials detection) AVAILABLE" | Out-File $ReportFile -Append
        "  - Risk-based Conditional Access AVAILABLE" | Out-File $ReportFile -Append
        "  - Custom Smart Lockout settings AVAILABLE" | Out-File $ReportFile -Append
    } elseif ($HasP1) {
        "STATUS: P1 licenses available - Most PHS features supported" | Out-File $ReportFile -Append
        "  - Custom Smart Lockout settings AVAILABLE" | Out-File $ReportFile -Append
        "  - Custom Banned Password List AVAILABLE" | Out-File $ReportFile -Append
        "  - Identity Protection (leaked credentials) NOT AVAILABLE" | Out-File $ReportFile -Append
        "`nRECOMMENDATION: Consider P2 licensing for Identity Protection benefits with PHS" | Out-File $ReportFile -Append
    } else {
        "STATUS: No P1/P2 licenses detected" | Out-File $ReportFile -Append
        "  - Using default Smart Lockout settings" | Out-File $ReportFile -Append
        "  - Custom Banned Password List NOT AVAILABLE" | Out-File $ReportFile -Append
        "  - Identity Protection NOT AVAILABLE" | Out-File $ReportFile -Append
        "`nRECOMMENDATION: P1 or P2 licensing recommended for optimal PHS security" | Out-File $ReportFile -Append
    }

} catch {
    "Error checking license availability: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region On-Premises Sync Configuration
Write-Section "ON-PREMISES SYNCHRONISATION CONFIGURATION"
Write-Host "Collecting sync configuration..." -ForegroundColor Yellow

$OnPremSync = Get-MgBetaDirectoryOnPremiseSynchronization

if ($OnPremSync) {
    "Sync Configuration Found: Yes" | Out-File $ReportFile -Append
    "Sync Configuration ID: $($OnPremSync.Id)" | Out-File $ReportFile -Append

    # CloudPasswordPolicyForPasswordSyncedUsersEnabled
    $CloudPwdPolicy = $OnPremSync.Features.CloudPasswordPolicyForPasswordSyncedUsersEnabled
    "`nCloudPasswordPolicyForPasswordSyncedUsersEnabled: $CloudPwdPolicy" | Out-File $ReportFile -Append

    if ($CloudPwdPolicy -eq $false) {
        "  STATUS: Disabled (Default - passwords set to never expire in cloud)" | Out-File $ReportFile -Append
        "  IMPACT: Synced users can sign in with expired on-premises passwords" | Out-File $ReportFile -Append
        "  RECOMMENDATION: Enable this feature before migrating to PHS" | Out-File $ReportFile -Append
    } else {
        "  STATUS: Enabled (Cloud password policies enforced for synced users)" | Out-File $ReportFile -Append
    }

    # UserForcePasswordChangeOnLogonEnabled
    $ForceChange = $OnPremSync.Features.UserForcePasswordChangeOnLogonEnabled
    "`nUserForcePasswordChangeOnLogonEnabled: $ForceChange" | Out-File $ReportFile -Append

    if ($ForceChange -eq $false) {
        "  STATUS: Disabled (Temporary passwords not synced)" | Out-File $ReportFile -Append
        "  IMPACT: 'User must change password at next logon' flag not enforced in Entra" | Out-File $ReportFile -Append
        "  RECOMMENDATION: Enable if using temporary passwords or admin password resets" | Out-File $ReportFile -Append
    } else {
        "  STATUS: Enabled (Temporary password flags synced to Entra)" | Out-File $ReportFile -Append
    }

    # Other sync features
    "`nAll Sync Features:" | Out-File $ReportFile -Append
    $OnPremSync.Features | Format-List | Out-File $ReportFile -Append

} else {
    "No on-premises sync configuration found." | Out-File $ReportFile -Append
}
#endregion

#region Domain Configuration and Federation Details
Write-Section "ENTRA DOMAIN CONFIGURATION"
Write-Host "Collecting domain configuration..." -ForegroundColor Yellow

$Domains = Get-MgBetaDomain
$FederatedDomains = @()
$ManagedDomains = @()

foreach ($Domain in $Domains) {
    "`n--- Domain: $($Domain.Id) ---" | Out-File $ReportFile -Append
    "Authentication Type: $($Domain.AuthenticationType)" | Out-File $ReportFile -Append
    "Is Default: $($Domain.IsDefault)" | Out-File $ReportFile -Append
    "Is Verified: $($Domain.IsVerified)" | Out-File $ReportFile -Append
    "Is Admin Managed: $($Domain.IsAdminManaged)" | Out-File $ReportFile -Append

    if ($Domain.AuthenticationType -eq "Federated") {
        $FederatedDomains += $Domain

        # Get federation configuration details
        Write-SubSection "Federation Configuration for $($Domain.Id)"

        try {
            $FederationConfig = Get-MgBetaDomainFederationConfiguration -DomainId $Domain.Id -ErrorAction SilentlyContinue

            if ($FederationConfig) {
                "Federation Brand Name: $($FederationConfig.DisplayName)" | Out-File $ReportFile -Append
                "Issuer URI: $($FederationConfig.IssuerUri)" | Out-File $ReportFile -Append
                "Passive Sign-In URI: $($FederationConfig.PassiveSignInUri)" | Out-File $ReportFile -Append
                "Active Sign-In URI: $($FederationConfig.ActiveSignInUri)" | Out-File $ReportFile -Append
                "Sign-Out URI: $($FederationConfig.SignOutUri)" | Out-File $ReportFile -Append
                "Metadata Exchange URI: $($FederationConfig.MetadataExchangeUri)" | Out-File $ReportFile -Append
                "Preferred Authentication Protocol: $($FederationConfig.PreferredAuthenticationProtocol)" | Out-File $ReportFile -Append
                "Federation Signing Certificate Expiry: $($FederationConfig.SigningCertificate)" | Out-File $ReportFile -Append

                "`nIMPACT FOR PHS MIGRATION:" | Out-File $ReportFile -Append
                "  - This domain uses federation (ADFS/third-party IdP)" | Out-File $ReportFile -Append
                "  - Migration requires converting to managed authentication" | Out-File $ReportFile -Append
                "  - Document federation endpoints for rollback planning" | Out-File $ReportFile -Append
            }
        } catch {
            "Unable to retrieve federation configuration details." | Out-File $ReportFile -Append
        }
    } else {
        $ManagedDomains += $Domain
        "Password Validity Period (days): $($Domain.PasswordValidityPeriodInDays)" | Out-File $ReportFile -Append
        "Password Notification Window (days): $($Domain.PasswordNotificationWindowInDays)" | Out-File $ReportFile -Append
    }
}

Write-SubSection "Domain Summary"
"Total Managed Domains: $($ManagedDomains.Count)" | Out-File $ReportFile -Append
"Total Federated Domains: $($FederatedDomains.Count)" | Out-File $ReportFile -Append

if ($FederatedDomains.Count -gt 0) {
    "`nWARNING: Federated domains require conversion to managed authentication for PHS" | Out-File $ReportFile -Append
    "Use Staged Rollout for gradual migration to minimise user impact" | Out-File $ReportFile -Append
}
#endregion

#region Staged Rollout Configuration
Write-Section "STAGED ROLLOUT CONFIGURATION"
Write-Host "Checking Staged Rollout configuration..." -ForegroundColor Yellow

try {
    $StagedRollout = Get-MgBetaPolicyFeatureRolloutPolicy -All -ErrorAction SilentlyContinue

    if ($StagedRollout) {
        "Staged Rollout Policies Found: $($StagedRollout.Count)" | Out-File $ReportFile -Append

        foreach ($Policy in $StagedRollout) {
            Write-SubSection "Policy: $($Policy.DisplayName)"

            "Policy ID: $($Policy.Id)" | Out-File $ReportFile -Append
            "Feature: $($Policy.Feature)" | Out-File $ReportFile -Append
            "Is Enabled: $($Policy.IsEnabled)" | Out-File $ReportFile -Append
            "Is Applied To Entire Organisation: $($Policy.IsAppliedToOrganization)" | Out-File $ReportFile -Append

            # Get applied groups count (not names for privacy)
            if ($Policy.AppliesTo) {
                $GroupCount = ($Policy.AppliesTo | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.group' }).Count
                $UserCount = ($Policy.AppliesTo | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.user' }).Count
                "Applied to Groups: $GroupCount" | Out-File $ReportFile -Append
                "Applied to Users directly: $UserCount" | Out-File $ReportFile -Append
            }
        }

        # Check for PHS-related policies
        $PHSPolicy = $StagedRollout | Where-Object { $_.Feature -eq "passwordHashSync" }
        $SeamlessSSOPolicy = $StagedRollout | Where-Object { $_.Feature -eq "seamlessSso" }
        $PTAPolicy = $StagedRollout | Where-Object { $_.Feature -eq "passthruAuthentication" }

        Write-SubSection "PHS Migration Relevant Policies"

        if ($PHSPolicy) {
            "Password Hash Sync Staged Rollout: CONFIGURED" | Out-File $ReportFile -Append
            "  Enabled: $($PHSPolicy.IsEnabled)" | Out-File $ReportFile -Append
        } else {
            "Password Hash Sync Staged Rollout: NOT CONFIGURED" | Out-File $ReportFile -Append
        }

        if ($SeamlessSSOPolicy) {
            "Seamless SSO Staged Rollout: CONFIGURED" | Out-File $ReportFile -Append
            "  Enabled: $($SeamlessSSOPolicy.IsEnabled)" | Out-File $ReportFile -Append
        } else {
            "Seamless SSO Staged Rollout: NOT CONFIGURED" | Out-File $ReportFile -Append
        }

        if ($PTAPolicy) {
            "Pass-Through Auth Staged Rollout: CONFIGURED" | Out-File $ReportFile -Append
            "  Enabled: $($PTAPolicy.IsEnabled)" | Out-File $ReportFile -Append
        } else {
            "Pass-Through Auth Staged Rollout: NOT CONFIGURED" | Out-File $ReportFile -Append
        }

    } else {
        "No Staged Rollout policies configured." | Out-File $ReportFile -Append
        "`nRECOMMENDATION: Use Staged Rollout for gradual PHS migration" | Out-File $ReportFile -Append
        "This allows testing with pilot groups before full deployment" | Out-File $ReportFile -Append
    }

} catch {
    "Error retrieving Staged Rollout configuration: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Pass-Through Authentication Agent Inventory
Write-Section "PASS-THROUGH AUTHENTICATION (PTA) AGENT INVENTORY"
Write-Host "Checking PTA agent configuration..." -ForegroundColor Yellow

try {
    $PTAAgents = Get-MgBetaOnPremisePublishingProfileAgent -OnPremisesPublishingProfileId "authentication" -All -ErrorAction SilentlyContinue

    if ($PTAAgents) {
        "Total PTA Agents: $($PTAAgents.Count)" | Out-File $ReportFile -Append

        $ActiveAgents = $PTAAgents | Where-Object { $_.Status -eq "active" }
        $InactiveAgents = $PTAAgents | Where-Object { $_.Status -ne "active" }

        "Active Agents: $($ActiveAgents.Count)" | Out-File $ReportFile -Append
        "Inactive Agents: $($InactiveAgents.Count)" | Out-File $ReportFile -Append

        foreach ($Agent in $PTAAgents) {
            Write-SubSection "Agent: $($Agent.MachineName)"
            "Status: $($Agent.Status)" | Out-File $ReportFile -Append
            "External IP: $($Agent.ExternalIp)" | Out-File $ReportFile -Append
            "Version: $($Agent.Version)" | Out-File $ReportFile -Append
        }

        "`nIMPACT FOR PHS MIGRATION:" | Out-File $ReportFile -Append
        "  - PTA agents can remain active during PHS migration" | Out-File $ReportFile -Append
        "  - PTA can serve as fallback if PHS issues arise" | Out-File $ReportFile -Append
        "  - After successful PHS migration, PTA agents can be decommissioned" | Out-File $ReportFile -Append
    } else {
        "No PTA agents found." | Out-File $ReportFile -Append
        "Current authentication may use PHS, Federation, or cloud-only." | Out-File $ReportFile -Append
    }

} catch {
    "Unable to retrieve PTA agent information: $($_.Exception.Message)" | Out-File $ReportFile -Append
    "This is normal if PTA is not configured or permissions are insufficient." | Out-File $ReportFile -Append
}
#endregion

#region SSPR Configuration
Write-Section "SELF-SERVICE PASSWORD RESET (SSPR) CONFIGURATION"
Write-Host "Checking SSPR configuration..." -ForegroundColor Yellow

try {
    # Get SSPR policy via directory settings
    $SSPRSettings = Get-MgBetaPolicyAuthorizationPolicy -ErrorAction SilentlyContinue

    if ($SSPRSettings) {
        "Allow Users to Self-Service Password Reset: $($SSPRSettings.AllowedToUseSSPR)" | Out-File $ReportFile -Append
    }

    # Get password reset policy
    $PasswordResetPolicy = Get-MgBetaPolicyAuthenticationMethodPolicy -ErrorAction SilentlyContinue

    if ($PasswordResetPolicy) {
        Write-SubSection "Authentication Methods for Password Reset"

        # Get specific SSPR configuration
        $PasswordMethods = $PasswordResetPolicy.AuthenticationMethodConfigurations |
            Where-Object { $_.State -eq "enabled" }

        foreach ($Method in $PasswordMethods) {
            "  - $($Method.Id): Enabled" | Out-File $ReportFile -Append
        }
    }

    # Try to get SSPR registration requirements
    try {
        $AuthMethodsPolicy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy" -ErrorAction SilentlyContinue

        if ($AuthMethodsPolicy.registrationEnforcement) {
            Write-SubSection "SSPR Registration Enforcement"
            "Authentication Methods Registration Campaign State: $($AuthMethodsPolicy.registrationEnforcement.authenticationMethodsRegistrationCampaign.state)" | Out-File $ReportFile -Append
        }
    } catch {
        # Silently continue if this specific call fails
    }

    "`nIMPACT FOR PHS MIGRATION:" | Out-File $ReportFile -Append
    "  - SSPR allows users to reset passwords in the cloud" | Out-File $ReportFile -Append
    "  - With PHS + Password Writeback, SSPR changes sync to AD" | Out-File $ReportFile -Append
    "  - Ensure Password Writeback is enabled for hybrid SSPR" | Out-File $ReportFile -Append

} catch {
    "Error retrieving SSPR configuration: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Identity Protection Status
Write-Section "IDENTITY PROTECTION CONFIGURATION"
Write-Host "Checking Identity Protection settings..." -ForegroundColor Yellow

try {
    # Check if Identity Protection is available (P2 feature)
    if ($HasP2) {
        Write-SubSection "Risk Policies"

        # Get user risk policy
        try {
            $UserRiskPolicy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies" -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty value |
                Where-Object { $_.conditions.userRiskLevels -ne $null }

            if ($UserRiskPolicy) {
                "Conditional Access policies with User Risk conditions: $($UserRiskPolicy.Count)" | Out-File $ReportFile -Append
            } else {
                "No Conditional Access policies with User Risk conditions found." | Out-File $ReportFile -Append
            }
        } catch {
            "Unable to query user risk policies." | Out-File $ReportFile -Append
        }

        # Get sign-in risk policy
        try {
            $SignInRiskPolicy = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/identity/conditionalAccess/policies" -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty value |
                Where-Object { $_.conditions.signInRiskLevels -ne $null }

            if ($SignInRiskPolicy) {
                "Conditional Access policies with Sign-In Risk conditions: $($SignInRiskPolicy.Count)" | Out-File $ReportFile -Append
            } else {
                "No Conditional Access policies with Sign-In Risk conditions found." | Out-File $ReportFile -Append
            }
        } catch {
            "Unable to query sign-in risk policies." | Out-File $ReportFile -Append
        }

        # Get current risky users count (aggregate only)
        try {
            $RiskyUsers = Get-MgBetaRiskyUser -All -Property Id, RiskLevel -ErrorAction SilentlyContinue

            if ($RiskyUsers) {
                $HighRisk = ($RiskyUsers | Where-Object { $_.RiskLevel -eq "high" }).Count
                $MediumRisk = ($RiskyUsers | Where-Object { $_.RiskLevel -eq "medium" }).Count
                $LowRisk = ($RiskyUsers | Where-Object { $_.RiskLevel -eq "low" }).Count

                Write-SubSection "Current Risky Users (Aggregate)"
                "High Risk Users: $HighRisk" | Out-File $ReportFile -Append
                "Medium Risk Users: $MediumRisk" | Out-File $ReportFile -Append
                "Low Risk Users: $LowRisk" | Out-File $ReportFile -Append
            }
        } catch {
            "Unable to retrieve risky user statistics." | Out-File $ReportFile -Append
        }

        "`nIMPACT FOR PHS MIGRATION:" | Out-File $ReportFile -Append
        "  - PHS enables leaked credentials detection in Identity Protection" | Out-File $ReportFile -Append
        "  - Microsoft compares password hashes against known breached passwords" | Out-File $ReportFile -Append
        "  - This feature is NOT available with PTA or Federation" | Out-File $ReportFile -Append
        "  - Major security benefit of PHS over other auth methods" | Out-File $ReportFile -Append

    } else {
        "Identity Protection requires Entra ID P2 licensing." | Out-File $ReportFile -Append
        "P2 licenses not detected in this tenant." | Out-File $ReportFile -Append
        "`nRECOMMENDATION: Consider P2 licensing to enable:" | Out-File $ReportFile -Append
        "  - Leaked credentials detection (PHS exclusive feature)" | Out-File $ReportFile -Append
        "  - Risk-based Conditional Access" | Out-File $ReportFile -Append
        "  - Automated risk remediation" | Out-File $ReportFile -Append
    }

} catch {
    "Error retrieving Identity Protection configuration: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Conditional Access Policy Summary
Write-Section "CONDITIONAL ACCESS POLICY SUMMARY"
Write-Host "Collecting Conditional Access policy summary..." -ForegroundColor Yellow

try {
    $CAPolicies = Get-MgBetaIdentityConditionalAccessPolicy -All -ErrorAction SilentlyContinue

    if ($CAPolicies) {
        "Total Conditional Access Policies: $($CAPolicies.Count)" | Out-File $ReportFile -Append

        $EnabledPolicies = $CAPolicies | Where-Object { $_.State -eq "enabled" }
        $ReportOnlyPolicies = $CAPolicies | Where-Object { $_.State -eq "enabledForReportingButNotEnforced" }
        $DisabledPolicies = $CAPolicies | Where-Object { $_.State -eq "disabled" }

        "Enabled Policies: $($EnabledPolicies.Count)" | Out-File $ReportFile -Append
        "Report-Only Policies: $($ReportOnlyPolicies.Count)" | Out-File $ReportFile -Append
        "Disabled Policies: $($DisabledPolicies.Count)" | Out-File $ReportFile -Append

        # Analyse grant controls
        Write-SubSection "Policy Grant Control Analysis"

        $MFAPolicies = $CAPolicies | Where-Object {
            $_.GrantControls.BuiltInControls -contains "mfa"
        }
        $BlockPolicies = $CAPolicies | Where-Object {
            $_.GrantControls.BuiltInControls -contains "block"
        }
        $CompliantDevicePolicies = $CAPolicies | Where-Object {
            $_.GrantControls.BuiltInControls -contains "compliantDevice"
        }
        $HybridJoinPolicies = $CAPolicies | Where-Object {
            $_.GrantControls.BuiltInControls -contains "domainJoinedDevice"
        }

        "Policies requiring MFA: $($MFAPolicies.Count)" | Out-File $ReportFile -Append
        "Policies with Block control: $($BlockPolicies.Count)" | Out-File $ReportFile -Append
        "Policies requiring Compliant Device: $($CompliantDevicePolicies.Count)" | Out-File $ReportFile -Append
        "Policies requiring Hybrid Entra Joined Device: $($HybridJoinPolicies.Count)" | Out-File $ReportFile -Append

        # Check for legacy authentication blocks
        $LegacyAuthBlocks = $CAPolicies | Where-Object {
            $_.Conditions.ClientAppTypes -contains "exchangeActiveSync" -or
            $_.Conditions.ClientAppTypes -contains "other"
        }

        Write-SubSection "Legacy Authentication"
        "Policies addressing legacy auth: $($LegacyAuthBlocks.Count)" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS MIGRATION:" | Out-File $ReportFile -Append
        "  - Conditional Access policies will continue to apply after PHS migration" | Out-File $ReportFile -Append
        "  - Review policies that reference on-premises resources" | Out-File $ReportFile -Append
        "  - MFA policies enhance security with PHS" | Out-File $ReportFile -Append

    } else {
        "No Conditional Access policies found." | Out-File $ReportFile -Append
        "Note: Conditional Access requires Entra ID P1 or P2 licensing." | Out-File $ReportFile -Append
    }

} catch {
    "Error retrieving Conditional Access policies: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Named Locations
Write-Section "NAMED LOCATIONS CONFIGURATION"
Write-Host "Checking Named Locations..." -ForegroundColor Yellow

try {
    $NamedLocations = Get-MgBetaIdentityConditionalAccessNamedLocation -All -ErrorAction SilentlyContinue

    if ($NamedLocations) {
        "Total Named Locations: $($NamedLocations.Count)" | Out-File $ReportFile -Append

        $IPLocations = $NamedLocations | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.ipNamedLocation' }
        $CountryLocations = $NamedLocations | Where-Object { $_.'@odata.type' -eq '#microsoft.graph.countryNamedLocation' }

        "IP-based Named Locations: $($IPLocations.Count)" | Out-File $ReportFile -Append
        "Country-based Named Locations: $($CountryLocations.Count)" | Out-File $ReportFile -Append

        # Check for trusted locations
        $TrustedLocations = $NamedLocations | Where-Object { $_.IsTrusted -eq $true }
        "Trusted Locations: $($TrustedLocations.Count)" | Out-File $ReportFile -Append

        Write-SubSection "Named Location Details (No IP Addresses)"

        foreach ($Location in $NamedLocations) {
            "Location: $($Location.DisplayName)" | Out-File $ReportFile -Append
            "  Type: $($Location.'@odata.type' -replace '#microsoft.graph.', '')" | Out-File $ReportFile -Append
            "  Is Trusted: $($Location.IsTrusted)" | Out-File $ReportFile -Append

            if ($Location.'@odata.type' -eq '#microsoft.graph.countryNamedLocation') {
                "  Countries: $($Location.CountriesAndRegions -join ', ')" | Out-File $ReportFile -Append
            }
            if ($Location.'@odata.type' -eq '#microsoft.graph.ipNamedLocation') {
                "  IP Range Count: $($Location.IpRanges.Count)" | Out-File $ReportFile -Append
            }
        }

        "`nIMPACT FOR PHS AND SMART LOCKOUT:" | Out-File $ReportFile -Append
        "  - Smart Lockout behaves differently for known vs unknown locations" | Out-File $ReportFile -Append
        "  - Trusted/familiar locations have higher lockout thresholds" | Out-File $ReportFile -Append
        "  - Unknown locations trigger more aggressive lockout" | Out-File $ReportFile -Append

    } else {
        "No Named Locations configured." | Out-File $ReportFile -Append
        "Smart Lockout will use default location-based behaviour." | Out-File $ReportFile -Append
    }

} catch {
    "Error retrieving Named Locations: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Hybrid Entra Joined Devices
Write-Section "HYBRID ENTRA JOINED DEVICE STATISTICS"
Write-Host "Collecting device statistics..." -ForegroundColor Yellow

try {
    # Get device counts by join type
    $AllDevices = Get-MgBetaDevice -All -Property Id, DeviceTrustType, IsManaged, IsCompliant -ConsistencyLevel eventual -ErrorAction SilentlyContinue

    if ($AllDevices) {
        $TotalDevices = $AllDevices.Count
        $HybridJoined = ($AllDevices | Where-Object { $_.DeviceTrustType -eq "ServerAd" }).Count
        $EntraJoined = ($AllDevices | Where-Object { $_.DeviceTrustType -eq "AzureAd" }).Count
        $EntraRegistered = ($AllDevices | Where-Object { $_.DeviceTrustType -eq "Workplace" }).Count

        "Total Devices: $TotalDevices" | Out-File $ReportFile -Append
        "Hybrid Entra Joined: $HybridJoined" | Out-File $ReportFile -Append
        "Entra Joined (Cloud): $EntraJoined" | Out-File $ReportFile -Append
        "Entra Registered: $EntraRegistered" | Out-File $ReportFile -Append

        if ($TotalDevices -gt 0) {
            $HybridPercentage = [math]::Round(($HybridJoined / $TotalDevices) * 100, 1)
            "Percentage Hybrid Joined: $HybridPercentage%" | Out-File $ReportFile -Append
        }

        # Compliance statistics
        Write-SubSection "Device Compliance"
        $ManagedDevices = ($AllDevices | Where-Object { $_.IsManaged -eq $true }).Count
        $CompliantDevices = ($AllDevices | Where-Object { $_.IsCompliant -eq $true }).Count

        "Managed Devices: $ManagedDevices" | Out-File $ReportFile -Append
        "Compliant Devices: $CompliantDevices" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS MIGRATION:" | Out-File $ReportFile -Append
        "  - Hybrid Entra Joined devices use Primary Refresh Token (PRT) for SSO" | Out-File $ReportFile -Append
        "  - PRT acquisition method differs between PHS, PTA, and Federation" | Out-File $ReportFile -Append
        "  - With PHS, PRT is obtained during Windows sign-in using password hash" | Out-File $ReportFile -Append
        "  - Seamless SSO enhances device sign-in experience with PHS" | Out-File $ReportFile -Append

    } else {
        "Unable to retrieve device statistics." | Out-File $ReportFile -Append
    }

} catch {
    "Error retrieving device statistics: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Password Protection Policy
Write-Section "PASSWORD PROTECTION POLICY (SMART LOCKOUT & BANNED PASSWORDS)"
Write-Host "Retrieving password protection policy settings..." -ForegroundColor Yellow

try {
    # The Password Rule Settings template ID is: 5cf42378-d67d-4f36-ba46-e8b86229381d
    $PasswordProtectionPolicy = Get-MgBetaDirectorySetting | Where-Object {
        $_.TemplateId -eq "5cf42378-d67d-4f36-ba46-e8b86229381d"
    }

    if ($PasswordProtectionPolicy) {
        "Custom Password Protection Policy Found: Yes" | Out-File $ReportFile -Append
        "Policy ID: $($PasswordProtectionPolicy.Id)" | Out-File $ReportFile -Append

        # Extract individual settings
        $PolicyValues = $PasswordProtectionPolicy.Values

        # Smart Lockout Settings
        Write-SubSection "Smart Lockout Configuration"
        $LockoutThreshold = ($PolicyValues | Where-Object {$_.Name -eq "LockoutThreshold"}).Value
        $LockoutDuration = ($PolicyValues | Where-Object {$_.Name -eq "LockoutDurationInSeconds"}).Value

        "Lockout Threshold (failed attempts before lockout): $LockoutThreshold" | Out-File $ReportFile -Append
        "Lockout Duration (seconds): $LockoutDuration" | Out-File $ReportFile -Append
        "Lockout Duration (minutes): $([math]::Round($LockoutDuration / 60, 1))" | Out-File $ReportFile -Append

        # Custom Banned Password List Settings
        Write-SubSection "Custom Banned Password List Configuration"
        $BannedPasswordCheckEnabled = ($PolicyValues | Where-Object {$_.Name -eq "EnableBannedPasswordCheck"}).Value
        $BannedPasswordList = ($PolicyValues | Where-Object {$_.Name -eq "BannedPasswordList"}).Value

        "Custom Banned Password List Enabled: $BannedPasswordCheckEnabled" | Out-File $ReportFile -Append

        if ($BannedPasswordList) {
            $BannedPasswords = $BannedPasswordList -split [char]9
            "Number of Custom Banned Passwords: $($BannedPasswords.Count)" | Out-File $ReportFile -Append
            "Maximum Allowed: 1000" | Out-File $ReportFile -Append
            "Note: Actual banned password list not displayed for security reasons" | Out-File $ReportFile -Append
        } else {
            "Number of Custom Banned Passwords: 0" | Out-File $ReportFile -Append
            "Note: Only Microsoft's global banned password list is active" | Out-File $ReportFile -Append
        }

        # On-Premises Integration Settings
        Write-SubSection "On-Premises Password Protection"
        $EnableOnPrem = ($PolicyValues | Where-Object {$_.Name -eq "EnableBannedPasswordCheckOnPremises"}).Value
        $OnPremMode = ($PolicyValues | Where-Object {$_.Name -eq "BannedPasswordCheckOnPremisesMode"}).Value

        "On-Premises Password Protection Enabled: $EnableOnPrem" | Out-File $ReportFile -Append
        "On-Premises Mode: $OnPremMode" | Out-File $ReportFile -Append

        if ($EnableOnPrem -eq "True") {
            "Note: Password protection extends to on-premises AD" | Out-File $ReportFile -Append
        }

    } else {
        "Custom Password Protection Policy Found: No" | Out-File $ReportFile -Append
        "Status: Using default password protection settings" | Out-File $ReportFile -Append
        "`nDefault Settings:" | Out-File $ReportFile -Append
        "  - Lockout Threshold: 10 failed attempts" | Out-File $ReportFile -Append
        "  - Lockout Duration: 60 seconds" | Out-File $ReportFile -Append
        "  - Custom Banned Password List: Disabled" | Out-File $ReportFile -Append
        "  - Microsoft Global Banned Password List: Enabled (always active)" | Out-File $ReportFile -Append
        "  - On-Premises Password Protection: Disabled" | Out-File $ReportFile -Append

        "`nNote: Custom password protection settings require Entra ID P1 or P2 licensing" | Out-File $ReportFile -Append
    }

} catch {
    "Error retrieving password protection policy: $($_.Exception.Message)" | Out-File $ReportFile -Append
    "This may indicate permissions issues or the feature is not available in your tenant." | Out-File $ReportFile -Append
}
#endregion

#region User Statistics
Write-Section "USER STATISTICS"
Write-Host "Retrieving user statistics..." -ForegroundColor Yellow

# Synced users
try {
    $AllSyncedUsers = Get-MgBetaUser -Filter "onPremisesSyncEnabled eq true" -All `
        -Property Id, OnPremisesSyncEnabled, PasswordPolicies `
        -ConsistencyLevel eventual -CountVariable syncedUserCount

    "Total synced users: $syncedUserCount" | Out-File $ReportFile -Append

    if ($syncedUserCount -gt 0) {
        $PolicyCounts = $AllSyncedUsers | Group-Object -Property PasswordPolicies

        "`nPassword policy distribution:" | Out-File $ReportFile -Append
        foreach ($Policy in $PolicyCounts) {
            $PolicyName = if ([string]::IsNullOrEmpty($Policy.Name)) {
                "None (Default)"
            } else {
                $Policy.Name
            }
            $Percentage = [math]::Round(($Policy.Count / $syncedUserCount) * 100, 1)
            "  $PolicyName : $($Policy.Count) users ($Percentage%)" | Out-File $ReportFile -Append
        }

        $DisabledExpiryCount = ($AllSyncedUsers | Where-Object {
            $_.PasswordPolicies -eq "DisablePasswordExpiration"
        }).Count

        if ($DisabledExpiryCount -gt 0) {
            "`nCRITICAL FINDING:" | Out-File $ReportFile -Append
            "$DisabledExpiryCount synced users have DisablePasswordExpiration policy set." | Out-File $ReportFile -Append
        }
    }
} catch {
    "Error retrieving synced user statistics: $($_.Exception.Message)" | Out-File $ReportFile -Append
}

# Cloud-only users
Write-SubSection "Cloud-Only Users"
try {
    $CloudOnlyUsers = Get-MgBetaUser -Filter "onPremisesSyncEnabled eq null or onPremisesSyncEnabled eq false" -All `
        -Property Id -ConsistencyLevel eventual -CountVariable cloudUserCount

    "Total cloud-only users: $cloudUserCount" | Out-File $ReportFile -Append
    "Note: These users are not affected by the PHS migration." | Out-File $ReportFile -Append
} catch {
    "Error retrieving cloud-only user statistics: $($_.Exception.Message)" | Out-File $ReportFile -Append
}

# Total users
Write-SubSection "Total Users"
try {
    Get-MgBetaUser -All -Property Id -ConsistencyLevel eventual -CountVariable totalUserCount | Out-Null
    "Total users in tenant: $totalUserCount" | Out-File $ReportFile -Append

    if ($syncedUserCount -and $totalUserCount) {
        $SyncPercentage = [math]::Round(($syncedUserCount / $totalUserCount) * 100, 1)
        "Percentage of synced users: $SyncPercentage%" | Out-File $ReportFile -Append
    }
} catch {
    "Error retrieving total user count: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Authentication Methods
Write-Section "AUTHENTICATION METHODS CONFIGURATION"
Write-Host "Collecting authentication methods..." -ForegroundColor Yellow

try {
    $AuthMethods = Get-MgBetaPolicyAuthenticationMethodPolicy
    "Authentication Methods Policy ID: $($AuthMethods.Id)" | Out-File $ReportFile -Append

    $AuthMethodConfigs = $AuthMethods.AuthenticationMethodConfigurations

    if ($AuthMethodConfigs) {
        "`nEnabled Authentication Methods:" | Out-File $ReportFile -Append
        $EnabledMethods = $AuthMethodConfigs | Where-Object {$_.State -eq "enabled"}
        foreach ($Method in $EnabledMethods) {
            "  - $($Method.Id)" | Out-File $ReportFile -Append
        }

        "`nDisabled Authentication Methods:" | Out-File $ReportFile -Append
        $DisabledMethods = $AuthMethodConfigs | Where-Object {$_.State -eq "disabled"}
        foreach ($Method in $DisabledMethods) {
            "  - $($Method.Id)" | Out-File $ReportFile -Append
        }

        "`nAuthentication Methods Summary:" | Out-File $ReportFile -Append
        "  Total Methods Enabled: $($EnabledMethods.Count)" | Out-File $ReportFile -Append
        "  Total Methods Disabled: $($DisabledMethods.Count)" | Out-File $ReportFile -Append
    }
} catch {
    "Unable to retrieve authentication methods policy." | Out-File $ReportFile -Append
}
#endregion

#region Critical Findings Summary
Write-Section "CRITICAL FINDINGS SUMMARY"

$CriticalFindings = @()
$Warnings = @()
$Info = @()

# Sync feature checks
if ($OnPremSync.Features.CloudPasswordPolicyForPasswordSyncedUsersEnabled -eq $false) {
    $CriticalFindings += "CloudPasswordPolicyForPasswordSyncedUsersEnabled is DISABLED"
}

if ($OnPremSync.Features.UserForcePasswordChangeOnLogonEnabled -eq $false) {
    $Warnings += "UserForcePasswordChangeOnLogonEnabled is DISABLED"
}

# Federation check
if ($FederatedDomains.Count -gt 0) {
    $CriticalFindings += "$($FederatedDomains.Count) domain(s) currently using federation (ADFS)"
}

# Password protection check
if (-not $PasswordProtectionPolicy) {
    $Warnings += "No custom password protection policy configured (using defaults)"
}

# License check
if (-not $HasP2) {
    $Warnings += "P2 licenses not detected - Identity Protection unavailable"
}

# Staged Rollout check
if (-not $StagedRollout) {
    $Info += "No Staged Rollout configured - consider for gradual migration"
}

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
    "Environment appears ready for PHS migration." | Out-File $ReportFile -Append
}
#endregion

#region Script Completion
Write-Host "`nAssessment complete. Report saved to: $ReportFile" -ForegroundColor Green
Write-Host "`nCritical Statistics:" -ForegroundColor Cyan
if ($totalUserCount) { Write-Host "  Total Users: $totalUserCount" -ForegroundColor White }
if ($syncedUserCount) { Write-Host "  Synced Users: $syncedUserCount" -ForegroundColor White }
if ($cloudUserCount) { Write-Host "  Cloud-Only Users: $cloudUserCount" -ForegroundColor White }

Write-Host "`nThis report contains NO personally identifiable information (PII)." -ForegroundColor Cyan
Write-Host "Only aggregate statistics and policy configurations have been collected." -ForegroundColor Cyan

# Disconnect
#Disconnect-MgGraph
#endregion
