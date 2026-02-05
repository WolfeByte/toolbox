<#
.SYNOPSIS
    Collects Active Directory password policy and authentication configuration for an Entra Password Hash Sync readiness assessment.
    PII-FREE VERSION - No user-identifiable information is collected.

.DESCRIPTION
    This script gathers configuration details from Active Directory including password policies,
    account statistics, and authentication-related configurations to assess readiness for
    Password Hash Sync. All user-identifying information is excluded.

    Checks performed:
    - Default domain and fine-grained password policies
    - Accounts requiring password change at next logon
    - Accounts that have never set a password
    - Reversible encryption settings
    - Protected Users and Denied RODC Password Replication groups
    - Privileged accounts (adminCount)
    - Kerberos delegation configuration
    - UPN suffix distribution and non-routable suffixes
    - Mail attribute analysis for Alternate Login ID readiness
    - ProxyAddresses conflicts and duplicates
    - Third-party password filter DLLs
    - Account expiration settings
    - Password never expires flags
    - Service accounts and Managed Service Accounts (gMSA/sMSA)
    - Logon hours restrictions
    - Smart card required accounts
    - User cannot change password flags
    - Sensitive account flags
    - DES-only encryption accounts
    - Currently locked accounts
    - Password age statistics and expiry timing
    - Linked mailbox users (resource forest detection)

.PARAMETER OutputPath
    The folder path where the assessment report will be saved.
    If not specified, you will be prompted to enter a path.
    The folder will be created if it does not exist.

.EXAMPLE
    .\Get-ADPHSReadiness.ps1
    Runs the script and prompts for an output folder location.

.EXAMPLE
    .\Get-ADPHSReadiness.ps1 -OutputPath "C:\Temp\PHSAssessment"
    Runs the script and saves the report to the specified folder.

.NOTES
    Author: Benjamin Wolfe
    Run this script on a Domain Controller with appropriate permissions.
    Requires: Active Directory PowerShell module

    DATA COLLECTED: Policy settings, aggregate statistics only
    DATA EXCLUDED: Names, usernames, email addresses, descriptions, or any PII
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

#Requires -Modules ActiveDirectory

#region Script Configuration
# Prompt for output path if not provided
if (-not $OutputPath) {
    $DefaultPath = "C:\Temp\PHSAssessment"
    $OutputPath = Read-Host "Enter output folder path (press Enter for default: $DefaultPath)"
    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = $DefaultPath
    }
}

