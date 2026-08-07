# AWS Organization Requirements

**Date:** 2026-08-06  
**Owner Required:** AWS Organization Administrator  
**Status:** BLOCKERS for UAT provisioning

## Overview

Two distinct items require AWS Organization administrator action before UAT environment provisioning can proceed. Both are managed at the organization level (management account `365528424207`) and cannot be provisioned by account-level administrators.

---

## 1. UAT Identity Center Integration

### Status

**BLOCKER** for UAT `eks-access` provisioning step.

### What We Discovered

From UAT account `672172129937`:
- ✅ Can READ Identity Center users (`identitystore:ListUsers`)
- ✅ Can READ AWS Organizations info
- ❌ **CANNOT** create permission sets (`sso:CreatePermissionSet` - AccessDenied)
- ❌ **CANNOT** list/manage permission sets (`sso:ListPermissionSets` - AccessDenied)

**The Identity Center instance:**
- **Identity Store ID:** `d-906621bc7e`
- **Instance ARN:** `arn:aws:sso:::instance/ssoins-722349018be2edbc`
- **Owner Account:** `365528424207` (management/root account)
- **Region:** `us-east-1`
- **Status:** ACTIVE

**Current user status:**
- ✅ `frankcheong` EXISTS (User ID: `e4c88448-9071-701b-5b15-f1dfebb3a7c0`, Email: `frankcheong@sml.com`)
- ❌ Other required users DO NOT EXIST yet: `yczhang`, `xavierlee`, `jiaweima`, `JesusRosario`, `jacklee`

### What We Need

#### 4 Permission Sets to Create

| Permission Set Name | Purpose | Initial User(s) | EKS Access Level | Policy |
|---|---|---|---|---|
| `UATInfraAdminEA` | Infrastructure admin | `frankcheong` | **Cluster admin** (full EKS) | `AdministratorAccess` |
| `UATApplicationDeveloper` | App deployment/debug | `yczhang`, `xavierlee`, `jiaweima` | **Cluster admin** (full EKS) | `PowerUserAccess` + `ReadOnlyAccess` |
| `UATBoomiAdmin` | Boomi integration admin | `JesusRosario`, `jacklee` | **Namespace admin** (`boomi-uat` only) | Custom inline (see below) |
| `UATBoomiProcessOwner` | Business process owner | (none initially) | **No EKS access** (validated only) | `ReadOnlyAccess` |

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

#### 5 Users to Create or Confirm

If these people already have Identity Center accounts under different usernames, use those instead:

1. `yczhang` (or confirm actual username)
2. `xavierlee` (or confirm actual username)
3. `jiaweima` (or confirm actual username)
4. `JesusRosario` (or confirm actual username)
5. `jacklee` (or confirm actual username)

### Who Can Do This

