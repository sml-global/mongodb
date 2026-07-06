# Environment Setup Guide

Complete this guide once per workstation before running any provisioning commands.

**Who this is for:** All personas (Infra Operator, Infra Architect, Boomi Admin, Enterprise Architect).

**Related docs:**
- After setup, operators proceed to the [Operator Runbook](operator-runbook.md)
- Boomi admins proceed to the [Boomi Integration Guide](boomi-integration-guide.md)
- Full component context in the [Component Catalog](../references/component-catalog.md)

---

## Prerequisites Checklist

Before starting, get these values from the platform or AWS account owner:

| Value | Why You Need It |
|---|---|
| AWS SSO start URL | Used by `aws configure sso` to create a login profile |
| AWS SSO region | Region where IAM Identity Center is configured (may differ from workload region) |
| AWS account ID | Confirms you are logged into the intended account |
| AWS SSO permission set/role | Determines what Terraform and kubectl can do |
| Workload AWS region | Used by Terraform providers and AWS CLI (`ap-east-1` for OMS dev) |
| EKS cluster name | Used by `aws eks update-kubeconfig` (`EKS-boomi-runtime-cluster` for OMS dev) |
| VPC ID and private subnet IDs | Required for Aurora PostgreSQL networking (pg scope only) |
| Remote state bucket name | Required for shared Terraform state (`sml-oms-dev-tfstate` for OMS dev) |

## Install Required Tools

### Required Commands

| Tool | Purpose | Minimum Version |
|---|---|---|
| `aws` | AWS CLI for SSO auth, EKS, S3, IAM operations | v2.x |
| `terraform` | Infrastructure provisioning | >= 1.5.0 |
| `kubectl` | Kubernetes cluster operations | v1.28+ |
| `kustomize` | Manifest rendering and overlays | v5.x |
| `rg` (ripgrep) | Fast text search for validation scripts | any |
| `openssl` | Secret generation (random bytes, base64) | any |
| `helm` | Only for platform admin bootstrap mode | v3.x |
| `groovy` | Only for Boomi audit log library testing | v4.x |

### macOS

```bash
brew install awscli terraform kubectl kustomize ripgrep openssl
# Optional (platform admin): brew install helm
# Optional (Boomi admin): brew install groovy
```

### Ubuntu/Debian

```bash
# Base packages
sudo apt-get update
sudo apt-get install -y curl wget unzip gnupg lsb-release ca-certificates ripgrep openssl

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip

# Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform

# kubectl
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubectl

# kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/kustomize
```

### Windows

Using `winget`:

```powershell
winget install --id Amazon.AWSCLI -e
winget install --id Hashicorp.Terraform -e
winget install --id Kubernetes.kubectl -e
winget install --id Kubernetes.kustomize -e
winget install --id BurntSushi.ripgrep.MSVC -e
winget install --id ShiningLight.OpenSSL.Light -e
```

Using Chocolatey:

```powershell
choco install awscli terraform kubernetes-cli kustomize ripgrep openssl -y
```

### Verify Installation

```bash
command -v aws terraform kubectl kustomize rg openssl
terraform version
aws --version
kubectl version --client
```

On Windows PowerShell:

```powershell
Get-Command aws, terraform, kubectl, kustomize, rg, openssl
terraform version
aws --version
kubectl version --client
```

## Configure AWS CLI With SSO

This repository uses AWS SSO session `oms-dev`.

Configured accounts/profiles:
- Account `815402439714` (OMS dev): profile `default` and `AdministratorAccess-815402439714`
- Account `307506882994`: profile `AdministratorAccess-307506882994`

### Quick Setup (OMS dev account)

```bash
aws sso login --profile default
export AWS_PROFILE=default
export AWS_REGION=ap-east-1
aws sts get-caller-identity
```

Expected result: account `815402439714`, role `AdministratorAccess`, region `ap-east-1`.

### First-Time Profile Creation

If SSO profile is missing on a new workstation:

```bash
aws configure sso --profile default
```

The prompt asks for: SSO start URL, SSO region, AWS account, permission set/role, default workload region, output format (`json`).

Then login and export:

```bash
aws sso login --profile default
export AWS_PROFILE=default
export AWS_REGION=ap-east-1
```

On Windows PowerShell:

```powershell
$env:AWS_PROFILE = "default"
$env:AWS_REGION = "ap-east-1"
```

### Verify AWS Access

```bash
aws sts get-caller-identity
aws configure get region
```

### Available Profiles

```bash
aws configure list-profiles
cat ~/.aws/config
```

## Configure Kubernetes Access

### Update Kubeconfig

```bash
aws eks update-kubeconfig \
  --name EKS-boomi-runtime-cluster \
  --region ap-east-1 \
  --profile "$AWS_PROFILE"
```

### Verify Cluster Connectivity

```bash
kubectl config current-context
kubectl cluster-info
kubectl get ns
```

### Verify Required Permissions

For MongoDB provisioning:

```bash
kubectl auth can-i get secrets -n mongodb
kubectl auth can-i create secrets -n mongodb
```

For SigNoz provisioning:

```bash
kubectl auth can-i get pods -n signoz
kubectl auth can-i create helmreleases -n signoz
```

## Confirm Repository Location

All scripts must run from the repository root:

```bash
pwd
test -d platform-prerequisites/terraform/mongodb && echo "repo root confirmed"
```

On Windows PowerShell:

```powershell
Get-Location
Test-Path platform-prerequisites/terraform/mongodb
```

## Run Preflight Verification

After completing setup, run the unified preflight check:

```bash
scripts/verify-platform-health.sh --preflight
```

This checks:
- All required CLI tools are available with minimum versions
- AWS SSO session is active and identity is confirmed
- Kubernetes cluster is reachable and context is correct
- Required CRDs exist (Flux, Kyverno, cert-manager)
- EBS CSI driver is present
- Repository root is confirmed

If any check fails, the output explains what to fix.

See [Verification Commands](../references/verification-commands.md) for the full reference.

## Network Access Requirements

| Target | Protocol | Port | From Where |
|---|---|---|---|
| AWS APIs (sts, s3, eks, iam, rds, ec2) | HTTPS | 443 | Workstation → internet |
| EKS Kubernetes API | HTTPS | 443 | Workstation → EKS endpoint |
| Aurora PostgreSQL | TCP | 5432 | Application pods / approved CIDRs → VPC |
| SigNoz dashboard (dev) | HTTP | 3301 (local) | Workstation localhost via port-forward |
| SigNoz dashboard (prod) | HTTPS | 443 | Browser → ingress endpoint |

No VPN or bastion is required for the current dev environment — EKS public endpoint is enabled. Production environments may restrict this.

## Next Steps

| Persona | Go to |
|---|---|
| Infra Operator | [Operator Runbook](operator-runbook.md) — start provisioning |
| Infra Architect | [Architect Reference](architect-reference.md) — understand architecture |
| Boomi Admin | [Boomi Integration Guide](boomi-integration-guide.md) — use the audit library |
| Enterprise Architect | [Enterprise Architecture](enterprise-architecture.md) — review design |
