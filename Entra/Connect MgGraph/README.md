# Connect-ClientCreds.ps1

![PowerShell](https://img.shields.io/badge/PowerShell-7+-blue) ![Microsoft Graph](https://img.shields.io/badge/Microsoft%20Graph-SDK-00BCF2) ![Entra](https://img.shields.io/badge/Microsoft-Entra_ID-0078D4)

A PowerShell script for testing connecting to Entra using Client Credentials

## Overview

This script connects to Entra using client credentials from an app registration with a client secret, then validates that the assigned scopes and application permissions are working as expected.

## Prerequisites

* **PowerShell**: 7.x or higher recommended
* **Required Modules**:
  - Microsoft.Graph - `Install-Module Microsoft.Graph`

## Usage

### Basic Example

```powershell
.\Connect-ClientCreds.ps1
```

