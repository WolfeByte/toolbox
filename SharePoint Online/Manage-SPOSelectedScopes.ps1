<#
.SYNOPSIS
    Grant granular, resource-specific permissions to service principals in SharePoint Online using Selective Scopes.
    Instead of granting all permissions to a service principal, you can grant only the permissions it needs, at the site, list, or item level.
    This is useful for security and compliance, as it limits the access of service principals to only what they need access to.
    See https://learn.microsoft.com/en-us/graph/permissions-selected-overview for more information.
.DESCRIPTION
    This script performs the following operations:
    1. Connects to Microsoft Graph with required scopes Directory.ReadWrite.All and Sites.FullControl.All
    2. Retrieves a SharePoint site by its URL
    3. Retrieves a service principal, managed identity, or enterprise application by name
    4. Grants selected Graph API permission to the service principal
    5. Grants the service principal permission to the SharePoint site
    7. Lists all permissions for the service principal and SharePoint site
    8. Removes permission from the SharePoint site for the service principal
.NOTES
    Author: Benjamin Wolfe
    Date: May 11, 2025
    Requires: Microsoft.Graph PowerShell modules
    Required Permissions: Directory.ReadWrite.All, Sites.FullControl.All
    
    TERMINOLOGY:
    - Service Principal: An identity used by applications/services to access resources
    - Managed Identity: A special type of service principal managed by Azure
    - Enterprise Application: How service principals appear in the Entra ID portal
    - Application Registration: The definition of an application in Entra ID
    
    All these objects are represented as service principals in Microsoft Graph API.
#>

# Check and install required modules
$requiredModules = @("Microsoft.Graph.Authentication", "Microsoft.Graph.Sites", "Microsoft.Graph.Applications")
foreach ($module in $requiredModules) {
    if (-not (Get-Module -Name $module -ListAvailable)) {
        Write-Host "Installing required module: $module..." -ForegroundColor Yellow
        Install-Module -Name $module -Scope CurrentUser -Force
    }
}

# Import required modules
Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Sites
Import-Module Microsoft.Graph.Applications

# Track if permissions were newly added
$script:graphPermissionWasNew = $false
$script:sitePermissionWasNew = $false

# Function to format and display messages consistently
function Write-StatusMessage {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Type = "Info"
    )
    
    switch ($Type) {
        "Info" {
            # Check if this message is about selected permissions
            if ($Message -like "*Selected Graph API permission scope:*") {
                $parts = $Message -split "Selected Graph API permission scope: "
                Write-Host "[INFO] Selected Graph API permission scope: " -ForegroundColor Cyan -NoNewline
                Write-Host $parts[1] -ForegroundColor Magenta
            }
            elseif ($Message -like "*Selected SharePoint permission role:*") {
                $parts = $Message -split "Selected SharePoint permission role: "
                Write-Host "[INFO] Selected SharePoint permission role: " -ForegroundColor Cyan -NoNewline
                Write-Host $parts[1] -ForegroundColor Yellow
            }
            elseif ($Message -like "*Getting SharePoint site with ID:*") {
                Write-Host "[INFO] $Message" -ForegroundColor Cyan
            }
            elseif ($Message -like "*Permission '*' is already assigned to*" -or $Message -like "*The Graph permission '*' is already assigned to*") {
                if ($Message -like "*The Graph permission '*' is already assigned to*") {
                    $parts = $Message -split "The Graph permission '"
                } else {
                    $parts = $Message -split "Permission '"
                }
                $parts2 = $parts[1] -split "' is already assigned to "
                Write-Host "[INFO] " -ForegroundColor Cyan -NoNewline
                if ($Message -like "*The Graph permission '*' is already assigned to*") {
                    Write-Host "The Graph permission '" -ForegroundColor Cyan -NoNewline
                } else {
                    Write-Host "Permission '" -ForegroundColor Cyan -NoNewline
                }
                Write-Host $parts2[0] -ForegroundColor Magenta -NoNewline
                Write-Host "' is already assigned to " -ForegroundColor Cyan -NoNewline
                Write-Host $parts2[1] -ForegroundColor Cyan
            }
            elseif ($Message -like "*Granting * permission to site:*") {
                $parts = $Message -split "Granting "
                $parts2 = $parts[1] -split " permission to site: "
                Write-Host "[INFO] Granting " -ForegroundColor Cyan -NoNewline
                Write-Host $parts2[0] -ForegroundColor Yellow -NoNewline
                Write-Host " permission to site: " -ForegroundColor Cyan -NoNewline
                Write-Host $parts2[1] -ForegroundColor Green
            }
            else {
                Write-Host "[INFO] $Message" -ForegroundColor Cyan
            }
        }
        "Success" {
            if ($Message -like "*Retrieved site:*") {
                $parts = $Message -split "Retrieved site: "
                Write-Host "[SUCCESS] Retrieved site: " -ForegroundColor Green -NoNewline
                Write-Host $parts[1] -ForegroundColor Green -BackgroundColor DarkGray
            }
            elseif ($Message -like "*Retrieved service principal:*" -or $Message -like "*Retrieved *:*") {
                Write-Host "[SUCCESS] $Message" -ForegroundColor Green
            }
            elseif ($Message -like "*permission granted to site*") {
                $parts = $Message -split " permission granted to site "
                Write-Host "[SUCCESS] " -ForegroundColor Green -NoNewline
                Write-Host $parts[0] -ForegroundColor Yellow -NoNewline
                Write-Host " permission granted to site " -ForegroundColor Green -NoNewline
                Write-Host $parts[1] -ForegroundColor Green -BackgroundColor DarkGray
            }
            else {
                Write-Host "[SUCCESS] $Message" -ForegroundColor Green
            }
        }
        "Warning" { Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
        "Error" { Write-Host "[ERROR] $Message" -ForegroundColor Red }
    }
}

