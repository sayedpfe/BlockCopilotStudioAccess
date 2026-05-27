#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication, Microsoft.Graph.Applications, Microsoft.Graph.Groups, Microsoft.Graph.Identity.SignIns, Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Read-only PASS/FAIL check that the Copilot Studio lockdown is fully applied.
.DESCRIPTION
    READ-ONLY. Verifies all four layers are in the locked state: the 3 environment-creation
    flags = True, consent plans empty, allowedToSignUpEmailBasedSubscriptions = False, and both
    Copilot Studio enterprise apps have AppRoleAssignmentRequired = True with the authors group
    assigned. Prints a result row per check and an overall verdict. The user-facing sign-in block
    (AADSTS50105) is NOT programmatically verifiable — this script reminds you to test it manually.
    DEMO/TEST TENANT ONLY (guarded by -TenantDomain). Expect 2 interactive sign-ins.
.PARAMETER TenantDomain
    The test tenant's default domain. Demo-tenant guard.
.PARAMETER AuthorsGroupName
    Security group expected to be assigned to the apps. Default 'Copilot Studio Authors'.
.EXAMPLE
    .\Verify-Lockdown.ps1 -TenantDomain contoso.onmicrosoft.com
.NOTES
    Required role: reader-level + Power Platform Admin to read tenant settings.
    Graph scopes: Application.Read.All, Group.Read.All, Policy.Read.All, Organization.Read.All.
    Author: Sayed Ali, Microsoft CSA. Not an official Microsoft solution. TEST TENANT ONLY.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Za-z0-9-]+\.[A-Za-z0-9.-]+$')]
    [string] $TenantDomain,

    [ValidateNotNullOrEmpty()]
    [string] $AuthorsGroupName = 'Copilot Studio Authors'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$targetApps = [ordered]@{
    'Power Virtual Agents (96ff4394)'        = '96ff4394-9197-43aa-b393-6a41652e21f8'
    'Copilot Studio Service (9d8f559b)'      = '9d8f559b-5984-46a4-902a-ad4271e83efa'
}

$needScopes = @('Application.Read.All','Group.Read.All','Policy.Read.All','Organization.Read.All')
$ctx = Get-MgContext
if (-not $ctx) { Connect-MgGraph -NoWelcome -Scopes $needScopes }
else {
    $missing = $needScopes | Where-Object { $_ -notin $ctx.Scopes }
    if ($missing) { throw "Current Graph context lacks scopes: $($missing -join ', '). Disconnect-MgGraph and re-run." }
}

$defaultDomain = ((Get-MgOrganization).VerifiedDomains | Where-Object { $_.IsDefault }).Name
if ($defaultDomain.ToLower() -ne $TenantDomain.ToLower()) {
    throw "ABORT: signed-in tenant '$defaultDomain' does not match -TenantDomain '$TenantDomain'."
}

$results = [System.Collections.Generic.List[object]]::new()
function Add-Check { param($Name,$Expected,$Actual)
    $pass = ($Expected -eq $Actual) -or ($Expected -is [array] -and $Actual -is [array] -and -not (Compare-Object $Expected $Actual))
    $results.Add([pscustomobject]@{ Check=$Name; Expected="$Expected"; Actual="$Actual"; Result= ($(if($pass){'PASS'}else{'FAIL'})) })
}

# --- authorization policy ---
$flag = (Get-MgPolicyAuthorizationPolicy).AllowedToSignUpEmailBasedSubscriptions
Add-Check 'Entra: allowedToSignUpEmailBasedSubscriptions = False (blocked)' $false $flag

# --- authors group + app locks ---
$grp = Get-MgGroup -Filter "displayName eq '$AuthorsGroupName'" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $grp) {
    $results.Add([pscustomobject]@{ Check="Authors group '$AuthorsGroupName' exists"; Expected='exists'; Actual='NOT FOUND'; Result='FAIL' })
} else {
    foreach ($name in $targetApps.Keys) {
        $s = Get-MgServicePrincipal -Filter "appId eq '$($targetApps[$name])'" -ErrorAction SilentlyContinue
        if (-not $s) {
            $results.Add([pscustomobject]@{ Check="$name SP exists"; Expected='exists'; Actual='NOT FOUND (app not provisioned?)'; Result='FAIL' })
            continue
        }
        Add-Check "$name : AppRoleAssignmentRequired = True" $true $s.AppRoleAssignmentRequired
        $asg = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $s.Id -All -ErrorAction SilentlyContinue
        $hasGroup = [bool]($asg | Where-Object { $_.PrincipalId -eq $grp.Id })
        Add-Check "$name : authors group assigned" $true $hasGroup
    }
}

# --- Power Platform ---
Write-Host "Connecting to Power Platform..."
Add-PowerAppsAccount | Out-Null
$ts = Get-TenantSettings
Add-Check 'PP: disableEnvironmentCreationByNonAdminUsers = True'          $true $ts.disableEnvironmentCreationByNonAdminUsers
Add-Check 'PP: disableTrialEnvironmentCreationByNonAdminUsers = True'     $true $ts.disableTrialEnvironmentCreationByNonAdminUsers
Add-Check 'PP: disableDeveloperEnvironmentCreationByNonAdminUsers = True' $true $ts.powerPlatform.governance.disableDeveloperEnvironmentCreationByNonAdminUsers
$plans = @((Get-AllowedConsentPlans).types)
Add-Check 'PP: allowed consent plans empty (Internal/Viral removed)' @() $plans

# --- report ---
$results | Format-Table -AutoSize
$fail = @($results | Where-Object Result -eq 'FAIL').Count
Write-Host ""
if ($fail -eq 0) { Write-Host "OVERALL: PASS — all programmatic checks locked." -ForegroundColor Green }
else { Write-Host "OVERALL: $fail check(s) FAILED — see table above." -ForegroundColor Red }

Write-Host "`nStill to test MANUALLY (cannot be confirmed via API):"
Write-Host "  * Author user (in '$AuthorsGroupName') signs into https://copilotstudio.microsoft.com -> should REACH the portal."
Write-Host "  * Non-member user (no CPS/Copilot license) -> should be BLOCKED with AADSTS50105."
Write-Host "  * Non-admin tries to create an environment / start a trial -> should be blocked. Allow 5-60 min propagation."
