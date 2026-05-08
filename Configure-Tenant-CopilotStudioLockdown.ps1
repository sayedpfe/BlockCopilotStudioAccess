# =============================================================================
# Configure-Tenant-CopilotStudioLockdown.ps1
# -----------------------------------------------------------------------------
# ONE-TIME tenant configuration. After running this:
#   * No one can use the Copilot Studio web portal except members of the
#     'Copilot Studio Authors' Entra group.
#   * No user can self-acquire viral / internal trial SKUs (which would
#     otherwise bypass the group restriction).
#   * Non-admins cannot create production / trial / developer environments
#     from make.powerapps.com.
#
# Adding a user to the 'Copilot Studio Authors' group is then the ONLY thing
# needed to grant Copilot Studio access.
#
# Required roles: Power Platform Administrator + Global Administrator
# =============================================================================

$ErrorActionPreference = 'Stop'

$AuthorsGroupName = 'Copilot Studio Authors'   # change if your group is named differently

# -----------------------------------------------------------------------------
# 0. Module check
# -----------------------------------------------------------------------------
$required = @(
    'Microsoft.PowerApps.Administration.PowerShell',
    'Microsoft.PowerApps.PowerShell',
    'Microsoft.Graph.Authentication',
    'Microsoft.Graph.Applications',
    'Microsoft.Graph.Groups'
)
foreach ($m in $required) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host "Installing $m ..."
        Install-Module $m -Scope CurrentUser -Force -AllowClobber
    }
}

# -----------------------------------------------------------------------------
# 1. Sign in
# -----------------------------------------------------------------------------
Write-Host "`n=== Signing in to Power Platform ==="
Add-PowerAppsAccount | Out-Null

Write-Host "`n=== Signing in to Microsoft Graph ==="
Connect-MgGraph -NoWelcome -Scopes `
    "Application.ReadWrite.All","AppRoleAssignment.ReadWrite.All","Group.Read.All"

# -----------------------------------------------------------------------------
# 2. LAYER 3 — Power Platform tenant flags
# -----------------------------------------------------------------------------
Write-Host "`n=== Layer 3: Power Platform tenant flags ==="
$ppBody = [pscustomobject]@{
    disableEnvironmentCreationByNonAdminUsers      = $true
    disableTrialEnvironmentCreationByNonAdminUsers = $true
    powerPlatform = [pscustomobject]@{
        governance = [pscustomobject]@{
            disableDeveloperEnvironmentCreationByNonAdminUsers = $true
        }
    }
}
Set-TenantSettings -RequestBody $ppBody | Out-Null

$v = Get-TenantSettings
"  disableEnvironmentCreationByNonAdminUsers           = $($v.disableEnvironmentCreationByNonAdminUsers)"
"  disableTrialEnvironmentCreationByNonAdminUsers      = $($v.disableTrialEnvironmentCreationByNonAdminUsers)"
"  disableDeveloperEnvironmentCreationByNonAdminUsers  = $($v.powerPlatform.governance.disableDeveloperEnvironmentCreationByNonAdminUsers)"

# -----------------------------------------------------------------------------
# 3. LAYER 2 — Block self-service viral / internal trials
# -----------------------------------------------------------------------------
Write-Host "`n=== Layer 2: Removing Internal + Viral consent plans ==="
try {
    Remove-AllowedConsentPlans -Types @('Internal','Viral') -ErrorAction Stop
    "  Removed."
} catch {
    "  (Already removed or: $($_.Exception.Message))"
}
"  Currently allowed: $((Get-AllowedConsentPlans).types -join ', ')"

# -----------------------------------------------------------------------------
# 4. LAYER 1 — Lock Copilot Studio web portal to the Authors group
#    Affects two enterprise apps:
#       Power Virtual Agents              (96ff4394-...)  -> portal sign-in
#       Microsoft Copilot Studio Service  (9d8f559b-...)  -> service backend
# -----------------------------------------------------------------------------
Write-Host "`n=== Layer 1: Locking Copilot Studio portal to '$AuthorsGroupName' ==="

$group = Get-MgGroup -Filter "displayName eq '$AuthorsGroupName'" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $group) {
    throw "Group '$AuthorsGroupName' not found. Create it first or edit `$AuthorsGroupName at the top of this script."
}
"  Authors group: $($group.DisplayName) ($($group.Id))"

$targets = @(
    '96ff4394-9197-43aa-b393-6a41652e21f8',   # Power Virtual Agents
    '9d8f559b-5984-46a4-902a-ad4271e83efa'    # Microsoft Copilot Studio Service
)

foreach ($appId in $targets) {
    $sp = Get-MgServicePrincipal -Filter "appId eq '$appId'" -ErrorAction SilentlyContinue
    if (-not $sp) { Write-Warning "  Service principal $appId not found. Skipping."; continue }

    "  --- $($sp.DisplayName) ---"

    if (-not $sp.AppRoleAssignmentRequired) {
        Update-MgServicePrincipal -ServicePrincipalId $sp.Id -AppRoleAssignmentRequired:$true
        "    AppRoleAssignmentRequired -> True"
    } else {
        "    AppRoleAssignmentRequired already True"
    }

    $alreadyAssigned = Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $sp.Id -All |
                       Where-Object { $_.PrincipalId -eq $group.Id }
    if ($alreadyAssigned) {
        "    Group already assigned"
    } else {
        New-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $sp.Id -BodyParameter @{
            principalId = $group.Id
            resourceId  = $sp.Id
            appRoleId   = '00000000-0000-0000-0000-000000000000'
        } | Out-Null
        "    Group assigned"
    }
}

Write-Host "`n=== Tenant configuration complete ==="
Write-Host "To grant a user access to Copilot Studio, simply add them to the '$AuthorsGroupName' group."
Write-Host "Example:"
Write-Host "    .\Grant-CopilotStudioAccess.ps1 -Upn newuser@yourtenant.onmicrosoft.com"