# Function to get user input with validation
function Get-ValidatedInput {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        
        [Parameter(Mandatory = $false)]
        [scriptblock]$ValidationScript,
        
        [Parameter(Mandatory = $false)]
        [string]$ErrorMessage = "Invalid input. Please try again."
    )
    
    do {
        $userInput = Read-Host -Prompt $Prompt
        $isValid = $true
        
        if ($ValidationScript -and -not (& $ValidationScript $userInput)) {
            Write-StatusMessage $ErrorMessage -Type Warning
            $isValid = $false
        }
    } while (-not $isValid)
    
    return $userInput
}

# Function to display menu and get selection
function Show-Menu {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Title,
        
        [Parameter(Mandatory = $true)]
        [array]$Options,
        
        [Parameter(Mandatory = $false)]
        [string]$Description = ""
    )
    
    Clear-Host
    Write-Host "================ $Title ================" -ForegroundColor Cyan
    
    if ($Description) {
        Write-Host $Description -ForegroundColor Yellow
        Write-Host "----------------------------------------" -ForegroundColor Cyan
    }
    
    for ($i = 0; $i -lt $Options.Count; $i++) {
        # Format with number and highlighted name
        Write-Host "[$($i+1)] " -ForegroundColor White -NoNewline
        Write-Host "$($Options[$i].Name)" -ForegroundColor Black -BackgroundColor Yellow -NoNewline
        Write-Host "" # New line after highlighted name
        
        if ($Options[$i].Description) {
            Write-Host "    $($Options[$i].Description)" -ForegroundColor Gray
        }
        
        # Add a small spacer between options for better readability
        if ($i -lt $Options.Count - 1) {
            Write-Host ""
        }
    }
    
    Write-Host "----------------------------------------" -ForegroundColor Cyan
    
    do {
        Write-Host ">> " -ForegroundColor Yellow -NoNewline
        $selection = Read-Host "Enter selection (1-$($Options.Count))"
        $validSelection = $selection -match '^\d+$' -and [int]$selection -ge 1 -and [int]$selection -le $Options.Count
        
        if (-not $validSelection) {
            Write-Host "Invalid selection. Please enter a number between 1 and $($Options.Count)." -ForegroundColor Red
        }
    } while (-not $validSelection)
    
    # Confirm selection with visual feedback
    Write-Host ""
    Write-Host "You selected: " -ForegroundColor White -NoNewline
    Write-Host "$($Options[[int]$selection-1].Name)" -ForegroundColor Black -BackgroundColor Yellow
    Write-Host ""
    
    return $Options[[int]$selection-1]
}

# Function to connect to Microsoft Graph
function Connect-ToMicrosoftGraph {
    try {
        # Check if already connected
        try {
            $context = Get-MgContext
            if ($context) {
                Write-StatusMessage "Already connected to Microsoft Graph as $($context.Account)" -Type Info
                
                # Check if we have the necessary permissions
                $requiredScopes = @("Directory.ReadWrite.All", "Sites.FullControl.All")
                $missingScopes = $requiredScopes | Where-Object { $context.Scopes -notcontains $_ }
                
                if ($missingScopes.Count -gt 0) {
                    Write-StatusMessage "Missing required permissions: $($missingScopes -join ', '). Reconnecting..." -Type Warning
                    Disconnect-MgGraph | Out-Null
                    throw "Reconnection needed"
                }
                
                return $true
            }
        } catch {
            # Connection check failed, proceed to connect
        }
        
        # Define required scopes
        $scopes = @("Directory.ReadWrite.All", "Sites.FullControl.All")
        
        Write-StatusMessage "Connecting to Microsoft Graph with required permissions..." -Type Info
        Write-StatusMessage "Required permissions: $($scopes -join ', ')" -Type Info
        
        Connect-MgGraph -Scopes $scopes
        
        # Verify connection
        $context = Get-MgContext
        if ($context) {
            Write-StatusMessage "Successfully connected to Microsoft Graph as $($context.Account)" -Type Success
            return $true
        } else {
            Write-StatusMessage "Failed to connect to Microsoft Graph" -Type Error
            return $false
        }
    } catch {
        Write-StatusMessage "Error connecting to Microsoft Graph: $_" -Type Error
        return $false
    }
}

# Function to get SharePoint site
function Get-SharePointSiteByUrl {
    param (
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl
    )
    
    try {
        $UrlParts = $SiteUrl.Split('//')[1].Split('/')
        $Domain = $UrlParts[0]
        $SitePath = $UrlParts[2]
        $SiteId = "$Domain" + ":/sites/" + "$SitePath"
        
        Write-StatusMessage "Getting SharePoint site with ID: $SiteId" -Type Info
        $Site = Get-MgSite -SiteId $SiteId
        
        if ($Site) {
            Write-StatusMessage "Retrieved site: $($Site.DisplayName)" -Type Success
            return $Site
        } else {
            Write-StatusMessage "Site not found" -Type Error
            return $null
        }
    } catch {
        Write-StatusMessage "Error retrieving site: $_" -Type Error
        return $null
    }
}

