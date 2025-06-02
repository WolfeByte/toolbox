

# SharePoint Graph Permissions Helper

A PowerShell script that simplifies managing SharePoint Online permissions using Microsoft Graph API's *Selected Scopes* model.

## Overview
If you’ve ever had to grant **application level-access** to SharePoint Online for automation tasks, you’ve likely run into a common limitation: the only option being to assign tenant wide Graph permissions. Need your app to manage a single document library? Too bad, it gets access to *all* of them. For example, assigning *Sites.ReadWrite.All* lets the app create or delete folders where needed... but also everywhere else, whether you like it or not. That’s not ideal if the identity is ever compromised.

Enter **Selected Scopes**.

Microsoft Graph’s *Selected Scopes* model for SharePoint Online lets you grant precise, resource specific access, down to individual sites, lists, or even items. It’s a much better way to enforce **least-privilege** access for service principals and managed identities. Microsoft has recently added support for even more granular permissions, which is great, but setting it all up via Graph is not exactly straightforward. Documentation is light on practical examples, and the process involves several layers of Graph calls.

This script aims to fix that. It gives you an interactive PowerShell interface to grant, view, and remove fine-grained SharePoint permissions using the Graph API. No manual JSON crafting, AppID or SiteID hunting, or API spelunking required.

If the term *application* feels ambiguous, you’re not alone. In the Microsoft ecosystem, it could mean a **Service Principal**, a **Managed Identity**, or an **Enterprise Application** all of which fall under the umbrella of *Workload Identities* (yes, it’s confusing). But if you’re here because, say, a Logic App needs access to just one SharePoint folder, and you've been banging your head against the wall for hours trying to set it up and get it to work, then you’re in the right place.

With this script you can:

* **Grant granular, resource-specific permissions** to a service principal (an Application) for a SharePoint site/list/item
* **View existing permissions** for any service principal for a SharePoint site/list/item
* **Remove permissions** for a service principal from a SharePoint site/list/item

![Image](https://github.com/user-attachments/assets/5fa1530f-e80c-4af8-8c63-47f5de0135bb)

By using the *Selected* permission model, you enforce the principle of least privilege, only granting access to specific SharePoint resources, rather than broad tenant-wide permissions.

## Key Features

* **Grant Permissions**: Assign precise Graph API permissions and SharePoint roles to service principals.
* **View Permissions**: Quickly check which service principals have access to a SharePoint site and what permissions they have.
* **Remove Permissions**: Easily revoke access from any service principal.
* **Interactive Menus**: User-friendly selection menus for all major operations.

## Prerequisites

* **PowerShell 7.1 or higher**
* **Microsoft Graph PowerShell SDK modules**:

  * `Microsoft.Graph.Authentication`
  * `Microsoft.Graph.Sites`
  * `Microsoft.Graph.Applications`
* **Required permissions** in Microsoft Entra ID for the account running the script:
  - `Directory.ReadWrite.All`
  - `Sites.FullControl.All`

The script will attempt to assign these permissions when you connect, as they are specified in the -Scope parameter. However, if you do not have sufficient privileges to grant consent for these permissions, you will need to request someone with the necessary elevated access to do so on your behalf.

To test assigning these permissions, you can connect to Microsoft Graph using the following command, specifying the required scopes in the -Scopes parameter:

```powershell
Connect-MgGraph -TenantId 'contoso.com' -Scopes 'Directory.ReadWrite.All', 'Sites.FullControl.All'
```

## Installation

1. Install the required Microsoft Graph PowerShell modules:

   ```powershell
   Install-Module Microsoft.Graph
   ```

2. Run the script in PowerShell:

   ```powershell
   .\SharePointGraphHelper.ps1
   ```

## Usage

The script provides an **interactive menu** for all key operations:

### Main Operations

1. **Grant Permission**: Grant access to a SharePoint site for a service principal.

   * Enter the SharePoint site URL
   * Enter the service principal Display Name
   * Choose a Graph API permission (e.g., Sites.Selected, Lists.SelectedOperations.Selected, etc.)
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

**Grant Graph Permissions** ![Image](https://github.com/user-attachments/assets/488c6a60-8450-4555-bd2c-94f79ba0a998)
**Grant SharePoint Permission** ![Image](https://github.com/user-attachments/assets/b01a3846-8fd0-4c37-bce5-429fc036b913)
**Successful Update** ![Image](https://github.com/user-attachments/assets/07b90e3b-843c-44c1-8040-808061abf9be)
**View Permissions** ![Image](https://github.com/user-attachments/assets/9e466a59-ccdf-4350-bc08-e9f61ed6da0d)
**Remove Permissions** ![Image](https://github.com/user-attachments/assets/c7632945-5778-4be5-a454-66aa82d15f38)

## Contributing

If you have suggestions or improvements, feel free to submit a pull request.

## References

* [SharePoint Selected Permission Scopes](https://learn.microsoft.com/en-us/graph/permissions-selected-overview?tabs=http)
* [Microsoft Graph PowerShell SDK](https://github.com/microsoftgraph/msgraph-sdk-powershell)
* [graphpermissions.merill.net - Sites.Selected](https://graphpermissions.merill.net/permission/Sites.Selected?tabs=apiv1%2CdocumentSetVersion1)
* [practical365.com - Restrict App Access to SharePoint Online Sites](https://practical365.com/restrict-app-access-to-sharepoint-sites)
* [www.michev.info - Granular permissions for working with files, list items and lists added to the Graph API!](https://www.michev.info/blog/post/6074/granular-permissions-for-working-with-files-list-items-and-lists-added-to-the-graph-api)

## License

This project is licensed under the MIT License - see the LICENSE file for details.

---
