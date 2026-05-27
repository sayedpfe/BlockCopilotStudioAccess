# Change Research: Block Copilot Studio access tenant-wide and restrict to one Entra security group

| Field | Value |
|---|---|
| Customer goal | Block Microsoft Copilot Studio for all users; grant access only to members of a specific Entra security group. Trigger: unlicensed users can still reach copilotstudio.microsoft.com and create Teams / Power Platform environments. |
| Researched by | change-researcher |
| Date | 2026-05-27 |
| Verdict on official fix | 🟠 **Partial** — Layers 2 and 3 map to officially documented controls (but Layer 2 has a real gap), while Layer 1 (enterprise-app `AppRoleAssignmentRequired` on the two Copilot Studio appIds) is a community workaround Microsoft does not document. |

---

## 0. Direct answer to Sayed's worry (trial-license blocking)

**There is a real gap — but not where the script is empty; it's where the script stops one step short.**

- `Remove-AllowedConsentPlans -Types @('Internal','Viral')` **is** the officially documented Power Platform control, and it **does** cover the self-service trial/developer SKUs that Power Apps/Power Automate/Copilot Studio surface (Internal = self-signup trial/developer plans; Viral = ad-hoc trial SKUs from signup.microsoft.com). (GA — `learn.microsoft.com/power-platform/admin/powerapps-powershell`, retrieved 2026-05-27)
- **However**, Microsoft's *dedicated Copilot Studio* admin page "Block unauthorized self-service sign-ups and purchases" prescribes **two additional controls the script does not touch**:
  1. The **Microsoft Entra authorization-policy flag** via `Update-MgPolicyAuthorizationPolicy` (set `allowedToSignUpEmailBasedSubscriptions = $false`; this is the modern Graph replacement for the legacy `AllowAdHocSubscriptions`). The Power Platform PowerShell doc itself says the consent-plan block should be paired with "**not allowing the setting `Update-MgPolicyAuthorizationPolicy -AllowedToSignUpEmailBasedSubscriptions`**." The script omits this. (GA, retrieved 2026-05-27)
  2. **MSCommerce `AllowSelfServicePurchase`** per-product (`Get/Update-MSCommerceProductPolicy`). This is a separate self-service-purchase/trial control that the script does **not** touch. (GA, retrieved 2026-05-27)
- Net: the script blocks the **viral/internal consent-plan trial path**, but does **not** set the **Entra email-based self-service-signup flag** that the official Copilot Studio doc explicitly pairs with consent-plan blocking. So the trial-blocking is **incomplete against Microsoft's own documented procedure.** See §3 for the exact remediation the solution-presenter should add.

> Note on MSCommerce scope: the official `AllowSelfServicePurchase` product list (retrieved 2026-05-27) lists *Microsoft 365 Copilot* (`CFQ7TTC0MM8R`) but **does not list a standalone "Copilot Studio" product**. The Copilot Studio *trial* is governed primarily through the **consent-plan + Entra authorization-policy** path, not `AllowSelfServicePurchase`. So the script's choice of `Remove-AllowedConsentPlans` is the right lever for the CPS trial — it just needs the Entra authorization-policy flag added alongside it. `[verify in-tenant: confirm CPS trial sign-up is actually blocked end-to-end after both controls are set]`

---

## 1. What changed / current behavior