# Function to get service principal
function Get-EntraServicePrincipal {
    param (
        [Parameter(Mandatory = $true)]
        [string]$EntraObjectName
    )
    
    try {
        $ServicePrincipal = Get-MgServicePrincipal -Filter "displayname eq '$EntraObjectName'"
        
        if ($ServicePrincipal) {
            # Identify what type of object it is
            $objectType = "Service Principal"
            if ($ServicePrincipal.ServicePrincipalType -eq "ManagedIdentity") {
                $objectType = "Managed Identity"
            }
            
            Write-StatusMessage "Retrieved ${objectType}: $($ServicePrincipal.DisplayName) (AppId: $($ServicePrincipal.AppId))" -Type Success
            return $ServicePrincipal
        } else {
            Write-StatusMessage "No service principal, managed identity, or enterprise application found with that name" -Type Error
            return $null
        }
    } catch {
        Write-StatusMessage "Error retrieving Entra ID object: $_" -Type Error
        return $null
    }
}

# Function to check if role assignment already exists
function Test-ExistingRoleAssignment {
    param (
        [Parameter(Mandatory = $true)]
        [string]$PrincipalId,
        
        [Parameter(Mandatory = $true)]
        [string]$ResourceId,
        
        [Parameter(Mandatory = $true)]
        [string]$AppRoleId
    )
    
    try {
        # Get all existing app role assignments
        $existingAssignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $PrincipalId
        
        # Check if the exact assignment already exists
        $alreadyAssigned = $existingAssignments | Where-Object { 
            $_.ResourceId -eq $ResourceId -and $_.AppRoleId -eq $AppRoleId 
        }
        
        return ($null -ne $alreadyAssigned)
    } catch {
        Write-StatusMessage "Error checking existing role assignments: $_" -Type Error
        return $false
    }
}

# Function to grant Graph API permission to service principal
function Grant-GraphPermission {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphServicePrincipal]$TargetServicePrincipal,
        
        [Parameter(Mandatory = $true)]
        [string]$PermissionValue
    )
    
    try {
        # Get Microsoft Graph service principal
        $GraphApp = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'" -ErrorAction SilentlyContinue
        
        if (-not $GraphApp) {
            Write-StatusMessage "Could not retrieve Microsoft Graph service principal" -Type Error
            return $false
        }
        
        # Get requested role
        $Role = $GraphApp.AppRoles | Where-Object {$_.Value -eq $PermissionValue}
        
        if (-not $Role) {
            Write-StatusMessage "Role '$PermissionValue' not found in Microsoft Graph API" -Type Error
            return $false
        }
        
        # Check if assignment already exists
        $assignmentExists = Test-ExistingRoleAssignment -PrincipalId $TargetServicePrincipal.Id -ResourceId $GraphApp.Id -AppRoleId $Role.Id
        
        if ($assignmentExists) {
            Write-StatusMessage "The Graph permission '$PermissionValue' is already assigned to $($TargetServicePrincipal.DisplayName)" -Type Info
            # Permission was not newly added
            $script:graphPermissionWasNew = $false
            return $true
        }
        
        # Create app role assignment object
        $AppRoleAssignment = @{
            "PrincipalId" = $TargetServicePrincipal.Id
            "ResourceId" = $GraphApp.Id
            "AppRoleId" = $Role.Id
        }
        
        # Assign the role
        $RoleAssignment = New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $TargetServicePrincipal.Id -BodyParameter $AppRoleAssignment
        
        if ($RoleAssignment.AppRoleId) {
            Write-StatusMessage "The Graph permission '$($Role.Value)' granted to $($TargetServicePrincipal.DisplayName)" -Type Success
            # Permission was newly added
            $script:graphPermissionWasNew = $true
            return $true
        } else {
            Write-StatusMessage "Failed to grant permission" -Type Error
            return $false
        }
    } catch {
        if ($_.Exception.Message -like "*Permission being assigned already exists*") {
            Write-StatusMessage "The Graph permission '$PermissionValue' is already assigned to $($TargetServicePrincipal.DisplayName)" -Type Info
            # Permission was not newly added
            $script:graphPermissionWasNew = $false
            return $true
        } else {
            Write-StatusMessage "Error granting permission: $_" -Type Error
            return $false
        }
    }
}

