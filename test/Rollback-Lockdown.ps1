#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications, Microsoft.Graph.Identity.SignIns, Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Restores the tenant to the pre-lockdown state captured by Snapshot-TenantState.ps1.
.DESCRIPTION
    Reverses every change the lockdown made, using the snapshot JSON as the source of truth:
      * environment-creation tenant flags  -> snapshot values
      * allowed consent plans              -> re-adds the types present in the snapshot
      * allowedToSignUpEmailBasedSubscriptions -> snapshot value
      * each Copilot Studio app's AppRoleAssignmentRequired -> snapshot value, and removes any
        app-role assignment that was NOT in the snapshot (i.e. added by the lockdown)
    Supports -WhatIf on every change. Optionally tears down the test group + test users with
    -RemoveTestObjects. DEMO/TEST TENANT ONLY (guarded by -TenantDomain). 2 interactive sign-ins.
.PARAMETER SnapshotPath
    Path to the JSON produced by Snapshot-TenantState.ps1.
.PARAMETER TenantDomain
    The test tenant's default domain. Demo-tenant guard.
.PARAMETER RemoveTestObjects
    Also delete the authors group and the named test users (full teardown).
.PARAMETER AuthorsGroupName
    Group to delete when -RemoveTestObjects. Default 'Copilot Studio Authors'.
.PARAMETER TestUserUpns
    Test user UPNs to delete when -RemoveTestObjects.
.PARAMETER WhatIf
    Preview every restore action without applying it.
.EXAMPLE
    .\Rollback-Lockdown.ps1 -SnapshotPath .\tenant-snapshot-2026-05-27.json -TenantDomain contoso.onmicrosoft.com -WhatIf
.EXAMPLE
    .\Rollback-Lockdown.ps1 -SnapshotPath .\tenant-snapshot-2026-05-27.json -TenantDomain contoso.onmicrosoft.com -RemoveTestObjects -TestUserUpns cps-author1@contoso.onmicrosoft.com,cps-blocked1@contoso.onmicrosoft.com
.NOTES
    Required role: Global Administrator + Power Platform Administrator (and User/Groups Admin for -RemoveTestObjects).
    Graph scopes: Application.ReadWrite.All, AppRoleAssignment.ReadWrite.All, Policy.ReadWrite.Authorization,
    Organization.Read.All (+ Group.ReadWrite.All, User.ReadWrite.All with -RemoveTestObjects).
    Author: Sayed Ali, Microsoft CSA. Not an official Microsoft solution. TEST TENANT ONLY.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ })]
    [string] $SnapshotPath,

    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9-]+\.[A-Za-z0-9.-]+$')]
    [string] $TenantDomain,

    [switch] $RemoveTestObjects,
    [string] $AuthorsGroupName = 'Copilot Studio Authors',
    [string[]] $TestUserUpns = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$snap = Get-Content $SnapshotPath -Raw | ConvertFrom-Json -AsHashtable

$needScopes = @('Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All','Policy.ReadWrite.Authorization','Organization.Read.All')
if ($RemoveTestObjects) { $needScopes += @('Group.ReadWrite.All','User.ReadWrite.All') }
$ctx = Get-MgContext
if (-not $ctx) { Connect-MgGraph -NoWelcome -Scopes $needScopes }
else {
    $missing = $needScopes | Where-Object { $_ -notin $ctx.Scopes }
    if ($missing) { throw "Current Graph context lacks scopes: $($missing -join ', '). Disconnect-MgGraph and re-run." }
}

$defaultDomain = ((Get-MgOrganization).VerifiedDomains | Where-Object { $_.IsDefault }).Name
if ($defaultDomain.ToLower() -ne $TenantDomain.ToLower()) {
    throw "ABORT: signed-in tenant '$defaultDomain' does not match -TenantDomain '$TenantDomain'. Nothing restored."
}
if ($snap.meta.tenant.ToLower() -ne $defaultDomain.ToLower()) {
    throw "ABORT: snapshot was taken in tenant '$($snap.meta.tenant)', not '$defaultDomain'. Wrong snapshot."
}
Write-Host "Restoring '$defaultDomain' from snapshot $($snap.meta.date)..."