Someone with **Identity Center administrator** permissions, specifically:
- `sso:CreatePermissionSet`
- `sso:AttachManagedPolicyToPermissionSet`
- `sso:CreateAccountAssignment`
- `identitystore:CreateUser` (if users don't exist)

Typically:
- **AWS Organization administrator** in account `365528424207`
- Someone with `IdentityCenterAdministrator` or `AWSOrganizationsFullAccess` permission set

### Request for Organization Administrator

**Subject: UAT Identity Center Setup Request - Permission Sets and User Assignments**

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
   - **Policy:** Custom inline policy (see above)
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

**After creating these, please send the 4 role ARNs** (they'll look like `arn:aws:iam::672172129937:role/aws-reserved/sso.amazonaws.com/us-east-1/AWSReservedSSO_UATInfraAdminEA_abc123...`). We need them to configure EKS access.

**Reference:** See `docs/guides/environment-setup.md` § "UAT Workforce Access Prerequisite" (line 401-509) for design rationale.

### What Happens After Permission Sets Are Created

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

### Why Account-Level Admin Cannot Do This

**Identity Center is org-wide** — permission sets and user assignments are managed centrally from the **management account** (`365528424207`), not from member accounts like UAT (`672172129937`).

Even with `AdministratorAccess` in the UAT account, that doesn't grant `sso:CreatePermissionSet` in the org-wide Identity Center. AWS separates:
- **Account-level admin** = manage resources within one account
- **Organization-level admin** = manage cross-account IAM/SSO

This is a **security best practice** preventing any single account admin from escalating privileges across the entire organization.

### Alternative: IAM Users (NOT RECOMMENDED)

The repository design **explicitly rejects** IAM users as an alternative (`docs/guides/environment-setup.md` line 418: "There is no SAML-role or IAM-user fallback").

**Why IAM users won't work:**
1. `validate-uat-workforce-principals.sh` **requires** Identity Center SSO role ARNs (path must match `aws-reserved/sso.amazonaws.com/...`)
2. IAM users must be created in every account separately (violates single-sign-on principle)
3. No audit trail of who accessed what across accounts
4. Password rotation nightmare
5. Goes against AWS Well-Architected best practices

---

## 2. Cross-Account S3 Access for Boomi ELT

### Business Requirement

Boomi processes running in the **Production** environment need to read/write S3 buckets in **UAT**, **DEV**, and **SIT** environments for Extract-Load-Transform (ELT) operations. Each environment resides in a separate AWS account under the same AWS Organization.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                       AWS Organization                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Production Account (111111111111)                        │  │
│  │                                                           │  │
│  │  ┌───────────────────────────────────────────────────┐   │  │
│  │  │ Boomi Atom (EC2 instance)                         │   │  │
│  │  │  IAM Role: sml-elt-admin-prod (attached)          │   │  │
│  │  │  - Full access to sml-elt-prod bucket             │   │  │
│  │  │  - sts:AssumeRole permission to UAT/DEV/SIT       │   │  │
│  │  └───────────────────────────────────────────────────┘   │  │
│  │                                                           │  │
│  │  S3 Bucket: sml-elt-prod                                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           │ sts:AssumeRole                     │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ UAT Account (222222222222)                               │  │
│  │                                                           │  │
│  │  IAM Role: sml-elt-cross-account-uat                     │  │
│  │  - Trust: sml-elt-admin-prod (prod account)              │  │
│  │  - External ID: boomi-elt-uat                            │  │
│  │  - Permissions: Full access to sml-elt-uat bucket        │  │
│  │                                                           │  │
│  │  S3 Bucket: sml-elt-uat                                  │  │
│  │  - Bucket policy: Allow sml-elt-admin-prod               │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  [Similar structure for DEV (333333333333) and SIT (444...)]   │
└─────────────────────────────────────────────────────────────────┘
```

### IAM Roles and Permissions

#### Production Account (111111111111)

**Role Name**: `sml-elt-admin-prod`

**Attached To**: EC2 instance running Boomi Atom in production

**Trust Policy** (who can assume this role):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

**Permissions Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ProdBucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::sml-elt-prod",
        "arn:aws:s3:::sml-elt-prod/*"
      ]
    },
    {
      "Sid": "AssumeRoleInTargetAccounts",
      "Effect": "Allow",
      "Action": "sts:AssumeRole",
      "Resource": [
        "arn:aws:iam::222222222222:role/sml-elt-cross-account-uat",
        "arn:aws:iam::333333333333:role/sml-elt-cross-account-dev",
        "arn:aws:iam::444444444444:role/sml-elt-cross-account-sit"
      ]
    }
  ]
}
```

**Max Session Duration**: 3600 seconds (1 hour)

---

#### UAT Account (222222222222)

**Role Name**: `sml-elt-cross-account-uat`

**Trust Policy** (who can assume this role):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/sml-elt-admin-prod"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "boomi-elt-uat"
        }
      }
    }
  ]
}
```

**Permissions Policy**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BucketAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": [
        "arn:aws:s3:::sml-elt-uat",
        "arn:aws:s3:::sml-elt-uat/*"
      ]
    }
  ]
}
```