# Function to grant permission to SharePoint site
function Grant-ManagedIdentitySitePermission {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphSite]$Site,
        
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphServicePrincipal]$ServicePrincipal,
        
        [Parameter(Mandatory = $true)]
        [string]$Permission
    )
    
    try {
        # Create application object for permission grant - Use original display name
        $Application = @{
            "id" = $ServicePrincipal.AppId
            "displayName" = $ServicePrincipal.DisplayName
        }
        
        # Check if permission already exists - not perfect but helpful
        $existingPermissions = Get-MgSitePermission -SiteId $Site.Id -ErrorAction SilentlyContinue
        $permissionExists = $false
        
        if ($existingPermissions) {
            foreach ($existingPermission in $existingPermissions) {
                $perm = Get-MgSitePermission -PermissionId $existingPermission.Id -SiteId $Site.Id -ErrorAction SilentlyContinue
                if ($perm -and 
                    $perm.GrantedToIdentitiesV2.Application.Id -eq $ServicePrincipal.AppId -and 
                    $perm.Roles -contains $Permission) {
                    $permissionExists = $true
                    break
                }
            }
        }
        
        if ($permissionExists) {
            Write-StatusMessage "Permission '$Permission' is already assigned to site for this application" -Type Info
            $script:sitePermissionWasNew = $false
            return $true
        }
        
        # Grant permission
        Write-StatusMessage "Granting $Permission permission to site: $($Site.DisplayName)" -Type Info
        $Status = New-MgSitePermission -SiteId $Site.Id -Roles $Permission -GrantedToIdentities @{"application" = $Application}
        
        if ($Status.Id) {
            Write-StatusMessage "$Permission permission granted to site $($Site.DisplayName)" -Type Success
            $script:sitePermissionWasNew = $true
            return $true
        } else {
            Write-StatusMessage "Failed to grant site permission" -Type Error
            return $false
        }
    } catch {
        Write-StatusMessage "Error granting site permission: $_" -Type Error
        return $false
    }
}

# Function to list site permissions
function Get-AllSitePermissions {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphSite]$Site
    )
    
    try {
        Write-StatusMessage "Retrieving permissions for site: $($Site.DisplayName)" -Type Info
        [array]$Permissions = Get-MgSitePermission -SiteId $Site.Id
        
        if (-not $Permissions -or $Permissions.Count -eq 0) {
            Write-StatusMessage "No permissions found for this site" -Type Warning
            return
        }
        
        Write-StatusMessage "Found $($Permissions.Count) permission entries" -Type Info
        
        # Create a table for better output formatting
        $PermissionTable = @()
        
        ForEach ($Permission in $Permissions) {
            $Data = Get-MgSitePermission -PermissionId $Permission.Id -SiteId $Site.Id -Property Id, Roles, GrantedToIdentitiesV2
            
            if ($Data.GrantedToIdentitiesV2.Application) {
                # Include both DisplayName and ID
                $PermissionTable += [PSCustomObject]@{
                    'Identity' = $Data.GrantedToIdentitiesV2.Application.DisplayName
                    'AppId' = $Data.GrantedToIdentitiesV2.Application.Id
                    'Roles' = ($Data.Roles -join ", ")
                }
            }
        }
        
        # Force display of the table with improved headers
        if ($PermissionTable.Count -gt 0) {
            Write-Host ""
            Write-Host "SharePoint site permissions:" -ForegroundColor Yellow
            
            # Define fixed column widths that are wide enough for the data
            $col1Width = 45  # DisplayName column
            $col2Width = 40  # AppId column 
            
            # Print headers
            Write-Host ("DisplayName".PadRight($col1Width)) -NoNewline -ForegroundColor Yellow
            Write-Host ("AppId".PadRight($col2Width)) -NoNewline -ForegroundColor Yellow
            Write-Host "Roles" -ForegroundColor Yellow
            
            # Print divider lines
            Write-Host (("-" * 11).PadRight($col1Width)) -NoNewline -ForegroundColor DarkGray
            Write-Host (("-" * 5).PadRight($col2Width)) -NoNewline -ForegroundColor DarkGray
            Write-Host ("-" * 5) -ForegroundColor DarkGray
            
            # Print each row with exact column widths
            foreach ($item in $PermissionTable) {
                # Ensure we truncate any values that are too long for columns
                $displayName = if ($item.Identity.Length -gt $col1Width) { 
                    $item.Identity.Substring(0, $col1Width-3) + "..." 
                } else { 
                    $item.Identity.PadRight($col1Width) 
                }
                
                $appId = if ($item.AppId.Length -gt $col2Width) { 
                    $item.AppId.Substring(0, $col2Width-3) + "..." 
                } else { 
                    $item.AppId.PadRight($col2Width) 
                }
                
                Write-Host $displayName -NoNewline -ForegroundColor White
                Write-Host $appId -NoNewline -ForegroundColor White
                Write-Host $item.Roles -ForegroundColor White
            }
            
            Write-Host ""
        }
        
        return $PermissionTable
    } catch {
        Write-StatusMessage "Error retrieving site permissions: $_" -Type Error
        return $null
    }
}