| Item | Detail | Status | Source (official) | Retrieved |
|---|---|---|---|---|
| Why unlicensed users still reach Copilot Studio | Access is **not** revoked by the "Copilot Studio authors" PPAC setting alone. A user keeps access if **any** of: (1) in the authors security group, (2) has a Copilot Studio per-user **or trial** license, (3) has a Microsoft 365 Copilot license. The authors group only *grants* access in a pay-as-you-go scenario; it does not *revoke*. | GA (troubleshooting article) | `learn.microsoft.com/troubleshoot/power-platform/copilot-studio/licensing/authors-access` | 2026-05-27 |
| Copilot Studio trial license exists and grants portal/authoring access | "Users in your organization can try Copilot Studio for a limited time." Trial lets users author and test (not publish). Self-signup can be disabled by admins. | GA | `learn.microsoft.com/microsoft-copilot-studio/requirements-licensing` (Trial plans) | 2026-05-27 |
| Self-service / viral trial sign-up is on by default | "By default, all types of consent plans are allowed in a tenant." Internal = self-signup trial/developer plans (Power Apps/Automate/desktop); Viral/ad-hoc = trial SKUs from `signup.microsoft.com`. | GA | `learn.microsoft.com/power-platform/admin/powerapps-powershell#block-trial-licenses-commands` | 2026-05-27 |
| Official Copilot Studio trial-blocking procedure | Combine: (a) `Update-MgPolicyAuthorizationPolicy` with `allowedToSignUpEmailBasedSubscriptions=$false`; (b) unassign existing viral licenses; (c) `Update-MSCommerceProductPolicy -PolicyId AllowSelfServicePurchase ... -Value Disabled` per product. | GA | `learn.microsoft.com/microsoft-copilot-studio/admin-block-viral-signups` | 2026-05-27 |
| Environment creation by non-admins (incl. trial/developer) is on by default | "Users with the correct licenses can create an environment as long as 1 GB of capacity is available." The Copilot Studio **trial plan** entitles a user to create **trial** environments. | GA | `learn.microsoft.com/power-platform/admin/control-environment-creation`; `learn.microsoft.com/power-platform/admin/create-environment` (Who can create environments — license table shows "Microsoft Copilot Studio trial plan → Trial: Yes") | 2026-05-27 |
| `disableEnvironmentCreationByNonAdminUsers` / `disableTrialEnvironmentCreationByNonAdminUsers` | Documented tenant settings; restrict creation to Global / Power Platform / Dynamics 365 admins. Exact casing per official reference: `disableEnvironmentCreationByNonAdminusers`, `disableTrialEnvironmentCreationByNonAdminusers`. | GA | `learn.microsoft.com/power-platform/admin/control-environment-creation#control-environment-creation-through-powershell`; `learn.microsoft.com/power-platform/admin/list-tenantsettings#definitions` | 2026-05-27 |
| `powerPlatform.governance.disableDeveloperEnvironmentCreationByNonAdminUsers` | Documented; restricts developer-environment creation to admins. Official example uses the exact nested `Set-TenantSettings -RequestBody` shape the script uses. | GA | `learn.microsoft.com/power-platform/admin/control-environment-creation` (Developer environments); `list-tenantsettings#definitions` | 2026-05-27 |
| Power Virtual Agents → Copilot Studio rename | "Power Virtual Agents is the former name for Microsoft Copilot Studio." Confirmed in the official Entra first-party service-principal reference table. | GA (renamed Nov 2023) | `learn.microsoft.com/entra/identity/monitoring-health/reference-service-principal-table` | 2026-05-27 |
| appId `9d8f559b-5984-46a4-902a-ad4271e83efa` identity | Officially listed as **"Power Virtual Agents Service"** — "allows the service to manage the applications and service principals created for each agent." Confirms the script's second target SP is a real CPS first-party app. | GA | `learn.microsoft.com/entra/identity/monitoring-health/reference-service-principal-table` | 2026-05-27 |
| appId `96ff4394-9197-43aa-b393-6a41652e21f8` identity | **Not found in any official Microsoft reference** (not in the Entra service-principal table; no Learn page). Commonly known in the community as the PVA portal/sign-in app, but unverified by an official source. | **Undocumented** | (no official source found as of 2026-05-27) | 2026-05-27 |
| `AppRoleAssignmentRequired` + group assignment as a *Copilot Studio* access-restriction method | Microsoft documents `AppRoleAssignmentRequired` (a.k.a. "Assignment required = Yes") only **generically** for restricting any Entra enterprise app to a set of users. **No Microsoft doc recommends applying it to the two Copilot Studio appIds** to lock the portal. | Generic feature GA; **CPS-specific use is undocumented** | `learn.microsoft.com/entra/identity-platform/howto-restrict-your-app-to-a-set-of-users` (generic only) | 2026-05-27 |