**S3 Bucket Policy** (on `sml-elt-uat` bucket):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowProdCrossAccountAccess",
      "Effect": "Allow",
      "Principal": {
        "AWS": "arn:aws:iam::111111111111:role/sml-elt-admin-prod"
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::sml-elt-uat",
        "arn:aws:s3:::sml-elt-uat/*"
      ]
    }
  ]
}
```

**Max Session Duration**: 3600 seconds (1 hour)

**External ID**: `boomi-elt-uat` (security measure to prevent confused deputy attacks)

---

#### DEV Account (333333333333)

**Role Name**: `sml-elt-cross-account-dev`

Same structure as UAT, with:
- External ID: `boomi-elt-dev`
- Bucket: `sml-elt-dev`

---

#### SIT Account (444444444444)

**Role Name**: `sml-elt-cross-account-sit`

Same structure as UAT, with:
- External ID: `boomi-elt-sit`
- Bucket: `sml-elt-sit`

---

### S3 Bucket Configuration

All buckets (`sml-elt-prod`, `sml-elt-uat`, `sml-elt-dev`, `sml-elt-sit`) have:

1. **Versioning**: Enabled (for accidental deletion recovery)
2. **Encryption**: SSE-S3 (AES256) - can upgrade to SSE-KMS if required
3. **Public Access**: Blocked (all 4 settings enabled)
4. **Lifecycle Policy**:
   - Current versions → STANDARD_IA after 90 days
   - Noncurrent versions → STANDARD_IA after 30 days
   - Noncurrent versions → Expire after 90 days

---

### Security Controls

#### 1. External ID (Confused Deputy Prevention)

**What it is**: A shared secret between the trusting account (UAT/DEV/SIT) and the trusted account (Prod).

**Why it's needed**: Prevents the "confused deputy" attack where a malicious actor tricks your production role into assuming a role on their behalf.

**How it works**:
- UAT role trust policy requires `sts:ExternalId = "boomi-elt-uat"`
- Production role must supply this exact string when calling `sts:AssumeRole`
- If the external ID doesn't match, AssumeRole fails

**Best practices**:
- External IDs are **not secrets** (visible in trust policies to anyone with IAM read access)
- Use different external IDs for each environment (already done: `boomi-elt-uat`, `boomi-elt-dev`, `boomi-elt-sit`)
- Never reuse external IDs across unrelated systems

#### 2. Least Privilege

- Production role can **only** assume roles in UAT/DEV/SIT (cannot assume arbitrary roles)
- Target account roles can **only** access their own S3 bucket (no other AWS resources)
- S3 bucket policies **only** allow production role (no other principals)

#### 3. Session Duration

- AssumeRole sessions last **1 hour maximum**
- Boomi library automatically handles credential refresh (re-assumes role on each operation)
- Reduces exposure window if credentials are leaked

#### 4. CloudTrail Audit

All cross-account access is logged in CloudTrail:
- `sts:AssumeRole` events in **production account** (who assumed what role)
- `s3:GetObject`, `s3:PutObject`, etc. in **target accounts** (what was accessed)

**Recommended queries**:
```sql
-- All cross-account AssumeRole calls from prod
SELECT eventTime, userIdentity.principalId, requestParameters.roleArn
FROM cloudtrail_logs
WHERE eventName = 'AssumeRole'
  AND userIdentity.sessionContext.sessionIssuer.arn LIKE '%sml-elt-admin-prod'
```

---

### Deployment Order

**CRITICAL**: Deploy in this order to avoid role dependency errors.

1. **Production account first** (creates `sml-elt-admin-prod` role + bucket)
2. **UAT/DEV/SIT in any order** (creates cross-account roles + buckets)

If you deploy UAT before production, the UAT role's trust policy will reference a non-existent production role (Terraform will succeed, but AssumeRole will fail until production is deployed).

---

### Testing Cross-Account Access

#### From AWS CLI (Production Account)

```bash
# 1. Verify production role can assume UAT role
aws sts assume-role \
  --role-arn "arn:aws:iam::222222222222:role/sml-elt-cross-account-uat" \
  --role-session-name "test-session" \
  --external-id "boomi-elt-uat" \
  --profile prod

# Expected output: Credentials object with AccessKeyId, SecretAccessKey, SessionToken

# 2. Use temporary credentials to access UAT bucket
export AWS_ACCESS_KEY_ID=<from step 1>
export AWS_SECRET_ACCESS_KEY=<from step 1>
export AWS_SESSION_TOKEN=<from step 1>

