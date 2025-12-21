# Dev Utils

This directory contains utility scripts for AWS infrastructure management and development setup.

## Dev Utilities

A comprehensive collection of shell functions that wrap common AWS CLI commands, making them easier to remember and use. Available for both Ubuntu and macOS platforms.

### Platform-Specific Scripts

- **`dev.ubuntu.sh`** - For Ubuntu Linux systems
- **`dev.macos.sh`** - For macOS systems

### Quick Start

Load the utilities directly from GitHub:

**For Ubuntu:**
```bash
# Method 1: Using source
source <(curl -sSL https://raw.githubusercontent.com/hanyouqing/devops-utils/main/dev.ubuntu.sh)

# Method 2: Using pipe
curl -sSL https://raw.githubusercontent.com/hanyouqing/devops-utils/main/dev.ubuntu.sh | source /dev/stdin
```

**For macOS:**
```bash
# Method 1: Using source
source <(curl -sSL https://raw.githubusercontent.com/hanyouqing/devops-utils/main/dev.macos.sh)

# Method 2: Using pipe
curl -sSL https://raw.githubusercontent.com/hanyouqing/devops-utils/main/dev.macos.sh | source /dev/stdin
```

Or load locally:

```bash
# Ubuntu
source dev.ubuntu.sh

# macOS
source dev.macos.sh
```

After loading, type `aws-help` to see all available commands.

### Default Values

- **Default Region**: `ap-southeast-1` (can be overridden with `AWS_DEFAULT_REGION` environment variable)
- **Default Cluster**: `my-cluster` (can be overridden with `AWS_EKS_CLUSTER` environment variable)

### EKS Functions

#### `eks-update-config [-c|--cluster CLUSTER] [-r|--region REGION]`

Update kubeconfig for an EKS cluster.

```bash
# Use defaults (my-cluster, ap-southeast-1)
eks-update-config

# Specify cluster and region using options
eks-update-config -c my-cluster -r ap-southeast-1
eks-update-config --cluster my-cluster --region ap-southeast-1

# Or use positional arguments
eks-update-config my-cluster ap-southeast-1

# Show AWS CLI command without executing
eks-update-config -c my-cluster --show
```

#### `eks-list-addons [-c|--cluster CLUSTER] [-r|--region REGION]`

List all addons installed in an EKS cluster.

```bash
# Use defaults
eks-list-addons

# Specify cluster and region
eks-list-addons -c my-cluster -r ap-southeast-1
eks-list-addons --cluster my-cluster --region ap-southeast-1

# Show AWS CLI command without executing
eks-list-addons -c my-cluster --show
```

#### `eks-automode-status [cluster-name] [region]`

Check if EKS cluster has auto mode enabled.

```bash
eks-automode-status
eks-automode-status my-cluster ap-southeast-1
```

#### `eks-automode-enabled [cluster-name] [region]`

Enable EKS auto mode for a cluster.

```bash
eks-automode-enabled
eks-automode-enabled my-cluster ap-southeast-1
```

#### `eks-automode-disabled [cluster-name] [region]`

Disable EKS auto mode for a cluster (destructive operation).

```bash
eks-automode-disabled
eks-automode-disabled my-cluster ap-southeast-1
```

#### `eks-describe [cluster-name] [region]`

Get detailed information about an EKS cluster.

```bash
eks-describe
eks-describe my-cluster ap-southeast-1
```

#### `eks-list [region]`

List all EKS clusters in a region.

```bash
eks-list
eks-list ap-southeast-1
```

#### `eks-list-nodegroups [cluster-name] [region]`

List all node groups for an EKS cluster.

```bash
eks-list-nodegroups
eks-list-nodegroups my-cluster ap-southeast-1
```

### ECR Functions

#### `ecr-list [region]`

List all ECR repositories and their URIs.

```bash
ecr-list
ecr-list ap-southeast-1
```

#### `ecr-list-images [-n|--name REPO] [-r|--region REGION]`

List all images in a specific ECR repository.

