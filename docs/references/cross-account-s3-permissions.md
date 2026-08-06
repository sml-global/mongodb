# Cross-Account S3 Permissions for Boomi ELT

## Overview

This document provides detailed information about the cross-account IAM permissions required for Boomi ELT S3 access. Use this when discussing the setup with your AWS Organization administrator.

## Business Requirement

Boomi processes running in the **Production** environment need to read/write S3 buckets in **UAT**, **DEV**, and **SIT** environments for Extract-Load-Transform (ELT) operations. Each environment resides in a separate AWS account under the same AWS Organization.

## Architecture

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

## IAM Roles and Permissions

### Production Account (111111111111)

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

### UAT Account (222222222222)

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

### DEV Account (333333333333)

**Role Name**: `sml-elt-cross-account-dev`

Same structure as UAT, with:
- External ID: `boomi-elt-dev`
- Bucket: `sml-elt-dev`

---

### SIT Account (444444444444)

**Role Name**: `sml-elt-cross-account-sit`

Same structure as UAT, with:
- External ID: `boomi-elt-sit`
- Bucket: `sml-elt-sit`

---

## S3 Bucket Configuration

All buckets (`sml-elt-prod`, `sml-elt-uat`, `sml-elt-dev`, `sml-elt-sit`) have:

1. **Versioning**: Enabled (for accidental deletion recovery)
2. **Encryption**: SSE-S3 (AES256) - can upgrade to SSE-KMS if required
3. **Public Access**: Blocked (all 4 settings enabled)
4. **Lifecycle Policy**:
   - Current versions → STANDARD_IA after 90 days
   - Noncurrent versions → STANDARD_IA after 30 days
   - Noncurrent versions → Expire after 90 days

---

## Security Controls

### 1. External ID (Confused Deputy Prevention)

**What it is**: A shared secret between the trusting account (UAT/DEV/SIT) and the trusted account (Prod).

**Why it's needed**: Prevents the "confused deputy" attack where a malicious actor tricks your production role into assuming a role on their behalf.

**How it works**:
- UAT role trust policy requires `sts:ExternalId = "boomi-elt-uat"`
- Production role must supply this exact string when calling `sts:AssumeRole`
- If the external ID doesn't match, AssumeRole fails

**Best practices**:
- External IDs are **not secrets** (they're part of trust policies, which are visible to anyone with IAM read access)
- Use different external IDs for each environment (already done: `boomi-elt-uat`, `boomi-elt-dev`, `boomi-elt-sit`)
- Never reuse external IDs across unrelated systems

### 2. Least Privilege

- Production role can **only** assume roles in UAT/DEV/SIT (cannot assume arbitrary roles)
- Target account roles can **only** access their own S3 bucket (no other AWS resources)
- S3 bucket policies **only** allow production role (no other principals)

### 3. Session Duration

- AssumeRole sessions last **1 hour maximum**
- Boomi library automatically handles credential refresh (re-assumes role on each operation)
- Reduces exposure window if credentials are leaked

### 4. CloudTrail Audit

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

## Deployment Order

**CRITICAL**: Deploy in this order to avoid role dependency errors.

1. **Production account first** (creates `sml-elt-admin-prod` role + bucket)
2. **UAT/DEV/SIT in any order** (creates cross-account roles + buckets)

If you deploy UAT before production, the UAT role's trust policy will reference a non-existent production role (Terraform will succeed, but AssumeRole will fail until production is deployed).

---

## Testing Cross-Account Access

### From AWS CLI (Production Account)

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

### From Boomi Groovy Script

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

## Troubleshooting

### Error: "AccessDenied: User is not authorized to perform: sts:AssumeRole"

**Cause**: Production role doesn't have `sts:AssumeRole` permission for target role.

**Fix**: Check production role policy has:
```json
{
  "Action": "sts:AssumeRole",
  "Resource": "arn:aws:iam::222222222222:role/sml-elt-cross-account-uat"
}
```

---

### Error: "AccessDenied: Not authorized to perform sts:AssumeRole"

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

### Error: "AccessDenied: Invalid ExternalId"

**Cause**: External ID mismatch between AssumeRole request and trust policy.

**Fix**: Ensure `BoomiEltS3Library.groovy` uses correct external IDs:
- UAT: `boomi-elt-uat`
- DEV: `boomi-elt-dev`
- SIT: `boomi-elt-sit`

---

### Error: "AccessDenied: s3:GetObject on sml-elt-uat"

**Cause**: Assumed role doesn't have S3 permissions, OR bucket policy blocks access.

**Fix**:
1. Check assumed role has S3 permissions policy
2. Check bucket policy allows production role ARN
3. Verify bucket exists and name matches (`sml-elt-uat`)

---

### Error: "No credentials provider found"

**Cause**: Boomi atom EC2 instance doesn't have `sml-elt-admin-prod` IAM role attached.

**Fix**: Attach instance profile `sml-elt-admin-prod` to Boomi atom EC2 instance.

---

## Cost Implications

### S3 Storage Costs

- **STANDARD**: $0.025/GB/month (first 90 days)
- **STANDARD_IA**: $0.0125/GB/month (after 90 days)

Estimated monthly cost for 100GB data:
- Month 1-3: $2.50/month
- Month 4+: $1.25/month

### S3 Request Costs

- **PUT/POST/DELETE**: $0.005 per 1000 requests
- **GET**: $0.0004 per 1000 requests

Estimated monthly cost for 1M requests (50/50 read/write):
- 500k writes: $2.50
- 500k reads: $0.20
- **Total**: $2.70/month

### Data Transfer Costs

- **Cross-account transfer**: $0.01/GB (HK region)
- **Intra-region transfer**: FREE

Estimated monthly cost for 500GB cross-account transfer: $5.00

**Total estimated monthly cost per environment**: ~$10/month

---

## Security Review Checklist

Before production deployment, verify:

- [ ] All S3 buckets have versioning enabled
- [ ] All S3 buckets block public access (4 settings enabled)
- [ ] All S3 buckets use encryption (SSE-S3 minimum)
- [ ] All IAM roles follow least privilege principle
- [ ] All cross-account trust policies use external IDs
- [ ] All AssumeRole sessions have 1-hour max duration
- [ ] CloudTrail is enabled in all 4 accounts
- [ ] Boomi atom EC2 instance has `sml-elt-admin-prod` role attached
- [ ] Account IDs are set as environment variables on Boomi atom
- [ ] Test cross-account access from production before production cutover
- [ ] Telemetry logs are flowing to SigNoz from Boomi processes

---

## Questions for AWS Organization Administrator

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

## Related Documents

- **Terraform Modules**: `platform-prerequisites/terraform/boomi-elt-s3/`
- **Groovy Library**: `scripts/groovy/boomi/BoomiEltS3Library.groovy`
- **Audit Log Contract**: `docs/references/audit-log-contract.md` (unified logging schema)
- **Component Catalog**: `docs/references/component-catalog.md`

---

## Revision History

| Date       | Author       | Changes                                      |
|------------|--------------|----------------------------------------------|
| 2026-08-06 | Claude Code  | Initial version for org admin review         |