# --- 1. Entra authorization policy ---
$wantFlag = [bool]$snap.authorizationPolicy.allowedToSignUpEmailBasedSubscriptions
if ($PSCmdlet.ShouldProcess('authorizationPolicy', "Set allowedToSignUpEmailBasedSubscriptions = $wantFlag")) {
    Update-MgPolicyAuthorizationPolicy -BodyParameter @{ allowedToSignUpEmailBasedSubscriptions = $wantFlag } | Out-Null
    Write-Host "  allowedToSignUpEmailBasedSubscriptions -> $wantFlag"
}

# --- 2. service principal locks ---
foreach ($k in $snap.servicePrincipals.Keys) {
    $rec = $snap.servicePrincipals[$k]
    if (-not $rec.found) { continue }
    $s = Get-MgServicePrincipal -Filter "appId eq '$($rec.appId)'" -ErrorAction SilentlyContinue
    if (-not $s) { Write-Warning "  ${k}: SP no longer present, skipping."; continue }
    $wantReq = [bool]$rec.appRoleAssignmentRequired
    if ($s.AppRoleAssignmentRequired -ne $wantReq -and $PSCmdlet.ShouldProcess($s.DisplayName, "Set AppRoleAssignmentRequired = $wantReq")) {
        Update-MgServicePrincipal -ServicePrincipalId $s.Id -AppRoleAssignmentRequired:$wantReq
        Write-Host "  $($s.DisplayName): AppRoleAssignmentRequired -> $wantReq"
    }
    # remove assignments added after the snapshot
    $snapPrincipals = @($rec.assignments | ForEach-Object { $_.principalId })
    $current = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $s.Id -All -ErrorAction SilentlyContinue
    foreach ($a in $current) {
        if ($a.PrincipalId -notin $snapPrincipals -and
            $PSCmdlet.ShouldProcess($s.DisplayName, "Remove app-role assignment for $($a.PrincipalDisplayName) (added after snapshot)")) {
            Remove-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $s.Id -AppRoleAssignmentId $a.Id
            Write-Host "  $($s.DisplayName): removed assignment for $($a.PrincipalDisplayName)"
        }
    }
}

# --- 3. Power Platform tenant flags + consent plans ---
Write-Host "Connecting to Power Platform..."
Add-PowerAppsAccount | Out-Null
$ppBody = [pscustomobject]@{
    disableEnvironmentCreationByNonAdminUsers      = [bool]$snap.tenantSettings.disableEnvironmentCreationByNonAdminUsers
    disableTrialEnvironmentCreationByNonAdminUsers = [bool]$snap.tenantSettings.disableTrialEnvironmentCreationByNonAdminUsers
    powerPlatform = [pscustomobject]@{ governance = [pscustomobject]@{
        disableDeveloperEnvironmentCreationByNonAdminUsers = [bool]$snap.tenantSettings.disableDeveloperEnvironmentCreationByNonAdminUsers } }
}
if ($PSCmdlet.ShouldProcess('tenant settings', "Restore env-creation flags to snapshot values")) {
    Set-TenantSettings -RequestBody $ppBody | Out-Null
    Write-Host "  Restored env-creation flags."
}
$wantPlans = @($snap.allowedConsentPlans)
$nowPlans  = @((Get-AllowedConsentPlans).types)
$toAdd = $wantPlans | Where-Object { $_ -notin $nowPlans }
if ($toAdd -and $PSCmdlet.ShouldProcess('consent plans', "Add back: $($toAdd -join ', ')")) {
    Add-AllowedConsentPlans -Types $toAdd
    Write-Host "  Re-added consent plans: $($toAdd -join ', ')"
} elseif (-not $toAdd) {
    Write-Host "  Consent plans already match snapshot ($($wantPlans -join ', ' ))."
}

# --- 4. optional teardown ---
if ($RemoveTestObjects) {
    foreach ($upn in $TestUserUpns) {
        $u = Get-MgUser -Filter "userPrincipalName eq '$upn'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($u -and $PSCmdlet.ShouldProcess($upn, "Delete test user")) { Remove-MgUser -UserId $u.Id; Write-Host "  Deleted user $upn" }
    }
    $g = Get-MgGroup -Filter "displayName eq '$AuthorsGroupName'" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($g -and $PSCmdlet.ShouldProcess($AuthorsGroupName, "Delete test group")) { Remove-MgGroup -GroupId $g.Id; Write-Host "  Deleted group $AuthorsGroupName" }
}

Write-Host "`n=== Rollback complete. Run Verify-Lockdown.ps1 to confirm the tenant is unlocked. ==="
