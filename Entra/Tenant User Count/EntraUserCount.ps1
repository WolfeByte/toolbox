#Requires -Modules Microsoft.Graph.Users, ExchangeOnlineManagement
# Install-Module -Name Microsoft.Graph.Users
# Install-Module -Name ExchangeOnlineManagement

<#
.SYNOPSIS
    Exports a count of user types across Entra ID and Exchange Online.

.DESCRIPTION
    Retrieves all Entra user objects and Exchange Online mailboxes, then
    produces a summary broken down by user type, mailbox type, and account
    enabled state. Calculates a true human account count by
    subtracting Exchange resource accounts (shared mailboxes, rooms,
    equipment) from the total Entra member and guest count.

.PARAMETER Output
    Controls where results are written.
    Console  - Terminal only (default)
    CSV      - Two CSV files (Entra + Exchange summaries)
    HTML     - Single HTML report file
    All      - Console + CSV + HTML

.NOTES
    Author:         Benjamin Wolfe
    Required roles for the account running this script:
      Exchange Online : View-Only Organization Management (role group)
      Entra ID        : Global Reader

.EXAMPLE
    .\ExportUserTypeCount.ps1
    .\ExportUserTypeCount.ps1 -Output HTML
    .\ExportUserTypeCount.ps1 -Output All
#>

param(
    [ValidateSet('Console', 'CSV', 'HTML', 'All')]
    [string]$Output = 'All'
)

# Connect to Graph and retrieve all users 

Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "User.Read.All" -NoWelcome

Write-Host "Retrieving all Entra user objects..." -ForegroundColor Cyan
$allUsers = Get-MgUser -All `
    -Property Id, DisplayName, UserPrincipalName, UserType, AccountEnabled

Write-Host "Retrieved $($allUsers.Count) user objects." -ForegroundColor Green

# Connect to Exchange Online and retrieve all mailboxes

Write-Host "Connecting to Exchange Online..." -ForegroundColor Cyan
Connect-ExchangeOnline -ShowBanner:$false

Write-Host "Retrieving all mailboxes..." -ForegroundColor Cyan
$allMailboxes = Get-Mailbox -ResultSize Unlimited | `
    Select-Object DisplayName, RecipientTypeDetails, ExternalDirectoryObjectId

Write-Host "Retrieved $($allMailboxes.Count) mailboxes." -ForegroundColor Green

# Build summary counts

Write-Host "Building summary counts..." -ForegroundColor Cyan

# Filter out Exchange system mailboxes with no Entra identity
$linkedMailboxes = $allMailboxes | Where-Object {
    -not [string]::IsNullOrEmpty($_.ExternalDirectoryObjectId)
}

Write-Host "Excluded $($allMailboxes.Count - $linkedMailboxes.Count) Exchange system mailbox(es) with no Entra identity." -ForegroundColor DarkGray

# -- Entra Summary --
$members = $allUsers | Where-Object { $_.UserType -eq 'Member' }
$guests  = $allUsers | Where-Object { $_.UserType -eq 'Guest' }

$entraSummary = @(
    [PSCustomObject]@{
        Type     = 'Regular Users (Member)'
        Total    = $members.Count
        Enabled  = ($members | Where-Object { $_.AccountEnabled -eq $true }).Count
        Disabled = ($members | Where-Object { $_.AccountEnabled -eq $false }).Count
    },
    [PSCustomObject]@{
        Type     = 'Guest Users'
        Total    = $guests.Count
        Enabled  = ($guests | Where-Object { $_.AccountEnabled -eq $true }).Count
        Disabled = ($guests | Where-Object { $_.AccountEnabled -eq $false }).Count
    }
)

$totalHuman = [PSCustomObject]@{
    Type     = 'Total Human Accounts'
    Total    = $members.Count + $guests.Count
    Enabled  = ($members | Where-Object { $_.AccountEnabled -eq $true }).Count +
               ($guests  | Where-Object { $_.AccountEnabled -eq $true }).Count
    Disabled = ($members | Where-Object { $_.AccountEnabled -eq $false }).Count +
               ($guests  | Where-Object { $_.AccountEnabled -eq $false }).Count
}

# -- Exchange Resource Account Summary --
$entraLookup = @{}
foreach ($user in $allUsers) {
    $entraLookup[$user.Id] = $user.AccountEnabled
}

$resourceTypes = @('SharedMailbox', 'RoomMailbox', 'EquipmentMailbox')