```bash
# Using options
ecr-list-images -n my-app
ecr-list-images --name my-app --region ap-southeast-1

# Using positional arguments
ecr-list-images my-app
ecr-list-images my-app ap-southeast-1

# Show AWS CLI command without executing
ecr-list-images -n my-app --show
```

#### `ecr-login [region]`

Login to ECR using Docker.

```bash
ecr-login
ecr-login ap-southeast-1
```

### EC2 Functions

#### `ec2-userdata [-i|--instance-id ID] [-r|--region REGION]`

Get user data script for an EC2 instance.

```bash
# Using options
ec2-userdata -i i-1234567890abcdef0
ec2-userdata --instance-id i-1234567890abcdef0 --region ap-southeast-1

# Using positional arguments
ec2-userdata i-1234567890abcdef0
ec2-userdata i-1234567890abcdef0 ap-southeast-1

# Show AWS CLI command without executing
ec2-userdata -i i-1234567890abcdef0 --show
```

#### `ec2-describe [-i|--instance-id ID] [-r|--region REGION]`

Get detailed information about an EC2 instance.

```bash
# Using options
ec2-describe -i i-1234567890abcdef0
ec2-describe --instance-id i-1234567890abcdef0 --region ap-southeast-1

# Using positional arguments
ec2-describe i-1234567890abcdef0
ec2-describe i-1234567890abcdef0 ap-southeast-1

# Show AWS CLI command without executing
ec2-describe -i i-1234567890abcdef0 --show
```

#### `ec2-console-output [-i|--instance-id ID] [-r|--region REGION]`

Get console output (logs) for an EC2 instance.

```bash
# Using options
ec2-console-output -i i-1234567890abcdef0
ec2-console-output --instance-id i-1234567890abcdef0 --region ap-southeast-1

# Using positional arguments
ec2-console-output i-1234567890abcdef0
ec2-console-output i-1234567890abcdef0 ap-southeast-1

# Show AWS CLI command without executing
ec2-console-output -i i-1234567890abcdef0 --show
```

#### `ec2-list [-r|--region REGION] [--filters FILTERS...]`

List EC2 instances with basic information.

```bash
# List all instances
ec2-list

# List instances in specific region
ec2-list -r ap-southeast-1
ec2-list --region ap-southeast-1

# List instances with filters
ec2-list -r ap-southeast-1 --filters "Name=instance-state-name,Values=running"
ec2-list --region ap-southeast-1 --filters "Name=tag:Environment,Values=prod"

# Show AWS CLI command without executing
ec2-list -r ap-southeast-1 --show
```

#### `ec2-logs [-i|--instance-id ID] [-g|--log-group GROUP] [-r|--region REGION] [-f|--follow]`

Get CloudWatch logs for an EC2 instance (if configured).

```bash
# Using options
ec2-logs -i i-1234567890abcdef0
ec2-logs --instance-id i-1234567890abcdef0 --log-group /aws/ec2/instance --region ap-southeast-1

# Follow log output (like tail -f)
ec2-logs -i i-1234567890abcdef0 -f
ec2-logs --instance-id i-1234567890abcdef0 --follow

# Show AWS CLI command without executing
ec2-logs -i i-1234567890abcdef0 --show
```

### VPC Functions

#### `vpc-list [region]`

List all VPCs in a region.

```bash
vpc-list
vpc-list ap-southeast-1
```

#### `vpc-list-subnets <vpc-id> [region]`

List all subnets in a VPC.

```bash
vpc-list-subnets vpc-1234567890abcdef0
vpc-list-subnets vpc-1234567890abcdef0 ap-southeast-1
```

### RDS Functions

#### `rds-list [region]`

List all RDS instances in a region.

```bash
rds-list
rds-list ap-southeast-1
```

### ECS Functions

#### `ecs-list-clusters [region]`

List all ECS clusters in a region.

```bash
ecs-list-clusters
ecs-list-clusters ap-southeast-1
```

#### `ecs-list-services <cluster-name> [region]`

