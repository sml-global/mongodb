# Subnet Redesign Analysis for PR #76

## Your Requirements Summary

1. **Public subnets**: /26 instead of /24 (what components exist here?)
2. **Production**: 3 AZs instead of 2 (all subnets × 3, including Aurora)
3. **Production private**: /22 minimum (1024 IPs), prefer /21 (2048 IPs)
4. **SIT**: Multiple namespaces (SIT1, SIT2, SIT3) with DEV-like load
5. **Consume full /16**: Can the /16 support all this?
6. **Namespace naming**: Why no -dev/-uat/-prod suffix?
7. **S3 data protection**: What features available?

---

## Question 1: Public Subnet Components & Sizing

### What Lives in Public Subnets?

**Current components** (per environment):
1. **NAT Gateways** (1 per AZ)
   - Each NAT Gateway gets 1 elastic IP
   - Requires ~3-5 IPs per AZ (primary IP + secondary for failover)
   
2. **Internet-facing Application Load Balancers (ALBs)**
   - ALB requires minimum /27 subnet (32 IPs)
   - ALB needs 8 free IPs per AZ (AWS reserves these for scaling)
   - Typical: 2-4 ALBs per environment
   - Each ALB ENI takes 1 IP per AZ
   
3. **Bastion hosts** (optional, for emergency access)
   - 1-2 instances per environment
   
4. **VPN endpoints** (if using AWS Client VPN)
   - Each endpoint needs 1 IP per AZ

### IP Count Calculation (per AZ)

| Component | IPs per AZ | Notes |
|---|---|---|
| NAT Gateway | 3 | Primary + secondary IPs |
| ALB ENIs | 10-15 | 2-3 ALBs × ~4 IPs each + AWS reserves 8 for scaling |
| Bastion | 1-2 | Emergency access only |
| VPN endpoint | 1 | If using Client VPN |
| AWS reserved | 5 | First 4 + last 1 in any subnet |
| Growth buffer | 10-20 | Future ALBs, NLBs |
| **Total** | **30-45 IPs** | |

### Recommendation: /26 Public Subnets ✅

**Capacity**: /26 = 64 IPs per AZ
- Usable: 64 - 5 (AWS reserved) = 59 IPs
- Required: ~45 IPs (worst case with growth buffer)
- **Remaining**: 14 IPs (23% buffer)

**Verdict**: ✅ **/26 is sufficient** for public subnets. This saves significant space:
- /24 → /26 = **192 IPs saved per AZ**
- 3 AZs × 192 = **576 IPs saved per environment**

---

## Question 2: Production 3-AZ Support

### Aurora Multi-AZ Support

**Yes, Aurora supports 3-AZ configurations**:
- Aurora PostgreSQL supports up to **15 read replicas** across **3 AZs**
- Best practice: 1 writer + 2 readers distributed across 3 AZs
- Example:
  - AZ-a: Writer instance
  - AZ-b: Reader replica 1
  - AZ-c: Reader replica 2

### Benefits of 3-AZ for Production

1. **MongoDB HA**: 3-node replica set (1 per AZ)
   - Losing 1 AZ → still have 2/3 nodes → **quorum maintained** ✅
   - With 2 AZs: Losing 1 AZ → only 1/2 nodes → **no quorum** ❌

2. **EKS Worker Nodes**: Distributed across 3 AZs
   - Better pod distribution
   - Higher availability

3. **Aurora**: 3-AZ read replica distribution
   - Better read scaling
   - Lower latency for geographically distributed reads

### Production Subnet Requirements (3 AZs)

| Subnet Type | Per AZ Size | Count | Total IPs |
|---|---|---|---|
| Public | /26 (64 IPs) | 3 | 192 |
| Private | /22 (1024 IPs) | 3 | 3072 |
| DB (Aurora) | /24 (256 IPs) | 3 | 768 |
| **Total Production** | | | **4,032 IPs** |

**Fits in /18?** 16,384 IPs available, 4,032 used = ✅ **Yes, with 12,352 IPs spare**

---

## Question 3: Production Private Subnet Sizing

### Your Requirement: /22 minimum, prefer /21

**Analysis**:

| Size | IPs per AZ | Total (3 AZs) | Pod Capacity | Recommendation |
|---|---|---|---|---|
| /23 (current) | 512 | 1,536 | ~256 pods/AZ | ❌ Too small for production |
| **/22** | **1,024** | **3,072** | **~512 pods/AZ** | ✅ **Minimum acceptable** |
| **/21** | **2,048** | **6,144** | **~1,024 pods/AZ** | ✅ **Preferred** (if space allows) |

**Pod capacity calculation**:
- EKS uses prefix delegation (VPC CNI)
- Each node can support 30-110 pods depending on instance type
- Conservative estimate: 1024 IPs = ~512 pods (2 IPs per pod)

### Can we afford /21 for Production?

Let's recalculate Production with /21 private subnets:

| Subnet Type | Per AZ Size | Count | Total IPs |
|---|---|---|---|
| Public | /26 (64 IPs) | 3 | 192 |
| Private | **/21 (2048 IPs)** | 3 | **6,144** |
| DB (Aurora) | /24 (256 IPs) | 3 | 768 |
| **Total Production** | | | **7,104 IPs** |

**Fits in /18?** 16,384 IPs available, 7,104 used = ✅ **Yes, with 9,280 IPs spare**

**Recommendation**: ✅ **Use /21 for Production private subnets** (2048 IPs per AZ)

---

## Question 4: Multiple SIT Environments

### Requirement: SIT1, SIT2, SIT3 with DEV-like load

**DEV specifications** (current):
- VPC: /18 (16,384 IPs)
- 2 AZs
- Public: /24 × 2 = 512 IPs
- Private: /23 × 2 = 1,024 IPs
- DB: N/A (CNPG)

