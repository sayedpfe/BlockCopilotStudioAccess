# Customer Runbook — Copilot Studio / Power Platform Governance Snapshot

**Script:** `Snapshot-TenantState.ps1`
**Audience:** `<Customer>` IT administrator
**Prepared by:** Sayed Ali, Cloud Solution Architect, Microsoft
**Date:** 2026-05-27

> **This procedure is read-only.** The script only *reads* your tenant configuration and writes a single local file. It makes **no changes** to your tenant.

---

## 1. Overview

`Snapshot-TenantState.ps1` captures the current Copilot Studio / Power Platform governance state of your Microsoft 365 tenant into one JSON file, so it can be reviewed before any governance change is planned. It records, **read-only**, the settings that control who can reach Copilot Studio and create environments.

### 1.1 What it captures

- The two Copilot Studio first-party enterprise applications — whether sign-in is restricted (`AppRoleAssignmentRequired`) and which groups are assigned.
- The Microsoft Entra self-service sign-up flag (`allowedToSignUpEmailBasedSubscriptions`).
- The authors security group and its members.
- The three Power Platform environment-creation tenant flags (production / trial / developer).
- The allowed self-service consent plans (Internal / Viral).

### 1.2 Why run it

To establish a documented, point-in-time baseline of the tenant's Copilot Studio access posture before any lockdown or change is proposed. Read-only assessment only.

---

## 2. What it does NOT do

- It makes **no changes** to your tenant — no settings are modified, no users or groups are created or altered.
- It does **not** disable, block, grant, or revoke anything.
- It does **not** transmit data anywhere. It writes one JSON file to the folder you run it from; you choose if and how to share it.
- There is nothing to undo after running it (see Section 8).

---

## 3. Required permissions

Least-privilege, read-only. The script requests only `*.Read.*` Graph scopes.

| Area | Requirement | Source in script |
|---|---|---|
| Microsoft Graph scopes (read-only) | `Application.Read.All`, `Group.Read.All`, `Policy.Read.All`, `Organization.Read.All` | line 50 |
| Microsoft Entra role | **Global Reader** is sufficient for all Graph reads (enterprise apps, authorization policy, groups, organization) | line 23 (`.NOTES`) |
| Power Platform | **Power Platform Administrator** (or Global Administrator) — required to read tenant settings and consent plans (`Get-TenantSettings`, `Get-AllowedConsentPlans`); no read-only Power Platform role exposes these | lines 101, 107, 23 |

### 3.1 Minimum role combination

**Global Reader + Power Platform Administrator** (or a single Global Administrator). The script never requests any write/modify scope.

---

## 4. Prerequisites

### 4.1 PowerShell

- **PowerShell 7.0 or later** (`#Requires -Version 7.0`, line 1).

### 4.2 Modules

The script declares these as hard requirements (line 2). Install once per machine:

```powershell
Install-Module Microsoft.Graph.Authentication           -Scope CurrentUser
Install-Module Microsoft.Graph.Applications             -Scope CurrentUser
Install-Module Microsoft.Graph.Groups                   -Scope CurrentUser
Install-Module Microsoft.Graph.Identity.SignIns         -Scope CurrentUser
Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
```

### 4.3 Sign-ins

Expect **two interactive sign-in prompts** when you run the script:

1. **Microsoft Graph** (browser sign-in) — prompts first.
2. **Power Platform** (browser sign-in) — prompts second.

Sign in with the same administrator account (Section 3) at both prompts.

---

## 5. How to run

1. Open a **PowerShell 7** window.
2. Change to the folder containing the script:
   ```powershell
   cd <path-to-folder>
   ```
3. Run the script, passing **your tenant's default domain**:
   ```powershell
   .\Snapshot-TenantState.ps1 -TenantDomain <yourtenant>.onmicrosoft.com
   ```
4. Complete the **Microsoft Graph** sign-in (prompt 1), then the **Power Platform** sign-in (prompt 2).
5. The script prints `=== Snapshot written: ... ===` and the output file path when finished.

### 5.1 Parameters

| Parameter | Required | Default | Purpose |
|---|---|---|---|
| `-TenantDomain` | Yes | — | Your tenant's default domain. A safety guard: the script **aborts** if the signed-in account is not in this tenant (lines 58–63). |
| `-AuthorsGroupName` | No | `Copilot Studio Authors` | Name of the security group to inspect. |
| `-OutputPath` | No | `.\tenant-snapshot-<date>.json` | Where the JSON is written. |

### 5.2 Example with a custom output location

```powershell
.\Snapshot-TenantState.ps1 -TenantDomain <yourtenant>.onmicrosoft.com -OutputPath C:\Temp\baseline.json
```

---

## 6. What you get

A single JSON file (default `tenant-snapshot-<date>.json`) containing:

| Section | Contents |
|---|---|
| `meta` | Tenant domain, tenant ID, capture date |
| `servicePrincipals` | The two Copilot Studio apps: object ID, display name, `AppRoleAssignmentRequired`, and any assigned groups |
| `authorizationPolicy` | `allowedToSignUpEmailBasedSubscriptions` value |
| `authorsGroup` | Group ID, display name, and member list (display name + UPN) |
| `tenantSettings` | The three environment-creation flags |
| `allowedConsentPlans` | The allowed self-service plan types |

This is a plain-text JSON file you can open in any editor.

---

## 7. Data handling

### 7.1 Sensitivity

The output JSON contains tenant configuration plus **directory identifiers**: your tenant ID, service principal object IDs, and the authors group's **member display names and UPNs** (personal data). Treat the file as **internal / confidential**.

### 7.2 GDPR / EU

Because the file contains personal data (user names and UPNs), handle it under your organisation's GDPR obligations. Store it in an EU-resident location where your policy requires.

### 7.3 Returning the file to Microsoft

Return the snapshot to Sayed Ali via an **approved secure channel** — a Microsoft-provided secure file-transfer or an access-restricted SharePoint/Teams location agreed in advance. **Do not send it by casual or personal email.** Confirm the channel with Sayed before sending.

---

## 8. Safety

- **Read-only.** The script only reads tenant settings and writes one local JSON file.
- **Nothing to roll back.** No tenant state is changed, so no undo step is required.
- The mandatory `-TenantDomain` guard prevents the script from running against the wrong tenant — if the signed-in account is not in the domain you passed, the script stops and captures nothing.

---

## 9. Support

| | |
|---|---|
| **Author / contact** | Sayed Ali, Cloud Solution Architect, Microsoft |
| **Script** | `Snapshot-TenantState.ps1` |
| **Status** | Community tool — not an official Microsoft solution |
| **Customer** | `<Customer>` |

For questions on running the script or interpreting the output, contact Sayed Ali before making any tenant changes based on the results.
