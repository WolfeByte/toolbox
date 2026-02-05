# EntraConnectConfig.ps1

Collects Entra Connect server configuration for PHS migration assessment.

## Where to Run
On the **Entra Connect server** (the server running Azure AD Connect / Microsoft Entra Connect).

## Requirements
- ADSync PowerShell module (installed with Entra Connect)
- Local administrator on the Entra Connect server
- Optional: Microsoft.Graph module for cloud-side feature verification

## What It Collects
| Category | Details |
|----------|---------|
| Version Info | Entra Connect version, ADSync module version |
| Staging Mode | Whether server is active or standby |
| Auth Features | PHS, PTA, SSO, Password Writeback status |
| Connectors | AD and Entra ID connector configuration |
| Password Sync | Per-connector password sync status |
| Sync Errors | Recent export/import/sync errors |
| Sync Rules | Custom rules that may affect password sync |
| FIPS | FIPS mode status (blocks PHS if enabled) |
| TLS | TLS 1.2 configuration status |

## Output
`C:\Temp\PHSAssessment\EntraConnect_Config_[timestamp].txt`

## Privacy
No PII collected. Only configuration settings and error counts.
