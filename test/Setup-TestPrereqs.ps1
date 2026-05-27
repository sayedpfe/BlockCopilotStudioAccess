#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Groups, Microsoft.Graph.Users, Microsoft.Graph.Identity.DirectoryManagement

<#
.SYNOPSIS
    Creates the prerequisites for testing the Copilot Studio lockdown in a TEST tenant:
    the authors security group and two test users (one future "author", one "blocked").
.DESCRIPTION
    Idempotent. Creates the 'Copilot Studio Authors' Entra security group if missing and
    two cloud users for the before/after test. Optionally assigns a license so the
    "blocked" user can actually reach Copilot Studio (needed to reproduce the baseline
    AND to provision the Copilot Studio enterprise apps in a brand-new tenant).
    DEMO/TEST TENANT ONLY: the script verifies the signed-in tenant's default domain
    matches -TenantDomain and aborts otherwise.
    Blast radius: creates directory objects (1 group, 2 users) and, if -LicenseSkuPartNumber
    is given, consumes one license seat. Nothing tenant-wide is changed.
.PARAMETER TenantDomain
    The test tenant's default domain (e.g. contoso.onmicrosoft.com). Used both as a
    demo-tenant guard and to build the test users' UPNs.
.PARAMETER AuthorsGroupName
    Name of the security group the lockdown scopes access to. Default 'Copilot Studio Authors'.
.PARAMETER AuthorMailNickname
    Mail nickname / UPN prefix for the user who WILL be granted access. Default 'cps-author1'.
.PARAMETER BlockedMailNickname
    Mail nickname / UPN prefix for the user who should END UP blocked. Default 'cps-blocked1'.
.PARAMETER LicenseSkuPartNumber
    Optional SKU part number to assign to the blocked user so they can reach Copilot Studio
    (e.g. a Copilot Studio or Microsoft 365 Copilot SKU available in the tenant). If omitted,
    assign a license manually before the baseline test.
.PARAMETER UsageLocation
    ISO country code required before any license can be assigned. Default 'US'.
.PARAMETER WhatIf
    Preview every object that would be created without creating it.
.EXAMPLE
    .\Setup-TestPrereqs.ps1 -TenantDomain contoso.onmicrosoft.com -WhatIf
    Shows the group + users that would be created.
.EXAMPLE
    .\Setup-TestPrereqs.ps1 -TenantDomain contoso.onmicrosoft.com -LicenseSkuPartNumber Microsoft_365_Copilot
    Creates the group + two users and licenses the blocked user so they can reach Copilot Studio.
.NOTES
    Required role: User Administrator + Groups Administrator (or Global Administrator).
    Graph scopes: Group.ReadWrite.All, User.ReadWrite.All, Organization.Read.All,
    and (only with -LicenseSkuPartNumber) Directory.Read.All.
    Author: Sayed Ali, Microsoft CSA. Not an official Microsoft solution. TEST TENANT ONLY.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9-]+\.[A-Za-z0-9.-]+$')]
    [string] $TenantDomain,

    [ValidateNotNullOrEmpty()]
    [string] $AuthorsGroupName = 'Copilot Studio Authors',

    [ValidateNotNullOrEmpty()]
    [string] $AuthorMailNickname = 'cps-author1',

    [ValidateNotNullOrEmpty()]
    [string] $BlockedMailNickname = 'cps-blocked1',

    [string] $LicenseSkuPartNumber,

    [ValidateNotNullOrEmpty()]
    [string] $UsageLocation = 'US'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- auth (reuse context if sufficient) ---
$needScopes = @('Group.ReadWrite.All','User.ReadWrite.All','Organization.Read.All')
if ($LicenseSkuPartNumber) { $needScopes += 'Directory.Read.All' }
$ctx = Get-MgContext
if (-not $ctx) {
    Connect-MgGraph -NoWelcome -Scopes $needScopes
} else {
    $missing = $needScopes | Where-Object { $_ -notin $ctx.Scopes }
    if ($missing) { throw "Current Graph context lacks scopes: $($missing -join ', '). Run Disconnect-MgGraph and re-run." }
}

