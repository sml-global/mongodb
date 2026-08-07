#!/usr/bin/env bash
# Audit Terraform resource names for naming convention compliance
#
# Convention:
# - EKS clusters: oms-{env}-eks-cluster
# - VPCs: oms-{env}-vpc
# - IAM roles: oms-{env}-{component} OR sml-{project}-{component}-{env}
# - S3 buckets: sml-oms-{component}-{env}
# - RDS/Aurora: oms-{env}-{database}
#
# Usage: ./scripts/audit-terraform-naming.sh

set -euo pipefail

TERRAFORM_DIR="platform-prerequisites/terraform"
REPORT_FILE="${1:-terraform-naming-audit-$(date +%Y-%m-%d).md}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "🔍 Auditing Terraform resource names for naming convention compliance..."
echo ""

# Initialize report
cat > "$REPORT_FILE" <<EOF
# Terraform Resource Naming Audit

**Date:** $(date +%Y-%m-%d)
**Purpose:** Identify Terraform resources that don't follow the approved naming convention

---

## Naming Convention

**EKS Clusters:**
- Standard: \`oms-{env}-eks-cluster\` (e.g., \`oms-dev-eks-cluster\`, \`oms-uat-eks-cluster\`)
- ❌ Legacy: \`EKS-boomi-runtime-cluster\` (DEV only, documented exception)

**VPCs:**
- Standard: \`oms-{env}-vpc\`

**IAM Roles:**
- Standard: \`oms-{env}-{component}\` OR \`sml-{project}-{component}-{env}\`
- Example: \`oms-uat-mongodb-backup\`, \`sml-elt-admin-prod\`

**S3 Buckets:**
- Standard: \`sml-oms-{component}-{env}\`
- ❌ Legacy: \`sml-elt-*\` (different project, separate naming scheme)

**RDS/Aurora:**
- Standard: \`oms-{env}-{database}\`

**EKS Node Groups:**
- Standard: \`oms-{env}-{purpose}\`

---

## Audit Results

EOF

# Function to extract resource names from Terraform files
audit_resource_type() {
    local resource_type=$1
    local pattern=$2
    local description=$3

    echo -e "${BLUE}Auditing ${description}...${NC}"
    echo "### $description" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"

    # Find all resources of this type
    found=0
    while IFS= read -r line; do
        file=$(echo "$line" | cut -d: -f1)
        resource=$(echo "$line" | cut -d: -f2-)

        # Extract resource name from 'resource "type" "name"' or name = "value"
        if [[ "$resource" =~ resource\ \"$resource_type\"\ \"([^\"]+)\" ]]; then
            resource_name="${BASH_REMATCH[1]}"
            resource_label="$resource_type.$resource_name"

            # Try to find the actual AWS name in the file
            aws_name=$(grep -A 20 "resource \"$resource_type\" \"$resource_name\"" "$file" | grep -E "^\s*name\s*=\s*\"" | head -1 | sed -E 's/.*name\s*=\s*"([^"]+)".*/\1/')

            if [[ -n "$aws_name" ]]; then
                echo "  Found: $resource_label → AWS name: $aws_name" | tee -a "$REPORT_FILE"

                # Check against pattern
                if [[ "$aws_name" =~ $pattern ]]; then
                    echo -e "    ${GREEN}✅ COMPLIANT${NC}" | tee -a "$REPORT_FILE"
                else
                    echo -e "    ${RED}❌ VIOLATION${NC} (does not match pattern: $pattern)" | tee -a "$REPORT_FILE"
                fi
            else
                echo "  Found: $resource_label (name extracted from variables)" | tee -a "$REPORT_FILE"
                echo -e "    ${YELLOW}⚠️  MANUAL REVIEW${NC} (name uses variables)" | tee -a "$REPORT_FILE"
            fi
            echo "" >> "$REPORT_FILE"
            ((found++))
        fi
    done < <(grep -r "resource \"$resource_type\"" "$TERRAFORM_DIR" --include="*.tf" 2>/dev/null || true)

    if [ $found -eq 0 ]; then
        echo "  No resources of type $resource_type found" | tee -a "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    fi
}

# Audit EKS Clusters
audit_resource_type "aws_eks_cluster" "^oms-(dev|uat|sit|prod)-eks-cluster$|^EKS-boomi-runtime-cluster$" "EKS Clusters"

# Audit VPCs
audit_resource_type "aws_vpc" "^oms-(dev|uat|sit|prod)-vpc$" "VPCs"

# Audit IAM Roles
audit_resource_type "aws_iam_role" "^(oms-(dev|uat|sit|prod)-[a-z-]+|sml-[a-z]+-[a-z-]+-(dev|uat|sit|prod))$" "IAM Roles"

# Audit S3 Buckets
audit_resource_type "aws_s3_bucket" "^sml-oms-[a-z-]+-(dev|uat|sit|prod)" "S3 Buckets"

# Audit RDS/Aurora Clusters
audit_resource_type "aws_rds_cluster" "^oms-(dev|uat|sit|prod)-[a-z]+$" "RDS/Aurora Clusters"

# Audit EKS Node Groups
audit_resource_type "aws_eks_node_group" "^oms-(dev|uat|sit|prod)-[a-z-]+$" "EKS Node Groups"

echo ""
echo -e "${GREEN}✅ Audit complete!${NC}"
echo "Report saved to: $REPORT_FILE"
echo ""

# Summary statistics
cat >> "$REPORT_FILE" <<EOF

---

## Summary

**Audit Date:** $(date +%Y-%m-%d %H:%M:%S)
**Terraform Directory:** \`$TERRAFORM_DIR\`

### Recommendations

1. **EKS Clusters:**
   - Accept \`EKS-boomi-runtime-cluster\` as legacy exception (DEV only)
   - Document in \`docs/references/component-catalog.md\` § "Naming Convention"
   - New clusters must follow \`oms-{env}-eks-cluster\` pattern

2. **Resources using variables:**
   - Review each file manually to confirm variable values match convention
   - Check \`.tfvars\` files for actual values

3. **Violations found:**
   - Create separate PR per violation category (low risk → high risk)
   - Use Terraform state moves where possible (non-destructive)
   - Document legacy exceptions that are too risky to rename

### Next Steps

- [ ] Review manual review items (resources using variables)
- [ ] Create decision document for violations
- [ ] Update documentation with legacy exceptions
- [ ] Create PRs for safe renames (if any)

EOF

# Print summary to console
echo "📊 Summary:"
echo "  - Report: $REPORT_FILE"
echo "  - Review the report for violations and manual review items"
echo "  - Next: Create decision document for any violations found"