# Create output folder if it doesn't exist
if (-not (Test-Path $OutputPath)) {
    try {
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
        Write-Host "Created output folder: $OutputPath" -ForegroundColor Green
    } catch {
        Write-Host "Error creating output folder: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ComputerName = $env:COMPUTERNAME
$ReportFile = Join-Path $OutputPath "AD_Assessment_$Timestamp.txt"

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
"PHS MIGRATION ASSESSMENT - ACTIVE DIRECTORY CONFIGURATION" | Out-File $ReportFile
"Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $ReportFile -Append
"Server: $ComputerName" | Out-File $ReportFile -Append
"Script Version: 2.1" | Out-File $ReportFile -Append
#endregion

Write-Host "Starting Active Directory configuration assessment..." -ForegroundColor Cyan

#region Domain Information
Write-Section "DOMAIN INFORMATION"
Write-Host "Collecting domain information..." -ForegroundColor Yellow

$Domain = Get-ADDomain
$Forest = Get-ADForest

"Domain Name: $($Domain.DNSRoot)" | Out-File $ReportFile -Append
"Domain Functional Level: $($Domain.DomainMode)" | Out-File $ReportFile -Append
"Forest Functional Level: $($Forest.ForestMode)" | Out-File $ReportFile -Append
"NetBIOS Name: $($Domain.NetBIOSName)" | Out-File $ReportFile -Append
#endregion

#region Default Domain Password Policy
Write-Section "DEFAULT DOMAIN PASSWORD POLICY"
Write-Host "Collecting default password policy..." -ForegroundColor Yellow

$DefaultPolicy = Get-ADDefaultDomainPasswordPolicy
$DefaultPolicy | Format-List ComplexityEnabled, LockoutDuration, LockoutObservationWindow,
    LockoutThreshold, MaxPasswordAge, MinPasswordAge, MinPasswordLength,
    PasswordHistoryCount, ReversibleEncryptionEnabled | Out-File $ReportFile -Append
#endregion

#region Fine-Grained Password Policies
Write-Section "FINE-GRAINED PASSWORD POLICIES (PSO) - CONFIGURATION ONLY"
Write-Host "Collecting fine-grained password policies..." -ForegroundColor Yellow

$PSOs = @(Get-ADFineGrainedPasswordPolicy -Filter *)
if ($PSOs) {
    "Total Fine-Grained Password Policies: $($PSOs.Count)" | Out-File $ReportFile -Append

    foreach ($PSO in $PSOs) {
        "`n--- Policy: $($PSO.Name) ---" | Out-File $ReportFile -Append
        "Precedence: $($PSO.Precedence)" | Out-File $ReportFile -Append
        "Number of Objects Applied To: $($PSO.AppliesTo.Count)" | Out-File $ReportFile -Append
        $PSO | Format-List ComplexityEnabled, LockoutDuration, LockoutObservationWindow,
            LockoutThreshold, MaxPasswordAge, MinPasswordAge, MinPasswordLength,
            PasswordHistoryCount, ReversibleEncryptionEnabled | Out-File $ReportFile -Append
    }
} else {
    "No Fine-Grained Password Policies found." | Out-File $ReportFile -Append
}
#endregion

#region Users Must Change Password at Next Logon (pwdLastSet = 0)
Write-Section "ACCOUNTS WITH 'MUST CHANGE PASSWORD AT NEXT LOGON' - STATISTICS"
Write-Host "Checking for accounts requiring password change at next logon..." -ForegroundColor Yellow

try {
    # pwdLastSet = 0 means "User must change password at next logon"
    $MustChangePassword = @(Get-ADUser -Filter {Enabled -eq $true} -Properties pwdLastSet |
        Where-Object { $_.pwdLastSet -eq 0 })

    if ($MustChangePassword) {
        "Total enabled accounts with 'Must change password at next logon': $($MustChangePassword.Count)" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - These accounts will NOT have their password synced to Entra unless" | Out-File $ReportFile -Append
        "    'UserForcePasswordChangeOnLogonEnabled' feature is enabled in Entra Connect" | Out-File $ReportFile -Append
        "  - Users will be unable to sign in to cloud resources until they change their AD password" | Out-File $ReportFile -Append

        "`nRECOMMENDATION:" | Out-File $ReportFile -Append
        "  - Enable 'UserForcePasswordChangeOnLogonEnabled' in Entra Connect before migration" | Out-File $ReportFile -Append
        "  - Or ensure all users change their password before PHS cutover" | Out-File $ReportFile -Append
    } else {
        "No enabled accounts with 'Must change password at next logon' found." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking for must-change-password accounts: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Users Who Have Never Set a Password
Write-Section "ACCOUNTS THAT HAVE NEVER SET A PASSWORD - STATISTICS"
Write-Host "Checking for accounts that have never set a password..." -ForegroundColor Yellow

try {
    # PasswordLastSet = null means the user has never set a password
    $NeverSetPassword = @(Get-ADUser -Filter {Enabled -eq $true} -Properties PasswordLastSet |
        Where-Object { $null -eq $_.PasswordLastSet })

    if ($NeverSetPassword) {
        "Total enabled accounts that have never set a password: $($NeverSetPassword.Count)" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - These accounts have no password hash to sync" | Out-File $ReportFile -Append
        "  - Users cannot authenticate via PHS until a password is set" | Out-File $ReportFile -Append

        "`nRECOMMENDATION:" | Out-File $ReportFile -Append
        "  - Review these accounts - they may be newly created or use alternative auth" | Out-File $ReportFile -Append
        "  - Ensure passwords are set before PHS migration if cloud access is required" | Out-File $ReportFile -Append
    } else {
        "No enabled accounts found that have never set a password." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking for never-set-password accounts: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Users with Reversible Encryption
Write-Section "ACCOUNTS WITH REVERSIBLE ENCRYPTION ENABLED - STATISTICS"
Write-Host "Checking for accounts with reversible encryption..." -ForegroundColor Yellow

try {
    $ReversibleEncryptionUsers = @(Get-ADUser -Filter {Enabled -eq $true -and AllowReversiblePasswordEncryption -eq $true} -Properties AllowReversiblePasswordEncryption)

    if ($ReversibleEncryptionUsers) {
        "Total enabled accounts with reversible encryption: $($ReversibleEncryptionUsers.Count)" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - Reversible encryption stores passwords in a way that can be decrypted" | Out-File $ReportFile -Append
        "  - This is a security risk and is generally discouraged" | Out-File $ReportFile -Append
        "  - PHS can sync these passwords but the underlying security concern remains" | Out-File $ReportFile -Append

        "`nRECOMMENDATION:" | Out-File $ReportFile -Append
        "  - Review why reversible encryption is enabled for these accounts" | Out-File $ReportFile -Append
        "  - Consider disabling unless required for specific applications (e.g., CHAP, Digest)" | Out-File $ReportFile -Append
        "  - Users will need to change password after disabling for new hash to be stored" | Out-File $ReportFile -Append
    } else {
        "No enabled accounts with reversible encryption found." | Out-File $ReportFile -Append
    }

    # Also check domain policy
    if ($DefaultPolicy.ReversibleEncryptionEnabled -eq $true) {
        "`nWARNING: Default domain policy has ReversibleEncryptionEnabled = True" | Out-File $ReportFile -Append
        "This affects all users not covered by a Fine-Grained Password Policy." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking for reversible encryption accounts: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Protected Users Group
Write-Section "PROTECTED USERS GROUP - STATISTICS"
Write-Host "Checking Protected Users group membership..." -ForegroundColor Yellow

try {
    $ProtectedUsersGroup = Get-ADGroup -Identity "Protected Users" -ErrorAction SilentlyContinue

    if ($ProtectedUsersGroup) {
        $ProtectedUsersMembers = @(Get-ADGroupMember -Identity "Protected Users" -Recursive -ErrorAction SilentlyContinue)

        if ($ProtectedUsersMembers) {
            $UserMembers = @($ProtectedUsersMembers | Where-Object { $_.objectClass -eq "user" })
            "Total members in Protected Users group: $($ProtectedUsersMembers.Count)" | Out-File $ReportFile -Append
            "User accounts in Protected Users group: $($UserMembers.Count)" | Out-File $ReportFile -Append
        } else {
            "Protected Users group exists but has no members." | Out-File $ReportFile -Append
        }

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - Protected Users have additional credential protections" | Out-File $ReportFile -Append
        "  - NTLM authentication is blocked for Protected Users" | Out-File $ReportFile -Append
        "  - DES and RC4 encryption types are not used" | Out-File $ReportFile -Append
        "  - Credential delegation (CredSSP) is blocked" | Out-File $ReportFile -Append
        "  - TGT lifetime is limited to 4 hours" | Out-File $ReportFile -Append

        "`nNOTE:" | Out-File $ReportFile -Append
        "  - PHS works normally for Protected Users members" | Out-File $ReportFile -Append
        "  - Cloud authentication is not affected by Protected Users membership" | Out-File $ReportFile -Append
    } else {
        "Protected Users group not found (requires Windows Server 2012 R2+ domain functional level)." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking Protected Users group: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Denied RODC Password Replication Group
Write-Section "DENIED RODC PASSWORD REPLICATION GROUP - STATISTICS"
Write-Host "Checking Denied RODC Password Replication Group membership..." -ForegroundColor Yellow

try {
    $DeniedRODCGroup = Get-ADGroup -Identity "Denied RODC Password Replication Group" -ErrorAction SilentlyContinue

    if ($DeniedRODCGroup) {
        $DeniedRODCMembers = @(Get-ADGroupMember -Identity "Denied RODC Password Replication Group" -Recursive -ErrorAction SilentlyContinue)

        if ($DeniedRODCMembers) {
            $DeniedUserMembers = @($DeniedRODCMembers | Where-Object { $_.objectClass -eq "user" })
            "Total members in Denied RODC Password Replication Group: $($DeniedRODCMembers.Count)" | Out-File $ReportFile -Append
            "User accounts in group: $($DeniedUserMembers.Count)" | Out-File $ReportFile -Append
        } else {
            "Denied RODC Password Replication Group exists but has no members." | Out-File $ReportFile -Append
        }

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - Users in this group do NOT have password hashes replicated to RODCs" | Out-File $ReportFile -Append
        "  - If Entra Connect uses an RODC, these accounts may fail to sync passwords" | Out-File $ReportFile -Append
        "  - Password hash may not be available on all domain controllers" | Out-File $ReportFile -Append

        "`nRECOMMENDATION:" | Out-File $ReportFile -Append
        "  - Ensure Entra Connect server uses a writable DC, not an RODC" | Out-File $ReportFile -Append
        "  - Verify password hash availability for these accounts" | Out-File $ReportFile -Append
    } else {
        "Denied RODC Password Replication Group not found." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking Denied RODC Password Replication Group: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Privileged Accounts (adminCount = 1)
Write-Section "PRIVILEGED ACCOUNTS (adminCount = 1) - STATISTICS"
Write-Host "Checking for privileged accounts with adminCount attribute..." -ForegroundColor Yellow

try {
    $AdminCountUsers = @(Get-ADUser -Filter {adminCount -eq 1 -and Enabled -eq $true} -Properties adminCount)

    if ($AdminCountUsers) {
        "Total enabled accounts with adminCount = 1: $($AdminCountUsers.Count)" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - These accounts are/were members of privileged AD groups" | Out-File $ReportFile -Append
        "  - SDProp process has modified their ACLs" | Out-File $ReportFile -Append
        "  - AdminSDHolder protections may affect password operations" | Out-File $ReportFile -Append

        "`nCONSIDERATIONS:" | Out-File $ReportFile -Append
        "  - Review if these accounts need cloud access" | Out-File $ReportFile -Append
        "  - Consider excluding privileged accounts from sync scope" | Out-File $ReportFile -Append
        "  - Ensure emergency access accounts exist in cloud-only form" | Out-File $ReportFile -Append
        "  - Consider Privileged Identity Management (PIM) for cloud access" | Out-File $ReportFile -Append

        # Check for orphaned adminCount
        "`nNote: Some accounts may have orphaned adminCount (removed from privileged groups but" | Out-File $ReportFile -Append
        "attribute not cleared). This is a common AD hygiene issue." | Out-File $ReportFile -Append
    } else {
        "No enabled accounts with adminCount = 1 found." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking for privileged accounts: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Kerberos Delegation Configuration
Write-Section "KERBEROS DELEGATION CONFIGURATION - STATISTICS"
Write-Host "Checking Kerberos delegation settings..." -ForegroundColor Yellow

try {
    # Users trusted for delegation (unconstrained)
    $UnconstrainedDelegationUsers = @(Get-ADUser -Filter {TrustedForDelegation -eq $true -and Enabled -eq $true} -Properties TrustedForDelegation)

    # Users trusted to authenticate for delegation (protocol transition)
    $ProtocolTransitionUsers = @(Get-ADUser -Filter {TrustedToAuthForDelegation -eq $true -and Enabled -eq $true} -Properties TrustedToAuthForDelegation)

    # Users with constrained delegation configured
    $ConstrainedDelegationUsers = @(Get-ADUser -Filter {Enabled -eq $true} -Properties 'msDS-AllowedToDelegateTo' |
        Where-Object { $_.'msDS-AllowedToDelegateTo' })

    # Computers trusted for delegation
    $DelegationComputers = @(Get-ADComputer -Filter {TrustedForDelegation -eq $true} -Properties TrustedForDelegation)

    "User accounts with unconstrained delegation: $($UnconstrainedDelegationUsers.Count)" | Out-File $ReportFile -Append
    "User accounts with protocol transition (S4U2Self): $($ProtocolTransitionUsers.Count)" | Out-File $ReportFile -Append
    "User accounts with constrained delegation: $($ConstrainedDelegationUsers.Count)" | Out-File $ReportFile -Append
    "Computer accounts with unconstrained delegation: $($DelegationComputers.Count)" | Out-File $ReportFile -Append

    $TotalDelegation = $UnconstrainedDelegationUsers.Count + $ProtocolTransitionUsers.Count + $ConstrainedDelegationUsers.Count

    if ($TotalDelegation -gt 0) {
        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - Kerberos delegation relies on on-premises authentication" | Out-File $ReportFile -Append
        "  - Applications using delegation may not work with cloud-only auth" | Out-File $ReportFile -Append
        "  - Constrained delegation to cloud services requires reconfiguration" | Out-File $ReportFile -Append

        "`nRECOMMENDATION:" | Out-File $ReportFile -Append
        "  - Inventory applications relying on Kerberos delegation" | Out-File $ReportFile -Append
        "  - Consider Azure AD Application Proxy with KCD for hybrid scenarios" | Out-File $ReportFile -Append
        "  - Review if delegation is still required or can be modernised" | Out-File $ReportFile -Append
    }

    if ($UnconstrainedDelegationUsers.Count -gt 0) {
        "`nWARNING: Unconstrained delegation on user accounts is a security risk." | Out-File $ReportFile -Append
        "Consider migrating to constrained delegation or resource-based constrained delegation." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking Kerberos delegation: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region UPN Suffix Distribution
Write-Section "UPN SUFFIX DISTRIBUTION - STATISTICS"
Write-Host "Analysing UPN suffix distribution..." -ForegroundColor Yellow

try {
    # Get all UPN suffixes configured in the forest
    $ConfiguredSuffixes = $Forest.UPNSuffixes
    $DefaultSuffix = $Forest.RootDomain

    "Default UPN Suffix (Forest Root): $DefaultSuffix" | Out-File $ReportFile -Append

    if ($ConfiguredSuffixes) {
        "Additional Configured UPN Suffixes: $($ConfiguredSuffixes.Count)" | Out-File $ReportFile -Append
        foreach ($Suffix in $ConfiguredSuffixes) {
            "  - $Suffix" | Out-File $ReportFile -Append
        }
    } else {
        "No additional UPN suffixes configured." | Out-File $ReportFile -Append
    }

    # Analyse actual UPN suffix usage
    Write-SubSection "Actual UPN Suffix Usage"

    $AllEnabledUsers = @(Get-ADUser -Filter {Enabled -eq $true} -Properties UserPrincipalName)
    $UPNDistribution = $AllEnabledUsers |
        ForEach-Object {
            if ($_.UserPrincipalName) {
                ($_.UserPrincipalName -split "@")[1]
            } else {
                "NO_UPN_SET"
            }
        } |
        Group-Object |
        Sort-Object Count -Descending

    "Total enabled users analysed: $($AllEnabledUsers.Count)" | Out-File $ReportFile -Append
    "`nUPN suffix distribution:" | Out-File $ReportFile -Append

    foreach ($UPNGroup in $UPNDistribution) {
        $Percentage = [math]::Round(($UPNGroup.Count / $AllEnabledUsers.Count) * 100, 1)
        "  $($UPNGroup.Name): $($UPNGroup.Count) users ($Percentage%)" | Out-File $ReportFile -Append

        # Check for non-routable suffixes
        if ($UPNGroup.Name -match "\.local$|\.internal$|\.corp$|\.lan$") {
            "    WARNING: Non-routable suffix - may require Alternate Login ID" | Out-File $ReportFile -Append
        }
    }

    # Check for users without UPN
    $NoUPN = $UPNDistribution | Where-Object { $_.Name -eq "NO_UPN_SET" }
    if ($NoUPN) {
        "`nWARNING: $($NoUPN.Count) users have no UPN set" | Out-File $ReportFile -Append
        "These users may have authentication issues in Entra ID." | Out-File $ReportFile -Append
    }

    "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
    "  - Non-routable UPN suffixes (.local, .internal, etc.) cannot be verified in Entra" | Out-File $ReportFile -Append
    "  - Options: Add routable suffix to AD, or use Alternate Login ID (mail attribute)" | Out-File $ReportFile -Append
    "  - Ensure all UPN suffixes are registered as verified domains in Entra" | Out-File $ReportFile -Append

} catch {
    "Error analysing UPN suffixes: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Mail Attribute Analysis (Alternate Login ID)
Write-Section "MAIL ATTRIBUTE ANALYSIS - ALTERNATE LOGIN ID READINESS"
Write-Host "Analysing mail attribute for Alternate Login ID scenarios..." -ForegroundColor Yellow

try {
    $UsersWithMail = @(Get-ADUser -Filter {Enabled -eq $true} -Properties mail, UserPrincipalName)

    # Users without mail attribute
    $NoMailAttribute = @($UsersWithMail | Where-Object { -not $_.mail -or $_.mail -eq "" })

    # Users where mail differs from UPN (potential Alternate Login ID candidates)
    $MailDiffersFromUPN = @($UsersWithMail | Where-Object {
        $_.mail -and $_.UserPrincipalName -and
        ($_.mail -split "@")[1] -ne ($_.UserPrincipalName -split "@")[1]
    })

    "Total enabled users analysed: $($UsersWithMail.Count)" | Out-File $ReportFile -Append
    "Users without mail attribute: $($NoMailAttribute.Count)" | Out-File $ReportFile -Append
    "Users where mail domain differs from UPN domain: $($MailDiffersFromUPN.Count)" | Out-File $ReportFile -Append

    # Check for duplicate mail attributes
    Write-SubSection "Duplicate Mail Attributes"
    $MailGroups = $UsersWithMail | Where-Object { $_.mail } | Group-Object mail | Where-Object { $_.Count -gt 1 }
    $DuplicateMailCount = ($MailGroups | Measure-Object -Property Count -Sum).Sum
    $DuplicateMailAddresses = $MailGroups.Count

    if ($DuplicateMailAddresses -gt 0) {
        "Duplicate mail addresses found: $DuplicateMailAddresses unique addresses shared by $DuplicateMailCount users" | Out-File $ReportFile -Append
        "`nWARNING: Duplicate mail attributes will cause sync conflicts if using Alternate Login ID" | Out-File $ReportFile -Append
    } else {
        "No duplicate mail attributes found." | Out-File $ReportFile -Append
    }

    if ($NoMailAttribute.Count -gt 0) {
        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - $($NoMailAttribute.Count) users cannot use Alternate Login ID (no mail attribute)" | Out-File $ReportFile -Append
        "  - If using non-routable UPN, these users need mail attribute populated" | Out-File $ReportFile -Append

        "`nRECOMMENDATION:" | Out-File $ReportFile -Append
        "  - Populate mail attribute for all users who need cloud access" | Out-File $ReportFile -Append
        "  - Ensure mail attribute uses a verified domain in Entra" | Out-File $ReportFile -Append
    }
} catch {
    "Error analysing mail attributes: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region ProxyAddresses Conflicts
Write-Section "PROXYADDRESSES ANALYSIS - SYNC CONFLICT DETECTION"
Write-Host "Checking for proxyAddresses conflicts..." -ForegroundColor Yellow

try {
    $UsersWithProxy = @(Get-ADUser -Filter {Enabled -eq $true} -Properties proxyAddresses |
        Where-Object { $_.proxyAddresses })

    "Total enabled users with proxyAddresses: $($UsersWithProxy.Count)" | Out-File $ReportFile -Append

    # Extract primary SMTP addresses and check for duplicates
    $PrimarySMTP = @()
    foreach ($User in $UsersWithProxy) {
        $Primary = $User.proxyAddresses | Where-Object { $_ -clike "SMTP:*" }
        if ($Primary) {
            $PrimarySMTP += [PSCustomObject]@{
                Address = ($Primary -replace "SMTP:", "").ToLower()
            }
        }
    }

    $DuplicateSMTP = $PrimarySMTP | Group-Object Address | Where-Object { $_.Count -gt 1 }

    if ($DuplicateSMTP) {
        $TotalDuplicates = ($DuplicateSMTP | Measure-Object -Property Count -Sum).Sum
        "`nWARNING: Duplicate primary SMTP addresses detected" | Out-File $ReportFile -Append
        "Unique addresses with duplicates: $($DuplicateSMTP.Count)" | Out-File $ReportFile -Append
        "Total users affected: $TotalDuplicates" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - Duplicate proxyAddresses cause sync failures in Entra Connect" | Out-File $ReportFile -Append
        "  - Only one object can sync with each unique address" | Out-File $ReportFile -Append

        "`nRECOMMENDATION:" | Out-File $ReportFile -Append
        "  - Resolve duplicate addresses before migration" | Out-File $ReportFile -Append
        "  - Use IdFix tool to identify and remediate conflicts" | Out-File $ReportFile -Append
    } else {
        "No duplicate primary SMTP addresses found." | Out-File $ReportFile -Append
    }

    # Check for invalid characters in proxyAddresses
    $InvalidChars = @($UsersWithProxy | Where-Object {
        $_.proxyAddresses | Where-Object { $_ -match '[<>()\\,\[\]";]' }
    })

    if ($InvalidChars.Count -gt 0) {
        "`nWARNING: $($InvalidChars.Count) users have proxyAddresses with invalid characters" | Out-File $ReportFile -Append
        "These may cause sync issues and should be remediated." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking proxyAddresses: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Third-Party Password Filter DLLs
Write-Section "PASSWORD FILTER DLL CONFIGURATION"
Write-Host "Checking for third-party password filter DLLs..." -ForegroundColor Yellow

try {
    # Check the registry for password filter DLLs
    $LSAPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    $NotificationPackages = (Get-ItemProperty -Path $LSAPath -Name "Notification Packages" -ErrorAction SilentlyContinue)."Notification Packages"

    if ($NotificationPackages) {
        "Registered Password Filter DLLs (Notification Packages):" | Out-File $ReportFile -Append

        # Default Windows packages
        $DefaultPackages = @("scecli", "rassfm")
        $ThirdPartyPackages = @()

        foreach ($Package in $NotificationPackages) {
            if ($Package -in $DefaultPackages) {
                "  - $Package (Windows Default)" | Out-File $ReportFile -Append
            } else {
                "  - $Package (Third-Party/Custom)" | Out-File $ReportFile -Append
                $ThirdPartyPackages += $Package
            }
        }

        if ($ThirdPartyPackages.Count -gt 0) {
            "`nWARNING: Third-party password filter DLLs detected" | Out-File $ReportFile -Append
            "Total third-party/custom filters: $($ThirdPartyPackages.Count)" | Out-File $ReportFile -Append

            "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
            "  - Password filters enforce custom password requirements on-premises" | Out-File $ReportFile -Append
            "  - These filters do NOT apply to cloud password changes (SSPR)" | Out-File $ReportFile -Append
            "  - Password Writeback will trigger filter validation for on-prem changes" | Out-File $ReportFile -Append

            "`nCONSIDERATIONS:" | Out-File $ReportFile -Append
            "  - Ensure filter compatibility with Password Writeback" | Out-File $ReportFile -Append
            "  - Test SSPR -> Writeback flow before migration" | Out-File $ReportFile -Append
            "  - Configure Entra Banned Password List to mirror filter rules where possible" | Out-File $ReportFile -Append
            "  - Some filters may need updates for Writeback compatibility" | Out-File $ReportFile -Append

            # Common third-party filters
            $KnownFilters = @{
                "passfilt" = "Microsoft Strong Password Filter"
                "pGina" = "pGina Credential Provider"
                "nFront" = "nFront Password Filter"
                "Specops" = "Specops Password Policy"
                "Anixis" = "Anixis Password Policy Enforcer"
                "Enzoic" = "Enzoic Password Filter"
            }

            foreach ($Package in $ThirdPartyPackages) {
                foreach ($Known in $KnownFilters.Keys) {
                    if ($Package -match $Known) {
                        "  Detected: $($KnownFilters[$Known]) ($Package)" | Out-File $ReportFile -Append
                    }
                }
            }
        } else {
            "`nNo third-party password filter DLLs detected." | Out-File $ReportFile -Append
            "Only default Windows password filters are in use." | Out-File $ReportFile -Append
        }
    } else {
        "Unable to retrieve password filter configuration." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking password filter DLLs: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Account Expiration Statistics
Write-Section "ACCOUNTS WITH EXPIRATION SET - STATISTICS"
Write-Host "Checking accounts with expiration dates..." -ForegroundColor Yellow

$ExpiringAccounts = @(Get-ADUser -Filter {AccountExpirationDate -like "*" -and Enabled -eq $true} -Properties AccountExpirationDate)

if ($ExpiringAccounts) {
    "Total enabled accounts with expiration: $($ExpiringAccounts.Count)" | Out-File $ReportFile -Append

    # Group by expiration timeframe
    $Now = Get-Date
    $Next30Days = @($ExpiringAccounts | Where-Object {$_.AccountExpirationDate -le $Now.AddDays(30) -and $_.AccountExpirationDate -gt $Now})
    $Next90Days = @($ExpiringAccounts | Where-Object {$_.AccountExpirationDate -le $Now.AddDays(90) -and $_.AccountExpirationDate -gt $Now.AddDays(30)})
    $Beyond90Days = @($ExpiringAccounts | Where-Object {$_.AccountExpirationDate -gt $Now.AddDays(90)})
    $AlreadyExpired = @($ExpiringAccounts | Where-Object {$_.AccountExpirationDate -le $Now})

    "`nBreakdown by timeframe:" | Out-File $ReportFile -Append
    "  Already expired: $($AlreadyExpired.Count)" | Out-File $ReportFile -Append
    "  Expiring within 30 days: $($Next30Days.Count)" | Out-File $ReportFile -Append
    "  Expiring within 31-90 days: $($Next90Days.Count)" | Out-File $ReportFile -Append
    "  Expiring beyond 90 days: $($Beyond90Days.Count)" | Out-File $ReportFile -Append

    "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
    "  - accountExpires attribute does NOT sync to Entra" | Out-File $ReportFile -Append
    "  - Expired AD accounts will remain active in Entra" | Out-File $ReportFile -Append

    "`nRECOMMENDATION:" | Out-File $ReportFile -Append
    "  - Implement automation to disable Entra accounts when AD accounts expire" | Out-File $ReportFile -Append
    "  - Consider Azure Automation runbook or Logic App for this purpose" | Out-File $ReportFile -Append
} else {
    "No enabled accounts with expiration dates found." | Out-File $ReportFile -Append
}
#endregion

#region Password Never Expires Statistics
Write-Section "ACCOUNTS WITH 'PASSWORD NEVER EXPIRES' FLAG - STATISTICS"
Write-Host "Checking accounts with password never expires..." -ForegroundColor Yellow

$NeverExpireUsers = @(Get-ADUser -Filter {PasswordNeverExpires -eq $true -and Enabled -eq $true} -Properties PasswordNeverExpires)

"Total enabled accounts with password never expires: $($NeverExpireUsers.Count)" | Out-File $ReportFile -Append

"`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
"  - When CloudPasswordPolicyForPasswordSyncedUsersEnabled is enabled, these accounts" | Out-File $ReportFile -Append
"    will have cloud password expiry enforced UNLESS DisablePasswordExpiration is set" | Out-File $ReportFile -Append

"`nRECOMMENDATION:" | Out-File $ReportFile -Append
"  - For service accounts: Set DisablePasswordExpiration policy in Entra" | Out-File $ReportFile -Append
"  - Review if PasswordNeverExpires is still appropriate for each account" | Out-File $ReportFile -Append
#endregion

#region Service Account Statistics
Write-Section "POTENTIAL SERVICE ACCOUNTS - STATISTICS"
Write-Host "Identifying potential service accounts..." -ForegroundColor Yellow

$ServiceAccounts = @(Get-ADUser -Filter {
    PasswordNeverExpires -eq $true -and
    Enabled -eq $true
} -Properties ServicePrincipalName | Where-Object {$_.ServicePrincipalName})

"Total accounts with both PasswordNeverExpires and ServicePrincipalName: $($ServiceAccounts.Count)" | Out-File $ReportFile -Append

"`nNote: These accounts will require DisablePasswordExpiration in Entra after" | Out-File $ReportFile -Append
"enabling CloudPasswordPolicyForPasswordSyncedUsersEnabled." | Out-File $ReportFile -Append
#endregion

#region Managed Service Accounts (gMSA and sMSA)
Write-Section "MANAGED SERVICE ACCOUNTS - gMSA AND sMSA"
Write-Host "Checking for Managed Service Accounts..." -ForegroundColor Yellow

try {
    # Get all service accounts (gMSA and sMSA)
    $AllServiceAccounts = @(Get-ADServiceAccount -Filter *)

    if ($AllServiceAccounts.Count -gt 0) {
        # Separate gMSA from sMSA
        $gMSAs = @($AllServiceAccounts | Where-Object { $_.ObjectClass -eq "msDS-GroupManagedServiceAccount" })
        $sMSAs = @($AllServiceAccounts | Where-Object { $_.ObjectClass -eq "msDS-ManagedServiceAccount" })

        "Total Managed Service Accounts: $($AllServiceAccounts.Count)" | Out-File $ReportFile -Append
        "  Group Managed Service Accounts (gMSA): $($gMSAs.Count)" | Out-File $ReportFile -Append
        "  Standalone Managed Service Accounts (sMSA): $($sMSAs.Count)" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - gMSA and sMSA accounts do NOT sync to Entra ID" | Out-File $ReportFile -Append
        "  - These accounts have automatically managed passwords" | Out-File $ReportFile -Append
        "  - No password hash is available for PHS sync" | Out-File $ReportFile -Append

        "`nNOTE:" | Out-File $ReportFile -Append
        "  - This is expected behaviour - MSAs are for on-premises services only" | Out-File $ReportFile -Append
        "  - Services using MSAs will continue to work on-premises" | Out-File $ReportFile -Append
        "  - For cloud workloads, use Managed Identities in Azure" | Out-File $ReportFile -Append
    } else {
        "No Managed Service Accounts (gMSA/sMSA) found." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking Managed Service Accounts: $($_.Exception.Message)" | Out-File $ReportFile -Append
    "Note: Get-ADServiceAccount requires appropriate permissions and AD schema." | Out-File $ReportFile -Append
}
#endregion

#region Logon Hours Restrictions
Write-Section "ACCOUNTS WITH LOGON HOURS RESTRICTIONS - STATISTICS"
Write-Host "Checking accounts with logon hours restrictions..." -ForegroundColor Yellow

$UsersWithLogonHours = @(Get-ADUser -Filter * -Properties LogonHours | Where-Object {$null -ne $_.LogonHours})

if ($UsersWithLogonHours) {
    "Total accounts with logon hours restrictions: $($UsersWithLogonHours.Count)" | Out-File $ReportFile -Append

    "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
    "  - Logon hours restrictions do NOT apply to cloud authentication" | Out-File $ReportFile -Append
    "  - Users can sign in to Entra/M365 outside their permitted AD hours" | Out-File $ReportFile -Append

    "`nRECOMMENDATION:" | Out-File $ReportFile -Append
    "  - Use Conditional Access policies to enforce time-based restrictions in cloud" | Out-File $ReportFile -Append
} else {
    "No accounts with logon hours restrictions found." | Out-File $ReportFile -Append
}
#endregion

#region Smart Card Required Accounts
Write-Section "ACCOUNTS WITH SMART CARD REQUIRED FOR INTERACTIVE LOGON - STATISTICS"
Write-Host "Checking accounts requiring smart card..." -ForegroundColor Yellow

$SmartCardUsers = @(Get-ADUser -Filter {SmartcardLogonRequired -eq $true} -Properties SmartcardLogonRequired)

if ($SmartCardUsers) {
    "Total accounts requiring smart card: $($SmartCardUsers.Count)" | Out-File $ReportFile -Append

    "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
    "  - Smart card required users have randomised passwords in AD" | Out-File $ReportFile -Append
    "  - PHS will sync this random password hash" | Out-File $ReportFile -Append
    "  - Users CANNOT use password auth for cloud services" | Out-File $ReportFile -Append

    "`nNOTE:" | Out-File $ReportFile -Append
    "  - Certificate-based authentication (CBA) should be configured in Entra" | Out-File $ReportFile -Append
    "  - Or FIDO2 security keys as an alternative" | Out-File $ReportFile -Append
} else {
    "No smart card required accounts found." | Out-File $ReportFile -Append
}
#endregion

#region User Cannot Change Password
Write-Section "ACCOUNTS WITH 'USER CANNOT CHANGE PASSWORD' FLAG - STATISTICS"
Write-Host "Checking accounts that cannot change their password..." -ForegroundColor Yellow

try {
    # CannotChangePassword is a computed property, need to check via Get-ADUser
    $CannotChangePassword = @(Get-ADUser -Filter {Enabled -eq $true} -Properties CannotChangePassword |
        Where-Object { $_.CannotChangePassword -eq $true })

    if ($CannotChangePassword.Count -gt 0) {
        "Total enabled accounts that cannot change password: $($CannotChangePassword.Count)" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - These users CANNOT use Self-Service Password Reset (SSPR)" | Out-File $ReportFile -Append
        "  - Password Writeback will fail for these accounts" | Out-File $ReportFile -Append
        "  - Users must contact helpdesk for all password changes" | Out-File $ReportFile -Append

        "`nRECOMMENDATION:" | Out-File $ReportFile -Append
        "  - Review if this restriction is still required" | Out-File $ReportFile -Append
        "  - Consider removing flag to enable SSPR self-service" | Out-File $ReportFile -Append
        "  - Document exceptions for helpdesk awareness" | Out-File $ReportFile -Append
    } else {
        "No enabled accounts with 'cannot change password' restriction found." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking cannot-change-password accounts: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Account is Sensitive and Cannot Be Delegated
Write-Section "ACCOUNTS WITH 'SENSITIVE AND CANNOT BE DELEGATED' FLAG - STATISTICS"
Write-Host "Checking accounts marked as sensitive..." -ForegroundColor Yellow

try {
    $SensitiveAccounts = @(Get-ADUser -Filter {AccountNotDelegated -eq $true -and Enabled -eq $true} -Properties AccountNotDelegated)

    if ($SensitiveAccounts.Count -gt 0) {
        "Total enabled accounts marked as sensitive: $($SensitiveAccounts.Count)" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - These accounts cannot be impersonated via Kerberos delegation" | Out-File $ReportFile -Append
        "  - This is a security feature, typically for privileged accounts" | Out-File $ReportFile -Append
        "  - PHS sync works normally for these accounts" | Out-File $ReportFile -Append

        "`nNOTE:" | Out-File $ReportFile -Append
        "  - Applications using delegation cannot act on behalf of these users" | Out-File $ReportFile -Append
        "  - This may affect some legacy application workflows" | Out-File $ReportFile -Append
        "  - Cloud apps using modern auth are not affected" | Out-File $ReportFile -Append
    } else {
        "No enabled accounts with 'sensitive and cannot be delegated' flag found." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking sensitive accounts: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region DES-Only Encryption Accounts
Write-Section "ACCOUNTS WITH DES-ONLY ENCRYPTION - STATISTICS"
Write-Host "Checking for accounts using DES-only encryption..." -ForegroundColor Yellow

try {
    $DESOnlyAccounts = @(Get-ADUser -Filter {UseDESKeyOnly -eq $true -and Enabled -eq $true} -Properties UseDESKeyOnly)

    if ($DESOnlyAccounts.Count -gt 0) {
        "Total enabled accounts with DES-only encryption: $($DESOnlyAccounts.Count)" | Out-File $ReportFile -Append

        "`nWARNING: DES encryption is deprecated and insecure" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - DES is an extremely weak encryption algorithm" | Out-File $ReportFile -Append
        "  - These accounts may have compatibility issues with modern systems" | Out-File $ReportFile -Append
        "  - PHS can sync these accounts but security is compromised" | Out-File $ReportFile -Append

        "`nRECOMMENDATION:" | Out-File $ReportFile -Append
        "  - Disable 'Use DES encryption types' flag on these accounts" | Out-File $ReportFile -Append
        "  - Update to AES encryption (default for modern AD)" | Out-File $ReportFile -Append
        "  - Users will need to change password after flag removal" | Out-File $ReportFile -Append
        "  - Investigate why DES was enabled (very old accounts or legacy apps)" | Out-File $ReportFile -Append
    } else {
        "No enabled accounts with DES-only encryption found." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking DES-only accounts: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Currently Locked Accounts
Write-Section "CURRENTLY LOCKED ACCOUNTS - STATISTICS"
Write-Host "Checking currently locked accounts..." -ForegroundColor Yellow

$LockedAccounts = @(Search-ADAccount -LockedOut)

if ($LockedAccounts) {
    "Total currently locked accounts: $($LockedAccounts.Count)" | Out-File $ReportFile -Append

    "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
    "  - Account lockout status does NOT sync to Entra" | Out-File $ReportFile -Append
    "  - AD lockout = User can still sign in to cloud" | Out-File $ReportFile -Append
    "  - Entra Smart Lockout provides independent cloud-side protection" | Out-File $ReportFile -Append
} else {
    "No currently locked accounts found." | Out-File $ReportFile -Append
}
#endregion

#region Password Age Statistics
Write-Section "PASSWORD AGE STATISTICS - AGGREGATED DATA"
Write-Host "Calculating password age statistics..." -ForegroundColor Yellow

$AllUsers = @(Get-ADUser -Filter {Enabled -eq $true} -Properties PasswordLastSet, PasswordNeverExpires |
    Where-Object {$_.PasswordNeverExpires -eq $false})

if ($AllUsers) {
    $PasswordAges = $AllUsers | ForEach-Object {
        if ($_.PasswordLastSet) {
            (New-TimeSpan -Start $_.PasswordLastSet -End (Get-Date)).Days
        }
    } | Where-Object {$_ -ne $null}

    "Total enabled users analysed (excluding PasswordNeverExpires): $($AllUsers.Count)" | Out-File $ReportFile -Append

    if ($PasswordAges) {
        $Stats = $PasswordAges | Measure-Object -Average -Maximum -Minimum
        "`nPassword age statistics:" | Out-File $ReportFile -Append
        "  Average password age: $([math]::Round($Stats.Average, 0)) days" | Out-File $ReportFile -Append
        "  Oldest password: $($Stats.Maximum) days" | Out-File $ReportFile -Append
        "  Newest password: $($Stats.Minimum) days" | Out-File $ReportFile -Append

        # Distribution analysis
        $Age0to30 = ($PasswordAges | Where-Object {$_ -le 30}).Count
        $Age31to60 = ($PasswordAges | Where-Object {$_ -gt 30 -and $_ -le 60}).Count
        $Age61to90 = ($PasswordAges | Where-Object {$_ -gt 60 -and $_ -le 90}).Count
        $Age91Plus = ($PasswordAges | Where-Object {$_ -gt 90}).Count

        "`nPassword age distribution:" | Out-File $ReportFile -Append
        "  0-30 days: $Age0to30 users" | Out-File $ReportFile -Append
        "  31-60 days: $Age31to60 users" | Out-File $ReportFile -Append
        "  61-90 days: $Age61to90 users" | Out-File $ReportFile -Append
        "  91+ days: $Age91Plus users" | Out-File $ReportFile -Append

        # Check passwords expiring soon based on domain policy
        Write-SubSection "Passwords Expiring Before Migration"
        $MaxPasswordAgeDays = $DefaultPolicy.MaxPasswordAge.Days

        if ($MaxPasswordAgeDays -gt 0) {
            # Users whose passwords will expire within 14 days of now
            $ExpiringWithin14Days = @($AllUsers | Where-Object {
                $_.PasswordLastSet -and
                ((New-TimeSpan -Start $_.PasswordLastSet -End (Get-Date)).Days + 14) -ge $MaxPasswordAgeDays
            })

            # Users whose passwords will expire within 30 days
            $ExpiringWithin30Days = @($AllUsers | Where-Object {
                $_.PasswordLastSet -and
                ((New-TimeSpan -Start $_.PasswordLastSet -End (Get-Date)).Days + 30) -ge $MaxPasswordAgeDays
            })

            "Domain password max age: $MaxPasswordAgeDays days" | Out-File $ReportFile -Append
            "Passwords expiring within 14 days: $($ExpiringWithin14Days.Count)" | Out-File $ReportFile -Append
            "Passwords expiring within 30 days: $($ExpiringWithin30Days.Count)" | Out-File $ReportFile -Append

            if ($ExpiringWithin14Days.Count -gt 0) {
                "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
                "  - $($ExpiringWithin14Days.Count) users may be forced to change password during migration" | Out-File $ReportFile -Append
                "  - Consider timing migration to avoid peak password expiry periods" | Out-File $ReportFile -Append
            }
        } else {
            "Domain policy does not enforce password expiry (MaxPasswordAge = 0)." | Out-File $ReportFile -Append
        }
    }
} else {
    "No enabled users found for password age analysis." | Out-File $ReportFile -Append
}
#endregion

#region User Account Statistics
Write-Section "USER ACCOUNT STATISTICS - COUNTS ONLY"
Write-Host "Collecting user account statistics..." -ForegroundColor Yellow

$AllEnabledUsers = @(Get-ADUser -Filter {Enabled -eq $true})
$AllDisabledUsers = @(Get-ADUser -Filter {Enabled -eq $false})

"Total enabled user accounts: $($AllEnabledUsers.Count)" | Out-File $ReportFile -Append
"Total disabled user accounts: $($AllDisabledUsers.Count)" | Out-File $ReportFile -Append
#endregion

#region Organisational Unit Structure
Write-Section "ORGANISATIONAL UNIT STRUCTURE - HIGH LEVEL"
Write-Host "Collecting OU structure information..." -ForegroundColor Yellow

$OUs = @(Get-ADOrganizationalUnit -Filter *)
"Total Organisational Units: $($OUs.Count)" | Out-File $ReportFile -Append

# Top-level OUs only (direct children of domain root)
$TopLevelOUs = @($OUs | Where-Object {
    $_.DistinguishedName -match "^OU=[^,]+,$($Domain.DistinguishedName)$"
})
"Top-level OUs: $($TopLevelOUs.Count)" | Out-File $ReportFile -Append
#endregion

#region Linked Mailbox Users (Resource Forest Scenarios)
Write-Section "LINKED MAILBOX USERS - RESOURCE FOREST DETECTION"
Write-Host "Checking for linked mailbox users..." -ForegroundColor Yellow

try {
    # Linked mailboxes have msExchMasterAccountSid attribute populated
    $LinkedMailboxUsers = @(Get-ADUser -Filter {Enabled -eq $true} -Properties msExchMasterAccountSid |
        Where-Object { $_.msExchMasterAccountSid })

    if ($LinkedMailboxUsers.Count -gt 0) {
        "Total enabled users with linked mailboxes: $($LinkedMailboxUsers.Count)" | Out-File $ReportFile -Append

        "`nIMPACT FOR PHS:" | Out-File $ReportFile -Append
        "  - Linked mailbox users authenticate via a separate account forest" | Out-File $ReportFile -Append
        "  - The resource forest user object is linked to an account forest identity" | Out-File $ReportFile -Append
        "  - PHS must be configured in the account forest, not the resource forest" | Out-File $ReportFile -Append

        "`nRECOMMENDATION:" | Out-File $ReportFile -Append
        "  - Ensure Entra Connect is configured in the account forest" | Out-File $ReportFile -Append
        "  - Review linked mailbox architecture for cloud migration strategy" | Out-File $ReportFile -Append
        "  - Consider consolidating to a single forest during cloud migration" | Out-File $ReportFile -Append
    } else {
        "No linked mailbox users found (not a resource forest scenario)." | Out-File $ReportFile -Append
    }
} catch {
    "Error checking for linked mailbox users: $($_.Exception.Message)" | Out-File $ReportFile -Append
}
#endregion

#region Critical Findings Summary
Write-Section "CRITICAL FINDINGS SUMMARY"

$CriticalFindings = @()
$Warnings = @()
$Info = @()

# Check for must change password
try {
    $MustChangeCount = @(Get-ADUser -Filter {Enabled -eq $true} -Properties pwdLastSet | Where-Object { $_.pwdLastSet -eq 0 }).Count
    if ($MustChangeCount -gt 0) {
        $Warnings += "$MustChangeCount users must change password at next logon (pwdLastSet=0)"
    }
} catch {}

# Check for reversible encryption
try {
    $ReversibleCount = @(Get-ADUser -Filter {Enabled -eq $true -and AllowReversiblePasswordEncryption -eq $true}).Count
    if ($ReversibleCount -gt 0) {
        $Warnings += "$ReversibleCount users have reversible encryption enabled"
    }
} catch {}

# Check for non-routable UPN suffixes
try {
    $NonRoutableUPNs = @(Get-ADUser -Filter {Enabled -eq $true} -Properties UserPrincipalName |
        Where-Object { $_.UserPrincipalName -match "\.local$|\.internal$|\.corp$|\.lan$" })
    if ($NonRoutableUPNs.Count -gt 0) {
        $CriticalFindings += "$($NonRoutableUPNs.Count) users have non-routable UPN suffixes"
    }
} catch {}

# Check for third-party password filters
try {
    $LSAPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    $NotificationPackages = (Get-ItemProperty -Path $LSAPath -Name "Notification Packages" -ErrorAction SilentlyContinue)."Notification Packages"
    $DefaultPackages = @("scecli", "rassfm")
    $ThirdParty = @($NotificationPackages | Where-Object { $_ -notin $DefaultPackages })
    if ($ThirdParty.Count -gt 0) {
        $Warnings += "$($ThirdParty.Count) third-party password filter DLL(s) detected"
    }
} catch {}

# Check for account expiration
try {
    $ExpiringCount = @(Get-ADUser -Filter {AccountExpirationDate -like "*" -and Enabled -eq $true}).Count
    if ($ExpiringCount -gt 0) {
        $Info += "$ExpiringCount accounts have expiration dates (won't sync to Entra)"
    }
} catch {}

# Check for users who cannot change password (SSPR impact)
try {
    $CannotChangePwdCount = @(Get-ADUser -Filter {Enabled -eq $true} -Properties CannotChangePassword |
        Where-Object { $_.CannotChangePassword -eq $true }).Count
    if ($CannotChangePwdCount -gt 0) {
        $Warnings += "$CannotChangePwdCount users cannot change password (SSPR will not work)"
    }
} catch {}

# Check for DES-only encryption accounts
try {
    $DESCount = @(Get-ADUser -Filter {UseDESKeyOnly -eq $true -and Enabled -eq $true}).Count
    if ($DESCount -gt 0) {
        $Warnings += "$DESCount users have DES-only encryption (deprecated/insecure)"
    }
} catch {}

# Check for duplicate proxyAddresses
try {
    $ProxyUsers = @(Get-ADUser -Filter {Enabled -eq $true} -Properties proxyAddresses | Where-Object { $_.proxyAddresses })
    $PrimarySMTPAddresses = @()
    foreach ($User in $ProxyUsers) {
        $Primary = $User.proxyAddresses | Where-Object { $_ -clike "SMTP:*" }
        if ($Primary) { $PrimarySMTPAddresses += ($Primary -replace "SMTP:", "").ToLower() }
    }
    $DupeSMTP = $PrimarySMTPAddresses | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($DupeSMTP.Count -gt 0) {
        $CriticalFindings += "$($DupeSMTP.Count) duplicate primary SMTP addresses (will cause sync failures)"
    }
} catch {}

# Check for users without mail attribute (Alternate Login ID readiness)
try {
    $NoMailCount = @(Get-ADUser -Filter {Enabled -eq $true} -Properties mail | Where-Object { -not $_.mail }).Count
    # Only flag if there are also non-routable UPNs (indicates Alternate Login ID may be needed)
    if ($NoMailCount -gt 0 -and $NonRoutableUPNs.Count -gt 0) {
        $Info += "$NoMailCount users missing mail attribute (needed for Alternate Login ID)"
    }
} catch {}

# Check for linked mailbox users (resource forest)
try {
    $LinkedCount = @(Get-ADUser -Filter {Enabled -eq $true} -Properties msExchMasterAccountSid |
        Where-Object { $_.msExchMasterAccountSid }).Count
    if ($LinkedCount -gt 0) {
        $Warnings += "$LinkedCount linked mailbox users detected (resource forest scenario)"
    }
} catch {}

# Check for Kerberos delegation
try {
    $UnconstrainedDelCount = @(Get-ADUser -Filter {TrustedForDelegation -eq $true -and Enabled -eq $true}).Count
    $ProtocolTransCount = @(Get-ADUser -Filter {TrustedToAuthForDelegation -eq $true -and Enabled -eq $true}).Count
    $ConstrainedDelCount = @(Get-ADUser -Filter {Enabled -eq $true} -Properties 'msDS-AllowedToDelegateTo' |
        Where-Object { $_.'msDS-AllowedToDelegateTo' }).Count
    $TotalDelUsers = $UnconstrainedDelCount + $ProtocolTransCount + $ConstrainedDelCount
    if ($TotalDelUsers -gt 0) {
        $Info += "$TotalDelUsers users have Kerberos delegation configured (review for cloud migration)"
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
    "Active Directory configuration appears ready for PHS migration." | Out-File $ReportFile -Append
}
#endregion

#region Script Completion
Write-Host "`nAssessment complete. Report saved to: $ReportFile" -ForegroundColor Green
Write-Host "This report contains NO personally identifiable information (PII)." -ForegroundColor Cyan
Write-Host "Only aggregate statistics and policy configurations have been collected." -ForegroundColor Cyan
#endregion
