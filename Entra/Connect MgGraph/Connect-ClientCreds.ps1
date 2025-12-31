<#
.SYNOPSIS
    Test connecting to Microsoft Graph and using client credentials and verify app permissions

.DESCRIPTION
    This script authenticates to Microsoft Graph using client credentials and validates the service 
    principal’s permissions by executing a simple Get-MgUser call. It verifies and reports 
    the service principal’s app roles and permission scopes granted that you can use for further operations.

.NOTES
    Author: Benjamin Wolfe
    Date: December 31, 2025
    Version: 1.0
    Requires: Microsoft.Graph PowerShell module
#>

# Connect to Microsoft Graph

# Prompt for credentials
$TenantID = Read-Host -Prompt "Enter your Tenant ID"
$ClientID = Read-Host -Prompt "Enter your Client ID"
$ClientSecret = Read-Host -Prompt "Enter your Client Secret" -AsSecureString

# Create a credential object
$ClientSecretCredential = New-Object System.Management.Automation.PSCredential ($ClientID, $ClientSecret)

# Connect to Microsoft Graph with the Tenant ID provided and no welcome message
Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -TenantId $TenantID -ClientSecretCredential $ClientSecretCredential -NoWelcome

# Check permissions and scopes
Write-Host "`nChecking app permissions..." -ForegroundColor Yellow

# Get the current context to see what scopes are available
$context = Get-MgContext
Write-Host "Connected as: $($context.Account)" -ForegroundColor Green
Write-Host "Scopes granted: $($context.Scopes -join ', ')" -ForegroundColor Green

# Get the service principal for this app to see its permissions
try {
    $servicePrincipal = Get-MgServicePrincipal -Filter "AppId eq '$ClientID'"
    if ($servicePrincipal) {
        Write-Host "`nService Principal Details:" -ForegroundColor Cyan
        Write-Host "Display Name: $($servicePrincipal.DisplayName)"
        Write-Host "App ID: $($servicePrincipal.AppId)"

        # Get app role assignments (application permissions)
        $appRoleAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $servicePrincipal.Id
        if ($appRoleAssignments) {
            Write-Host "`nApplication Permissions (App Roles):" -ForegroundColor Cyan
            foreach ($assignment in $appRoleAssignments) {
                $resourceSP = Get-MgServicePrincipal -ServicePrincipalId $assignment.ResourceId -ErrorAction SilentlyContinue
                if ($resourceSP) {
                    $appRole = $resourceSP.AppRoles | Where-Object { $_.Id -eq $assignment.AppRoleId }
                    Write-Host "  - $($appRole.Value) on $($resourceSP.DisplayName)" -ForegroundColor White
                }
            }
        } else {
            Write-Host "No application permissions found." -ForegroundColor Yellow
        }
    } else {
        Write-Host "Service principal not found for Client ID: $ClientID" -ForegroundColor Red
    }
} catch {
    Write-Host "Error retrieving service principal information: $($_.Exception.Message)" -ForegroundColor Red
}

# Test a simple permission by trying to read basic directory info
Write-Host "`nTesting permissions with a simple query..." -ForegroundColor Yellow
try {
    $testUser = Get-MgUser -Top 1 -ErrorAction Stop
    Write-Host "✓ Successfully queried users - User.Read permissions are working" -ForegroundColor Green
} catch {
    Write-Host "✗ Failed to query users: $($_.Exception.Message)" -ForegroundColor Red
}

# Get the service principal count
$spCount = Get-MgServicePrincipal -All| Measure-Object
Write-Host "Number of service principals: $($spCount.Count)"

# Disconnect from Microsoft Graph
Disconnect-MgGraph