---

## 2. Why the prior/expected approach is affected

The "Copilot Studio authors" group setting in PPAC does not behave like an allow-list that revokes everyone else — it only *grants* access for a pay-as-you-go scenario and never removes access from licensed users (`troubleshoot/.../authors-access`, GA, 2026-05-27). Because the **Copilot Studio trial** (and any per-user or Microsoft 365 Copilot license) independently grants portal/authoring access, and because **viral/self-service trial sign-up and environment creation are enabled by default** (`powerapps-powershell`, `control-environment-creation`, GA, 2026-05-27), an unlicensed user can self-acquire a trial and reach the portal and create trial environments. That is exactly the behavior the customer observed, and it is the reason a multi-layer lockdown is required rather than the single PPAC group setting.

---

## 3. Is there an official supported fix?

**Per layer:**

- **Layer 3 (environment-creation tenant flags) — ✅ Official.** All three flags and the exact `Set-TenantSettings` shapes are documented (`control-environment-creation`, `list-tenantsettings`, GA, 2026-05-27). Supported as-is.

- **Layer 2 (block self-service trials) — 🟠 Official lever, but incomplete.** `Remove-AllowedConsentPlans -Types Internal,Viral` is officially documented and correctly targets the trial/developer consent plans (`powerapps-powershell` / cmdlet reference, GA). **Gap:** Microsoft's own Copilot Studio guidance requires *also* setting the Entra authorization-policy flag (`Update-MgPolicyAuthorizationPolicy -BodyParameter @{ allowedToSignUpEmailBasedSubscriptions = $false }`) and recommends `AllowSelfServicePurchase` (MSCommerce) per product (`admin-block-viral-signups`, GA, 2026-05-27). The script omits the Entra authorization-policy flag. **The solution-presenter should add it** to make Layer 2 match Microsoft's documented procedure.
  - *Caveat to flag:* the doc's sample sets `allowedToSignUpEmailBasedSubscriptions = $true` in a block-context code snippet, which reads contradictorily; the surrounding prose and the Power Platform PowerShell doc make clear the intent is to **not allow** email-based subscriptions (i.e. `$false`). `[verify in-tenant: confirm the correct boolean direction before shipping]`

- **Layer 1 (lock the portal via `AppRoleAssignmentRequired` on the two appIds) — ⛔ No official path; community workaround.**
  - The **officially documented way to control who can access/author in Copilot Studio is by LICENSE and the authors security group**, per the troubleshooting article's three conditions: a user is blocked only when they are (1) not in the authors group, (2) without a CPS per-user/trial license, and (3) without an M365 Copilot license (`troubleshoot/.../authors-access`, GA, 2026-05-27). Microsoft frames access control as license-assignment + group, **not** as flipping `AppRoleAssignmentRequired` on first-party enterprise apps.
  - `AppRoleAssignmentRequired` is real and supported **generically** (`howto-restrict-your-app-to-a-set-of-users`, GA), but **no Microsoft source documents applying it to the Copilot Studio / PVA enterprise apps** for this purpose. One of the two target appIds (`9d8f559b-…`) is confirmed as a real CPS first-party app; the other (`96ff4394-…`) **cannot be verified against any official source**. Restricting first-party Microsoft service principals this way carries undocumented blast-radius risk (it can affect service-to-service token issuance, since `9d8f559b-…` is the service that *manages per-agent service principals*).
  - **Label required:** *"Not an official Microsoft solution; Microsoft may change the underlying behavior (or these appIds) without notice. The appId `96ff4394-…` is unverified against official documentation."*

