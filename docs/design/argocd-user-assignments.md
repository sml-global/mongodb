# ArgoCD User Assignments

**Quick reference for AWS Identity Center group assignments**

Last updated: 2026-08-07

---

## User Role Assignments

| User | Email | AWS SSO Group | ArgoCD Role | Production | UAT | DEV | SIT |
|---|---|---|---|---|---|---|---|
| Xavier Lee | xavierlee@sml.com | ArgoCD-Admin | role:admin | ✅ Full | ✅ Full | ✅ Full | ✅ Full |
| Jiawei Ma | jiaweima@sml.com | ArgoCD-Admin | role:admin | ✅ Full | ✅ Full | ✅ Full | ✅ Full |
| YC Zhang | yczhang@sml.com | ArgoCD-Operator | role:operator | 👁️ View | ✅ Deploy | ✅ Deploy | ✅ Deploy |
| Vince Huang | vincehuang@sml.com | ArgoCD-Operator | role:operator | 👁️ View | ✅ Deploy | ✅ Deploy | ✅ Deploy |
| Frank Cheong | frankcheong@sml.com | ArgoCD-Viewer | role:readonly | 👁️ View | 👁️ View | 👁️ View | 👁️ View |

---

## Permission Matrix

### ArgoCD-Admin (xavierlee@sml.com, jiaweima@sml.com)

| Permission | Production | UAT | DEV | SIT |
|---|---|---|---|---|
| View applications | ✅ | ✅ | ✅ | ✅ |
| Create applications | ✅ | ✅ | ✅ | ✅ |
| Sync (deploy) | ✅ | ✅ | ✅ | ✅ |
| Delete applications | ✅ | ✅ | ✅ | ✅ |
| Rollback | ✅ | ✅ | ✅ | ✅ |
| View logs | ✅ | ✅ | ✅ | ✅ |
| Exec into pods | ✅ | ✅ | ✅ | ✅ |
| Manage clusters | ✅ | ✅ | ✅ | ✅ |
| Manage repositories | ✅ | ✅ | ✅ | ✅ |

### ArgoCD-Operator (yczhang@sml.com, vincehuang@sml.com)

| Permission | Production | UAT | DEV | SIT |
|---|---|---|---|---|
| View applications | ✅ | ✅ | ✅ | ✅ |
| Create applications | ❌ | ✅ | ✅ | ✅ |
| Sync (deploy) | ❌ | ✅ | ✅ | ✅ |
| Delete applications | ❌ | ✅ | ✅ | ✅ |
| Rollback | ❌ | ✅ | ✅ | ✅ |
| View logs | ✅ | ✅ | ✅ | ✅ |
| Exec into pods | ❌ | ✅ | ✅ | ✅ |
| Manage clusters | ❌ | ❌ | ❌ | ❌ |
| Manage repositories | ❌ (view only) | ❌ (view only) | ❌ (view only) | ❌ (view only) |

### ArgoCD-Viewer (frankcheong@sml.com)

| Permission | Production | UAT | DEV | SIT |
|---|---|---|---|---|
| View applications | ✅ | ✅ | ✅ | ✅ |
| Create applications | ❌ | ❌ | ❌ | ❌ |
| Sync (deploy) | ❌ | ❌ | ❌ | ❌ |
| Delete applications | ❌ | ❌ | ❌ | ❌ |
| Rollback | ❌ | ❌ | ❌ | ❌ |
| View logs | ✅ | ✅ | ✅ | ✅ |
| Exec into pods | ❌ | ❌ | ❌ | ❌ |
| Manage clusters | ❌ | ❌ | ❌ | ❌ |
| Manage repositories | ❌ | ❌ | ❌ | ❌ |

---

## AWS Identity Center Setup Checklist

### Step 1: Create Groups

- [ ] Create group: `ArgoCD-Admin`
- [ ] Create group: `ArgoCD-Operator`
- [ ] Create group: `ArgoCD-Viewer`

### Step 2: Add Users to Groups

**ArgoCD-Admin**:
- [ ] Add xavierlee@sml.com
- [ ] Add jiaweima@sml.com

**ArgoCD-Operator**:
- [ ] Add yczhang@sml.com
- [ ] Add vincehuang@sml.com

**ArgoCD-Viewer**:
- [ ] Add frankcheong@sml.com

### Step 3: Create Permission Sets

- [ ] Create permission set: `ArgoCD-Admin-Production`
  - Attach AWS managed policy: `ReadOnlyAccess`
  - Attach custom inline policy (see design doc)
  
- [ ] Create permission set: `ArgoCD-Operator-Production`
  - Attach AWS managed policy: `ReadOnlyAccess`
  - Attach custom inline policy (see design doc)

- [ ] Create permission set: `ArgoCD-Viewer-Production`
  - Attach AWS managed policy: `ReadOnlyAccess`

### Step 4: Assign Permission Sets to Production Account

- [ ] Assign `ArgoCD-Admin-Production` to group `ArgoCD-Admin` in account 632674123947
- [ ] Assign `ArgoCD-Operator-Production` to group `ArgoCD-Operator` in account 632674123947
- [ ] Assign `ArgoCD-Viewer-Production` to group `ArgoCD-Viewer` in account 632674123947

---

## Testing Access

After AWS Identity Center setup is complete:

### Test Admin Access (xavierlee@sml.com)

```bash
# Login to Production account
aws sso login --profile AdministratorAccess-632674123947

# Access Production EKS cluster
kubectl --context oms-prod-eks-cluster get pods -n argocd

# Browse to ArgoCD UI
open https://argocd.oms-prod.example.com
# Login via AWS SSO
# Verify: Can see all 4 clusters
# Verify: Has "Sync" button on all apps
```

### Test Operator Access (yczhang@sml.com)

```bash
# Login to Production account
aws sso login --profile ArgoCD-Operator-Production

# Browse to ArgoCD UI
open https://argocd.oms-prod.example.com
# Login via AWS SSO
# Verify: Can see all 4 clusters
# Verify: Has "Sync" button on UAT/DEV/SIT apps
# Verify: NO "Sync" button on Production apps (view only)
```

### Test Viewer Access (frankcheong@sml.com)

```bash
# Login to Production account
aws sso login --profile ArgoCD-Viewer-Production

# Browse to ArgoCD UI
open https://argocd.oms-prod.example.com
# Login via AWS SSO
# Verify: Can see all 4 clusters
# Verify: NO "Sync" button on any apps (read-only)
# Verify: Can view logs but cannot exec into pods
```

---

## Adding New Users

### To add a new Admin:

1. Add user email to AWS SSO
2. Add user to group: `ArgoCD-Admin`
3. User logs into ArgoCD → automatically gets admin access

### To add a new Operator:

1. Add user email to AWS SSO
2. Add user to group: `ArgoCD-Operator`
3. User logs into ArgoCD → automatically gets operator access

### To add a new Viewer:

1. Add user email to AWS SSO
2. Add user to group: `ArgoCD-Viewer`
3. User logs into ArgoCD → automatically gets viewer access

---

## References

- [ArgoCD User Access Design](argocd-user-access-design.md) - Full design specification
- [ArgoCD Multi-Environment Architecture](../../ARGOCD-MULTI-ENV-ARCHITECTURE.md) - Cross-account setup
- [ArgoCD RBAC Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
