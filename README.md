# Copilot Studio Access Lockdown

PowerShell scripts to restrict **Microsoft Copilot Studio** and **Dataverse-for-Teams environment creation** to a single Microsoft Entra security group in your tenant.

> [!WARNING]
> ## ⚠️ Use at your own risk
>
> **This is not an official Microsoft solution.** It is a community workaround discovered through testing and reading public Microsoft Learn documentation. It works against undocumented combinations of tenant-level controls and Entra app assignment requirements.
>
> - Microsoft has explicitly stated in the docs that **no single supported setting blocks Dataverse-for-Teams environment creation**.
> - The approach here combines four independent locks. Microsoft may change any of them at any time without notice.
> - Service-principal `AppId` values for *Power Virtual Agents* and *Microsoft Copilot Studio Service* are hard-coded; if Microsoft introduces new apps for the same surface, this script will not block them.
> - **Test in a non-production tenant first.** The author and contributors accept no responsibility for tenant-wide outages, broken automations, lost productivity, or licensing changes that may result from running these scripts.
> - Always review every command before running it as a Global / Power Platform Administrator.

---

## What it does

The `Configure-Tenant-CopilotStudioLockdown.ps1` script applies **three independent layers** of defense:

| Layer | Control | Effect |
|---|---|---|
| **1. Entra portal lock** | Sets `AppRoleAssignmentRequired = True` on the *Power Virtual Agents* and *Microsoft Copilot Studio Service* enterprise apps and assigns the `Copilot Studio Authors` group | Anyone outside the group is rejected at sign-in to `copilotstudio.microsoft.com` with `AADSTS50105`. |
| **2. Self-service trial block** | `Remove-AllowedConsentPlans -Types Internal,Viral` | Users can no longer self-acquire trial SKUs (e.g. *Copilot Studio Viral Trial*) that would bypass the group. |
| **3. Power Platform tenant flags** | Sets `disableEnvironmentCreationByNonAdminUsers`, `disableTrialEnvironmentCreationByNonAdminUsers`, `disableDeveloperEnvironmentCreationByNonAdminUsers` to `true` | Non-admins cannot create environments from `make.powerapps.com`. |

