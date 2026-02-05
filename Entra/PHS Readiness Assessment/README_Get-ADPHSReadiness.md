# ADPasswordPolicyConfig.ps1

Collects Active Directory password policy and user attribute configuration for PHS migration assessment.

## Where to Run
On a **Domain Controller** or machine with RSAT and AD access.

## Requirements
- ActiveDirectory PowerShell module
- Read access to Active Directory

## What It Collects
| Category | Details |
|----------|---------|
| Domain Info | Domain/forest functional levels |
| Password Policies | Default policy and Fine-Grained Password Policies |
| Must Change Password | Users with pwdLastSet=0 (won't sync without feature enabled) |
| Never Set Password | Users who have never set a password |
| Reversible Encryption | Users storing passwords with reversible encryption |
| Protected Users | Members of Protected Users group |
| Privileged Accounts | Users with adminCount=1 |
| UPN Suffixes | Distribution and non-routable suffix detection |
| Password Filters | Third-party password filter DLLs |
| Account Expiration | Accounts with expiry dates (won't sync to Entra) |
| Password Statistics | Age distribution, never expires count |

## Output
`C:\Temp\PHSAssessment\AD_Assessment_[timestamp].txt`

## Privacy
No PII collected. Only aggregate counts and policy settings.