# Function to list all permissions for a service principal
function Get-ServicePrincipalGraphPermissions {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphServicePrincipal]$ServicePrincipal
    )
    
    try {
        Write-StatusMessage "Retrieving permissions for: $($ServicePrincipal.DisplayName)" -Type Info
        
        # Get all app role assignments for the service principal
        $assignments = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $ServicePrincipal.Id
        
        if (-not $assignments -or $assignments.Count -eq 0) {
            Write-StatusMessage "No application permissions found for this service principal" -Type Warning
            return @()
        }
        
        Write-StatusMessage "Found $($assignments.Count) permission assignments" -Type Info
        
        # Create a collection to store all permissions info
        $allPermissions = @()
        
        # Display with improved formatting
        Write-Host ""
        Write-Host "Service principal permissions:" -ForegroundColor Yellow
        
        # Define column widths
        $col1Width = 20
        $col2Width = 40
        
        # Print headers with consistent width
        Write-Host ("Resource".PadRight($col1Width)) -ForegroundColor Yellow -NoNewline
        Write-Host ("Permission".PadRight($col2Width)) -ForegroundColor Yellow -NoNewline
        Write-Host "Description" -ForegroundColor Yellow
        
        # Print divider line with consistent column width
        Write-Host (("-" * 8).PadRight($col1Width)) -ForegroundColor DarkGray -NoNewline
        Write-Host (("-" * 10).PadRight($col2Width)) -ForegroundColor DarkGray -NoNewline
        Write-Host ("-" * 11) -ForegroundColor DarkGray
        
        foreach ($assignment in $assignments) {
            # Get the resource service principal
            $resourceSp = $null
            
            try {
                $resourceSp = Get-MgServicePrincipal -ServicePrincipalId $assignment.ResourceId -ErrorAction SilentlyContinue
            } catch {
                # Couldn't get resource SP
            }
            
            $resourceName = if ($resourceSp) { $resourceSp.DisplayName } else { "Unknown Resource" }
            
            # Find the role definition
            $role = $null
            if ($resourceSp) {
                $role = $resourceSp.AppRoles | Where-Object { $_.Id -eq $assignment.AppRoleId }
            }
            
            $permissionName = if ($role) { $role.Value } else { "Unknown" }
            $displayName = if ($role) { $role.DisplayName } else { "Unknown" }
            
            # Create permission info object
            $permInfo = [PSCustomObject]@{
                'Resource' = $resourceName
                'Permission' = $permissionName
                'DisplayName' = $displayName
                'AppRoleId' = $assignment.AppRoleId
            }
            
            $allPermissions += $permInfo
            
            # Display with fixed width columns - ensure alignment
            Write-Host ($resourceName.PadRight($col1Width)) -ForegroundColor White -NoNewline
            Write-Host ($permissionName.PadRight($col2Width)) -ForegroundColor White -NoNewline
            Write-Host $displayName -ForegroundColor White
        }
        
        Write-Host ""
        return $allPermissions
        
    } catch {
        Write-StatusMessage "Error retrieving permissions: $_" -Type Error
        return @()
    }
}

# Function to remove SharePoint site permission
function Remove-SharePointSitePermission {
    param (
        [Parameter(Mandatory = $true)]
        [Microsoft.Graph.PowerShell.Models.MicrosoftGraphSite]$Site,
        
        [Parameter(Mandatory = $true)]
        [string]$ApplicationId
    )
    
    try {
        # Get all permissions for the site
        $sitePermissions = Get-MgSitePermission -SiteId $Site.Id
        
        $permissionFound = $false
        
        # Find the permission for the specified application
        foreach ($permission in $sitePermissions) {
            $permDetails = Get-MgSitePermission -SiteId $Site.Id -PermissionId $permission.Id
            
            if ($permDetails.GrantedToIdentitiesV2.Application.Id -eq $ApplicationId) {
                # Found the permission, now remove it
                Write-StatusMessage "Found permission for application ID: $ApplicationId. Removing..." -Type Info
                
                Remove-MgSitePermission -SiteId $Site.Id -PermissionId $permission.Id
                
                Write-StatusMessage "Permission successfully removed from site: $($Site.DisplayName)" -Type Success
                $permissionFound = $true
                break
            }
        }
        
        if (-not $permissionFound) {
            Write-StatusMessage "No permission found for application ID: $ApplicationId on site: $($Site.DisplayName)" -Type Warning
            return $false
        }
        
        return $true
    }
    catch {
        Write-StatusMessage "Error removing site permission: $_" -Type Error
        return $false
    }
}

# Main script execution
Write-Host "======================================================" -ForegroundColor Cyan
$headerText = "     SharePoint Selected Permission Management Script     " 
Write-Host $headerText -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "======================================================" -ForegroundColor Cyan
Write-StatusMessage "Starting script execution" -Type Info

# Step 0: Connect to Microsoft Graph with required permissions
$connected = Connect-ToMicrosoftGraph
if (-not $connected) {
    Write-StatusMessage "Script execution stopped: Unable to connect to Microsoft Graph with required permissions" -Type Error
    exit
}

# Define operations
$availableOperations = @(
    @{
        Name = "Grant Permission"
        Value = "grant"
        Description = "Grant permission to a SharePoint site for a service principal"
    },
    @{
        Name = "View Permissions"
        Value = "view"
        Description = "View all permissions for a specific SharePoint site"
    },
    @{
        Name = "Remove Permission"
        Value = "remove"
        Description = "Remove permission from a SharePoint site for a service principal"
    }
)

# Show menu for operation selection
$selectedOperation = Show-Menu -Title "Select Operation" -Options $availableOperations -Description "Choose what you'd like to do:"
$operation = $selectedOperation.Value

# Get user input for SharePoint URL
$SharePointUrl = Get-ValidatedInput -Prompt "Enter SharePoint site URL (e.g., https://contoso.sharepoint.com/sites/MySite)" -ValidationScript {
    param($url)
    return $url -match "^https://.*\.sharepoint\.com/sites/.*$"
} -ErrorMessage "Please enter a valid SharePoint URL (https://domain.sharepoint.com/sites/sitename)"