**Bottom line:** Microsoft documents a supported way to *block access* (deny the three license/group conditions) and to *stop trials* (consent plans + Entra authorization policy + MSCommerce). It does **not** document the enterprise-app `AppRoleAssignmentRequired` portal-lock. The strongest officially-supported design leans on **license/trial denial + authors group**, with the app-restriction step treated as an optional, explicitly-unsupported hardening layer.

---

## 4. Constraints the fix must respect

| Constraint | Detail | Source |
|---|---|---|
| Permissions/roles implied | Layer 3 tenant flags: Global Admin / Power Platform Admin / D365 Admin. Layer 2 consent plans: Power Platform admin context (Power Apps Admin module). Entra authorization policy: `Policy.ReadWrite.Authorization` (Graph). MSCommerce: **Global or Billing Administrator**. Layer 1 enterprise-app change: app owner or **Cloud Application Administrator** (Graph scopes `Application.ReadWrite.All`, `AppRoleAssignment.ReadWrite.All`). | `tenant-settings`; `admin-block-viral-signups`; `allowselfservicepurchase-powershell`; `howto-restrict-your-app-to-a-set-of-users` (all GA, 2026-05-27) |
| Tenant-wide side effects | Disabling env creation affects ALL non-admins tenant-wide (existing environments created before the change remain manageable by their creators). Removing consent plans blocks *all* Internal/Viral self-signup (Power Apps/Automate/Developer plans too), not just Copilot Studio. `AppRoleAssignmentRequired` on `9d8f559b-…` (the service that manages per-agent SPs) is the riskiest step — undocumented impact on existing agents' service-to-service auth. | `control-environment-creation` (note on existing environments); `powerapps-powershell`; `reference-service-principal-table` |
| Global Admin exemption | Setting "Assignment required = Yes" on an app **does not apply to Global Administrators** — they retain access regardless. Don't rely on it to block GAs. | `howto-restrict-your-app-to-a-set-of-users` (Note), GA, 2026-05-27 |
| Propagation delay | `AllowSelfServicePurchase` / self-service changes can take **up to 72 hours** to take effect. | `manage-self-service-purchases-admins`, GA, 2026-05-27 |
| Module deprecation | The legacy `AllowAdHocSubscriptions` lever was set via **MSOnline** (`Set-MsolCompanySettings`), which is **deprecated**. Use the **Microsoft Graph** equivalent `Update-MgPolicyAuthorizationPolicy` (`allowedToSignUpEmailBasedSubscriptions`). Script should not introduce MSOnline. | `admin-block-viral-signups` (Note: "Azure PowerShell and MSOnline are deprecated"), GA, 2026-05-27 |
| Guest users | Guests already cannot access Copilot Studio per docs — no extra control needed for them. | `requirements-licensing`, GA, 2026-05-27 |
| Preview features involved | `list-tenantsettings` is published as "(preview)" but the individual tenant flags used (env-creation) are GA controls surfaced in PPAC. No core layer depends on a preview API. | `list-tenantsettings`, 2026-05-27 |

---

## 5. Open questions for the operator

1. **Is the optional, unsupported Layer 1 (enterprise-app lock) wanted at all?** Given Microsoft documents access control via license/trial + authors group, the supported design may be: deny trials (Layer 2, completed) + don't assign CPS/M365 Copilot licenses + use the authors group — without touching the enterprise apps. Confirm whether Sayed wants to keep the app-restriction layer as explicit hardening (with the unsupported label) or drop it.
2. **Correct boolean direction for `allowedToSignUpEmailBasedSubscriptions`** — the official doc snippet shows `$true` in a "block" context, which is contradictory. Needs an in-tenant confirmation (research could not resolve the contradiction from docs alone). `[undocumented contradiction — verify in-tenant]`
3. **Can we verify appId `96ff4394-9197-43aa-b393-6a41652e21f8` in the customer tenant** (via `Get-MgServicePrincipal`) and capture its real `DisplayName`, since no official Microsoft reference confirms it?
4. **Does the customer also use the Microsoft 365 Copilot license?** If yes, that license independently grants Copilot Studio access (condition 3 of the troubleshooting article) — the group restriction will not block those users unless that is also addressed.
5. **Should `AllowSelfServicePurchase` be disabled for Microsoft 365 Copilot** (`CFQ7TTC0MM8R`) as defense-in-depth, even though there is no standalone CPS product in that list?

