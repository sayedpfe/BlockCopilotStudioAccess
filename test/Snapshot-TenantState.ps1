#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications, Microsoft.Graph.Groups, Microsoft.Graph.Identity.SignIns, Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Captures the pre-change state of everything the Copilot Studio lockdown touches, to JSON.
.DESCRIPTION
    READ-ONLY. Because the lockdown script has no -WhatIf, this snapshot is the rollback
    safety net and the baseline for Verify-Lockdown.ps1. Captures: the 3 environment-creation
    tenant flags, allowed consent plans, the Entra authorization-policy sign-up flag, the two
    Copilot Studio enterprise apps (AppRoleAssignmentRequired + assignments), and the authors
    group membership. Changes nothing. DEMO/TEST TENANT ONLY (guarded by -TenantDomain).
    Expect 2 interactive sign-ins: Microsoft Graph and Power Platform.
.PARAMETER TenantDomain
    The test tenant's default domain. Demo-tenant guard — aborts if the signed-in tenant differs.
.PARAMETER AuthorsGroupName
    Security group to snapshot. Default 'Copilot Studio Authors'.
.PARAMETER OutputPath
    Where to write the snapshot JSON. Default .\tenant-snapshot-<yyyy-MM-dd>.json
.EXAMPLE
    .\Snapshot-TenantState.ps1 -TenantDomain contoso.onmicrosoft.com
.NOTES
    Required role: reader-level is enough (Global Reader + Power Platform Admin to read settings).
    Graph scopes: Application.Read.All, Group.Read.All, Policy.Read.All, Organization.Read.All.
    Author: Sayed Ali, Microsoft CSA. Not an official Microsoft solution. TEST TENANT ONLY.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9-]+\.[A-Za-z0-9.-]+$')]
    [string] $TenantDomain,

    [ValidateNotNullOrEmpty()]
    [string] $AuthorsGroupName = 'Copilot Studio Authors',

    [string] $OutputPath = ".\tenant-snapshot-$(Get-Date -Format 'yyyy-MM-dd').json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# the two Copilot Studio first-party apps the lockdown targets
$targetApps = [ordered]@{
    'PowerVirtualAgents_96ff4394'   = '96ff4394-9197-43aa-b393-6a41652e21f8'
    'CopilotStudioService_9d8f559b' = '9d8f559b-5984-46a4-902a-ad4271e83efa'
}

# --- Graph auth (read-only) ---
$needScopes = @('Application.Read.All','Group.Read.All','Policy.Read.All','Organization.Read.All')
$ctx = Get-MgContext
if (-not $ctx) { Connect-MgGraph -NoWelcome -Scopes $needScopes }
else {
    $missing = $needScopes | Where-Object { $_ -notin $ctx.Scopes }
    if ($missing) { throw "Current Graph context lacks scopes: $($missing -join ', '). Disconnect-MgGraph and re-run." }
}

# --- DEMO/TEST TENANT guard ---
$org = Get-MgOrganization
$defaultDomain = ($org.VerifiedDomains | Where-Object { $_.IsDefault }).Name
if ($defaultDomain.ToLower() -ne $TenantDomain.ToLower()) {
    throw "ABORT: signed-in tenant '$defaultDomain' does not match -TenantDomain '$TenantDomain'. Nothing captured."
}
Write-Host "Demo-tenant guard passed: $defaultDomain"

$snap = [ordered]@{ meta = [ordered]@{ tenant = $defaultDomain; tenantId = $org.Id; date = (Get-Date -Format 'yyyy-MM-dd'); capturedBy = 'Snapshot-TenantState.ps1' } }

# --- service principals ---
Write-Verbose "Reading service principals"
$sp = [ordered]@{}
foreach ($k in $targetApps.Keys) {
    $id = $targetApps[$k]
    $s = Get-MgServicePrincipal -Filter "appId eq '$id'" -ErrorAction SilentlyContinue
    if ($s) {
        $asg = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $s.Id -All -ErrorAction SilentlyContinue
        $sp[$k] = [ordered]@{ appId=$id; found=$true; spObjectId=$s.Id; displayName=$s.DisplayName
            appRoleAssignmentRequired=$s.AppRoleAssignmentRequired
            assignments=@($asg | ForEach-Object { @{ principalId=$_.PrincipalId; principalDisplayName=$_.PrincipalDisplayName; principalType=$_.PrincipalType } }) }
    } else {
        $sp[$k] = [ordered]@{ appId=$id; found=$false }
    }
}
$snap.servicePrincipals = $sp

# --- authorization policy ---
$snap.authorizationPolicy = [ordered]@{ allowedToSignUpEmailBasedSubscriptions = (Get-MgPolicyAuthorizationPolicy).AllowedToSignUpEmailBasedSubscriptions }

# --- authors group ---
$grp = Get-MgGroup -Filter "displayName eq '$AuthorsGroupName'" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($grp) {
    $members = Get-MgGroupMember -GroupId $grp.Id -All -ErrorAction SilentlyContinue
    $snap.authorsGroup = [ordered]@{ found=$true; id=$grp.Id; displayName=$grp.DisplayName
        members=@($members | ForEach-Object { @{ id=$_.Id; display=$_.AdditionalProperties['displayName']; upn=$_.AdditionalProperties['userPrincipalName'] } }) }
} else {
    $snap.authorsGroup = [ordered]@{ found=$false; displayName=$AuthorsGroupName }
}

# --- Power Platform (tenant settings + consent plans) ---
Write-Host "`nConnecting to Power Platform..."
Add-PowerAppsAccount | Out-Null
$ts = Get-TenantSettings
$snap.tenantSettings = [ordered]@{
    disableEnvironmentCreationByNonAdminUsers          = $ts.disableEnvironmentCreationByNonAdminUsers
    disableTrialEnvironmentCreationByNonAdminUsers     = $ts.disableTrialEnvironmentCreationByNonAdminUsers
    disableDeveloperEnvironmentCreationByNonAdminUsers = $ts.powerPlatform.governance.disableDeveloperEnvironmentCreationByNonAdminUsers
}
$snap.allowedConsentPlans = @((Get-AllowedConsentPlans).types)

$snap | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8
Write-Host "`n=== Snapshot written: $OutputPath ==="
Write-Host "Keep this file — Rollback-Lockdown.ps1 restores the tenant from it."