List all services in an ECS cluster.

```bash
ecs-list-services my-cluster
ecs-list-services my-cluster ap-southeast-1
```

#### `ecs-describe-service <cluster-name> <service-name> [region]`

Get detailed information about an ECS service.

```bash
ecs-describe-service my-cluster my-service
ecs-describe-service my-cluster my-service ap-southeast-1
```

#### `ecs-list-tasks <cluster-name> [service-name] [region]`

List all tasks in an ECS cluster or service.

```bash
ecs-list-tasks my-cluster
ecs-list-tasks my-cluster my-service ap-southeast-1
```

#### `ecs-update-service <cluster-name> <service-name> [region] [--force-new-deployment]`

Update an ECS service (e.g., force new deployment).

```bash
ecs-update-service my-cluster my-service
ecs-update-service my-cluster my-service ap-southeast-1 --force-new-deployment
```

### App Runner Functions

#### `apprunner-list-services [region]`

List all App Runner services in a region.

```bash
apprunner-list-services
apprunner-list-services ap-southeast-1
```

#### `apprunner-describe-service <service-name-or-arn> [region]`

Get detailed information about an App Runner service.

```bash
apprunner-describe-service my-service
apprunner-describe-service arn:aws:apprunner:... ap-southeast-1
```

#### `apprunner-pause-service <service-name-or-arn> [region]`

Pause an App Runner service.

```bash
apprunner-pause-service my-service
apprunner-pause-service my-service ap-southeast-1
```

#### `apprunner-resume-service <service-name-or-arn> [region]`

Resume a paused App Runner service.

```bash
apprunner-resume-service my-service
apprunner-resume-service my-service ap-southeast-1
```

### Other Functions

#### `aws-whoami`

Show current AWS identity (account, user/role, ARN).

```bash
aws-whoami
```

#### `s3-list`

List all S3 buckets.

```bash
s3-list
```

#### `aws-help`

Display help message with all available functions.

```bash
aws-help
```

#### `install-k8s-tools [--plugins]`

Install all Kubernetes tools (kubectl, krew, helm, kustomize) and optionally kubectl plugins.

```bash
# Install all tools
install-k8s-tools

# Install tools + plugins (ns, ctx, history, images)
install-k8s-tools --plugins
```

### Usage Examples

```bash
# Load the utilities (Ubuntu)
source <(curl -sSL https://raw.githubusercontent.com/hanyouqing/devops-utils/main/dev.ubuntu.sh)

# Or for macOS
source <(curl -sSL https://raw.githubusercontent.com/hanyouqing/devops-utils/main/dev.macos.sh)

# Set custom defaults
export AWS_DEFAULT_REGION=us-east-1
export AWS_EKS_CLUSTER=my-cluster

# Tools will be auto-installed on first load
# kubectl, krew, helm, kustomize, tfenv, packer, fzf

# Use kubectl alias 'k' (auto-configured)
k get pods
k get nodes

# Update kubeconfig
eks-update-config

# Check cluster status
eks-automode-status
eks-list-addons

# List ECR repositories
ecr-list

# Get EC2 instance user data
ec2-userdata i-1234567890abcdef0

# View EC2 console logs
ec2-console-output i-1234567890abcdef0

# List all VPCs
vpc-list

# ECS operations
ecs-list-clusters
ecs-list-services my-cluster
ecs-update-service my-cluster my-service --force-new-deployment

# App Runner operations
apprunner-list-services
apprunner-describe-service my-service

# Install all Kubernetes tools manually (if needed)
install-k8s-tools
install-k8s-tools --plugins  # Also install kubectl plugins

# Show help
aws-help
```

### Auto-Installation Features

The scripts automatically install and configure development tools:

**Kubernetes Tools** (auto-install enabled by default):
- `kubectl` - Kubernetes command-line tool
- `krew` - kubectl plugin manager
- `helm` - Kubernetes package manager
- `kustomize` - Kubernetes configuration customization
- kubectl plugins: `ns`, `ctx`, `history`, `images`

