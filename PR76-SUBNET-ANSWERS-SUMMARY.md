# PR #76 Subnet Design - Summary of Answers

## Quick Answers to Your 7 Questions

### 1. Public Subnet Components & /26 Sizing ✅

**Components in public subnets**:
- NAT Gateways (1 per AZ): ~3-5 IPs each
- Internet-facing ALBs: 8-15 IPs per AZ (AWS reserves 8 for scaling)
- Bastion hosts (optional): 1-2 IPs
- VPN endpoints (optional): 1 IP per AZ
- **Total**: ~30-45 IPs per AZ

**/26 (64 IPs) is sufficient**: Usable 59 IPs (64 - 5 AWS reserved) > 45 required
- **Savings**: /24 → /26 saves **576 IPs per environment** (192 per AZ × 3 AZs)

### 2. Production 3-AZ Support ✅

**Yes, Aurora supports 3 AZs**:
- 1 writer + 2 read replicas across 3 AZs
- Best practice for HA

**MongoDB requires 3 AZs for HA**:
- 3-node replica set (1 per AZ)
- Losing 1 AZ → 2/3 quorum maintained ✅
- With 2 AZs: Losing 1 AZ → 1/2 no quorum ❌

### 3. Production Private Subnet: /21 Preferred ✅

**Comparison**:
| Size | IPs/AZ | Pod Capacity | Verdict |
|---|---|---|---|
| /23 | 512 | ~256 pods | ❌ Too small |
| /22 | 1024 | ~512 pods | ✅ Minimum |
| **/21** | **2048** | **~1024 pods** | **✅ Recommended** |

**Fits in /18?** Yes, 7,104 IPs used / 16,384 available = **56.6% spare capacity**

### 4. Multiple SIT Environments ✅

**SIT sizing** (DEV-like load, test-only):
- Each SIT: **/20 (4,096 IPs)**
- 2 AZs (don't need 3 for test)
- Public: /26 × 2 = 128 IPs
- Private: /22 × 2 = 2,048 IPs
- **Fits**: SIT1, SIT2, SIT3 + 1 reserved block

### 5. Full /16 Consumption ✅

**Yes, perfectly allocated**:
```
DEV:        10.200.0.0/18    (16,384 IPs)
UAT:        10.200.64.0/18   (16,384 IPs)
Production: 10.200.128.0/18  (16,384 IPs)
SIT1:       10.200.192.0/20  (4,096 IPs)
SIT2:       10.200.208.0/20  (4,096 IPs)
SIT3:       10.200.224.0/20  (4,096 IPs)
Reserved:   10.200.240.0/20  (4,096 IPs)
─────────────────────────────────────────
TOTAL:      10.200.0.0/16    (65,536 IPs) ✅
```

### 6. Namespace Naming (Why no -dev suffix) 📋

**DEV uses `mongodb` (no `-dev`)**: Historical/backward compatibility
- Existing PVCs, secrets, scripts reference `mongodb`
- Changing requires: backup → destroy → recreate → restore (high risk)

**All other environments use suffix**:
- UAT: `mongodb-uat` ✅
- Production: `mongodb-prod` ✅
- SIT1/2/3: `mongodb-sit1/2/3` ✅

**Recommendation**: Keep DEV as-is (don't change), enforce suffix for all new environments

### 7. S3 Data Protection Features 🛡️

**Available features**:
1. ✅ **Versioning** (already enabled) - prevents accidental deletion
2. 🔒 **Object Lock (WORM)** - compliance retention (7 years for audit)
3. 🌍 **Cross-Region Replication** - DR protection
4. ♻️ **Lifecycle Policies** (already enabled) - auto-archive to Glacier
5. 💾 **AWS Backup** - continuous point-in-time recovery
6. 🔐 **Encryption** (already enabled) - KMS encryption at rest
7. 🔑 **MFA Delete** - requires MFA token to delete objects

**Recommended for audit data**:
- Versioning ✅
- Object Lock (GOVERNANCE mode, 7-year retention) ← ADD THIS
- Cross-Region Replication to backup region ← ADD THIS
- **Cost**: ~$50/TB/month (vs. $23/TB without protection)

---

## Corrected Production Subnet Allocation (3 AZs)

```
Production VPC: 10.200.128.0/18 (16,384 IPs)

PUBLIC SUBNETS (3 × /26 = 192 IPs total):
  AZ-a: 10.200.128.0/26   (64 IPs)
  AZ-b: 10.200.128.64/26  (64 IPs)
  AZ-c: 10.200.128.128/26 (64 IPs)

PRIVATE SUBNETS (3 × /21 = 6,144 IPs total):
  AZ-a: 10.200.136.0/21   (2,048 IPs)
  AZ-b: 10.200.144.0/21   (2,048 IPs)
  AZ-c: 10.200.152.0/21   (2,048 IPs)

DB SUBNETS (3 × /24 = 768 IPs total):
  AZ-a: 10.200.160.0/24   (256 IPs)
  AZ-b: 10.200.161.0/24   (256 IPs)
  AZ-c: 10.200.162.0/24   (256 IPs)

Total: 7,104 IPs used (43.4%)
Spare: 9,280 IPs (56.6%)
```

**Verified**:
- ✅ All subnets within Production /18
- ✅ No overlaps
- ✅ Proper CIDR alignment (/21 on 2048-byte boundary)

---

## Action Required

**Should I update `environment-reference.md` in PR #76 with these subnet changes?**

This would involve:
1. Changing Production from 2 AZs → 3 AZs
2. Changing Production public from /24 → /26 (all 3 AZs)
3. Changing Production private from /23 → /21 (all 3 AZs)
4. Adding SIT1, SIT2, SIT3 (each /20)
5. Adding Reserved /20 block
6. Updating subnet tables with exact CIDRs above
7. Adding S3 data protection recommendations section

**Note**: This would effectively merge PR #84 (production 3-AZ network) into PR #76.
