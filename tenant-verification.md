# Tenant Verification: Block Copilot Studio access tenant-wide and restrict to one Entra security group

| Field | Value |
|---|---|
| Demo tenant | `M365CPI90282478.onmicrosoft.com` (TenantId `b22f8675-8375-455b-941a-67bee4cf7747`) — operator-confirmed |
| Verified by | tenant-verifier (orchestrated in main session due to interactive sign-in + per-phase operator gates) |
| Date | 2026-05-27 |
| Phase B (mutation) run? | **No — read-only (Phase A) only.** No tenant state was changed. |
| Tenant restored to pre-state after Phase B? | N/A (no mutation performed) |
| Pre-state snapshot | `tenant-verification-snapshot-2026-05-27.json` |

> Demo-tenant assertion enforced in code before any read: signed-in default domain was checked equal to `m365cpi90282478.onmicrosoft.com` and would have aborted otherwise. It PASSED.

---

## 0. Headline finding (resolves the operator's core question)

**Why removing the Copilot Studio license did NOT block HadarC: HadarC is a member of the `Copilot Studio Authors` group, and Authors-group membership is an *independent* access grant.** Per Microsoft's own 3-condition model (`troubleshoot/.../authors-access`), a user keeps Copilot Studio access if **any** of: (1) in the authors group, (2) has a CPS/trial license, (3) has an M365 Copilot license. HadarC's Copilot Studio service plan (`COPILOT_STUDIO_IN_COPILOT_FOR_M365`, `fe6c28b3-…`) **is already disabled** on their M365 Copilot license — yet HadarC remains in the Authors group, so condition 1 still grants access.

**Consequence for the fix:** removing the Copilot Studio service plan is **necessary-but-not-sufficient**. To actually block a user you must remove them from the Authors group (and ensure no other license path) — the app-lock (`AppRoleAssignmentRequired`) then enforces the block at sign-in. This is the "Documented ≠ Actual" trap admins hit: the intuitive "pull the license → access gone" is false while a group/Power Platform grant persists.

---

## Verification matrix

