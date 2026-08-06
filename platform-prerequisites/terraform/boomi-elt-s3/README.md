# Boomi ELT S3 - Cross-Account Access (Terraform Module)

## Overview

Provisions S3 buckets and IAM roles for Boomi ELT cross-account access:
- **Production**: `sml-elt-admin-prod` role can access prod bucket + assume roles in UAT/DEV/SIT
- **UAT/DEV/SIT**: Cross-account assumable roles with bucket access

## Architecture

```
Production (111111111111)
├─ IAM Role: sml-elt-admin-prod (attached to Boomi atom EC2)
│  ├─ Access to s3://sml-elt-prod
│  └─ sts:AssumeRole to UAT/DEV/SIT roles
└─ S3 Bucket: sml-elt-prod

UAT (222222222222)
├─ IAM Role: sml-elt-cross-account-uat (trusts prod role with external ID)
│  └─ Access to s3://sml-elt-uat
└─ S3 Bucket: sml-elt-uat (bucket policy allows prod role)

[Similar for DEV/SIT]
```

## Deployment

**CRITICAL**: Deploy production first, then UAT/DEV/SIT (cross-account roles trust production role).

### Step 1: Set Account IDs as Environment Variables

```bash
export TF_VAR_prod_account_id=111111111111
export TF_VAR_uat_account_id=222222222222
export TF_VAR_dev_account_id=333333333333
export TF_VAR_sit_account_id=444444444444
```

### Step 2: Deploy Production

```bash
cd platform-prerequisites/terraform/boomi-elt-s3
export AWS_PROFILE=prod-admin  # or appropriate SSO profile

terraform init
terraform apply \
  -var="environment=prod" \
  -var="aws_account_id=${TF_VAR_prod_account_id}"
```

**Outputs**: `sml-elt-admin-prod` role ARN, `sml-elt-prod` bucket name

### Step 3: Deploy UAT

```bash
export AWS_PROFILE=uat-admin

terraform init -reconfigure  # switch backend to UAT state
terraform apply \
  -var="environment=uat" \
  -var="aws_account_id=${TF_VAR_uat_account_id}"
```

### Step 4: Deploy DEV

```bash
export AWS_PROFILE=dev-admin

terraform init -reconfigure
terraform apply \
  -var="environment=dev" \
  -var="aws_account_id=${TF_VAR_dev_account_id}"
```

### Step 5: Deploy SIT

```bash
export AWS_PROFILE=sit-admin

terraform init -reconfigure
terraform apply \
  -var="environment=sit" \
  -var="aws_account_id=${TF_VAR_sit_account_id}"
```

### Step 6: Configure Boomi Atom

Attach `sml-elt-admin-prod` role to production Boomi atom EC2 instance, then set environment variables:

```bash
# On Boomi atom EC2 instance (add to /etc/environment or user data)
export AWS_ACCOUNT_ID_PROD=111111111111
export AWS_ACCOUNT_ID_UAT=222222222222
export AWS_ACCOUNT_ID_DEV=333333333333
export AWS_ACCOUNT_ID_SIT=444444444444
```

**Alternative**: Set Boomi process properties:
- `boomi.elt.account.prod` = 111111111111
- `boomi.elt.account.uat` = 222222222222
- `boomi.elt.account.dev` = 333333333333
- `boomi.elt.account.sit` = 444444444444

## Groovy Library Usage

See `scripts/groovy/boomi/BoomiEltS3Library.groovy` for complete implementation.

**Dependencies** (add to Boomi Atom):
- AWS SDK for Java: `com.amazonaws:aws-java-sdk-s3:1.12.x`
- AWS SDK STS: `com.amazonaws:aws-java-sdk-sts:1.12.x`

**Example:**
```groovy
import com.boomi.elt.s3.BoomiEltS3Library

def s3 = new BoomiEltS3Library()

// Read from UAT bucket (prod Boomi atom assumes UAT role)
String content = s3.readObject("uat", "documents/order-001.csv")
logger.info("Read ${content.length()} bytes from UAT")

// Process data
String processed = processOrder(content)

// Write to UAT bucket
s3.writeObject("uat", "processed/order-001.csv", processed)
logger.info("Wrote processed data to UAT")

// List objects in DEV bucket
List<String> files = s3.listObjects("dev", "documents/")
logger.info("Found ${files.size()} documents in DEV")

// Check if file exists
if (s3.objectExists("sit", "config/settings.json")) {
    String config = s3.readObject("sit", "config/settings.json")
}

// Delete file
s3.deleteObject("dev", "temp/temp-file.csv")
```

**Important Notes**:
- The library automatically handles AssumeRole for non-prod environments
- Session credentials are valid for 1 hour
- Production bucket uses native IAM role credentials (no AssumeRole)
- All operations include error handling with descriptive exceptions
- All operations log telemetry to SigNoz (matching unified logging schema)

## Outputs

After deployment, use `terraform output` to get:

- `bucket_name` — S3 bucket name
- `bucket_arn` — S3 bucket ARN
- `iam_role_arn` — IAM role ARN
- `cross_account_role_arns` — (prod only) ARNs of assumable roles in UAT/DEV/SIT
- `external_id` — (non-prod only) External ID for AssumeRole

## Security

- **Least Privilege:** Each role only has access to its own bucket
- **External IDs:** `boomi-elt-{env}` prevents confused deputy attacks
- **Cross-Account Audit:** CloudTrail logs all AssumeRole calls
- **Encryption:** S3 buckets use SSE-S3 (AES256)
- **Versioning:** Enabled by default (90-day retention for noncurrent versions)
- **Public Access:** Blocked (all 4 settings enabled)

## Telemetry and Logging

The Groovy library logs all S3 operations to SigNoz via OTLP, matching the unified logging schema:

- **trace_id**: Boomi execution ID
- **action**: `s3.read`, `s3.write`, `s3.list`, `s3.delete`, `s3.exists`
- **resource_type**: `s3.object`
- **resource_id**: `s3://{bucket}/{key}`
- **meta**: `environment`, `bytes`, `bucket`, `key`, `library_version`

Query example in SigNoz:
```sql
resource_type = 's3.object' AND meta.environment = 'uat'
```

## Testing

```bash
# Test from prod account (should work)
aws sts assume-role \
  --role-arn "arn:aws:iam::222222222222:role/sml-elt-cross-account-uat" \
  --role-session-name "test-session" \
  --external-id "boomi-elt-uat"

# Test S3 access (after assuming role)
aws s3 ls s3://sml-elt-uat/ --profile uat-assumed
```

## Detailed Documentation

See `docs/references/cross-account-s3-permissions.md` for:
- Full IAM policy JSON
- Security controls explanation
- Troubleshooting guide
- Questions for AWS org administrator
- Cost implications