---

## 6. Sources consulted

| Topic | URL | Status | Retrieved |
|---|---|---|---|
| Authors group does not revoke access; 3 conditions to block CPS | https://learn.microsoft.com/troubleshoot/power-platform/copilot-studio/licensing/authors-access | GA | 2026-05-27 |
| Block viral sign-ups (Entra auth policy + unassign + MSCommerce) — CPS-specific | https://learn.microsoft.com/microsoft-copilot-studio/admin-block-viral-signups | GA | 2026-05-27 |
| Copilot Studio licensing & trial plans (AllowAdHocSubscriptions) | https://learn.microsoft.com/microsoft-copilot-studio/requirements-licensing | GA | 2026-05-27 |
| Get access / sign up for CPS trial | https://learn.microsoft.com/microsoft-copilot-studio/requirements-licensing-subscriptions | GA | 2026-05-27 |
| Copilot Studio licensing (access methods incl. authors role) | https://learn.microsoft.com/microsoft-copilot-studio/billing-licensing | GA | 2026-05-27 |
| Remove-AllowedConsentPlans cmdlet reference | https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/remove-allowedconsentplans | GA | 2026-05-27 |
| Block trial licenses commands; consent plan types; pair with Entra auth policy | https://learn.microsoft.com/power-platform/admin/powerapps-powershell | GA | 2026-05-27 |
| AllowSelfServicePurchase (MSCommerce) — per-product, product list (no standalone CPS) | https://learn.microsoft.com/microsoft-365/commerce/subscriptions/allowselfservicepurchase-powershell | GA | 2026-05-27 |
| Manage self-service purchases/trials (per-product; 72h delay; can't disable tenant-wide in one cmd) | https://learn.microsoft.com/microsoft-365/commerce/subscriptions/manage-self-service-purchases-admins | GA | 2026-05-27 |
| Control who can create environments (the 3 tenant flags + PowerShell) | https://learn.microsoft.com/power-platform/admin/control-environment-creation | GA | 2026-05-27 |
| Who can create environments (license table — CPS trial → trial env) | https://learn.microsoft.com/power-platform/admin/create-environment | GA | 2026-05-27 |
| Tenant settings definitions (exact flag names/casing) | https://learn.microsoft.com/power-platform/admin/list-tenantsettings | GA (page marked preview) | 2026-05-27 |
| Tenant settings page (roles required) | https://learn.microsoft.com/power-platform/admin/tenant-settings | GA | 2026-05-27 |
| Restrict an Entra app to a set of users (generic AppRoleAssignmentRequired; GA exemption) | https://learn.microsoft.com/entra/identity-platform/howto-restrict-your-app-to-a-set-of-users | GA | 2026-05-27 |
| Entra first-party service principal reference (confirms 9d8f559b = PVA Service = CPS former name; rename) | https://learn.microsoft.com/entra/identity/monitoring-health/reference-service-principal-table | GA | 2026-05-27 |
| Self-service sign-up controls (Update-MgPolicyAuthorizationPolicy params) | https://learn.microsoft.com/entra/identity/users/directory-self-service-signup | GA | 2026-05-27 |
| Update-MgPolicyAuthorizationPolicy cmdlet | https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/update-mgpolicyauthorizationpolicy | GA | 2026-05-27 |
| PVA → Copilot Studio rename (unified authoring GA) | https://learn.microsoft.com/microsoft-copilot-studio/unified-authoring-conversion | GA | 2026-05-27 |

**Any non-official source used (opted-in only):** none. (The community attribution of appId `96ff4394-…` to the PVA portal app is noted only as *unverified*; it is not cited as "Microsoft says.")
