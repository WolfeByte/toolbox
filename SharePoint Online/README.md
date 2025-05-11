Your README is already quite comprehensive, well-structured, and clear. However, I can suggest a few improvements for clarity, flow, and to ensure the key selling points stand out more. Here’s an enhanced version:

---

# SharePoint Selected Scopes Permissions Manager

A PowerShell script that simplifies managing SharePoint Online permissions using Microsoft Graph API's *Selected Scopes* model.

## Overview

This script makes it easier to manage service principal permissions for SharePoint Online sites via Microsoft Graph API’s *Selected Scopes* model. It provides administrators with the ability to:

* **Grant granular, resource-specific permissions** to service principals
* **View existing permissions** for SharePoint sites
* **Remove permissions** from SharePoint sites

By using the *Selected* permission model, you enforce the principle of least privilege, only granting access to specific SharePoint resources, rather than broad tenant-wide permissions.

## Key Features

* **Grant Permissions**: Assign precise Graph API permissions and SharePoint roles to service principals.
* **View Permissions**: Quickly check which service principals have access to a SharePoint site and what permissions they have.
* **Remove Permissions**: Easily revoke access from any service principal.
* **Interactive Menus**: User-friendly selection menus for all major operations.
* **Color-Coded Output**: Easy-to-read and follow console instructions and output.

## Prerequisites

* **PowerShell 7.1 or higher**
* **Microsoft Graph PowerShell SDK modules**:

  * `Microsoft.Graph.Authentication`
  * `Microsoft.Graph.Sites`
  * `Microsoft.Graph.Applications`
* **Appropriate Permissions** in Microsoft Entra ID

  * `Directory.ReadWrite.All`
  * `Sites.FullControl.All`

## Installation

1. Clone or download this repository.

2. Install the required Microsoft Graph PowerShell modules:

   ```powershell
   Install-Module Microsoft.Graph
   ```

3. Run the script in PowerShell:

   ```powershell
   .\Manage-SPOSelectedPermissions.ps1
   ```

## Usage

The script provides an **interactive menu** for all key operations:

### Main Operations

1. **Grant Permission**: Grant access to a SharePoint site for a service principal.

   * Enter the SharePoint site URL
   * Select the service principal
   * Choose a Graph API permission (e.g., Sites.Selected, Lists.Selected, etc.)
   * Pick a SharePoint role (read, write, manage, full control)

2. **View Permissions**: View all permissions associated with a SharePoint site.

   * Enter the SharePoint site URL
   * List all service principals with access and their permissions
   * Optionally, view detailed permissions for specific service principals

3. **Remove Permission**: Revoke a service principal's access from a SharePoint site.

   * Enter the SharePoint site URL
   * Choose the service principal from the list
   * Confirm the removal of permissions

## Permission Scope Reference

Supported Microsoft Graph API permission scopes:

| Permission Scope                        | Description                                    |
| --------------------------------------- | ---------------------------------------------- |
| `Sites.Selected`                        | Access at the site collection level            |
| `Lists.SelectedOperations.Selected`     | Access at the list level                       |
| `ListItems.SelectedOperations.Selected` | Access at the file, list item, or folder level |
| `Files.SelectedOperations.Selected`     | Access at the file or library folder level     |

Supported SharePoint permission roles:

| Role          | Description                                              |
| ------------- | -------------------------------------------------------- |
| `read`        | Read-only access to the site                             |
| `write`       | Read and write access to the site                        |
| `manage`      | Full read, write, and management capabilities            |
| `fullcontrol` | Complete control over all aspects of the SharePoint site |

## Terminology Explanation

The script helps clarify common Microsoft identity terminology:

* **Service Principal**: An identity used by applications or services to access resources.
* **Managed Identity**: A service principal managed by Azure, commonly used for Azure resources.
* **Enterprise Application**: The object representing service principals in the Entra ID portal.
* **Application Registration**: The definition of an application within Entra ID.

Collectively, these are all represented as service principals in the Microsoft Graph API.

## Screenshots

![Main Menu](https://example.com/screenshots/main-menu.png)
![Grant Permission](https://example.com/screenshots/grant-permission.png)
![View Permissions](https://example.com/screenshots/view-permissions.png)

## Contributing

If you have suggestions or improvements, feel free to submit a pull request.

## References

* [SharePoint Selected Permission Scopes](https://learn.microsoft.com/en-us/graph/permissions-selected-overview?tabs=http)
* [Microsoft Graph PowerShell SDK](https://github.com/microsoftgraph/msgraph-sdk-powershell)

## License

This project is licensed under the MIT License - see the LICENSE file for details.

---