| # | Claim (from change-research.md) | Documented behavior | Observed in demo tenant (Phase A, read-only) | Match? | Evidence |
|---|---|---|---|---|---|
| 1 | Removing the CPS service plan from an M365 Copilot license blocks the user | Implied block | CPS service plan `fe6c28b3-…` **is in DisabledPlans** on HadarC's `Microsoft_365_Copilot` SKU AND shows `capabilityStatus=Deleted` — **yet HadarC is in the Authors group**, an independent grant. Actual sign-in effect needs a manual test (see below). | ❌ **GAP** (license removal alone does not block) | `Get-MgUser -Property assignedLicenses,assignedPlans` → Copilot SKU `639dec6b` DisabledPlans=[`fe6c28b3-…`]; group check below — 2026-05-27 |
| 2 | appId `96ff4394-…` exists / real displayName | Undocumented in official refs | **FOUND.** `DisplayName = "Power Virtual Agents "` (trailing space), spObjectId `87833469-5eac-43d8-954e-f2f1f57f8130`. | ✅ exists (still undocumented officially) | `Get-MgServicePrincipal -Filter "appId eq '96ff4394-…'"` — 2026-05-27 |
| 2b | appId `9d8f559b-…` identity | "Microsoft Copilot Studio Service" / PVA Service | **FOUND.** `DisplayName = "Microsoft Copilot Studio Service"`, spObjectId `39dad9dd-…`. | ✅ matches docs | same cmdlet — 2026-05-27 |
| 3 | `allowedToSignUpEmailBasedSubscriptions` value + correct direction | Doc snippet shows `$true` in a *block* context (reads backwards) | **Actual current value = `True`** = email-based self-service sign-up is currently **ALLOWED (not blocked)**. To BLOCK, set **`$false`**. | ✅ contradiction RESOLVED | `Get-MgPolicyAuthorizationPolicy` → `AllowedToSignUpEmailBasedSubscriptions = True` — 2026-05-27 |
| 4 | Layer 1 app-lock state | `AppRoleAssignmentRequired=Yes` + group assigned restricts the app | **Already applied:** both SPs `AppRoleAssignmentRequired=True`; each has exactly **one** assignment = the `Copilot Studio Authors` group (Group type). **No direct user assignments.** | ✅ applied (still an unsupported method per change-research) | `Get-MgServicePrincipalAppRoleAssignedTo` on both SPs — 2026-05-27 |
| 5 | Layer 2 consent-plan removal | Removes Internal/Viral self-service trials | **Already applied:** `Get-AllowedConsentPlans` returns **empty** (`types = ` / none). | ✅ applied | `Get-AllowedConsentPlans` → `types` empty — 2026-05-27 |
| 6 | Layer 2 Entra flag (the omitted step) | Should be `$false` to block email-based subs | **Still `True`** — the documented companion control is **NOT set**; trial-blocking is incomplete exactly as change-research predicted. | ❌ **GAP** (control missing) | `Get-MgPolicyAuthorizationPolicy` — 2026-05-27 |
| 7 | Layer 3 env-creation flags | Restrict env/trial/dev creation to admins | **All three = `True`** (`disableEnvironmentCreationByNonAdminUsers`, `disableTrialEnvironmentCreationByNonAdminUsers`, `disableDeveloperEnvironmentCreationByNonAdminUsers`). | ✅ applied & correct | `Get-TenantSettings` — 2026-05-27 |
| 8 | Authors group membership of target | — | `Copilot Studio Authors` (`8bd49156-…`) has **1 member = HadarC** (`HadarC@M365CPI90282478.OnMicrosoft.com`, `d5a6f2cc-…`). | n/a (explains #1) | `Get-MgGroupMember` — 2026-05-27 |

---

## ⚠️ Documented ≠ actual — gaps found

1. **License removal does not equal access removal (GAP, claim #1).** HadarC's Copilot Studio service plan is *already disabled* on the M365 Copilot license, but HadarC retains access because they are still in the `Copilot Studio Authors` group (an independent grant) and additionally hold an **Enabled** `PowerAppsService` plan (`9c0dab89-…`, a Power Platform access vector). The naive "remove the Copilot Studio license to revoke access" does **not** hold in-tenant. This is the headline customer caveat. *(Note: HadarC's actual ability to open the portal is operator-reported and corroborated by configuration; the live sign-in result is a manual test — see below — so it is reported as configuration-verified + behaviour-pending, not asserted.)*

2. **Trial-blocking is incomplete (GAP, claim #6).** Consent plans are removed (Layer 2 part 1 ✅), but `allowedToSignUpEmailBasedSubscriptions` is still `True`. Microsoft's CPS "block viral sign-ups" procedure requires this flag to be `$false`. The script omits it; in-tenant it is confirmed still in the permissive state.

3. **The app-lock — not the license — is what would actually enforce a block.** Because both first-party SPs have `AppRoleAssignmentRequired=True` and only the Authors group is assigned, a user *removed from the group* has no app-role assignment and should be blocked at sign-in (AADSTS50105) — independent of any license. This reframes the design: **group membership is the real control surface**; license edits are secondary. (The app-lock remains an officially-**unsupported** method per change-research.md — verified present, not verified as endorsed.)

---

## Resolved flags from change-research.md

- **appId `96ff4394-9197-43aa-b393-6a41652e21f8`:** ✅ **exists** in-tenant; real `DisplayName = "Power Virtual Agents "` (note trailing space). Still **not** in any official Microsoft reference — existence verified, official endorsement not.
- **appId `9d8f559b-5984-46a4-902a-ad4271e83efa`:** ✅ `DisplayName = "Microsoft Copilot Studio Service"` — matches official reference.
- **`allowedToSignUpEmailBasedSubscriptions`:** ✅ **resolved.** Current value `True` = *allowed*. **To block, set `$false`.** The official doc snippet showing `$true` in a block context is backwards/misleading; empirical state confirms the correct direction.
- **Authors group:** exists (`Copilot Studio Authors`, `8bd49156-…`), single member = HadarC. Confirms group membership is the live grant explaining the "license didn't block" observation.

---

## Not programmatically verifiable — hand to operator for manual sign-in test

The user-facing block (AADSTS50105 "not assigned to a role for the application") and actual portal reachability cannot be observed via Graph/PowerApps read APIs — they require an interactive sign-in **as HadarC**. Do NOT assert the outcome; test it:

**Test T1 — does HadarC currently reach Copilot Studio (baseline, in-group)?**
1. In a private/incognito browser, sign in as `HadarC@M365CPI90282478.onmicrosoft.com`.
2. Go to `https://copilotstudio.microsoft.com`.
3. Expected (current state): **reaches the portal** (HadarC is in the Authors group → app-role assignment satisfied). Record the result + screenshot.

**Test T2 — does removing HadarC from the group block them (the real fix)?** *(requires a controlled Phase B — operator go-ahead)*
1. Snapshot already captures group membership (rollback = re-add HadarC).
2. Remove HadarC from `Copilot Studio Authors`.
3. Wait for propagation (5–60 min; sign HadarC out/in).
4. HadarC opens `https://copilotstudio.microsoft.com`.
5. Expected: **blocked with AADSTS50105** (no app-role assignment on the restricted SPs), *even though* HadarC may still hold residual Power Platform plans — this demonstrates the app-lock, not the license, is the enforcer.
6. **Rollback:** re-add HadarC to the group (`Grant-CopilotStudioAccess.ps1 -Upn HadarC@…`), confirm membership restored.

---

## Snapshot / rollback record

- **Pre-state snapshot:** `tenant-verification-snapshot-2026-05-27.json` (service principals + assignments, authorization policy flag, authors group + members, HadarC license/service-plan state, M365 Copilot SKU composition, tenant env flags, allowed consent plans).
- **Phase B executed:** No. **Rollback executed:** N/A. **Restore verified:** N/A.
- No tenant state was modified during verification. Any Phase B (e.g., Test T2 group removal) is gated on explicit operator go-ahead and will re-verify restore against this snapshot.

---

## Confidence tags for solution-presenter

- `[tenant-verified: 2026-05-27, M365CPI90282478]` — claims #2, #2b, #3, #4, #5, #6, #7, #8 and the group-membership explanation of #1.
- `[operator-reported + config-verified, sign-in pending]` — HadarC's actual portal reachability (Test T1/T2 will close this).
- `[doc-only / unsupported]` — Layer 1 as a *Microsoft-endorsed* method (existence verified in-tenant; endorsement not).