$exchangeSummary = foreach ($type in $resourceTypes) {
    $mailboxesOfType = $linkedMailboxes | Where-Object { $_.RecipientTypeDetails -eq $type }
    $enabled  = 0
    $disabled = 0
    foreach ($mbx in $mailboxesOfType) {
        $accountEnabled = $entraLookup[$mbx.ExternalDirectoryObjectId.ToString()]
        if ($accountEnabled -eq $true) { $enabled++ }
        else                           { $disabled++ }
    }
    [PSCustomObject]@{
        Type     = $type
        Total    = $mailboxesOfType.Count
        Enabled  = $enabled
        Disabled = $disabled
    }
}

$otherMailboxes = $linkedMailboxes | Where-Object {
    $_.RecipientTypeDetails -notin $resourceTypes -and
    $_.RecipientTypeDetails -ne 'UserMailbox'
}

if ($otherMailboxes.Count -gt 0) {
    $enabled  = 0
    $disabled = 0
    foreach ($mbx in $otherMailboxes) {
        $accountEnabled = $entraLookup[$mbx.ExternalDirectoryObjectId.ToString()]
        if ($accountEnabled -eq $true) { $enabled++ }
        else                           { $disabled++ }
    }
    $exchangeSummary += [PSCustomObject]@{
        Type     = 'Other / Linked'
        Total    = $otherMailboxes.Count
        Enabled  = $enabled
        Disabled = $disabled
    }
}

$totalResources = [PSCustomObject]@{
    Type     = 'Total Resource Accounts'
    Total    = ($exchangeSummary | Measure-Object -Property Total    -Sum).Sum
    Enabled  = ($exchangeSummary | Measure-Object -Property Enabled  -Sum).Sum
    Disabled = ($exchangeSummary | Measure-Object -Property Disabled -Sum).Sum
}

$licensable = [PSCustomObject]@{
    Type     = 'Licensable Human Accounts'
    Total    = $totalHuman.Total    - $totalResources.Total
    Enabled  = $totalHuman.Enabled  - $totalResources.Enabled
    Disabled = $totalHuman.Disabled - $totalResources.Disabled
}

Write-Host "Summary counts complete." -ForegroundColor Green

# ── Stage 4: Console output ────────────────────────────────────────────────────

function Write-TableRow {
    param(
        [string]$Type,
        [int]$Total,
        [int]$Enabled,
        [int]$Disabled,
        [string]$Colour = 'White',
        [switch]$Header
    )
    if ($Header) {
        Write-Host ("{0,-35} {1,8} {2,10} {3,10}" -f "Type", "Total", "Enabled", "Disabled") -ForegroundColor DarkGray
        Write-Host ("{0,-35} {1,8} {2,10} {3,10}" -f ("─" * 33), ("─" * 6), ("─" * 8), ("─" * 8)) -ForegroundColor DarkGray
    } else {
        Write-Host ("{0,-35} {1,8} {2,10} {3,10}" -f $Type, $Total, $Enabled, $Disabled) -ForegroundColor $Colour
    }
}

$divider = "─" * 65

Write-Host ""
Write-Host "  Tenant User Account Summary" -ForegroundColor Cyan
Write-Host ("  " + ("═" * 63)) -ForegroundColor Cyan
Write-Host ""
Write-TableRow -Header
foreach ($row in $entraSummary) {
    Write-TableRow -Type $row.Type -Total $row.Total -Enabled $row.Enabled -Disabled $row.Disabled
}
Write-Host $divider -ForegroundColor DarkGray
Write-TableRow -Type $totalHuman.Type -Total $totalHuman.Total -Enabled $totalHuman.Enabled -Disabled $totalHuman.Disabled -Colour Yellow

Write-Host ""
Write-Host "  Exchange Resource Accounts  (non-human, excluded from licensing)" -ForegroundColor Cyan
Write-Host ("  " + ("═" * 63)) -ForegroundColor Cyan
Write-Host ""
Write-TableRow -Header
foreach ($row in $exchangeSummary) {
    Write-TableRow -Type $row.Type -Total $row.Total -Enabled $row.Enabled -Disabled $row.Disabled
}
Write-Host $divider -ForegroundColor DarkGray
Write-TableRow -Type $totalResources.Type -Total $totalResources.Total -Enabled $totalResources.Enabled -Disabled $totalResources.Disabled -Colour Yellow