**Infrastructure Tools** (auto-install enabled by default):
- `tfenv` - Terraform version manager
- `packer` - Machine image builder
- `fzf` - Fuzzy finder for command history and file search

**Convenience Features**:
- `k` alias for `kubectl` with autocompletion
- fzf key bindings (Ctrl+R for history, Ctrl+T for file search, Alt+C for directory navigation)

**Disable auto-installation** (if needed):
```bash
export KUBECTL_AUTO_INSTALL=false
export KREW_AUTO_INSTALL=false
export HELM_AUTO_INSTALL=false
export KUSTOMIZE_AUTO_INSTALL=false
export TFENV_AUTO_INSTALL=false
export PACKER_AUTO_INSTALL=false
export FZF_AUTO_INSTALL=false
export KUBECTL_ALIAS_AUTO_SETUP=false
```

### Requirements

- AWS CLI (auto-installed if missing)
- `jq` (optional, for JSON formatting)
- Bash or Zsh shell
- Ubuntu 18.04+ or macOS 10.14+

### Features

- **Color-coded output**: Functions use colors for better readability
- **Error handling**: Functions validate inputs and provide helpful error messages
- **Flexible parameters**: Region and cluster names are optional with sensible defaults
- **Environment variable support**: Override defaults using `AWS_DEFAULT_REGION` and `AWS_EKS_CLUSTER`
- **Auto-installation**: Automatically installs missing tools (can be disabled)
- **Platform-specific**: Optimized installation methods for Ubuntu (apt-get) and macOS (Homebrew)
- **Shell compatibility**: Supports both bash and zsh (macOS)

## Other Scripts

### Setup Scripts

- `setup-aws.sh` - AWS authentication and configuration setup
- `setup-aws-sso.sh` - AWS SSO setup
- `setup-cloudshell.sh` - AWS CloudShell setup

### Development Scripts

- **`dev.ubuntu.sh`** - Main development utilities for Ubuntu (AWS CLI, Kubernetes tools, Terraform, Packer, fzf)
- **`dev.macos.sh`** - Main development utilities for macOS (AWS CLI, Kubernetes tools, Terraform, Packer, fzf)
- `dev.ubuntu-24.04.sh` - Development environment setup for Ubuntu 24.04
- `dev.ubuntu-24.04.userdata.sh` - User data script for development instances
- `userdata.ubuntu-24.04.sh` - Ubuntu 24.04 user data script
- `userdata.ubuntu-24.04.minimal.sh` - Minimal Ubuntu 24.04 user data script

### Infrastructure Scripts

- `push-to-ecr.sh` - Build and push Docker images to ECR
- `kubectl.ubuntu-24.04.sh` - kubectl installation script
- `hashicorp.ubuntu-24.04.sh` - HashiCorp tools installation script

### Utility Scripts

- `format-ip-cidr.sh` - IP CIDR formatting utility
- `diagnose-config.sh` - Diagnostic tool for container config file issues
- `container-config-troubleshooting.md` - Troubleshooting guide for container config file problems
- `check-binary-dependency.sh` - Dynamic binary dependency checker for containers
- `fix-binary-check.sh` - Fix hardcoded binary paths in startup scripts
- `binary-dependency-fix.md` - Guide for fixing binary dependency check issues
- `check-gitlab-ci.sh` - GitLab CI configuration checker for image/binary name mismatches
- `gitlab-ci-analysis.md` - Analysis guide for GitLab CI configuration issues
- `lightsail-ipsec-deploy.sh` - Lightsail IPSec deployment
- `lightsail-proxy-deploy.sh` - Lightsail proxy deployment

## Contributing

When adding new scripts:

1. Make scripts executable: `chmod +x script-name.sh`
2. Add shebang: `#!/usr/bin/env bash` or `#!/bin/bash`
3. Include usage instructions in script comments
4. Update this README with script description and usage examples
5. Follow shell scripting best practices (error handling, input validation)

## License

See [LICENSE](../LICENSE) file in the project root.

