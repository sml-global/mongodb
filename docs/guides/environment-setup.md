# Environment Setup Guide

Complete this guide once per workstation before running any provisioning commands.

**Who this is for:** All personas (Infra Operator, Infra Architect, Boomi Admin, Enterprise Architect).

**Typical effort:**
- Infra Operator / Infra Architect: 45-90 minutes on a fresh workstation
- Boomi Admin (local harness use): 30-60 minutes
- Viewer-only report consumer: 10-20 minutes (SSO + dashboard access only)

**Access needed before you start:**
- Internet access to AWS endpoints
- Local admin rights to install tools
- AWS SSO start URL and assigned permission set

**Related docs:**
- After setup, operators proceed to the [Operator Runbook](operator-runbook.md)
- Boomi admins proceed to the [Boomi Integration Guide](boomi-integration-guide.md)
- Full component context in the [Component Catalog](../references/component-catalog.md)

## Persona-Specific Setup Paths

Use the smallest setup path that matches your role. The "Why" column explains
why your role needs (or doesn't need) each piece — so you're not just
following steps blindly.

| Persona | What You Need To Do | Why |
|---|---|---|
| Infra Operator | Complete this full guide | You run Terraform and kubectl directly to provision/destroy infrastructure — you need every tool this guide installs. |
| Infra Architect | Complete this full guide | You review and modify the same Terraform/Kubernetes definitions the Operator applies, and need to reproduce/validate changes locally before they're rolled out. |
| Boomi Admin (integration development) | AWS SSO + required tools + optional Groovy + optional kubectl (if local testing) | You call the audit-log library and read telemetry — you don't provision infrastructure, so Terraform/kustomize aren't needed. Groovy/kubectl are only needed if you run the test harness locally instead of relying on an Operator-provisioned environment. |
| Enterprise Architect / report viewer | AWS SSO login + SigNoz dashboard access only (tool installation not required) | Your job is reviewing telemetry/compliance reports and design posture, not changing infrastructure — no CLI tooling touches production state on your behalf. |

If you are only reviewing telemetry reports, skip Terraform and kubectl sections.

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
| `tfenv` + `terraform` | Terraform version management + provisioning | tfenv latest; TF pinned via `.terraform-version` |
| `kubectl` | Kubernetes cluster operations | within ±1 of server (currently: v1.34–v1.36) |
| `kustomize` | Manifest rendering and overlays | v5.x |
| `rg` (ripgrep) | Fast text search for validation scripts | any |
| `openssl` | Secret generation (random bytes, base64) | any |
| `python3` | URL-encodes passwords in `scripts/create-audit-writer-secret.sh` (required for Day-1 MongoDB setup) | v3.8+ |
| `helm` | Only for platform admin bootstrap mode | v3.x |
| `groovy` | Only for Boomi audit log library testing | v4.x |
| `playwright` (Python package) | Only for the SigNoz Service Account/API key bootstrap (`scripts/bootstrap-signoz-service-account.sh`) -- drives a headless browser so no manual UI step is needed | v1.x |

> **Note:** `python3` is required, not optional — `scripts/create-audit-writer-secret.sh` fails without it. It is not covered by `scripts/verify-platform-health.sh --preflight`, so verify it manually with `python3 --version` on every platform.

> **Note:** `playwright` is only needed by whoever runs `scripts/provision.sh signoz-observability` for the first time in an environment (typically the Infra Operator/Architect) -- install it once with:
> ```bash
> python3 -m pip install playwright
> python3 -m playwright install chromium
> ```

### Terraform Version Management (tfenv)

This repo uses [tfenv](https://github.com/tfutils/tfenv) for Terraform version management. The file `.terraform-version` in the repo root pins the exact version (currently `1.15.7`).

**Why tfenv?** Different projects may need different Terraform versions. tfenv auto-switches when you `cd` into this repo.

Install tfenv first, then Terraform is managed automatically:

```bash
# macOS
brew install tfenv

# Linux
git clone https://github.com/tfutils/tfenv.git ~/.tfenv
echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc

# Then install the pinned version (reads .terraform-version automatically)
tfenv install
tfenv use
terraform version   # should show 1.15.7
```

If you prefer not to use tfenv, install Terraform `1.15.7` directly — but you are responsible for version alignment.

### macOS

> **Homebrew prerequisite:** these commands assume Homebrew is already installed. On a fresh Mac, install it first:
> ```bash
> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
> ```

```bash
# tfenv + terraform: already covered by "Terraform Version Management (tfenv)" above
#   brew install tfenv && tfenv install && tfenv use
brew install awscli kubectl kustomize ripgrep openssl python3
# Optional (platform admin): brew install helm
# Optional (Boomi admin): brew install groovy
```

> macOS no longer ships `python3` by default (Xcode Command Line Tools only provide a stub that prompts an install). `brew install python3` guarantees it is present.

### Ubuntu/Debian

```bash
# Base packages (includes python3, which ships by default on Ubuntu but is listed
# explicitly since minimal/container base images may omit it)
sudo apt-get update
sudo apt-get install -y curl wget unzip gnupg lsb-release ca-certificates ripgrep openssl python3

# AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip && sudo ./aws/install && rm -rf aws awscliv2.zip

# Terraform: do NOT install via apt here — it installs the latest version and
# bypasses the tfenv version pinning described above. Instead, follow
# "Terraform Version Management (tfenv)" above:
#   git clone https://github.com/tfutils/tfenv.git ~/.tfenv
#   echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
#   tfenv install && tfenv use

# kubectl
sudo install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update && sudo apt-get install -y kubectl

# kustomize
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
sudo mv kustomize /usr/local/bin/kustomize

# Optional (platform admin): helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Optional (Boomi admin): groovy, via SDKMAN (apt does not carry a current groovy package)
curl -s "https://get.sdkman.io" | bash
source "$HOME/.sdkman/bin/sdkman-init.sh"
sdk install groovy
```

### Windows

> **tfenv note:** tfenv is a bash tool and has no native Windows build. Either run the setup inside WSL2 (Ubuntu) and follow the Ubuntu/Debian instructions above, or pin the exact Terraform version manually on native Windows (see below) instead of installing an unpinned "latest" version.

Using `winget`:

```powershell
winget install --id Amazon.AWSCLI -e
winget install --id Hashicorp.Terraform -e   # installs latest; pin manually, see note below
winget install --id Kubernetes.kubectl -e
winget install --id Kubernetes.kustomize -e
winget install --id BurntSushi.ripgrep.MSVC -e
winget install --id ShiningLight.OpenSSL.Light -e
winget install --id Python.Python.3.12 -e
# Optional (platform admin):
winget install --id Helm.Helm -e
# Optional (Boomi admin) — groovy has no winget package; install via SDKMAN in WSL2,
# or download the Groovy Windows installer from https://groovy.apache.org/download.html
```

To pin Terraform to `1.15.7` on native Windows instead of the winget "latest" package:

```powershell
choco install terraform --version=1.15.7 -y
terraform version   # should show 1.15.7
```

Using Chocolatey:

> **Chocolatey prerequisite:** unlike winget, Chocolatey does not ship with Windows. Install it first (in an elevated PowerShell prompt) — see the [official install docs](https://chocolatey.org/install) — or use the winget path above instead.

```powershell
choco install awscli terraform --version=1.15.7 kubernetes-cli kustomize ripgrep openssl python3 -y
# Optional (platform admin):
choco install kubernetes-helm -y
```

### Verify Installation

```bash
command -v aws terraform kubectl kustomize rg openssl python3
terraform version
aws --version
kubectl version --client
python3 --version
```

On Windows PowerShell:

```powershell
Get-Command aws, terraform, kubectl, kustomize, rg, openssl, python
terraform version
aws --version
kubectl version --client
python --version
```

## Configure AWS CLI With SSO

AWS SSO (IAM Identity Center) is your centralized login. You authenticate once in a browser and then CLI tools use temporary credentials instead of long-lived access keys.

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

On Windows PowerShell:

```powershell
aws configure list-profiles
Get-Content "$env:USERPROFILE\.aws\config"
```

## Configure Kubernetes Access

### Update Kubeconfig

```bash
aws eks update-kubeconfig \
  --name EKS-boomi-runtime-cluster \
  --region ap-east-1 \
  --profile "$AWS_PROFILE"
```

On Windows PowerShell:

```powershell
aws eks update-kubeconfig `
  --name EKS-boomi-runtime-cluster `
  --region ap-east-1 `
  --profile $env:AWS_PROFILE
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
