# Copilot Studio Lockdown — Full Test Runbook (fresh tenant)

**Tenant:** TEST / DEMO only. Every script enforces a `-TenantDomain` guard and aborts if the
signed-in tenant's default domain doesn't match. Never run against a customer tenant.

**Roles you need:** Global Administrator **+** Power Platform Administrator on the test tenant.

**Set once (PowerShell 7):**
```powershell
$Domain = '<yourtenant>.onmicrosoft.com'   # e.g. contoso.onmicrosoft.com
cd 'd:\LearningProjects\BlockCopilotStudio\BlockCopilotStudioAccess\test'
```

> **The order matters.** In a brand-new tenant the two Copilot Studio enterprise apps
> (`Power Virtual Agents`, `Microsoft Copilot Studio Service`) are **not provisioned** until
> someone with a license signs into Copilot Studio. If you lock down first, Layer 1 finds no
> apps and silently does nothing. So: **reproduce the problem first, then lock down.**

---

## Phase 1 — Create prerequisites + reproduce the baseline

Creates the authors group and two test users. If you pass a SKU, it licenses the "blocked"
user so they can actually reach Copilot Studio (which also provisions the enterprise apps).

```powershell
# Preview first
.\Setup-TestPrereqs.ps1 -TenantDomain $Domain -WhatIf

# Create. Add -LicenseSkuPartNumber <SKU> if you have a CPS / M365 Copilot SKU to assign.
.\Setup-TestPrereqs.ps1 -TenantDomain $Domain
# (find available SKUs:  Get-MgSubscribedSku -All | Select SkuPartNumber, SkuId)
```

**Baseline check (manual, proves the problem + provisions the apps):**
1. Sign in as `cps-blocked1@<domain>` (private browser) at **https://copilotstudio.microsoft.com**.
2. Confirm they **can** reach it (start a trial if prompted) — this is the behavior you're fixing.
3. Try **make.powerapps.com** → create an environment → confirm a non-admin currently can.

✅ Expected before lockdown: access works. The enterprise apps now exist in Entra.

---

## Phase 2 — Snapshot (rollback safety net)

The lockdown script has no `-WhatIf`, so capture state first.

```powershell
.\Snapshot-TenantState.ps1 -TenantDomain $Domain
# writes tenant-snapshot-<date>.json  — keep this file
```

---

## Phase 3 — Apply the lockdown

Runs all layers (now including the completed Layer 2b — the Entra sign-up flag).

```powershell
..\Configure-Tenant-CopilotStudioLockdown.ps1
```

Then grant the author (the only step needed to give someone access):

```powershell
..\Grant-CopilotStudioAccess.ps1 -Upn cps-author1@$Domain
```

---

## Phase 4 — Verify

**Programmatic (automated PASS/FAIL):**
```powershell
.\Verify-Lockdown.ps1 -TenantDomain $Domain
```
Expect every row **PASS**: 3 env flags = True, consent plans empty,
`allowedToSignUpEmailBasedSubscriptions = False`, both apps `AppRoleAssignmentRequired = True`
with the authors group assigned.

**Manual (cannot be confirmed via API — allow 5–60 min propagation):**

| Test | User | Expected |
|---|---|---|
| T1 — author reaches portal | `cps-author1` (in group) | **Reaches** copilotstudio.microsoft.com |
| T2 — non-member blocked | `cps-blocked1` (remove any trial license first; sign out/in) | **Blocked: AADSTS50105** |
| T3 — env creation blocked | `cps-blocked1` (non-admin) | Cannot create prod/trial/dev environment |
| T4 — trial sign-up blocked | `cps-blocked1` | Cannot self-start a Copilot Studio trial |

> **Important confound:** if `cps-blocked1` still holds a Copilot Studio / M365 Copilot license,
> the *license* grants access (condition 2/3 of Microsoft's model) regardless of the app-lock.
> For a clean T2, remove that user's CPS/Copilot license **and** confirm they're not in the group.

---

## Phase 5 — Rollback (restore the tenant)

```powershell
# Preview the restore
.\Rollback-Lockdown.ps1 -SnapshotPath .\tenant-snapshot-<date>.json -TenantDomain $Domain -WhatIf

# Restore settings only (keeps the test group/users)
.\Rollback-Lockdown.ps1 -SnapshotPath .\tenant-snapshot-<date>.json -TenantDomain $Domain

# OR full teardown (also deletes the group + test users)
.\Rollback-Lockdown.ps1 -SnapshotPath .\tenant-snapshot-<date>.json -TenantDomain $Domain `
    -RemoveTestObjects -TestUserUpns "cps-author1@$Domain","cps-blocked1@$Domain"
```

**Confirm restore:** re-run `.\Verify-Lockdown.ps1 -TenantDomain $Domain` — rows should now read
the pre-lockdown (unlocked) values from your snapshot.

---

## Scripts in this folder

| Script | Mutates? | What it does |
|---|---|---|
| `Setup-TestPrereqs.ps1` | Yes (`-WhatIf`) | Creates authors group + 2 test users; optional license |
| `Snapshot-TenantState.ps1` | No (read-only) | Captures pre-state to JSON |
| `Verify-Lockdown.ps1` | No (read-only) | PASS/FAIL check of all 4 layers |
| `Rollback-Lockdown.ps1` | Yes (`-WhatIf`) | Restores tenant from the snapshot; optional teardown |

All four enforce the `-TenantDomain` demo-tenant guard. Not official Microsoft solutions — TEST use.