aws s3 ls s3://sml-elt-uat/
# Expected: Bucket listing (may be empty if no files exist)

# 3. Test write access
echo "test" > test.txt
aws s3 cp test.txt s3://sml-elt-uat/test/test.txt
# Expected: upload successful

# 4. Test read access
aws s3 cp s3://sml-elt-uat/test/test.txt test-downloaded.txt
cat test-downloaded.txt
# Expected: "test"
```

#### From Boomi Groovy Script

```groovy
import com.boomi.elt.s3.BoomiEltS3Library

// Set account IDs as environment variables on Boomi atom
// AWS_ACCOUNT_ID_PROD=111111111111
// AWS_ACCOUNT_ID_UAT=222222222222
// AWS_ACCOUNT_ID_DEV=333333333333
// AWS_ACCOUNT_ID_SIT=444444444444

def s3 = new BoomiEltS3Library()

try {
    // Test write
    s3.writeObject("uat", "test/hello.txt", "Hello from Boomi!")
    logger.info("Write successful")

    // Test read
    String content = s3.readObject("uat", "test/hello.txt")
    logger.info("Read successful: ${content}")

    // Test list
    List<String> files = s3.listObjects("uat", "test/")
    logger.info("Found ${files.size()} files")

    // Test delete
    s3.deleteObject("uat", "test/hello.txt")
    logger.info("Delete successful")

} catch (Exception e) {
    logger.error("Cross-account S3 test failed: ${e.message}")
    e.printStackTrace()
}
```

---

### Troubleshooting

#### Error: "AccessDenied: User is not authorized to perform: sts:AssumeRole"

**Cause**: Production role doesn't have `sts:AssumeRole` permission for target role.

**Fix**: Check production role policy has:
```json
{
  "Action": "sts:AssumeRole",
  "Resource": "arn:aws:iam::222222222222:role/sml-elt-cross-account-uat"
}
```

---

#### Error: "AccessDenied: Not authorized to perform sts:AssumeRole"

**Cause**: Target account role's trust policy doesn't trust production role.

**Fix**: Check UAT role trust policy has:
```json
{
  "Principal": {
    "AWS": "arn:aws:iam::111111111111:role/sml-elt-admin-prod"
  }
}
```

---

#### Error: "AccessDenied: Invalid ExternalId"

**Cause**: External ID mismatch between AssumeRole request and trust policy.

**Fix**: Ensure `BoomiEltS3Library.groovy` uses correct external IDs:
- UAT: `boomi-elt-uat`
- DEV: `boomi-elt-dev`
- SIT: `boomi-elt-sit`

---

#### Error: "AccessDenied: s3:GetObject on sml-elt-uat"

**Cause**: Assumed role doesn't have S3 permissions, OR bucket policy blocks access.

**Fix**:
1. Check assumed role has S3 permissions policy
2. Check bucket policy allows production role ARN
3. Verify bucket exists and name matches (`sml-elt-uat`)

---

#### Error: "No credentials provider found"

**Cause**: Boomi atom EC2 instance doesn't have `sml-elt-admin-prod` IAM role attached.

**Fix**: Attach instance profile `sml-elt-admin-prod` to Boomi atom EC2 instance.

---

### Cost Implications

#### S3 Storage Costs

- **STANDARD**: $0.025/GB/month (first 90 days)
- **STANDARD_IA**: $0.0125/GB/month (after 90 days)

Estimated monthly cost for 100GB data:
- Month 1-3: $2.50/month
- Month 4+: $1.25/month

#### S3 Request Costs

- **PUT/POST/DELETE**: $0.005 per 1000 requests
- **GET**: $0.0004 per 1000 requests

Estimated monthly cost for 1M requests (50/50 read/write):
- 500k writes: $2.50
- 500k reads: $0.20
- **Total**: $2.70/month

#### Data Transfer Costs

- **Cross-account transfer**: $0.01/GB (HK region)
- **Intra-region transfer**: FREE

Estimated monthly cost for 500GB cross-account transfer: $5.00

**Total estimated monthly cost per environment**: ~$10/month

---

### Questions for AWS Organization Administrator

1. **Account IDs**: What are the 12-digit AWS account IDs for PROD, UAT, DEV, and SIT?
2. **Bucket Names**: Are these bucket names available: `sml-elt-prod`, `sml-elt-uat`, `sml-elt-dev`, `sml-elt-sit`?
3. **Encryption**: Do we need SSE-KMS instead of SSE-S3? (requires KMS key management)
4. **Compliance**: Are there any compliance requirements (e.g., GDPR, HIPAA) that affect bucket configuration?
5. **Lifecycle**: Is 90-day retention acceptable, or do we need longer retention for audit/compliance?
6. **SCPs**: Are there any Service Control Policies (SCPs) in the AWS Organization that might block cross-account AssumeRole?
7. **VPC Endpoints**: Should S3 access go through VPC endpoints (for extra security), or is internet gateway acceptable?
8. **MFA**: Should AssumeRole require MFA? (would require manual authentication, not suitable for automated Boomi processes)
9. **Session Tags**: Do we need session tags for cost allocation or access control?
10. **CloudTrail**: Is CloudTrail already enabled in all accounts, or do we need to enable it?

---

## Summary Checklist

Before UAT provisioning can proceed:

### Identity Center (Section 1)
- [ ] 4 permission sets created (`UATInfraAdminEA`, `UATApplicationDeveloper`, `UATBoomiAdmin`, `UATBoomiProcessOwner`)
- [ ] 5 users created or confirmed to exist (`yczhang`, `xavierlee`, `jiaweima`, `JesusRosario`, `jacklee`)
- [ ] Users assigned to appropriate permission sets
- [ ] 4 role ARNs provided for `config/environments/uat.local/workforce-principals.json`

### Cross-Account S3 (Section 2)
- [ ] All 4 AWS account IDs confirmed (PROD, UAT, DEV, SIT)
- [ ] S3 buckets created in all 4 environments (versioning enabled, encryption enabled, public access blocked)
- [ ] IAM role `sml-elt-admin-prod` created in production account
- [ ] Cross-account roles created in UAT/DEV/SIT (`sml-elt-cross-account-uat`, etc.)
- [ ] Bucket policies applied to allow production role
- [ ] `sml-elt-admin-prod` IAM role attached to Boomi atom EC2 instance in production
- [ ] Environment variables set on Boomi atom (`AWS_ACCOUNT_ID_PROD`, `AWS_ACCOUNT_ID_UAT`, `AWS_ACCOUNT_ID_DEV`, `AWS_ACCOUNT_ID_SIT`)
- [ ] Cross-account access tested from production (AWS CLI test)
- [ ] Groovy library tested from Boomi (read/write/list/delete/exists)
- [ ] Telemetry logs verified in SigNoz
- [ ] CloudTrail logs verified showing AssumeRole calls

---

## Related Documents

- **Identity Center design rationale**: `docs/guides/environment-setup.md` § "UAT Workforce Access Prerequisite" (line 401-509)
- **Identity Center validation script**: `scripts/validate-uat-workforce-principals.sh`
- **Cross-account S3 Terraform modules**: `platform-prerequisites/terraform/boomi-elt-s3/`
- **Boomi ELT S3 Groovy library**: `scripts/groovy/boomi/BoomiEltS3Library.groovy`
- **Unified logging schema**: `docs/references/audit-log-contract.md`
- **Operator runbook**: `docs/guides/operator-runbook.md` (lines 42-130 for Identity Center troubleshooting)
- **Issue #28**: Validate infra-admin/Boomi-admin user journey docs against real setup
- **Issue #75**: Cross-account S3 access for Boomi ELT (prod → UAT/DEV/SIT)
- **PR #76**: feat(boomi-elt): add cross-account S3 access for prod → UAT/DEV/SIT

---

## Revision History

| Date       | Author       | Changes                                      |
|------------|--------------|----------------------------------------------|
| 2026-08-06 | Claude Code  | Consolidated from `UAT-IDENTITY-CENTER-SETUP-REQUIRED.md` and `cross-account-s3-permissions.md` |
