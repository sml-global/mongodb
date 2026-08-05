# UAT Identity Center Setup Required

**Date:** 2026-08-06  
**Status:** BLOCKER for UAT `eks-access` provisioning  
**Owner Required:** Someone with `sso:CreatePermissionSet` permission in Identity Center

## Deep Research Summary

### What I Discovered

1. **Your current access from UAT account 672172129937:**
   - ✅ Can READ Identity Center users (`identitystore:ListUsers`)
   - ✅ Can READ AWS Organizations info
   - ❌ **CANNOT** create permission sets (`sso:CreatePermissionSet` - AccessDenied)
   - ❌ **CANNOT** list/manage permission sets (`sso:ListPermissionSets` - AccessDenied)

2. **The correct Identity Center instance:**
   - **Identity Store ID:** `d-906621bc7e` ✅ (matches issue #28)
   - **Instance ARN:** `arn:aws:sso:::instance/ssoins-722349018be2edbc`
   - **Owner Account:** `365528424207` (management/root account)
   - **Region:** `us-east-1`
   - **Status:** ACTIVE

3. **Current user status:**
   - Your user `frankcheong` EXISTS in Identity Center ✅
     - User ID: `e4c88448-9071-701b-5b15-f1dfebb3a7c0`
     - Email: `frankcheong@sml.com`
   - Other required users **DO NOT EXIST** yet ❌:
     - `yczhang`
     - `xavierlee`
     - `jiaweima`
     - `JesusRosario`
     - `jacklee`

## What You Need

You are **BLOCKED** on UAT provisioning step 4 (`eks-access`) because the following **do not exist** in Identity Center:

### 4 Permission Sets to Create

| Permission Set Name | Purpose | Initial User(s) | EKS Access Level |
|---|---|---|---|
| `UATInfraAdminEA` | Infrastructure admin | `frankcheong` (you) | **Cluster admin** (full EKS) |
| `UATApplicationDeveloper` | App deployment/debug | `yczhang`, `xavierlee`, `jiaweima` | **Cluster admin** (full EKS) |
| `UATBoomiAdmin` | Boomi integration admin | `JesusRosario`, `jacklee` | **Namespace admin** (`boomi-uat` only) |
| `UATBoomiProcessOwner` | Business process owner | (none initially) | **No EKS access** (validated only) |

### 5 Users to Create (or confirm exist with different usernames)

If these people already have Identity Center accounts under different usernames, you can use those instead. Otherwise, someone needs to create:

1. `yczhang` (or confirm actual username)
2. `xavierlee` (or confirm actual username)
3. `jiaweima` (or confirm actual username)
4. `JesusRosario` (or confirm actual username)
5. `jacklee` (or confirm actual username)

## Who Can Do This

You need someone with **Identity Center administrator** permissions, specifically:
- `sso:CreatePermissionSet`
- `sso:AttachManagedPolicyToPermissionSet`
- `sso:CreateAccountAssignment`
- `identitystore:CreateUser` (if users don't exist)

This is typically:
- **AWS Organization administrator** in account `365528424207`
- Someone with `IdentityCenterAdministrator` or `AWSOrganizationsFullAccess` permission set

## What to Ask Your Colleague

Send this to whoever manages your AWS Organization / Identity Center:

---

**Subject: UAT Identity Center Setup Request - Permission Sets and User Assignments**

Hi [colleague name],

I'm setting up the UAT EKS environment (account `672172129937`) and need 4 permission sets created in our org-wide Identity Center (`d-906621bc7e`).

**Required permission sets:**

1. **Permission Set:** `UATInfraAdminEA`
   - **Policy:** `AdministratorAccess` managed policy
   - **Session Duration:** 12 hours
   - **Assign to account:** `672172129937` (UAT)
   - **Assign to user:** `frankcheong@sml.com`

2. **Permission Set:** `UATApplicationDeveloper`
   - **Policy:** `PowerUserAccess` + `ReadOnlyAccess` managed policies
   - **Session Duration:** 8 hours
   - **Assign to account:** `672172129937` (UAT)
   - **Assign to users (if they exist, or create them):**
     - `yczhang` (or confirm actual username)
     - `xavierlee` (or confirm actual username)
     - `jiaweima` (or confirm actual username)

3. **Permission Set:** `UATBoomiAdmin`
   - **Policy:** Custom inline policy (see below)
   - **Session Duration:** 8 hours
   - **Assign to account:** `672172129937` (UAT)
   - **Assign to users (if they exist, or create them):**
     - `JesusRosario` (or confirm actual username)
     - `jacklee` (or confirm actual username)

4. **Permission Set:** `UATBoomiProcessOwner`
   - **Policy:** `ReadOnlyAccess` managed policy
   - **Session Duration:** 4 hours
   - **Assign to account:** `672172129937` (UAT)
   - **Assign to users:** (none initially - reserve for future)

**Custom inline policy for UATBoomiAdmin** (EKS namespace-scoped access):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    }
  ]
}
```
*(Kubernetes-level RBAC will further restrict to `boomi-uat` namespace)*

**After creating these, please send me the 4 role ARNs** (they'll look like `arn:aws:iam::672172129937:role/aws-reserved/sso.amazonaws.com/us-east-1/AWSReservedSSO_UATInfraAdminEA_abc123...`). I need them to configure EKS access.

**Reference:** See `docs/guides/environment-setup.md` § "UAT Workforce Access Prerequisite" (line 401-509) for the design rationale.

---

## What Happens After Permission Sets Are Created

Once your colleague provides the 4 role ARNs, you will:

1. Create `config/environments/uat.local/workforce-principals.json`:
   ```json
   {
     "infra_admin_role_arn": "arn:aws:iam::672172129937:role/aws-reserved/sso.amazonaws.com/us-east-1/AWSReservedSSO_UATInfraAdminEA_<suffix>",
     "application_developer_role_arn": "arn:aws:iam::672172129937:role/aws-reserved/sso.amazonaws.com/us-east-1/AWSReservedSSO_UATApplicationDeveloper_<suffix>",
     "boomi_admin_role_arn": "arn:aws:iam::672172129937:role/aws-reserved/sso.amazonaws.com/us-east-1/AWSReservedSSO_UATBoomiAdmin_<suffix>",
     "process_owner_role_arn": "arn:aws:iam::672172129937:role/aws-reserved/sso.amazonaws.com/us-east-1/AWSReservedSSO_UATBoomiProcessOwner_<suffix>"
   }
   ```

2. Validate the file:
   ```bash
   bash scripts/validate-uat-workforce-principals.sh \
     --input config/environments/uat.local/workforce-principals.json \
     --output /tmp/test-output.json
   ```

3. Continue UAT provisioning:
   ```bash
   bash scripts/provision.sh --env uat eks-access --auto-approve
   ```

## Why You Can't Do This Yourself

**Identity Center is org-wide** — it's not scoped to individual AWS accounts. Permission sets and user assignments are managed centrally from the **management account** (`365528424207`), not from member accounts like UAT (`672172129937`).

Even though you have `AdministratorAccess` in the UAT account, that doesn't grant you `sso:CreatePermissionSet` permissions in the org-wide Identity Center. This is **by design** — AWS separates:
- **Account-level admin** (you have this) = manage resources within one account
- **Organization-level admin** (you don't have this) = manage cross-account IAM/SSO

This is actually a **security best practice** — it prevents any single account admin from escalating privileges across the entire organization.

## Alternative: Using Local IAM Users (NOT RECOMMENDED)

You mentioned creating "local users in each individual account" — this means **IAM users** (not Identity Center users). This is **explicitly rejected** by the repository design:

From `docs/guides/environment-setup.md` line 418:
> "There is no SAML-role or IAM-user fallback."

**Why IAM users won't work:**
1. The `validate-uat-workforce-principals.sh` script **requires** Identity Center SSO role ARNs (path must match `aws-reserved/sso.amazonaws.com/...`)
2. IAM users would need to be created in every account separately (violates single-sign-on principle)
3. No audit trail of who accessed what across accounts
4. Password rotation becomes a nightmare
5. Goes against AWS Well-Architected best practices

## Next Steps

1. **Identify** who in your organization has Identity Center admin permissions
2. **Send them** the request above (or share this document)
3. **Wait for** the 4 role ARNs
4. **Fill** `config/environments/uat.local/workforce-principals.json`
5. **Continue** with `bash scripts/provision.sh --env uat eks-access --auto-approve`

---

**Current blocker documented in:** Issue #28, finding #3  
**Related docs:** `docs/guides/environment-setup.md` lines 401-509, `docs/guides/operator-runbook.md` lines 42-130