Write-Host ""
Write-Host ("  " + ("═" * 63)) -ForegroundColor Green
Write-TableRow -Type $licensable.Type -Total $licensable.Total -Enabled $licensable.Enabled -Disabled $licensable.Disabled -Colour Green
Write-Host "  Members + Guests, minus Exchange resource accounts" -ForegroundColor DarkGray
Write-Host ("  " + ("═" * 63)) -ForegroundColor Green
Write-Host ""

# Create CSV output 

if ($Output -in @('CSV', 'All')) {
    $date        = Get-Date -Format 'yyyyMMdd'
    $csvEntra    = ".\EntraUserSummary_$date.csv"
    $csvExchange = ".\ExchangeMailboxSummary_$date.csv"

    # Add a blank separator row and the totals row into each CSV for clarity
    $entraCsvData = $entraSummary + [PSCustomObject]@{
        Type = ''; Total = ''; Enabled = ''; Disabled = ''
    } + $totalHuman + [PSCustomObject]@{
        Type = ''; Total = ''; Enabled = ''; Disabled = ''
    } + $licensable

    $exchangeCsvData = $exchangeSummary + [PSCustomObject]@{
        Type = ''; Total = ''; Enabled = ''; Disabled = ''
    } + $totalResources

    $entraCsvData    | Export-Csv -Path $csvEntra    -NoTypeInformation -Encoding UTF8
    $exchangeCsvData | Export-Csv -Path $csvExchange -NoTypeInformation -Encoding UTF8

}

# Create HTML output

