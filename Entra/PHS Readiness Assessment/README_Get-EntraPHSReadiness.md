# Get-EntraPHSReadiness.ps1

Collects Microsoft Entra ID configuration for PHS migration assessment.

## Where to Run
Any machine with internet access and Microsoft Graph PowerShell modules.

## Requirements
- Microsoft.Graph.Beta.Identity.DirectoryManagement module
- Microsoft.Graph.Beta.Users module
- Global Reader role (minimum) in Entra ID

## What It Collects
| Category | Details |
|----------|---------|
| Licensing | P1/P2 availability for Identity Protection |
| Sync Features | CloudPasswordPolicy, ForcePasswordChange settings |
| Domains | Managed vs Federated, federation endpoints |
| Staged Rollout | Current rollout policies for gradual migration |
| PTA Agents | Pass-Through Authentication agent inventory |
| SSPR | Self-Service Password Reset configuration |
| Identity Protection | Risk policies, risky user counts (P2) |
| Conditional Access | Policy summary and grant controls |
| Named Locations | Locations affecting Smart Lockout behaviour |
| Devices | Hybrid Entra Joined device count |
| Password Protection | Smart Lockout, banned password list |
| User Statistics | Synced vs cloud-only user counts |

## Output
`C:\Temp\PHSAssessment\Entra_Assessment_[timestamp].txt`

## Privacy
No PII collected. Only aggregate statistics and policy configurations.
