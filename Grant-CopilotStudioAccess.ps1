# =============================================================================
# Grant-CopilotStudioAccess.ps1
# -----------------------------------------------------------------------------
# Adds a user to the 'Copilot Studio Authors' group, which is the only thing
# needed (after the tenant is configured) to grant Copilot Studio access.
#
# Usage:
#   .\Grant-CopilotStudioAccess.ps1 -Upn user@yourtenant.onmicrosoft.com
# =============================================================================
param(
    [Parameter(Mandatory)] [string] $Upn,
    [string] $GroupName = 'Copilot Studio Authors'
)
$ErrorActionPreference = 'Stop'

if (-not (Get-MgContext)) {
    Connect-MgGraph -NoWelcome -Scopes "Group.ReadWrite.All","User.Read.All"
}

$group = Get-MgGroup -Filter "displayName eq '$GroupName'" -ErrorAction Stop | Select-Object -First 1
$user  = Get-MgUser  -UserId $Upn -ErrorAction Stop

# Skip if already a member
$existing = Get-MgGroupMember -GroupId $group.Id -All | Where-Object { $_.Id -eq $user.Id }
if ($existing) {
    Write-Host "$($user.UserPrincipalName) is already a member of '$GroupName'."
    return
}

New-MgGroupMember -GroupId $group.Id -DirectoryObjectId $user.Id
Write-Host "Added $($user.UserPrincipalName) to '$GroupName'."
Write-Host "User must sign out and back in. Propagation can take 5-60 minutes."