if ($Output -in @('HTML', 'All')) {
    $date        = Get-Date -Format 'yyyyMMdd'
    $timestamp   = Get-Date -Format 'dd MMMM yyyy, HH:mm'
    $htmlFile    = ".\TenantUserSummary_$date.html"

    function ConvertTo-HtmlRows {
        param([PSCustomObject[]]$Data, [string]$TotalClass = '')
        $rows = ''
        foreach ($row in $Data) {
            $rows += "<tr><td>$($row.Type)</td><td>$($row.Total)</td><td>$($row.Enabled)</td><td>$($row.Disabled)</td></tr>`n"
        }
        return $rows
    }

    $entraRows    = ConvertTo-HtmlRows -Data $entraSummary
    $exchangeRows = ConvertTo-HtmlRows -Data $exchangeSummary

    $html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Tenant User Summary</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600&family=DM+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
  *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

  :root {
    --bg:         #f4f5f7;
    --surface:    #ffffff;
    --border:     #e4e6ea;
    --text:       #1a1d23;
    --text-muted: #6b7280;
    --accent:     #0f62fe;
    --green:      #0a7c41;
    --green-bg:   #f0faf4;
    --yellow:     #7c5c00;
    --yellow-bg:  #fefce8;
    --row-alt:    #f9fafb;
    --shadow:     0 1px 3px rgba(0,0,0,.06), 0 4px 16px rgba(0,0,0,.04);
  }

  body {
    font-family: 'DM Sans', sans-serif;
    background: var(--bg);
    color: var(--text);
    padding: 48px 24px;
    min-height: 100vh;
  }

  .page {
    max-width: 760px;
    margin: 0 auto;
  }

  header {
    margin-bottom: 40px;
  }

  header h1 {
    font-size: 1.75rem;
    font-weight: 600;
    letter-spacing: -0.02em;
    color: var(--text);
  }

  header p {
    margin-top: 6px;
    font-size: 0.875rem;
    color: var(--text-muted);
    font-weight: 300;
  }

  .card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    box-shadow: var(--shadow);
    margin-bottom: 24px;
    overflow: hidden;
  }

  .card-header {
    padding: 20px 24px 16px;
    border-bottom: 1px solid var(--border);
  }

  .card-header h2 {
    font-size: 0.9375rem;
    font-weight: 600;
    color: var(--text);
    letter-spacing: -0.01em;
  }

  .card-header p {
    font-size: 0.8125rem;
    color: var(--text-muted);
    margin-top: 3px;
    font-weight: 300;
  }

  table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.875rem;
  }

  thead th {
    padding: 10px 24px;
    text-align: left;
    font-size: 0.75rem;
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--text-muted);
    background: var(--row-alt);
    border-bottom: 1px solid var(--border);
  }

  thead th:not(:first-child) { text-align: right; }

  tbody tr:nth-child(even) { background: var(--row-alt); }

  tbody tr:hover { background: #f0f4ff; transition: background 0.15s; }

  tbody td {
    padding: 11px 24px;
    color: var(--text);
    font-family: 'DM Sans', sans-serif;
  }

  tbody td:not(:first-child) {
    text-align: right;
    font-family: 'DM Mono', monospace;
    font-size: 0.8125rem;
  }

  .total-row td {
    padding: 12px 24px;
    font-weight: 600;
    background: var(--yellow-bg) !important;
    color: var(--yellow);
    border-top: 1px solid var(--border);
  }

  .licensable-card {
    background: var(--green-bg);
    border: 1px solid #bbf0d4;
    border-radius: 12px;
    box-shadow: var(--shadow);
    margin-bottom: 24px;
    overflow: hidden;
  }

  .licensable-card .card-header {
    border-bottom: 1px solid #bbf0d4;
  }

  .licensable-card .card-header h2 { color: var(--green); }

  .licensable-card table thead th {
    background: #e6f7ee;
    border-bottom: 1px solid #bbf0d4;
  }

  .licensable-card tbody tr:nth-child(even) { background: #edf9f2; }
  .licensable-card tbody tr:hover { background: #ddf5e8; }

  .licensable-card .licensable-row td {
    font-weight: 600;
    font-size: 1rem;
    color: var(--green);
    padding: 16px 24px;
    font-family: 'DM Mono', monospace;
  }

  .licensable-card .licensable-row td:first-child {
    font-family: 'DM Sans', sans-serif;
  }

  footer {
    text-align: center;
    font-size: 0.75rem;
    color: var(--text-muted);
    margin-top: 16px;
    font-weight: 300;
  }
</style>
</head>
<body>
<div class="page">

  <header>
    <h1>Tenant User Summary</h1>
    <p>Generated $timestamp &nbsp;·&nbsp; Entra ID + Exchange Online</p>
  </header>

  <!-- Entra Summary -->
  <div class="card">
    <div class="card-header">
      <h2>Tenant User Account Summary</h2>
      <p>All user objects retrieved from Entra ID, split by user type</p>
    </div>
    <table>
      <thead>
        <tr><th>Type</th><th>Total</th><th>Enabled</th><th>Disabled</th></tr>
      </thead>
      <tbody>
        $entraRows
        <tr class="total-row">
          <td>$($totalHuman.Type)</td>
          <td>$($totalHuman.Total)</td>
          <td>$($totalHuman.Enabled)</td>
          <td>$($totalHuman.Disabled)</td>
        </tr>
      </tbody>
    </table>
  </div>

  <!-- Exchange Resource Summary -->
  <div class="card">
    <div class="card-header">
      <h2>Exchange Resource Accounts</h2>
      <p>Non-human accounts created by Exchange Online — excluded from IGA licensing counts</p>
    </div>
    <table>
      <thead>
        <tr><th>Type</th><th>Total</th><th>Enabled</th><th>Disabled</th></tr>
      </thead>
      <tbody>
        $exchangeRows
        <tr class="total-row">
          <td>$($totalResources.Type)</td>
          <td>$($totalResources.Total)</td>
          <td>$($totalResources.Enabled)</td>
          <td>$($totalResources.Disabled)</td>
        </tr>
      </tbody>
    </table>
  </div>

  <!-- Licensable Count -->
  <div class="licensable-card">
    <div class="card-header">
      <h2>Licensable Human Accounts</h2>
      <p>Members + Guests, minus Exchange resource accounts</p>
    </div>
    <table>
      <thead>
        <tr><th>Type</th><th>Total</th><th>Enabled</th><th>Disabled</th></tr>
      </thead>
      <tbody>
        <tr class="licensable-row">
          <td>$($licensable.Type)</td>
          <td>$($licensable.Total)</td>
          <td>$($licensable.Enabled)</td>
          <td>$($licensable.Disabled)</td>
        </tr>
      </tbody>
    </table>
  </div>

  <footer>
    Exported by ExportUserTypeCount.ps1 &nbsp;·&nbsp; $timestamp
  </footer>

</div>
</body>
</html>
"@

    $html | Out-File -FilePath $htmlFile -Encoding UTF8
}

# Output file summary

if ($Output -in @('CSV', 'HTML', 'All')) {
    $outputDir = (Resolve-Path .\).Path
    Write-Host "Output files written to: $outputDir" -ForegroundColor Cyan
    Write-Host ""
    if ($Output -in @('CSV', 'All')) {
        Write-Host "  [CSV]  $csvEntra"    -ForegroundColor White
        Write-Host "  [CSV]  $csvExchange" -ForegroundColor White
    }
    if ($Output -in @('HTML', 'All')) {
        Write-Host "  [HTML] $htmlFile"    -ForegroundColor White
    }
    Write-Host ""
}