> [!NOTE]
> The Microsoft documentation confirms that *"Disabling Power Apps and Microsoft Copilot Studio in Teams prevents users from creating new apps and agents but does NOT prevent the creation of Dataverse for Teams environments."*
> ([About the Microsoft Dataverse for Teams environment](https://learn.microsoft.com/en-us/power-platform/admin/about-teams-environment#ability-to-govern-dataverse-for-teams))
>
> This repo combines license, trial, and Entra app assignment controls to close that gap.

---

## Files

| File | Purpose |
|---|---|
| `Configure-Tenant-CopilotStudioLockdown.ps1` | One-time tenant configuration (runs all three layers). Idempotent. |
| `Grant-CopilotStudioAccess.ps1` | Per-user onboarding — adds a user to the `Copilot Studio Authors` group. |
| `runbook.html` | Self-contained HTML runbook with diagrams, decision flow, and rollback steps. Open in a browser. |

---

## Prerequisites

- **PowerShell 7+** (`pwsh`)
- An Entra security or M365 group named **`Copilot Studio Authors`** (rename via the `$AuthorsGroupName` parameter if your group is different)
- The user running the scripts must hold both:
  - **Power Platform Administrator**
  - **Global Administrator** (or equivalent: Application Administrator + sufficient Graph scopes)

The scripts auto-install these PowerShell modules on first run:

- `Microsoft.PowerApps.Administration.PowerShell`
- `Microsoft.PowerApps.PowerShell`
- `Microsoft.Graph.Authentication`
- `Microsoft.Graph.Applications`
- `Microsoft.Graph.Groups`

---

## Usage

### 1. One-time tenant configuration

```powershell
.\Configure-Tenant-CopilotStudioLockdown.ps1
```

You will be prompted to sign in twice — once to Power Platform, once to Microsoft Graph. The script prints a verification summary at the end.

### 2. Grant access to a user

```powershell
.\Grant-CopilotStudioAccess.ps1 -Upn alice@yourtenant.onmicrosoft.com
```

Bulk add:

```powershell
'alice@tenant.com','bob@tenant.com','carol@tenant.com' |
    ForEach-Object { .\Grant-CopilotStudioAccess.ps1 -Upn $_ }
```

The user must sign out and back in. Token / app-assignment propagation can take **5–60 minutes**.

### 3. Revoke access

Just remove the user from the group:

```powershell
Connect-MgGraph -NoWelcome -Scopes "Group.ReadWrite.All","User.Read.All"
$g = Get-MgGroup -Filter "displayName eq 'Copilot Studio Authors'"
$u = Get-MgUser  -UserId 'alice@yourtenant.onmicrosoft.com'
Remove-MgGroupMemberByRef -GroupId $g.Id -DirectoryObjectId $u.Id
```

---

## Verification checklist

| Test | Expected result |
|---|---|
| Sign in to `copilotstudio.microsoft.com` as a non-Authors user | `AADSTS50105` — sign-in blocked |
| Sign in as a member of `Copilot Studio Authors` | Portal loads |
| Try **+ New environment** at `make.powerapps.com` as a non-admin | Hidden / disabled |
| Try to start a Power Apps trial | Blocked by tenant policy |
| `(Get-TenantSettings).disableEnvironmentCreationByNonAdminUsers` | `True` |
| `(Get-AllowedConsentPlans).types` | Empty (or `Premium` only) |

---

## Full rollback

### Re-allow Copilot Studio portal for everyone

```powershell
Connect-MgGraph -NoWelcome -Scopes "Application.ReadWrite.All"
$sps = '96ff4394-9197-43aa-b393-6a41652e21f8','9d8f559b-5984-46a4-902a-ad4271e83efa'
foreach ($appId in $sps) {
    $sp = Get-MgServicePrincipal -Filter "appId eq '$appId'"
    Update-MgServicePrincipal -ServicePrincipalId $sp.Id -AppRoleAssignmentRequired:$false
}
```

### Re-allow viral / internal trial signups

```powershell
Add-AllowedConsentPlans -Types @('Internal','Viral')
```

### Re-enable non-admin environment creation

```powershell
$body = [pscustomobject]@{
    disableEnvironmentCreationByNonAdminUsers      = $false
    disableTrialEnvironmentCreationByNonAdminUsers = $false
    powerPlatform = [pscustomobject]@{
        governance = [pscustomobject]@{
            disableDeveloperEnvironmentCreationByNonAdminUsers = $false
        }
    }
}
Set-TenantSettings -RequestBody $body
```

---

## Troubleshooting

**`Get-TenantSettings` returns 400 with `Could not find member 'disableTeamsEnvironmentCreation'`**
The legacy `disableTeamsEnvironmentCreation` flag was removed from the Power Platform tenant-settings schema. This script does not use it — only the currently supported flags.

**`Set-TenantSettings` returns 400 with `TenantSettingReadOnly`**
You re-sent a read-only field (e.g. `FlexRoutingEnabled`). The script only sends the fields it intends to change, which avoids this. Do not echo the entire `Get-TenantSettings` response back into `Set-TenantSettings`.

**`New-MgGroupMember` fails with insufficient scopes**
`Grant-CopilotStudioAccess.ps1` reuses an existing Graph context if one exists. If your existing context lacks `Group.ReadWrite.All`, run `Disconnect-MgGraph` first, then re-run the script.

**User still has access after being removed from the group**
Token caching. Wait up to 60 minutes, or have the user sign out everywhere (`https://myaccount.microsoft.com/device-list`) and back in.

**A user with M365 E5 still cannot create agents even after being added to the group**
Their license may have `CDS_O365_P3` (Common Data Service for Teams) or `POWER_VIRTUAL_AGENTS_O365_P3` disabled (this can happen if licensing was previously hardened). Check `Get-MgUser -UserId <upn> -Property assignedLicenses` and re-enable those service plans if needed. The simplest licensing path that "just works" is **Microsoft 365 Copilot**, which includes the entitlement.

---

## Maintenance notes

- The hard-coded service-principal AppIds (`96ff4394-...` and `9d8f559b-...`) are Microsoft first-party IDs and have been stable for years, but Microsoft may introduce additional apps for the same surface. If users start bypassing the lock, search Entra Enterprise Apps for new "Copilot Studio" / "Power Virtual Agents" entries and add them to the `$targets` array.
- Re-run `Configure-Tenant-CopilotStudioLockdown.ps1` after any tenant-level Power Platform schema change announcement — the script is idempotent.

---

## License

MIT. Provided **as-is, without warranty of any kind**. See the disclaimer at the top of this README.

This project is **not affiliated with, endorsed by, or supported by Microsoft**. Trademarks (Microsoft, Copilot Studio, Power Platform, Entra, Dataverse, Teams) belong to their respective owners.