# Get SharePoint site
$Site = Get-SharePointSiteByUrl -SiteUrl $SharePointUrl
if (-not $Site) {
    Write-StatusMessage "Script execution stopped: Unable to retrieve site" -Type Error
    exit
}

# If View operation selected, just show the site permissions and exit
if ($operation -eq "view") {
    Write-Host "======================================================" -ForegroundColor Cyan
    $headerText = "     SharePoint Site Permissions Summary     "
    Write-Host $headerText -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "======================================================" -ForegroundColor Cyan
    $SitePermissions = Get-AllSitePermissions -Site $Site
    
    # List all service principals with permissions to this site
    Write-Host ""
    Write-Host "Service Principals with access to this site:" -ForegroundColor Yellow
    $uniqueSPs = @()
    
    # Get all site permissions
    [array]$Permissions = Get-MgSitePermission -SiteId $Site.Id
    
    if ($Permissions -and $Permissions.Count -gt 0) {
        foreach ($Permission in $Permissions) {
            $Data = Get-MgSitePermission -PermissionId $Permission.Id -SiteId $Site.Id -Property Id, Roles, GrantedToIdentitiesV2
            
            if ($Data.GrantedToIdentitiesV2.Application) {
                $appId = $Data.GrantedToIdentitiesV2.Application.Id
                $displayName = $Data.GrantedToIdentitiesV2.Application.DisplayName
                
                # Add to unique list if not already present
                if (-not ($uniqueSPs | Where-Object { $_.AppId -eq $appId })) {
                    $uniqueSPs += [PSCustomObject]@{
                        'DisplayName' = $displayName
                        'AppId' = $appId
                    }
                }
            }
        }
        
        # Display the list of service principals
        if ($uniqueSPs.Count -gt 0) {
            for ($i = 0; $i -lt $uniqueSPs.Count; $i++) {
                Write-Host "[$($i+1)] " -ForegroundColor White -NoNewline
                Write-Host "$($uniqueSPs[$i].DisplayName)" -ForegroundColor Cyan -NoNewline
                Write-Host " (AppId: $($uniqueSPs[$i].AppId))" -ForegroundColor Gray
            }
            
            # Ask if user wants to see details for a specific service principal
            Write-Host ""
            $viewDetails = Read-Host "Would you like to see permission details for a specific service principal? (Y/N)"
            
            if ($viewDetails -eq "Y" -or $viewDetails -eq "y") {
                $spIndex = Read-Host "Enter the number of the service principal (1-$($uniqueSPs.Count))"
                
                if ($spIndex -match '^\d+$' -and [int]$spIndex -ge 1 -and [int]$spIndex -le $uniqueSPs.Count) {
                    $selectedSP = $uniqueSPs[[int]$spIndex-1]
                    
                    # Get the full service principal object
                    $ServicePrincipal = Get-MgServicePrincipal -Filter "appId eq '$($selectedSP.AppId)'"
                    
                    if ($ServicePrincipal) {
                        Write-Host ""
                        Write-Host "======================================================" -ForegroundColor Cyan
                        $headerText = "     Service Principal Permissions Summary     "
                        Write-Host $headerText -ForegroundColor White -BackgroundColor DarkBlue
                        Write-Host "======================================================" -ForegroundColor Cyan
                        
                        $AllPermissions = Get-ServicePrincipalGraphPermissions -ServicePrincipal $ServicePrincipal
                    } else {
                        Write-StatusMessage "Could not retrieve detailed information for the selected service principal" -Type Warning
                    }
                } else {
                    Write-StatusMessage "Invalid selection" -Type Warning
                }
            }
        } else {
            Write-Host "No service principals found with access to this site." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No permissions found for this site." -ForegroundColor Yellow
    }
    
    Write-StatusMessage "Operation completed" -Type Success
    exit
}

# If Remove operation selected
if ($operation -eq "remove") {
    Write-Host "======================================================" -ForegroundColor Cyan
    $headerText = "     Remove SharePoint Site Permission     "
    Write-Host $headerText -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host "======================================================" -ForegroundColor Cyan
    
    # Show current permissions
    $SitePermissions = Get-AllSitePermissions -Site $Site
    
    # List all service principals with permissions to this site
    Write-Host ""
    Write-Host "Service Principals with access to this site:" -ForegroundColor Yellow
    $uniqueSPs = @()
    
    # Get all site permissions
    [array]$Permissions = Get-MgSitePermission -SiteId $Site.Id
    
    if ($Permissions -and $Permissions.Count -gt 0) {
        foreach ($Permission in $Permissions) {
            $Data = Get-MgSitePermission -PermissionId $Permission.Id -SiteId $Site.Id -Property Id, Roles, GrantedToIdentitiesV2
            
            if ($Data.GrantedToIdentitiesV2.Application) {
                $appId = $Data.GrantedToIdentitiesV2.Application.Id
                $displayName = $Data.GrantedToIdentitiesV2.Application.DisplayName
                
                # Add to unique list if not already present
                if (-not ($uniqueSPs | Where-Object { $_.AppId -eq $appId })) {
                    $uniqueSPs += [PSCustomObject]@{
                        'DisplayName' = $displayName
                        'AppId' = $appId
                    }
                }
            }
        }
        
        # Display the list of service principals
        if ($uniqueSPs.Count -gt 0) {
            for ($i = 0; $i -lt $uniqueSPs.Count; $i++) {
                Write-Host "[$($i+1)] " -ForegroundColor White -NoNewline
                Write-Host "$($uniqueSPs[$i].DisplayName)" -ForegroundColor Cyan -NoNewline
                Write-Host " (AppId: $($uniqueSPs[$i].AppId))" -ForegroundColor Gray
            }
            
            # Ask which service principal's permission to remove
            Write-Host ""
            $spIndex = Read-Host "Enter the number of the service principal to remove permission for (1-$($uniqueSPs.Count))"
            
            if ($spIndex -match '^\d+$' -and [int]$spIndex -ge 1 -and [int]$spIndex -le $uniqueSPs.Count) {
                $selectedSP = $uniqueSPs[[int]$spIndex-1]
                
                # Confirm before removing
                Write-Host ""
                Write-Host "You are about to:" -ForegroundColor White
                Write-Host "Remove permission for " -NoNewline
                Write-Host "$($selectedSP.DisplayName)" -ForegroundColor Cyan -NoNewline
                Write-Host " from SharePoint site " -NoNewline
                Write-Host "$SharePointUrl" -ForegroundColor Green
                Write-Host ""
                
                $confirmation = Read-Host "Do you want to proceed? (Y/N)"
                if ($confirmation -eq "Y" -or $confirmation -eq "y") {
                    # Remove the permission
                    $removed = Remove-SharePointSitePermission -Site $Site -ApplicationId $selectedSP.AppId
                    
                    # Show updated permissions if removal successful
                    if ($removed) {
                        Write-Host ""
                        Write-Host "Updated permissions for site:" -ForegroundColor Yellow
                        Get-AllSitePermissions -Site $Site
                    }
                } else {
                    Write-Host "Operation cancelled by user." -ForegroundColor Red
                }
            } else {
                Write-StatusMessage "Invalid selection" -Type Warning
            }
        } else {
            Write-Host "No service principals found with access to this site." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No permissions found for this site." -ForegroundColor Yellow
    }
    
    Write-StatusMessage "Operation completed" -Type Success
    exit
}

# If Grant operation selected, continue with the normal flow...
# Note about terminology 
Write-Host ""
Write-Host "NOTE ABOUT TERMINOLOGY:" -ForegroundColor Yellow
Write-Host "In Microsoft Entra ID, these terms are related but distinct:" -ForegroundColor Gray
Write-Host "• A service principal is the local representation of an application in your tenant" -ForegroundColor Gray
Write-Host "• A managed identity is a special type of service principal managed by Azure" -ForegroundColor Gray
Write-Host "• An enterprise application is how service principals appear in the portal" -ForegroundColor Gray
Write-Host "This script works with any of these objects using their display name." -ForegroundColor Gray
Write-Host ""

# Get user input for service principal/managed identity/enterprise application name
$ApplicationName = Get-ValidatedInput -Prompt "Enter the name of the service principal, managed identity, or enterprise application" -ValidationScript {
    param($name)
    return -not [string]::IsNullOrWhiteSpace($name)
} -ErrorMessage "Name cannot be empty"

# Define available Graph permission scopes
$availableGraphScopes = @(
    @{
        Name = "Sites.Selected"
        Value = "Sites.Selected"
        Description = "Highest level - Manages application access at the site collection level, providing access to a specific site collection"
    },
    @{
        Name = "Lists.SelectedOperations.Selected"
        Value = "Lists.SelectedOperations.Selected"
        Description = "Manages application access at the list level, providing access to a specific list"
    },
    @{
        Name = "ListItems.SelectedOperations.Selected"
        Value = "ListItems.SelectedOperations.Selected"
        Description = "Manages application access at the files, list item, or folder level, providing access to one or more list items"
    },
    @{
        Name = "Files.SelectedOperations.Selected"
        Value = "Files.SelectedOperations.Selected"
        Description = "Manages application access at the file or library folder level, providing access to one or more files"
    }
)

# Show menu for Graph permission scope selection
$selectedGraphScope = Show-Menu -Title "Select Graph API Permission Scope" -Options $availableGraphScopes -Description "Choose the Graph API permission scope to grant to the service principal:"
$RequestedGraphScope = $selectedGraphScope.Value

Write-StatusMessage "Selected Graph API permission scope: $RequestedGraphScope" -Type Info

# Define available SharePoint permission roles
$availableRoles = @(
    @{
        Name = "read"
        Value = "read"
        Description = "Read-only access to the site"
    },
    @{
        Name = "write"
        Value = "write"
        Description = "Read and write access to the site"
    },
    @{
        Name = "manage"
        Value = "manage"
        Description = "Read, write, and manage lists/designer capabilities"
    },
    @{
        Name = "fullcontrol"
        Value = "fullcontrol"
        Description = "Full control - all permissions"
    }
)

# Show menu for SharePoint permission role selection
$selectedRole = Show-Menu -Title "Select SharePoint Permission Role" -Options $availableRoles -Description "Choose the SharePoint permission level to grant to the service principal:"
$RequestedRole = $selectedRole.Value

Write-StatusMessage "Selected SharePoint permission role: $RequestedRole" -Type Info

# Get service principal
$ServicePrincipal = Get-EntraServicePrincipal -EntraObjectName $ApplicationName
if (-not $ServicePrincipal) {
    Write-StatusMessage "Script execution stopped: Unable to retrieve service principal" -Type Error
    exit
}

# Display the selections
Write-Host ""
Write-Host "You are about to:" -ForegroundColor White
Write-Host "1. Grant " -NoNewline
Write-Host "$RequestedGraphScope" -ForegroundColor Magenta -NoNewline
Write-Host " Graph API permission to the Entra ID object: " -NoNewline
Write-Host "$ApplicationName" -ForegroundColor Cyan -NoNewline

# Add more specific object type information if available
if ($ServicePrincipal.ServicePrincipalType -eq "ManagedIdentity") {
    Write-Host " (Managed Identity)" -ForegroundColor Cyan
} else {
    Write-Host " (Service Principal)" -ForegroundColor Cyan
}

Write-Host "2. Grant " -NoNewline
Write-Host "$RequestedRole" -ForegroundColor Yellow -NoNewline
Write-Host " permission to SharePoint site " -NoNewline
Write-Host "$SharePointUrl" -ForegroundColor Green
Write-Host ""

# Get confirmation before proceeding
$confirmation = Read-Host "Do you want to proceed? (Y/N)"
if ($confirmation -ne "Y" -and $confirmation -ne "y") {
    Write-Host "Operation cancelled by user." -ForegroundColor Red
    exit
}

# Step 3: Grant Graph API permission to service principal
$GraphPermissionGranted = Grant-GraphPermission -TargetServicePrincipal $ServicePrincipal -PermissionValue $RequestedGraphScope
if (-not $GraphPermissionGranted) {
    Write-StatusMessage "Warning: Failed to grant Graph API permission" -Type Warning
}

# Step 4: Grant managed identity permission to SharePoint site
$SitePermissionGranted = Grant-ManagedIdentitySitePermission -Site $Site -ServicePrincipal $ServicePrincipal -Permission $RequestedRole
if (-not $SitePermissionGranted) {
    Write-StatusMessage "Warning: Failed to grant site permission" -Type Warning
}

# Add blank lines for visual separation
Write-Host ""

# Step 5: List all permissions for the site
Write-Host "======================================================" -ForegroundColor Cyan
$headerText = "     SharePoint Site Permissions Summary     "
Write-Host $headerText -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "======================================================" -ForegroundColor Cyan
$SitePermissions = Get-AllSitePermissions -Site $Site

# Add blank lines for visual separation
Write-Host ""

# Step 6: List all Graph permissions for the service principal
Write-Host "======================================================" -ForegroundColor Cyan
$headerText = "     Service Principal Graph Permissions Summary     "
Write-Host $headerText -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "======================================================" -ForegroundColor Cyan
$AllPermissions = Get-ServicePrincipalGraphPermissions -ServicePrincipal $ServicePrincipal

# Add blank lines for visual separation
Write-Host ""

# Final summary
Write-Host "======================================================" -ForegroundColor Cyan
$headerText = "                   Summary                   "
Write-Host $headerText -ForegroundColor White -BackgroundColor DarkBlue
Write-Host "======================================================" -ForegroundColor Cyan

# Determine the object type more specifically
$objectType = "Service Principal"
if ($ServicePrincipal.ServicePrincipalType -eq "ManagedIdentity") {
    $objectType = "Managed Identity"
}

Write-Host "Entra ID Object Type: " -ForegroundColor White -NoNewline
Write-Host "$objectType" -ForegroundColor Yellow
Write-Host "Display Name: " -ForegroundColor White -NoNewline
Write-Host "$($ServicePrincipal.DisplayName)" -ForegroundColor Yellow
Write-Host "Application ID: " -ForegroundColor White -NoNewline
Write-Host "$($ServicePrincipal.AppId)" -ForegroundColor Yellow
Write-Host "SharePoint Site: " -ForegroundColor White -NoNewline
Write-Host "$($Site.DisplayName)" -ForegroundColor Green
Write-Host ""

# Show what changed - different messages based on whether permissions were new or not
Write-Host "PERMISSION CHANGES:" -ForegroundColor Magenta
Write-Host "-------------------" -ForegroundColor Magenta

if ($script:graphPermissionWasNew) {
    Write-Host "Graph Permission Added: " -ForegroundColor White -NoNewline
    Write-Host "$RequestedGraphScope" -ForegroundColor Green
} else {
    Write-Host "Graph Permission: " -ForegroundColor White -NoNewline
    Write-Host "$RequestedGraphScope (already assigned)" -ForegroundColor Gray
}

if ($script:sitePermissionWasNew) {
    Write-Host "SharePoint Permission Added: " -ForegroundColor White -NoNewline
    Write-Host "$RequestedRole" -ForegroundColor Green
} else {
    Write-Host "SharePoint Permission: " -ForegroundColor White -NoNewline
    Write-Host "$RequestedRole (already assigned)" -ForegroundColor Gray
}

# Add Next Steps section
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Magenta
Write-Host "1. Test the application's access to SharePoint" -ForegroundColor White
Write-Host "2. Review security implications of granted permissions" -ForegroundColor White
Write-Host "3. For detailed permission auditing run:" -ForegroundColor White
Write-Host "   Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId '$($ServicePrincipal.Id)'" -ForegroundColor Gray
Write-Host "======================================================" -ForegroundColor Cyan

Write-StatusMessage "Script execution completed" -Type Success

# End of script