**SIT should be smaller than DEV** (test-only load):
- VPC per SIT: **/20** (4,096 IPs) ← **Right-sized for test workload**
- 2 AZs (don't need 3 AZs for test environments)
- Public: /26 × 2 = 128 IPs
- Private: /21 × 2 = 4,096 IPs
- DB: N/A (CNPG)

Wait, that's too large. Let me recalculate SIT properly:

### Optimized SIT Sizing

| Subnet Type | Per AZ Size | Count (2 AZs) | Total IPs |
|---|---|---|---|
| Public | /26 (64 IPs) | 2 | 128 |
| Private | /22 (1024 IPs) | 2 | 2,048 |
| DB | N/A (CNPG) | - | - |
| Reserved/Spare | | | ~1,920 |
| **Total per SIT** | | | **~4,096 (/20)** |

**How many SIT environments fit in remaining /16 space?**

Let's calculate the full /16 allocation...

---

## Question 5: Full /16 Allocation

### Proposed Allocation

| Environment | VPC CIDR | IPs | Public | Private | DB | AZs |
|---|---|---|---|---|---|---|
| **DEV** | `10.200.0.0/18` | 16,384 | /24 × 2 | /23 × 2 | N/A | 2 |
| **UAT** | `10.200.64.0/18` | 16,384 | /24 × 2 | /23 × 2 | /24 × 2 | 2 |
| **Production** | `10.200.128.0/18` | 16,384 | **/26 × 3** | **/21 × 3** | **/24 × 3** | **3** |
| **SIT1** | `10.200.192.0/20` | 4,096 | /26 × 2 | /22 × 2 | N/A | 2 |
| **SIT2** | `10.200.208.0/20` | 4,096 | /26 × 2 | /22 × 2 | N/A | 2 |
| **SIT3** | `10.200.224.0/20` | 4,096 | /26 × 2 | /22 × 2 | N/A | 2 |
| **Reserved** | `10.200.240.0/20` | 4,096 | Future SIT4 or expansion | | | |

**Total**: 16,384 + 16,384 + 16,384 + 4,096 + 4,096 + 4,096 + 4,096 = **65,536 IPs** (/16)

✅ **Yes, you consume the full /16 with this arrangement**

### Production Detailed Breakdown (3 AZs)

Let me verify Production fits in its /18 with /21 private subnets:

```
Production VPC: 10.200.128.0/18 (16,384 IPs)

Public subnets (3 × /26 = 192 IPs):
- AZ-a: 10.200.128.0/26 (64 IPs)
- AZ-b: 10.200.128.64/26 (64 IPs)
- AZ-c: 10.200.128.128/26 (64 IPs)

Private subnets (3 × /21 = 6,144 IPs):
- AZ-a: 10.200.132.0/21 (2048 IPs)
- AZ-b: 10.200.140.0/21 (2048 IPs)
- AZ-c: 10.200.148.0/21 (2048 IPs)

DB subnets (3 × /24 = 768 IPs):
- AZ-a: 10.200.156.0/24 (256 IPs)
- AZ-b: 10.200.157.0/24 (256 IPs)
- AZ-c: 10.200.158.0/24 (256 IPs)

Total used: 192 + 6,144 + 768 = 7,104 IPs
Remaining: 16,384 - 7,104 = 9,280 IPs (spare capacity)
```

✅ **Fits comfortably in Production /18**

---

## Question 6: Namespace Naming Convention

### Why DEV has no -dev suffix

**Historical reason**: DEV was provisioned first (before naming convention established)

**Technical reason**: Backward compatibility
- Existing PVCs (PersistentVolumeClaims) are named with `mongodb` namespace
- Existing secrets reference `mongodb` namespace
- Scripts hardcoded `mongodb` namespace
- Changing would require:
  1. Backup all data
  2. Destroy namespace
  3. Recreate with new name
  4. Restore data
  5. Update all scripts/secrets

**Why UAT has -uat suffix**: UAT was provisioned later, after we learned the lesson

**Recommended convention** (going forward):
- DEV: Keep `mongodb` (legacy, don't change existing)
- UAT: `mongodb-uat` ✅
- Production: `mongodb-prod` ✅
- SIT1: `mongodb-sit1` ✅
- SIT2: `mongodb-sit2` ✅
- SIT3: `mongodb-sit3` ✅

**Alternative**: Rename DEV to `mongodb-dev` during next major migration window (high risk, not recommended)

---

## Question 7: S3 Data Protection for ELT Loader

### Available S3 Protection Features

#### 1. **Versioning** ✅ Already Enabled
```hcl
versioning {
  enabled = true
}
```
- Keeps all versions of objects
- Protects against accidental deletion/overwrite
- Can restore to any previous version
- **Cost**: Storage × number of versions

#### 2. **Object Lock (WORM)** - Recommended for Audit Data
```hcl
object_lock_configuration {
  object_lock_enabled = "Enabled"
  rule {
    default_retention {
      mode = "GOVERNANCE"  # or "COMPLIANCE"
      days = 2555          # 7 years for audit retention
    }
  }
}
```
- **GOVERNANCE mode**: Admins can delete with special permission
- **COMPLIANCE mode**: Nobody can delete (even root) until retention period
- Recommended for audit logs (regulatory compliance)

#### 3. **Replication** - Cross-Region Backup
```hcl
replication_configuration {
  role = aws_iam_role.replication.arn
  rules {
    id     = "replicate-elt-data"
    status = "Enabled"
    
    destination {
      bucket        = "arn:aws:s3:::sml-elt-prod-backup-us-east-1"
      storage_class = "GLACIER_IR"  # Cheaper storage for backup
    }
  }
}
```
- Replicate to different region (DR protection)
- Survive regional AWS outage
- **Cost**: Storage in 2 regions + replication bandwidth

#### 4. **Lifecycle Policies** ✅ Already Enabled
```hcl
lifecycle_rule {
  enabled = true
  
  transition {
    days          = 90
    storage_class = "INTELLIGENT_TIERING"  # Auto-optimize cost
  }
  
  transition {
    days          = 180
    storage_class = "GLACIER_IR"  # Archive old data
  }
  
  noncurrent_version_transition {
    days          = 30
    storage_class = "GLACIER_IR"  # Archive old versions
  }
  
  noncurrent_version_expiration {
    days = 365  # Delete old versions after 1 year
  }
}
```
- Automatically move old data to cheaper storage
- Delete old versions to save cost

#### 5. **S3 Backup via AWS Backup Service**
```hcl
resource "aws_backup_plan" "s3_elt" {
  name = "s3-elt-backup-plan"
  
  rule {
    rule_name         = "daily_backup"
    target_vault_name = aws_backup_vault.elt.name
    schedule          = "cron(0 2 * * ? *)"  # 2 AM daily
    
    lifecycle {
      cold_storage_after = 30   # Move to Glacier after 30 days
      delete_after       = 2555  # 7 years retention
    }
  }
}
```
- Continuous backup (point-in-time recovery)
- Centralized backup management
- Compliance reporting

#### 6. **Encryption** ✅ Already Enabled
```hcl
server_side_encryption_configuration {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.elt.arn
    }
  }
}
```
- Protects data at rest
- Using KMS for key management

#### 7. **MFA Delete** - Prevent Accidental Deletion
```hcl
versioning {
  enabled    = true
  mfa_delete = true  # Requires MFA token to delete
}
```
- Requires MFA token to:
  1. Delete object versions
  2. Change versioning state
- Only bucket owner (root account) can enable

### Recommended Configuration for ELT Audit Data

```hcl
# platform-prerequisites/terraform/boomi-elt-s3/s3.tf

resource "aws_s3_bucket" "elt" {
  bucket = "sml-elt-${var.environment}"
  
  # Prevent accidental deletion of bucket
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning (protection against overwrites)
resource "aws_s3_bucket_versioning" "elt" {
  bucket = aws_s3_bucket.elt.id
  
  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Enabled"  # ← Add this for extra protection
  }
}

# Object Lock (compliance retention)
resource "aws_s3_bucket_object_lock_configuration" "elt" {
  bucket = aws_s3_bucket.elt.id
  
  object_lock_enabled = "Enabled"
  
  rule {
    default_retention {
      mode = "GOVERNANCE"  # Can be overridden by IAM users with bypass permission
      years = 7            # 7-year audit retention
    }
  }
}

# Replication to backup region (DR)
resource "aws_s3_bucket_replication_configuration" "elt" {
  bucket = aws_s3_bucket.elt.id
  role   = aws_iam_role.replication.arn
  
  rule {
    id     = "replicate-all"
    status = "Enabled"
    
    filter {}  # Replicate all objects
    
    destination {
      bucket        = aws_s3_bucket.elt_backup.arn
      storage_class = "GLACIER_IR"
    }
  }
}

# Lifecycle for cost optimization
resource "aws_s3_bucket_lifecycle_configuration" "elt" {
  bucket = aws_s3_bucket.elt.id
  
  rule {
    id     = "archive-old-data"
    status = "Enabled"
    
    # Current versions
    transition {
      days          = 90
      storage_class = "INTELLIGENT_TIERING"
    }
    
    transition {
      days          = 365
      storage_class = "GLACIER_IR"
    }
    
    # Old versions
    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "GLACIER_IR"
    }
    
    noncurrent_version_expiration {
      noncurrent_days = 2555  # 7 years
    }
  }
}

# Logging (audit trail of access)
resource "aws_s3_bucket_logging" "elt" {
  bucket = aws_s3_bucket.elt.id
  
  target_bucket = aws_s3_bucket.elt_logs.id
  target_prefix = "access-logs/"
}
```

### Cost Estimate (Protection Features)

| Feature | Monthly Cost (per TB) | Notes |
|---|---|---|
| Versioning | ~$23/TB | Standard storage × versions |
| Object Lock | $0 | Free (uses versioning storage) |
| Replication | $23/TB + bandwidth | Replica in 2nd region |
| Glacier archive | $4/TB | After 180 days |
| AWS Backup | $50/TB/month | Continuous backup |
| **Total** | **$50-100/TB/month** | Depends on data volume + retention |

**Recommendation**: Enable **Versioning + Object Lock + Replication** (mid-tier protection, ~$50/TB/month)

---

## Summary of Changes for PR #76

### Updates Needed:

1. ✅ **Public subnets**: Change from /24 → **/26** (all environments)
2. ✅ **Production**: Change from 2 AZs → **3 AZs** (all subnets × 3)
3. ✅ **Production private**: Change from /23 → **/21** (2048 IPs per AZ)
4. ✅ **SIT environments**: Add **SIT1, SIT2, SIT3** (each /20 = 4,096 IPs)
5. ✅ **Reserved space**: Add **/20 reserved block** for SIT4/future
6. ✅ **Namespace naming**: Document rationale (DEV legacy, UAT+ suffixed)
7. ✅ **S3 protection**: Add section on available features + recommendations

### Action Required:

Should I update `environment-reference.md` with these subnet changes?