# --- DEMO/TEST TENANT guard ---
$defaultDomain = ((Get-MgOrganization).VerifiedDomains | Where-Object { $_.IsDefault }).Name
if ($defaultDomain.ToLower() -ne $TenantDomain.ToLower()) {
    throw "ABORT: signed-in tenant '$defaultDomain' does not match -TenantDomain '$TenantDomain'. Nothing created."
}
Write-Host "Demo-tenant guard passed: $defaultDomain"

# --- helper: random complex password ---
function New-TestPassword {
    $u = -join ((65..90)  | Get-Random -Count 3 | ForEach-Object {[char]$_})
    $l = -join ((97..122) | Get-Random -Count 4 | ForEach-Object {[char]$_})
    $d = -join ((0..9)    | Get-Random -Count 3)
    return "$u$l$d!"
}

$created = [System.Collections.Generic.List[object]]::new()

# --- 1. group (idempotent) ---
$group = Get-MgGroup -Filter "displayName eq '$AuthorsGroupName'" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($group) {
    Write-Host "Group '$AuthorsGroupName' already exists ($($group.Id))."
} elseif ($PSCmdlet.ShouldProcess($AuthorsGroupName, "Create security group")) {
    $group = New-MgGroup -DisplayName $AuthorsGroupName -MailEnabled:$false `
                         -MailNickname ($AuthorsGroupName -replace '[^A-Za-z0-9]','') `
                         -SecurityEnabled:$true
    Write-Host "Created group '$AuthorsGroupName' ($($group.Id))."
}

# --- 2. test users (idempotent) ---
function New-TestUser {
    param([string]$Nick,[string]$Display)
    $upn = "$Nick@$TenantDomain"
    $existing = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) { Write-Host "User $upn already exists ($($existing.Id))."; return [pscustomobject]@{ Upn=$upn; Id=$existing.Id; Password=$null } }
    if (-not $PSCmdlet.ShouldProcess($upn, "Create test user")) { return $null }
    $pw = New-TestPassword
    $u = New-MgUser -DisplayName $Display -AccountEnabled:$true -MailNickname $Nick `
                    -UserPrincipalName $upn -UsageLocation $UsageLocation `
                    -PasswordProfile @{ Password = $pw; ForceChangePasswordNextSignIn = $false }
    Write-Host "Created user $upn ($($u.Id))."
    return [pscustomobject]@{ Upn=$upn; Id=$u.Id; Password=$pw }
}
$author  = New-TestUser -Nick $AuthorMailNickname  -Display 'CPS Test Author'
$blocked = New-TestUser -Nick $BlockedMailNickname -Display 'CPS Test Blocked'
if ($author)  { $created.Add($author) }
if ($blocked) { $created.Add($blocked) }

# --- 3. optional license on the blocked user (to reproduce access + provision the CPS apps) ---
if ($LicenseSkuPartNumber -and $blocked) {
    $sku = Get-MgSubscribedSku -All | Where-Object { $_.SkuPartNumber -eq $LicenseSkuPartNumber } | Select-Object -First 1
    if (-not $sku) { Write-Warning "SKU '$LicenseSkuPartNumber' not found in tenant. Skipping license assignment." }
    elseif ($PSCmdlet.ShouldProcess($blocked.Upn, "Assign license $LicenseSkuPartNumber")) {
        Set-MgUserLicense -UserId $blocked.Id -AddLicenses @(@{ SkuId = $sku.SkuId }) -RemoveLicenses @() | Out-Null
        Write-Host "Assigned $LicenseSkuPartNumber to $($blocked.Upn)."
    }
}

# --- summary ---
Write-Host "`n=== Prerequisites ready ==="
foreach ($c in $created) {
    if ($c.Password) { Write-Host ("  {0}  (initial password: {1})" -f $c.Upn, $c.Password) }
    else             { Write-Host ("  {0}" -f $c.Upn) }
}
Write-Host "`nNext:"
Write-Host "  1. Sign in as the blocked user at https://copilotstudio.microsoft.com to confirm baseline access AND provision the Copilot Studio enterprise apps."
Write-Host "  2. Run .\Snapshot-TenantState.ps1 -TenantDomain $TenantDomain"
Write-Host "  3. Apply the lockdown, then .\Verify-Lockdown.ps1"
