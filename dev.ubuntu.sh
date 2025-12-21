#!/usr/bin/env bash
#
# AWS Utilities for Ubuntu - Common AWS CLI commands wrapped as shell functions
# Usage: curl -sSL https://raw.githubusercontent.com/hanyouqing/devops-utils/main/dev.ubuntu.sh | source /dev/stdin
# Or: source <(curl -sSL https://raw.githubusercontent.com/hanyouqing/devops-utils/main/dev.ubuntu.sh)
#
# Default region: ap-southeast-1
# Default cluster: my-cluster (override with AWS_EKS_CLUSTER environment variable)
# Platform: Ubuntu only

# Color output helpers
_red() { echo -e "\033[0;31m$*\033[0m"; }
_green() { echo -e "\033[0;32m$*\033[0m"; }
_yellow() { echo -e "\033[0;33m$*\033[0m"; }
_blue() { echo -e "\033[0;34m$*\033[0m"; }

# ==============================================================================
# Dependency Checks
# ==============================================================================

# Check if AWS CLI is installed
_check_aws_cli() {
  if ! command -v aws &> /dev/null; then
    _red "Error: AWS CLI is not installed"
    
    # Attempt automatic installation if enabled
    local auto_install="${AWS_AUTO_INSTALL_CLI:-true}"
    if [[ "$auto_install" == "true" ]]; then
      echo ""
      _blue "Attempting to install AWS CLI automatically..."
      if _install_aws_cli; then
        # Verify installation succeeded
        if command -v aws &> /dev/null; then
          local aws_version=$(aws --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
          if [[ -n "$aws_version" ]]; then
            _green "✓ AWS CLI version: $aws_version"
          fi
          return 0
        else
          return 1
        fi
      fi
      echo ""
    fi
    
    echo "Please install AWS CLI: https://aws.amazon.com/cli/"
    _yellow "To disable auto-installation, set: export AWS_AUTO_INSTALL_CLI=false"
    return 1
  fi
  
  # Check AWS CLI version (should be v2 for better compatibility)
  local aws_version=$(aws --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  if [[ -n "$aws_version" ]]; then
    _green "✓ AWS CLI version: $aws_version"
  fi
}

# Check if AWS credentials are configured
_check_aws_credentials() {
  local identity_output
  identity_output=$(aws sts get-caller-identity 2>&1)
  local aws_exit_code=$?
  
  if [[ $aws_exit_code -ne 0 ]]; then
    _yellow "Warning: AWS credentials not configured or invalid"
    echo "Please configure AWS credentials using one of the following methods:"
    echo "  1. Run: aws configure"
    echo "  2. Set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    echo "  3. Use AWS SSO: aws sso login"
    echo "  4. Use IAM roles (if running on EC2/ECS/Lambda)"
    return 1
  else
    local account
    local arn
    account=$(echo "$identity_output" | grep -oE '"Account": "[0-9]+"' | cut -d'"' -f4 2>/dev/null)
    arn=$(echo "$identity_output" | grep -oE '"Arn": "[^"]+"' | cut -d'"' -f4 2>/dev/null)
    if [[ -n "$account" ]]; then
      _green "✓ AWS credentials configured (Account: $account)"
      if [[ -n "$arn" ]]; then
        _blue "  Identity: $arn"
      fi
    else
      _green "✓ AWS credentials configured"
    fi
  fi
}

# Check if jq is installed (optional but recommended)
_check_jq() {
  if ! command -v jq &> /dev/null; then
    _yellow "Warning: jq is not installed (optional but recommended)"
    echo "  Most functions use AWS CLI --query parameter, but some formatting functions require jq"
    echo "  Functions that require jq: ec2-list, vpc-list, vpc-list-subnets, rds-list"
    echo "  Install jq: https://stedolan.github.io/jq/download/"
    return 1
  else
    _green "✓ jq is installed"
  fi
}

# Get shell profile file path
_get_shell_profile() {
  if [[ -n "${ZSH_VERSION:-}" ]]; then
    echo "$HOME/.zshrc"
  elif [[ -n "${BASH_VERSION:-}" ]]; then
    if [[ -f "$HOME/.bash_profile" ]]; then
      echo "$HOME/.bash_profile"
    else
      echo "$HOME/.bashrc"
    fi
  else
    echo "$HOME/.bashrc"
  fi
}

# Check if docker is installed (required for ecr-login)
_check_docker() {
  if ! command -v docker &> /dev/null; then
    _yellow "Warning: docker is not installed"
    echo "  The 'ecr-login' function requires docker"
    echo "  Install docker: https://docs.docker.com/get-docker/"
    return 1
  else
    _green "✓ docker is installed"
  fi
}

# Check if running in interactive terminal
_is_interactive() {
  [[ -t 1 ]] && [[ "${PS1:-}" != "" ]]
}

# Detect if running on Ubuntu
_detect_ubuntu() {
  if [[ -f /etc/os-release ]]; then
    if grep -qi "ubuntu" /etc/os-release; then
      return 0
    fi
  fi
  return 1
}

# Check if running on Ubuntu
_check_ubuntu() {
  if ! _detect_ubuntu; then
    _red "Error: This script only supports Ubuntu"
    _yellow "Detected OS: $(cat /etc/os-release 2>/dev/null | grep "^NAME=" | cut -d'"' -f2 || echo "unknown")"
    return 1
  fi
  return 0
}

# Install AWS CLI (Ubuntu only)
_install_aws_cli() {
  if ! _check_ubuntu; then
    return 1
  fi
  
  local install_success=false
  _blue "Installing AWS CLI on Ubuntu using official method..."
  # Reference: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
  
  # Check for required tools
  if ! command -v curl &> /dev/null; then
    _blue "curl not found, installing..."
    sudo apt-get update -qq && sudo apt-get install -y curl 2>&1 || return 1
  fi
  
  if ! command -v unzip &> /dev/null; then
    _blue "unzip not found, installing..."
    sudo apt-get update -qq && sudo apt-get install -y unzip 2>&1 || return 1
  fi
  
  # Use official AWS CLI installation method
  local zip_file="/tmp/awscliv2.zip"
  local extract_dir="/tmp"
  
  # Download AWS CLI v2 for Linux based on architecture
  local arch=$(uname -m)
  local url=""
  if [[ "$arch" == "x86_64" ]]; then
    url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
  elif [[ "$arch" == "aarch64" ]] || [[ "$arch" == "arm64" ]]; then
    url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
  else
    _yellow "Unsupported architecture: $arch"
    return 1
  fi
  
  _blue "Downloading AWS CLI v2 from $url..."
  if curl -sSL "$url" -o "$zip_file"; then
    _blue "Extracting AWS CLI installer..."
    if unzip -q "$zip_file" -d "$extract_dir" 2>/dev/null; then
      _blue "Installing AWS CLI using official installer (this may require sudo password)..."
      local install_output
      install_output=$(cd "$extract_dir" && sudo ./aws/install 2>&1)
      local install_exit_code=$?
      if [[ $install_exit_code -eq 0 ]]; then
        install_success=true
        _green "AWS CLI installed successfully using official method"
      else
        _yellow "Installation failed:"
        echo "$install_output" | tail -10
      fi
      rm -rf "$extract_dir/aws" "$zip_file"
    else
      _yellow "Failed to extract AWS CLI archive"
      rm -f "$zip_file"
    fi
  else
    _yellow "Failed to download AWS CLI"
  fi
  
  if [[ "$install_success" == "true" ]]; then
    # Verify installation - official installer creates symlink at /usr/local/bin/aws
    # Reference: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
    local aws_cmd=""
    
    # Check if aws command is available (should be in PATH after official installation)
    if command -v aws &> /dev/null; then
      aws_cmd="aws"
    # Check official installation paths
    elif [[ -f "/usr/local/bin/aws" ]]; then
      aws_cmd="/usr/local/bin/aws"
      # /usr/local/bin should already be in PATH, but ensure it's there
      if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
        export PATH="/usr/local/bin:$PATH"
        _blue "Added /usr/local/bin to PATH for this session"
      fi
    # Check for user-local installation (fallback)
    elif [[ -f "$HOME/.local/bin/aws" ]]; then
      aws_cmd="$HOME/.local/bin/aws"
      export PATH="$HOME/.local/bin:$PATH"
    fi
    
    if [[ -n "$aws_cmd" ]]; then
      local aws_version=$($aws_cmd --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      _green "✓ AWS CLI installed successfully (version: $aws_version)"
      _blue "Installation location: /usr/local/aws-cli"
      _blue "Command available at: $aws_cmd"
      return 0
    else
      _yellow "AWS CLI installation completed but 'aws' command not found in PATH"
      _yellow "You may need to restart your terminal or run: export PATH=\"/usr/local/bin:\$PATH\""
      return 1
    fi
  else
    _red "Failed to install AWS CLI automatically"
    _yellow "Please install manually: https://aws.amazon.com/cli/"
    _yellow "Official installation guide: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    return 1
  fi
}

# ==============================================================================
# Kubernetes Tools Installation
# ==============================================================================

# Install kubectl (Ubuntu only)
_install_kubectl() {
  if ! _check_ubuntu; then
    return 1
  fi
  
  local install_success=false
  _blue "Installing kubectl on Ubuntu..."
  
  local arch=$(uname -m)
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) _yellow "Unsupported architecture: $arch"; return 1 ;;
  esac
  
  local kubectl_bin="/usr/local/bin/kubectl"
  local url="https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/${arch}/kubectl"
  
  if curl -LO "$url" && chmod +x kubectl && sudo mv kubectl "$kubectl_bin"; then
    install_success=true
  fi
  
  if [[ "$install_success" == "true" ]] && command -v kubectl &> /dev/null; then
    local version=$(kubectl version --client --short 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    _green "✓ kubectl installed successfully (version: $version)"
    return 0
  else
    _yellow "Failed to install kubectl"
    return 1
  fi
}

# Install krew (kubectl plugin manager) - Ubuntu only
_install_krew() {
  if ! _check_ubuntu; then
    return 1
  fi
  
  local install_success=false
  
  if ! command -v kubectl &> /dev/null; then
    _yellow "kubectl is required for krew installation"
    return 1
  fi
  
  _blue "Installing krew on Ubuntu..."
  
  # Install krew using official method
  # Reference: https://krew.sigs.k8s.io/docs/user-guide/setup/install/
  (
    set -x
    cd "$(mktemp -d)" &&
    OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
    ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
    KREW="krew-${OS}_${ARCH}" &&
    curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
    tar zxvf "${KREW}.tar.gz" &&
    ./"${KREW}" install krew
  ) && install_success=true
  
  if [[ "$install_success" == "true" ]]; then
    # Add krew to PATH for current session
    export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
    
    # Automatically add to shell profile
    local shell_profile=$(_get_shell_profile)
    if ! grep -q "KREW_ROOT.*krew.*bin" "$shell_profile" 2>/dev/null; then
      echo "" >> "$shell_profile"
      echo "# krew (kubectl plugin manager)" >> "$shell_profile"
      echo "export PATH=\"\${KREW_ROOT:-\$HOME/.krew}/bin:\$PATH\"" >> "$shell_profile"
    fi
    
    if command -v kubectl-krew &> /dev/null || kubectl krew version &> /dev/null; then
      _green "✓ krew installed successfully"
      _yellow "Added to shell profile ($shell_profile). Restart your terminal or run: source $shell_profile"
      return 0
    else
      _yellow "krew installation completed but 'kubectl krew' command not found in PATH"
      _yellow "Added to shell profile ($shell_profile). Restart your terminal or run: source $shell_profile"
      return 1
    fi
  else
    _yellow "Failed to install krew"
    return 1
  fi
}

# Install Helm (Ubuntu only)
_install_helm() {
  if ! _check_ubuntu; then
    return 1
  fi
  
  local install_success=false
  _blue "Installing Helm on Ubuntu..."
  
  # Use official installation script
  if curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash 2>&1; then
    install_success=true
  fi
  
  if [[ "$install_success" == "true" ]] && command -v helm &> /dev/null; then
    local version=$(helm version --short 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    _green "✓ Helm installed successfully (version: $version)"
    return 0
  else
    _yellow "Failed to install Helm"
    return 1
  fi
}

# Install Kustomize (Ubuntu only)
_install_kustomize() {
  if ! _check_ubuntu; then
    return 1
  fi
  
  local install_success=false
  _blue "Installing Kustomize on Ubuntu..."
  
  local arch=$(uname -m)
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) _yellow "Unsupported architecture: $arch"; return 1 ;;
  esac
  
  local platform="linux"
  
  # Get latest version
  local version=$(curl -s https://api.github.com/repos/kubernetes-sigs/kustomize/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^kustomize\///')
  if [[ -z "$version" ]]; then
    version="v5.4.1"  # Fallback version
  fi
  
  local kustomize_bin="/usr/local/bin/kustomize"
  local url="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2F${version}/kustomize_${version}_${platform}_${arch}.tar.gz"
  
  local temp_dir=$(mktemp -d)
  if curl -L "$url" -o "$temp_dir/kustomize.tar.gz" && \
     tar -xzf "$temp_dir/kustomize.tar.gz" -C "$temp_dir" && \
     chmod +x "$temp_dir/kustomize" && \
     sudo mv "$temp_dir/kustomize" "$kustomize_bin"; then
    install_success=true
  fi
  rm -rf "$temp_dir"
  
  if [[ "$install_success" == "true" ]] && command -v kustomize &> /dev/null; then
    local installed_version=$(kustomize version --short 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    _green "✓ Kustomize installed successfully (version: $installed_version)"
    return 0
  else
    _yellow "Failed to install Kustomize"
    return 1
  fi
}

# Install kubectl plugins via krew
_install_kubectl_plugins() {
  if ! command -v kubectl &> /dev/null; then
    _yellow "kubectl is required for plugin installation"
    return 1
  fi
  
  # Ensure krew is installed
  if ! command -v kubectl-krew &> /dev/null; then
    _blue "krew not found, installing krew first..."
    _install_krew || return 1
  fi
  
  # Ensure krew is in PATH
  export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
  
  _blue "Installing kubectl plugins..."
  
  # List of plugins to install
  local plugins=(
    "ns"           # Namespace switcher
    "ctx"          # Context switcher
    "history"      # Command history
    "images"       # Show container images
  )
  
  local installed=0
  local failed=0
  
  for plugin in "${plugins[@]}"; do
    if kubectl krew install "$plugin" 2>&1; then
      _green "  ✓ Installed plugin: $plugin"
      installed=$((installed + 1))
    else
      _yellow "  ✗ Failed to install plugin: $plugin"
      failed=$((failed + 1))
    fi
  done
  
  echo ""
  if [[ $installed -gt 0 ]]; then
    _green "✓ Installed $installed kubectl plugin(s)"
    _yellow "Note: Restart your terminal or run: export PATH=\"\${KREW_ROOT:-\$HOME/.krew}/bin:\$PATH\""
  fi
  
  if [[ $failed -gt 0 ]]; then
    _yellow "⚠ Failed to install $failed plugin(s)"
  fi
  
  return 0
}

# Check and install kubectl
_check_kubectl() {
  if ! command -v kubectl &> /dev/null; then
    _yellow "kubectl is not installed"
    local auto_install="${KUBECTL_AUTO_INSTALL:-true}"
    if [[ "$auto_install" == "true" ]]; then
      echo ""
      _blue "Attempting to install kubectl automatically..."
      if _install_kubectl; then
        return 0
      fi
      echo ""
    else
      echo "Install kubectl: https://kubernetes.io/docs/tasks/tools/"
      _yellow "To disable auto-installation, set: export KUBECTL_AUTO_INSTALL=false"
      return 1
    fi
  else
    local version=$(kubectl version --client --short 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    _green "✓ kubectl version: $version"
  fi
}

# Check and install krew
_check_krew() {
  export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"
  if ! command -v kubectl-krew &> /dev/null; then
    _yellow "krew is not installed (optional)"
    local auto_install="${KREW_AUTO_INSTALL:-true}"
    if [[ "$auto_install" == "true" ]]; then
      echo ""
      _blue "Attempting to install krew automatically..."
      if _install_krew; then
        return 0
      fi
      echo ""
    else
      echo "Install krew: https://krew.sigs.k8s.io/"
      _yellow "To disable auto-installation, set: export KREW_AUTO_INSTALL=false"
      return 1
    fi
  else
    _green "✓ krew is installed"
  fi
}

# Check and install Helm
_check_helm() {
  if ! command -v helm &> /dev/null; then
    _yellow "Helm is not installed (optional)"
    local auto_install="${HELM_AUTO_INSTALL:-true}"
    if [[ "$auto_install" == "true" ]]; then
      echo ""
      _blue "Attempting to install Helm automatically..."
      if _install_helm; then
        return 0
      fi
      echo ""
    else
      echo "Install Helm: https://helm.sh/docs/intro/install/"
      _yellow "To disable auto-installation, set: export HELM_AUTO_INSTALL=false"
      return 1
    fi
  else
    local version=$(helm version --short 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    _green "✓ Helm version: $version"
  fi
}

# Check and install Kustomize
_check_kustomize() {
  if ! command -v kustomize &> /dev/null; then
    _yellow "Kustomize is not installed (optional)"
    local auto_install="${KUSTOMIZE_AUTO_INSTALL:-true}"
    if [[ "$auto_install" == "true" ]]; then
      echo ""
      _blue "Attempting to install Kustomize automatically..."
      if _install_kustomize; then
        return 0
      fi
      echo ""
    else
      echo "Install Kustomize: https://kustomize.io/"
      _yellow "To disable auto-installation, set: export KUSTOMIZE_AUTO_INSTALL=false"
      return 1
    fi
  else
    local version=$(kustomize version --short 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    _green "✓ Kustomize version: $version"
  fi
}

# ==============================================================================
# Terraform & Packer Tools Installation
# ==============================================================================

# Install tfenv (Terraform version manager) - Ubuntu only
_install_tfenv() {
  if ! _check_ubuntu; then
    return 1
  fi
  
  local install_success=false
  _blue "Installing tfenv on Ubuntu..."
  
  # Check for git (required for tfenv)
  if ! command -v git &> /dev/null; then
    _blue "git not found, installing..."
    sudo apt-get update -qq && sudo apt-get install -y git 2>&1 || return 1
  fi
  
  # Install tfenv using official method
  # Reference: https://github.com/tfutils/tfenv
  local tfenv_dir="${TFENV_ROOT:-$HOME/.tfenv}"
  
  if [[ -d "$tfenv_dir" ]]; then
    _yellow "tfenv already exists at $tfenv_dir, updating..."
    (cd "$tfenv_dir" && git pull) || return 1
  else
    _blue "Cloning tfenv repository..."
    if git clone https://github.com/tfutils/tfenv.git "$tfenv_dir" 2>&1; then
      install_success=true
    fi
  fi
  
  if [[ "$install_success" == "true" ]] || [[ -d "$tfenv_dir" ]]; then
    # Add tfenv to PATH
    export PATH="$tfenv_dir/bin:$PATH"
    if command -v tfenv &> /dev/null; then
      _green "✓ tfenv installed successfully"
      _yellow "Add to your shell profile: export PATH=\"\${TFENV_ROOT:-\$HOME/.tfenv}/bin:\$PATH\""
      _blue "Install Terraform: tfenv install latest"
      return 0
    else
      _yellow "tfenv installation completed but 'tfenv' command not found in PATH"
      _yellow "Add to your shell profile: export PATH=\"\${TFENV_ROOT:-\$HOME/.tfenv}/bin:\$PATH\""
      return 1
    fi
  else
    _yellow "Failed to install tfenv"
    return 1
  fi
}

# Install Packer - Ubuntu only
_install_packer() {
  if ! _check_ubuntu; then
    return 1
  fi
  
  local install_success=false
  _blue "Installing Packer on Ubuntu..."
  
  # Get latest version
  local version=$(curl -s https://api.github.com/repos/hashicorp/packer/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' | sed 's/^v//')
  if [[ -z "$version" ]]; then
    version="1.10.0"  # Fallback version
  fi
  
  local arch=$(uname -m)
  case "$arch" in
    x86_64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) _yellow "Unsupported architecture: $arch"; return 1 ;;
  esac
  
  local packer_bin="/usr/local/bin/packer"
  local url="https://releases.hashicorp.com/packer/${version}/packer_${version}_linux_${arch}.zip"
  
  local temp_dir=$(mktemp -d)
  if curl -L "$url" -o "$temp_dir/packer.zip" && \
     unzip -q "$temp_dir/packer.zip" -d "$temp_dir" && \
     chmod +x "$temp_dir/packer" && \
     sudo mv "$temp_dir/packer" "$packer_bin"; then
    install_success=true
  fi
  rm -rf "$temp_dir"
  
  if [[ "$install_success" == "true" ]] && command -v packer &> /dev/null; then
    local installed_version=$(packer version 2>&1 | grep -oE 'Packer v[0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    _green "✓ Packer installed successfully (version: $installed_version)"
    return 0
  else
    _yellow "Failed to install Packer"
    return 1
  fi
}

# Setup kubectl alias 'k' with autocompletion
_setup_kubectl_alias() {
  if ! command -v kubectl &> /dev/null; then
    _yellow "kubectl is required for 'k' alias setup"
    return 1
  fi
  
  _blue "Setting up kubectl alias 'k' with autocompletion..."
  
  # Create alias
  if ! grep -q "alias k=kubectl" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# kubectl alias" >> ~/.bashrc
    echo "alias k=kubectl" >> ~/.bashrc
  fi
  
  # Setup bash completion for kubectl
  if ! grep -q "source <(kubectl completion bash)" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# kubectl bash completion" >> ~/.bashrc
    echo "source <(kubectl completion bash)" >> ~/.bashrc
    echo "complete -F __start_kubectl k" >> ~/.bashrc
  fi
  
  # Always setup for current session (even if already in ~/.bashrc)
  alias k=kubectl 2>/dev/null || true
  if command -v kubectl &> /dev/null; then
    # Load kubectl completion for current session if not already loaded
    if ! type __start_kubectl &> /dev/null 2>&1; then
      source <(kubectl completion bash) 2>/dev/null || true
    fi
    # Setup completion for 'k' alias
    complete -F __start_kubectl k 2>/dev/null || true
  fi
  
  # Verify alias is set
  if alias k &> /dev/null; then
    _green "✓ kubectl alias 'k' configured with autocompletion"
    _yellow "Note: Alias is now available in this session. For future sessions, restart your terminal or run: source ~/.bashrc"
  else
    _yellow "⚠ kubectl alias 'k' configured in ~/.bashrc but not available in current session"
    _yellow "Run: source ~/.bashrc or restart your terminal"
  fi
  return 0
}

# Install fzf (fuzzy finder) - Ubuntu only
_install_fzf() {
  if ! _check_ubuntu; then
    return 1
  fi
  
  local install_success=false
  _blue "Installing fzf on Ubuntu..."
  
  # Check for git (required for fzf)
  if ! command -v git &> /dev/null; then
    _blue "git not found, installing..."
    sudo apt-get update -qq && sudo apt-get install -y git 2>&1 || return 1
  fi
  
  # Install fzf using official method
  # Reference: https://github.com/junegunn/fzf
  local fzf_dir="${FZF_ROOT:-$HOME/.fzf}"
  
  if [[ -d "$fzf_dir" ]]; then
    _yellow "fzf already exists at $fzf_dir, updating..."
    (cd "$fzf_dir" && git pull) || return 1
  else
    _blue "Cloning fzf repository..."
    if git clone --depth 1 https://github.com/junegunn/fzf.git "$fzf_dir" 2>&1; then
      install_success=true
    fi
  fi
  
  if [[ "$install_success" == "true" ]] || [[ -d "$fzf_dir" ]]; then
    # Run fzf install script (non-interactive mode)
    _blue "Running fzf install script..."
    if bash "$fzf_dir/install" --bin 2>&1; then
      # Add fzf to PATH
      export PATH="$fzf_dir/bin:$PATH"
      
      # Setup fzf key bindings and completion in ~/.bashrc
      if ! grep -q "source.*fzf.bash" ~/.bashrc 2>/dev/null; then
        echo "" >> ~/.bashrc
        echo "# fzf key bindings and completion" >> ~/.bashrc
        echo "[ -f ~/.fzf.bash ] && source ~/.fzf.bash" >> ~/.bashrc
      fi
      
      # Also source for current session if available
      if [[ -f ~/.fzf.bash ]]; then
        source ~/.fzf.bash 2>/dev/null || true
      fi
      
      if command -v fzf &> /dev/null; then
        local fzf_version=$(fzf --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        _green "✓ fzf installed successfully (version: $fzf_version)"
        _yellow "Add to your shell profile: export PATH=\"\${FZF_ROOT:-\$HOME/.fzf}/bin:\$PATH\""
        _blue "Key bindings: Ctrl+R (history), Ctrl+T (file search), Alt+C (cd)"
        return 0
      else
        _yellow "fzf installation completed but 'fzf' command not found in PATH"
        _yellow "Add to your shell profile: export PATH=\"\${FZF_ROOT:-\$HOME/.fzf}/bin:\$PATH\""
        return 1
      fi
    else
      _yellow "fzf install script failed, but repository cloned"
      return 1
    fi
  else
    _yellow "Failed to install fzf"
    return 1
  fi
}

# Setup fzf configuration
_setup_fzf_config() {
  if ! command -v fzf &> /dev/null; then
    return 1
  fi
  
  _blue "Setting up fzf configuration..."
  
  # Create fzf config directory if it doesn't exist
  mkdir -p ~/.config/fzf 2>/dev/null || true
  
  # Setup useful fzf aliases and functions
  if ! grep -q "# fzf aliases and functions" ~/.bashrc 2>/dev/null; then
    echo "" >> ~/.bashrc
    echo "# fzf aliases and functions" >> ~/.bashrc
    echo "export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'" >> ~/.bashrc
    echo "export FZF_CTRL_T_OPTS=\"--preview 'bat --color=always --style=header,grid --line-range :300 {}'\"" >> ~/.bashrc
    echo "alias fzfv='fzf --preview \"bat --color=always --style=header,grid --line-range :300 {}\"'" >> ~/.bashrc
    echo "alias fzfg='fzf --preview \"git diff {}\"'" >> ~/.bashrc
  fi
  
  # Export for current session
  export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=header,grid --line-range :300 {}'"
  alias fzfv='fzf --preview "bat --color=always --style=header,grid --line-range :300 {}"' 2>/dev/null || true
  alias fzfg='fzf --preview "git diff {}"' 2>/dev/null || true
  
  _green "✓ fzf configuration completed"
  return 0
}

# Check and install tfenv
_check_tfenv() {
  export PATH="${TFENV_ROOT:-$HOME/.tfenv}/bin:$PATH"
  if ! command -v tfenv &> /dev/null; then
    _yellow "tfenv is not installed (optional)"
    local auto_install="${TFENV_AUTO_INSTALL:-true}"
    if [[ "$auto_install" == "true" ]]; then
      echo ""
      _blue "Attempting to install tfenv automatically..."
      if _install_tfenv; then
        return 0
      fi
      echo ""
    else
      echo "Install tfenv: https://github.com/tfutils/tfenv"
      _yellow "To disable auto-installation, set: export TFENV_AUTO_INSTALL=false"
      return 1
    fi
  else
    _green "✓ tfenv is installed"
  fi
}

# Check and install Packer
_check_packer() {
  if ! command -v packer &> /dev/null; then
    _yellow "Packer is not installed (optional)"
    local auto_install="${PACKER_AUTO_INSTALL:-true}"
    if [[ "$auto_install" == "true" ]]; then
      echo ""
      _blue "Attempting to install Packer automatically..."
      if _install_packer; then
        return 0
      fi
      echo ""
    else
      echo "Install Packer: https://www.packer.io/downloads"
      _yellow "To disable auto-installation, set: export PACKER_AUTO_INSTALL=false"
      return 1
    fi
  else
    local version=$(packer version 2>&1 | grep -oE 'Packer v[0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    _green "✓ Packer version: $version"
  fi
}

# Check and install fzf
_check_fzf() {
  export PATH="${FZF_ROOT:-$HOME/.fzf}/bin:$PATH"
  if ! command -v fzf &> /dev/null; then
    _yellow "fzf is not installed (optional)"
    local auto_install="${FZF_AUTO_INSTALL:-true}"
    if [[ "$auto_install" == "true" ]]; then
      echo ""
      _blue "Attempting to install fzf automatically..."
      if _install_fzf; then
        # Setup fzf configuration after installation
        _setup_fzf_config || true
        return 0
      fi
      echo ""
    else
      echo "Install fzf: https://github.com/junegunn/fzf"
      _yellow "To disable auto-installation, set: export FZF_AUTO_INSTALL=false"
      return 1
    fi
  else
    local fzf_version=$(fzf --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    _green "✓ fzf version: $fzf_version"
    # Ensure configuration is set up
    _setup_fzf_config || true
  fi
}

# Setup kubectl alias and autocompletion
_check_kubectl_alias() {
  if command -v kubectl &> /dev/null; then
    local auto_setup="${KUBECTL_ALIAS_AUTO_SETUP:-true}"
    if [[ "$auto_setup" == "true" ]]; then
      # Always ensure alias is set up in ~/.bashrc for future sessions
      if ! grep -q "alias k=kubectl" ~/.bashrc 2>/dev/null; then
        _setup_kubectl_alias || true
      else
        # Even if alias exists in ~/.bashrc, ensure it's set in current session
        alias k=kubectl 2>/dev/null || true
        if command -v kubectl &> /dev/null; then
          # Load kubectl completion for current session if not already loaded
          if ! type __start_kubectl &> /dev/null 2>&1; then
            source <(kubectl completion bash) 2>/dev/null || true
          fi
          # Setup completion for 'k' alias
          complete -F __start_kubectl k 2>/dev/null || true
        fi
        # Verify alias is set
        if alias k &> /dev/null; then
          _green "✓ kubectl alias 'k' is available in current session"
        else
          _yellow "⚠ kubectl alias 'k' found in ~/.bashrc but failed to set in current session"
          _yellow "Run: source ~/.bashrc or restart your terminal"
        fi
      fi
    fi
  fi
}

# Install all Kubernetes tools
install-k8s-tools() {
  local tools=("kubectl" "krew" "helm" "kustomize")
  local install_plugins=false
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plugins|-p)
        install_plugins=true
        shift
        ;;
      --help|-h)
        echo "Usage: install-k8s-tools [--plugins]"
        echo ""
        echo "Install Kubernetes tools: kubectl, krew, helm, kustomize"
        echo ""
        echo "Options:"
        echo "  --plugins, -p    Also install kubectl plugins (ns, ctx, history, images)"
        echo "  --help, -h       Show this help message"
        return 0
        ;;
      *)
        _red "Unknown option: $1"
        return 1
        ;;
    esac
  done
  
  _blue "Installing Kubernetes tools..."
  echo ""
  
  _install_kubectl || _yellow "Failed to install kubectl"
  echo ""
  
  _install_krew || _yellow "Failed to install krew"
  echo ""
  
  _install_helm || _yellow "Failed to install Helm"
  echo ""
  
  _install_kustomize || _yellow "Failed to install Kustomize"
  echo ""
  
  if [[ "$install_plugins" == "true" ]]; then
    _install_kubectl_plugins
  fi
  
  # Setup kubectl alias
  _setup_kubectl_alias || true
  
  echo ""
  _green "✓ Kubernetes tools installation complete"
  _yellow "Note: You may need to restart your terminal or reload your shell profile"
}

# Run all dependency checks
_check_dependencies() {
  local errors=0
  local quiet="${1:-false}"
  
  if [[ "$quiet" != "true" ]] && _is_interactive; then
    _blue "Checking dependencies..."
    echo ""
  fi
  
  if ! _check_aws_cli; then
    errors=$((errors + 1))
  fi
  
  if ! _check_aws_credentials; then
    errors=$((errors + 1))
  fi
  
  if [[ "$quiet" != "true" ]]; then
    _check_jq || true  # jq is optional, don't count as error
    _check_docker || true  # docker is optional, don't count as error
    _check_kubectl || true  # kubectl is optional, don't count as error
    _check_krew || true  # krew is optional, don't count as error
    _check_helm || true  # helm is optional, don't count as error
    _check_kustomize || true  # kustomize is optional, don't count as error
    _check_tfenv || true  # tfenv is optional, don't count as error
    _check_packer || true  # packer is optional, don't count as error
    _check_fzf || true  # fzf is optional, don't count as error
    _check_kubectl_alias || true  # kubectl alias setup is optional
  fi
  
  if [[ "$quiet" != "true" ]] && _is_interactive; then
    echo ""
  fi
  
  if [[ $errors -gt 0 ]]; then
    if [[ "$quiet" != "true" ]]; then
      _red "Some required dependencies are missing. Please fix the errors above."
    fi
    return 1
  else
    if [[ "$quiet" != "true" ]] && _is_interactive; then
      _green "✓ All required dependencies are available"
    fi
    return 0
  fi
}

# Check Ubuntu before proceeding
# Only check if script is being sourced, not executed directly
# This prevents errors when .bashrc is executed directly (bash ~/.bashrc)
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  if ! _check_ubuntu; then
    _red "This script only supports Ubuntu. Exiting."
    return 1 2>/dev/null || true
  fi
  
  # Perform dependency checks when script is sourced
  # Skip checks if SKIP_AWS_CHECKS environment variable is set
  # Use quiet mode if AWS_QUIET_CHECKS is set (for non-interactive environments)
  if [[ "${SKIP_AWS_CHECKS:-}" != "true" ]]; then
    quiet_mode="${AWS_QUIET_CHECKS:-false}"
    _check_dependencies "$quiet_mode" || {
      if _is_interactive; then
        _yellow "Note: You can skip dependency checks by setting: export SKIP_AWS_CHECKS=true"
      fi
    }
  fi
fi

# Default values
_DEFAULT_REGION="${AWS_DEFAULT_REGION:-ap-southeast-1}"
_DEFAULT_CLUSTER="${AWS_EKS_CLUSTER:-my-cluster}"

# ==============================================================================
# Documentation Helper
# ==============================================================================

# Get AWS CLI documentation URL for a service and command
# Usage: _get_docs_url <service> <command>
_get_docs_url() {
  local service="$1"
  local command="$2"
  echo "https://docs.aws.amazon.com/cli/latest/reference/${service}/${command}.html"
}

# AWS CLI documentation URLs
_DOCS_BASE="https://docs.aws.amazon.com/cli/latest/reference"
_DOCS_EKS_UPDATE_KUBECONFIG="${_DOCS_BASE}/eks/update-kubeconfig.html"
_DOCS_EKS_LIST_ADDONS="${_DOCS_BASE}/eks/list-addons.html"
_DOCS_EKS_DESCRIBE_CLUSTER="${_DOCS_BASE}/eks/describe-cluster.html"
_DOCS_EKS_LIST_CLUSTERS="${_DOCS_BASE}/eks/list-clusters.html"
_DOCS_EKS_LIST_NODEGROUPS="${_DOCS_BASE}/eks/list-nodegroups.html"
_DOCS_EKS_UPDATE_CLUSTER_CONFIG="${_DOCS_BASE}/eks/update-cluster-config.html"
_DOCS_ECR_DESCRIBE_REPOSITORIES="${_DOCS_BASE}/ecr/describe-repositories.html"
_DOCS_ECR_LIST_IMAGES="${_DOCS_BASE}/ecr/list-images.html"
_DOCS_ECR_GET_LOGIN_PASSWORD="${_DOCS_BASE}/ecr/get-login-password.html"
_DOCS_EC2_DESCRIBE_INSTANCE_ATTRIBUTE="${_DOCS_BASE}/ec2/describe-instance-attribute.html"
_DOCS_EC2_DESCRIBE_INSTANCES="${_DOCS_BASE}/ec2/describe-instances.html"
_DOCS_EC2_GET_CONSOLE_OUTPUT="${_DOCS_BASE}/ec2/get-console-output.html"
_DOCS_LOGS_TAIL="${_DOCS_BASE}/logs/tail.html"
_DOCS_EC2_DESCRIBE_VPCS="${_DOCS_BASE}/ec2/describe-vpcs.html"
_DOCS_EC2_DESCRIBE_SUBNETS="${_DOCS_BASE}/ec2/describe-subnets.html"
_DOCS_RDS_DESCRIBE_DB_INSTANCES="${_DOCS_BASE}/rds/describe-db-instances.html"
_DOCS_ECS_LIST_CLUSTERS="${_DOCS_BASE}/ecs/list-clusters.html"
_DOCS_ECS_LIST_SERVICES="${_DOCS_BASE}/ecs/list-services.html"
_DOCS_ECS_DESCRIBE_SERVICES="${_DOCS_BASE}/ecs/describe-services.html"
_DOCS_ECS_LIST_TASKS="${_DOCS_BASE}/ecs/list-tasks.html"
_DOCS_ECS_DESCRIBE_TASKS="${_DOCS_BASE}/ecs/describe-tasks.html"
_DOCS_ECS_UPDATE_SERVICE="${_DOCS_BASE}/ecs/update-service.html"
_DOCS_ECS_STOP_TASK="${_DOCS_BASE}/ecs/stop-task.html"
_DOCS_ECS_RUN_TASK="${_DOCS_BASE}/ecs/run-task.html"
_DOCS_APPRUNNER_LIST_SERVICES="${_DOCS_BASE}/apprunner/list-services.html"
_DOCS_APPRUNNER_DESCRIBE_SERVICE="${_DOCS_BASE}/apprunner/describe-service.html"
_DOCS_APPRUNNER_LIST_OPERATIONS="${_DOCS_BASE}/apprunner/list-operations.html"
_DOCS_APPRUNNER_PAUSE_SERVICE="${_DOCS_BASE}/apprunner/pause-service.html"
_DOCS_APPRUNNER_RESUME_SERVICE="${_DOCS_BASE}/apprunner/resume-service.html"
_DOCS_STS_GET_CALLER_IDENTITY="${_DOCS_BASE}/sts/get-caller-identity.html"
_DOCS_S3_LS="${_DOCS_BASE}/s3/ls.html"

# ==============================================================================
# Argument Parsing Helper
# ==============================================================================

# Show AWS CLI command and exit
# Usage: _show_aws_cmd "aws service command" [args...]
_show_aws_cmd() {
  local cmd="$*"
  _green "AWS CLI Command:"
  echo "  $cmd"
  echo ""
  _blue "You can copy and run this command directly, or share it with your colleagues."
  return 0
}

# Parse common options (region, cluster, etc.)
# Usage: _parse_common_opts "$@" - sets _OPT_REGION, _OPT_CLUSTER, etc.
# Supports: -r/--region, -c/--cluster, -h/--help, --show
_parse_common_opts() {
  _OPT_REGION="${_DEFAULT_REGION}"
  _OPT_CLUSTER="${_DEFAULT_CLUSTER}"
  _OPT_HELP=false
  _OPT_SHOW=false
  _OPT_POSITIONAL=()
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--region)
        if [[ -z "${2:-}" ]]; then
          _red "Error: --region requires a value"
          return 1
        fi
        _OPT_REGION="$2"
        shift 2
        ;;
      -c|--cluster)
        if [[ -z "${2:-}" ]]; then
          _red "Error: --cluster requires a value"
          return 1
        fi
        _OPT_CLUSTER="$2"
        shift 2
        ;;
      -h|--help)
        _OPT_HELP=true
        shift
        ;;
      --show)
        _OPT_SHOW=true
        shift
        ;;
      --)
        shift
        _OPT_POSITIONAL+=("$@")
        break
        ;;
      -*)
        _red "Error: Unknown option: $1"
        return 1
        ;;
      *)
        _OPT_POSITIONAL+=("$1")
        shift
        ;;
    esac
  done
}

# Parse EC2-specific options
# Usage: _parse_ec2_opts "$@" - sets _OPT_INSTANCE_ID, _OPT_REGION, etc.
_parse_ec2_opts() {
  _OPT_INSTANCE_ID=""
  _OPT_REGION="${_DEFAULT_REGION}"
  _OPT_LOG_GROUP="/aws/ec2/instance"
  _OPT_FILTERS=()
  _OPT_HELP=false
  _OPT_SHOW=false
  _OPT_FOLLOW=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--instance-id)
        if [[ -z "${2:-}" ]]; then
          _red "Error: --instance-id requires a value"
          return 1
        fi
        _OPT_INSTANCE_ID="$2"
        shift 2
        ;;
      -r|--region)
        if [[ -z "${2:-}" ]]; then
          _red "Error: --region requires a value"
          return 1
        fi
        _OPT_REGION="$2"
        shift 2
        ;;
      -g|--log-group)
        if [[ -z "${2:-}" ]]; then
          _red "Error: --log-group requires a value"
          return 1
        fi
        _OPT_LOG_GROUP="$2"
        shift 2
        ;;
      -f|--follow)
        _OPT_FOLLOW=true
        shift
        ;;
      --filters)
        shift
        while [[ $# -gt 0 ]] && [[ "$1" != -* ]]; do
          _OPT_FILTERS+=("$1")
          shift
        done
        ;;
      -h|--help)
        _OPT_HELP=true
        shift
        ;;
      --show)
        _OPT_SHOW=true
        shift
        ;;
      --)
        shift
        _OPT_FILTERS+=("$@")
        break
        ;;
      -*)
        _red "Error: Unknown option: $1"
        return 1
        ;;
      *)
        # Positional argument - treat as instance-id if not set
        if [[ -z "$_OPT_INSTANCE_ID" ]]; then
          _OPT_INSTANCE_ID="$1"
        else
          _OPT_FILTERS+=("$1")
        fi
        shift
        ;;
    esac
  done
}

# ==============================================================================
# EKS Functions
# ==============================================================================

# Update kubeconfig for EKS cluster
# Usage: eks-update-config [-c|--cluster CLUSTER] [-r|--region REGION] [-h|--help]
eks-update-config() {
  _parse_common_opts "$@"
  
  if [[ "$_OPT_HELP" == "true" ]]; then
    echo "Usage: eks-update-config [-c|--cluster CLUSTER] [-r|--region REGION] [-h|--help] [--show]"
    echo ""
    echo "Options:"
    echo "  -c, --cluster CLUSTER    EKS cluster name (default: ${_DEFAULT_CLUSTER})"
    echo "  -r, --region REGION      AWS region (default: ${_DEFAULT_REGION})"
    echo "  -h, --help               Show this help message"
    echo "  --show                   Show the AWS CLI command without executing it"
    echo ""
    echo "Examples:"
    echo "  eks-update-config"
    echo "  eks-update-config -c my-cluster -r us-east-1"
    echo "  eks-update-config --cluster prod-cluster --region ap-southeast-1"
    echo "  eks-update-config -c my-cluster --show"
    echo ""
    echo "AWS Documentation: ${_DOCS_EKS_UPDATE_KUBECONFIG}"
    return 0
  fi
  
  local cluster="${_OPT_POSITIONAL[0]:-${_OPT_CLUSTER}}"
  local region="${_OPT_REGION}"
  
  if [[ -z "$cluster" ]]; then
    _red "Error: Cluster name is required"
    echo "Usage: eks-update-config [-c|--cluster CLUSTER] [-r|--region REGION]"
    return 1
  fi
  
  if [[ "$_OPT_SHOW" == "true" ]]; then
    _show_aws_cmd "aws eks update-kubeconfig --region $region --name $cluster"
    return 0
  fi
  
  _blue "Updating kubeconfig for cluster: $cluster in region: $region"
  aws eks update-kubeconfig --region "$region" --name "$cluster" && \
    _green "✓ Kubeconfig updated successfully"
}

# List EKS addons for a cluster
# Usage: eks-list-addons [-c|--cluster CLUSTER] [-r|--region REGION] [-h|--help]
eks-list-addons() {
  _parse_common_opts "$@"
  
  if [[ "$_OPT_HELP" == "true" ]]; then
    echo "Usage: eks-list-addons [-c|--cluster CLUSTER] [-r|--region REGION] [-h|--help] [--show]"
    echo ""
    echo "Options:"
    echo "  -c, --cluster CLUSTER    EKS cluster name (default: ${_DEFAULT_CLUSTER})"
    echo "  -r, --region REGION      AWS region (default: ${_DEFAULT_REGION})"
    echo "  -h, --help               Show this help message"
    echo "  --show                   Show the AWS CLI command without executing it"
    echo ""
    echo "AWS Documentation: ${_DOCS_EKS_LIST_ADDONS}"
    return 0
  fi
  
  local cluster="${_OPT_POSITIONAL[0]:-${_OPT_CLUSTER}}"
  local region="${_OPT_REGION}"
  
  if [[ -z "$cluster" ]]; then
    _red "Error: Cluster name is required"
    echo "Usage: eks-list-addons [-c|--cluster CLUSTER] [-r|--region REGION]"
    return 1
  fi
  
  if [[ "$_OPT_SHOW" == "true" ]]; then
    _show_aws_cmd "aws eks list-addons --cluster-name $cluster --region $region --query 'addons[]' --output text"
    return 0
  fi
  
  _blue "Listing addons for cluster: $cluster in region: $region"
  aws eks list-addons --cluster-name "$cluster" --region "$region" --query 'addons[]' --output text 2>/dev/null || \
    aws eks list-addons --cluster-name "$cluster" --region "$region"
}

# Check if EKS cluster has auto mode enabled
# Usage: eks-automode-status [cluster-name] [region] [--show]
eks-automode-status() {
  local cluster="${1:-${_DEFAULT_CLUSTER}}"
  local region="${2:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${3:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$cluster" ]]; then
    _red "Error: Cluster name is required"
    echo "Usage: eks-automode-status [cluster-name] [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws eks describe-cluster --name $cluster --region $region --query 'cluster.autoModeConfig.enabled' --output text"
    return 0
  fi
  
  _blue "Checking auto mode for cluster: $cluster in region: $region"
  
  # Get the enabled status directly
  local enabled=$(aws eks describe-cluster \
    --name "$cluster" \
    --region "$region" \
    --query 'cluster.autoModeConfig.enabled' \
    --output text 2>/dev/null)
  
  local aws_exit_code=$?
  
  if [[ $aws_exit_code -ne 0 ]]; then
    _red "Error: Failed to query cluster information"
    return 1
  fi
  
  # Handle different return values
  case "$enabled" in
    "True"|"true"|"TRUE")
    _green "✓ Auto mode is ENABLED"
      ;;
    "False"|"false"|"FALSE")
    _yellow "✗ Auto mode is DISABLED"
      ;;
    "None")
      # When enabled is None, it means autoModeConfig exists but enabled field is not set
      # This typically means auto mode is not explicitly configured
      _yellow "Auto mode is not explicitly configured (enabled: None)"
      _blue "Note: Auto mode configuration exists but the 'enabled' field is not set"
      _blue "You may need to explicitly enable or disable auto mode for this cluster"
      ;;
    "null"|"")
      # Check if autoModeConfig exists at all
      local auto_mode_config=$(aws eks describe-cluster \
        --name "$cluster" \
        --region "$region" \
        --query 'cluster.autoModeConfig' \
        --output json 2>/dev/null)
      
      if [[ -z "$auto_mode_config" ]] || [[ "$auto_mode_config" == "null" ]] || [[ "$auto_mode_config" == "{}" ]]; then
        _yellow "Auto mode configuration is not available for this cluster"
        _blue "Note: Auto mode is only available for EKS clusters created with Kubernetes version 1.27 or later"
      else
        _yellow "Auto mode status: ${enabled:-unknown}"
        _blue "Debug info - autoModeConfig: $auto_mode_config"
      fi
      ;;
    *)
      _yellow "Auto mode status: ${enabled}"
      _blue "Unexpected return value. Please check the cluster configuration."
      ;;
  esac
}

# Enable EKS auto mode
# Usage: eks-automode-enabled [cluster-name] [region] [--show]
eks-automode-enabled() {
  local cluster="${1:-${_DEFAULT_CLUSTER}}"
  local region="${2:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${3:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$cluster" ]]; then
    _red "Error: Cluster name is required"
    echo "Usage: eks-automode-enabled [cluster-name] [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws eks update-cluster-config --name $cluster --region $region --auto-mode-config enabled=true --query 'update.id' --output text"
    return 0
  fi
  
  _blue "Enabling auto mode for cluster: $cluster in region: $region"
  
  # Check current status first
  local current_status=$(aws eks describe-cluster \
    --name "$cluster" \
    --region "$region" \
    --query 'cluster.autoModeConfig.enabled' \
    --output text 2>/dev/null)
  
  if [[ "$current_status" == "True" ]] || [[ "$current_status" == "true" ]]; then
    _yellow "Auto mode is already enabled for cluster: $cluster"
    return 0
  fi
  
  # Enable auto mode
  local update_id=$(aws eks update-cluster-config \
    --name "$cluster" \
    --region "$region" \
    --auto-mode-config enabled=true \
    --query 'update.id' \
    --output text 2>/dev/null)
  
  local aws_exit_code=$?
  
  if [[ $aws_exit_code -eq 0 ]]; then
    _green "✓ Auto mode enable request submitted successfully"
    _blue "The cluster update is in progress. You can check the status with: eks-automode-status $cluster $region"
    
    # Show update status
    if [[ -n "$update_id" ]] && [[ "$update_id" != "None" ]] && [[ "$update_id" != "null" ]]; then
      _blue "Update ID: $update_id"
    fi
  else
    _red "Error: Failed to enable auto mode"
    echo "$update_id" | grep -i "error\|exception\|failed" 2>/dev/null || echo "$update_id"
    return 1
  fi
}

# Disable EKS auto mode
# Usage: eks-automode-disabled [cluster-name] [region] [--show]
eks-automode-disabled() {
  local cluster="${1:-${_DEFAULT_CLUSTER}}"
  local region="${2:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${3:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$cluster" ]]; then
    _red "Error: Cluster name is required"
    echo "Usage: eks-automode-disabled [cluster-name] [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws eks update-cluster-config --name $cluster --region $region --auto-mode-config enabled=false --query 'update.id' --output text"
    return 0
  fi
  
  # Check current status first
  local current_status=$(aws eks describe-cluster \
    --name "$cluster" \
    --region "$region" \
    --query 'cluster.autoModeConfig.enabled' \
    --output text 2>/dev/null)
  
  if [[ "$current_status" == "False" ]] || [[ "$current_status" == "false" ]]; then
    _yellow "Auto mode is already disabled for cluster: $cluster"
    return 0
  fi
  
  _yellow "Warning: Disabling auto mode is a destructive operation!"
  _yellow "EKS will terminate all EC2 instances managed by auto mode and delete related load balancers."
  _yellow "EBS volumes provisioned by auto mode will NOT be deleted."
  echo ""
  
  read -p "Are you sure you want to disable auto mode for cluster '$cluster'? (yes/no): " confirm
  
  if [[ "$confirm" != "yes" ]]; then
    _blue "Operation cancelled"
    return 0
  fi
  
  _blue "Disabling auto mode for cluster: $cluster in region: $region"
  
  # Disable auto mode
  local update_id=$(aws eks update-cluster-config \
    --name "$cluster" \
    --region "$region" \
    --auto-mode-config enabled=false \
    --query 'update.id' \
    --output text 2>&1)
  
  local aws_exit_code=$?
  
  if [[ $aws_exit_code -eq 0 ]]; then
    _green "✓ Auto mode disable request submitted successfully"
    _yellow "Warning: The cluster update is in progress. Resources managed by auto mode will be terminated."
    _blue "You can check the status with: eks-automode-status $cluster $region"
    
    # Show update status
    if [[ -n "$update_id" ]] && [[ "$update_id" != "None" ]] && [[ "$update_id" != "null" ]]; then
      _blue "Update ID: $update_id"
    fi
    
    echo ""
    _blue "Note: After disabling auto mode, you may need to manually delete security groups created by auto mode:"
    _blue "  aws ec2 describe-security-groups --filters Name=tag:eks:eks-cluster-name,Values=$cluster --query 'SecurityGroups[*].[GroupId,GroupName]'"
  else
    _red "Error: Failed to disable auto mode"
    echo "$update_id" | grep -i "error\|exception\|failed" 2>/dev/null || echo "$update_id"
    return 1
  fi
}

# Get EKS cluster details
# Usage: eks-describe [cluster-name] [region] [--show]
eks-describe() {
  local cluster="${1:-${_DEFAULT_CLUSTER}}"
  local region="${2:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${3:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$cluster" ]]; then
    _red "Error: Cluster name is required"
    echo "Usage: eks-describe [cluster-name] [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws eks describe-cluster --name $cluster --region $region --output json"
    return 0
  fi
  
  _blue "Describing cluster: $cluster in region: $region"
  aws eks describe-cluster --name "$cluster" --region "$region" --output json 2>/dev/null || \
    aws eks describe-cluster --name "$cluster" --region "$region"
}

# List all EKS clusters
# Usage: eks-list [region] [--show]
eks-list() {
  local region="${1:-${_DEFAULT_REGION}}"
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${2:-}" == "--show" ]]; then
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
    _show_aws_cmd "aws eks list-clusters --region $region --query 'clusters[]' --output text"
    return 0
  fi
  
  _blue "Listing EKS clusters in region: $region"
  aws eks list-clusters --region "$region" --query 'clusters[]' --output text 2>/dev/null || \
    aws eks list-clusters --region "$region"
}

# Get EKS node groups for a cluster
# Usage: eks-list-nodegroups [cluster-name] [region] [--show]
eks-list-nodegroups() {
  local cluster="${1:-${_DEFAULT_CLUSTER}}"
  local region="${2:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${3:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$cluster" ]]; then
    _red "Error: Cluster name is required"
    echo "Usage: eks-list-nodegroups [cluster-name] [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws eks list-nodegroups --cluster-name $cluster --region $region --query 'nodegroups[]' --output text"
    return 0
  fi
  
  _blue "Listing node groups for cluster: $cluster in region: $region"
  aws eks list-nodegroups --cluster-name "$cluster" --region "$region" --query 'nodegroups[]' --output text 2>/dev/null || \
    aws eks list-nodegroups --cluster-name "$cluster" --region "$region"
}

# ==============================================================================
# ECR Functions
# ==============================================================================

# List ECR repositories
# Usage: ecr-list [region] [--show]
ecr-list() {
  local region="${1:-${_DEFAULT_REGION}}"
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${2:-}" == "--show" ]]; then
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
    _show_aws_cmd "aws ecr describe-repositories --region $region --query 'repositories[].repositoryUri' --output text"
    return 0
  fi
  
  _blue "Listing ECR repositories in region: $region"
  aws ecr describe-repositories --region "$region" --query 'repositories[].repositoryUri' --output text 2>/dev/null || \
    aws ecr describe-repositories --region "$region"
}

# List images in an ECR repository
# Usage: ecr-list-images [-n|--name REPO] [-r|--region REGION] [-h|--help] [--show]
ecr-list-images() {
  local repo=""
  local region="${_DEFAULT_REGION}"
  local help=false
  local show=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -n|--name)
        if [[ -z "${2:-}" ]]; then
          _red "Error: --name requires a value"
          return 1
        fi
        repo="$2"
        shift 2
        ;;
      -r|--region)
        if [[ -z "${2:-}" ]]; then
          _red "Error: --region requires a value"
          return 1
        fi
        region="$2"
        shift 2
        ;;
      -h|--help)
        help=true
        shift
        ;;
      --show)
        show=true
        shift
        ;;
      -*)
        _red "Error: Unknown option: $1"
        return 1
        ;;
      *)
        if [[ -z "$repo" ]]; then
          repo="$1"
        fi
        shift
        ;;
    esac
  done
  
  if [[ "$help" == "true" ]]; then
    echo "Usage: ecr-list-images [-n|--name REPO] [-r|--region REGION] [-h|--help] [--show]"
    echo ""
    echo "Options:"
    echo "  -n, --name REPO           ECR repository name (required)"
    echo "  -r, --region REGION       AWS region (default: ${_DEFAULT_REGION})"
    echo "  -h, --help                Show this help message"
    echo "  --show                    Show the AWS CLI command without executing it"
    echo ""
    echo "AWS Documentation: ${_DOCS_ECR_LIST_IMAGES}"
    return 0
  fi
  
  if [[ -z "$repo" ]]; then
    _red "Error: Repository name is required"
    echo "Usage: ecr-list-images [-n|--name REPO] [-r|--region REGION]"
    return 1
  fi
  
  if [[ "$show" == "true" ]]; then
    _show_aws_cmd "aws ecr list-images --repository-name $repo --region $region --output json"
    return 0
  fi
  
  _blue "Listing images in repository: $repo in region: $region"
  aws ecr list-images --repository-name "$repo" --region "$region" --output json 2>/dev/null || \
    aws ecr list-images --repository-name "$repo" --region "$region"
}

# Get ECR login token
# Usage: ecr-login [region] [--show]
ecr-login() {
  local region="${1:-${_DEFAULT_REGION}}"
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${2:-}" == "--show" ]]; then
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
    local account_cmd="aws sts get-caller-identity --query Account --output text"
    _green "AWS CLI Commands:"
    echo "  # Get ECR login password"
    echo "  aws ecr get-login-password --region $region | docker login --username AWS --password-stdin \$(aws sts get-caller-identity --query Account --output text).dkr.ecr.${region}.amazonaws.com"
    echo ""
    _blue "You can copy and run these commands directly, or share them with your colleagues."
    return 0
  fi
  
  _blue "Getting ECR login token for region: $region"
  aws ecr get-login-password --region "$region" | docker login --username AWS --password-stdin \
    $(aws sts get-caller-identity --query Account --output text).dkr.ecr.${region}.amazonaws.com && \
    _green "✓ ECR login successful"
}

# ==============================================================================
# EC2 Functions
# ==============================================================================

# Get EC2 instance user data
# Usage: ec2-userdata [-i|--instance-id INSTANCE_ID] [-r|--region REGION] [-h|--help]
ec2-userdata() {
  _parse_ec2_opts "$@"
  
  if [[ "$_OPT_HELP" == "true" ]]; then
    echo "Usage: ec2-userdata [-i|--instance-id INSTANCE_ID] [-r|--region REGION] [-h|--help] [--show]"
    echo ""
    echo "Options:"
    echo "  -i, --instance-id ID      EC2 instance ID (required)"
    echo "  -r, --region REGION       AWS region (default: ${_DEFAULT_REGION})"
    echo "  -h, --help                Show this help message"
    echo "  --show                    Show the AWS CLI command without executing it"
    echo ""
    echo "AWS Documentation: ${_DOCS_EC2_DESCRIBE_INSTANCE_ATTRIBUTE}"
    return 0
  fi
  
  local instance_id="${_OPT_INSTANCE_ID}"
  local region="${_OPT_REGION}"
  
  if [[ -z "$instance_id" ]]; then
    _red "Error: Instance ID is required"
    echo "Usage: ec2-userdata [-i|--instance-id INSTANCE_ID] [-r|--region REGION]"
    return 1
  fi
  
  if [[ "$_OPT_SHOW" == "true" ]]; then
    _show_aws_cmd "aws ec2 describe-instance-attribute --instance-id $instance_id --attribute userData --region $region --query 'UserData.Value' --output text"
    return 0
  fi
  
  _blue "Getting user data for instance: $instance_id in region: $region"
  local userdata=$(aws ec2 describe-instance-attribute \
    --instance-id "$instance_id" \
    --attribute userData \
    --region "$region" \
    --query 'UserData.Value' \
    --output text 2>/dev/null)
  
  if [[ -n "$userdata" ]]; then
    echo "$userdata" | base64 -d
  else
    _yellow "No user data found for instance: $instance_id"
  fi
}

# Get EC2 instance details
# Usage: ec2-describe [-i|--instance-id INSTANCE_ID] [-r|--region REGION] [-h|--help]
ec2-describe() {
  _parse_ec2_opts "$@"
  
  if [[ "$_OPT_HELP" == "true" ]]; then
    echo "Usage: ec2-describe [-i|--instance-id INSTANCE_ID] [-r|--region REGION] [-h|--help] [--show]"
    echo ""
    echo "Options:"
    echo "  -i, --instance-id ID      EC2 instance ID (required)"
    echo "  -r, --region REGION        AWS region (default: ${_DEFAULT_REGION})"
    echo "  -h, --help                 Show this help message"
    echo "  --show                     Show the AWS CLI command without executing it"
    echo ""
    echo "AWS Documentation: ${_DOCS_EC2_DESCRIBE_INSTANCES}"
    return 0
  fi
  
  local instance_id="${_OPT_INSTANCE_ID}"
  local region="${_OPT_REGION}"
  
  if [[ -z "$instance_id" ]]; then
    _red "Error: Instance ID is required"
    echo "Usage: ec2-describe [-i|--instance-id INSTANCE_ID] [-r|--region REGION]"
    return 1
  fi
  
  if [[ "$_OPT_SHOW" == "true" ]]; then
    _show_aws_cmd "aws ec2 describe-instances --instance-ids $instance_id --region $region --output json"
    return 0
  fi
  
  _blue "Describing instance: $instance_id in region: $region"
  aws ec2 describe-instances --instance-ids "$instance_id" --region "$region" --output json 2>/dev/null || \
    aws ec2 describe-instances --instance-ids "$instance_id" --region "$region"
}

# Get EC2 instance console output (logs)
# Usage: ec2-console-output [-i|--instance-id INSTANCE_ID] [-r|--region REGION] [-h|--help]
ec2-console-output() {
  _parse_ec2_opts "$@"
  
  if [[ "$_OPT_HELP" == "true" ]]; then
    echo "Usage: ec2-console-output [-i|--instance-id INSTANCE_ID] [-r|--region REGION] [-h|--help] [--show]"
    echo ""
    echo "Options:"
    echo "  -i, --instance-id ID      EC2 instance ID (required)"
    echo "  -r, --region REGION        AWS region (default: ${_DEFAULT_REGION})"
    echo "  -h, --help                 Show this help message"
    echo "  --show                     Show the AWS CLI command without executing it"
    echo ""
    echo "AWS Documentation: ${_DOCS_EC2_GET_CONSOLE_OUTPUT}"
    return 0
  fi
  
  local instance_id="${_OPT_INSTANCE_ID}"
  local region="${_OPT_REGION}"
  
  if [[ -z "$instance_id" ]]; then
    _red "Error: Instance ID is required"
    echo "Usage: ec2-console-output [-i|--instance-id INSTANCE_ID] [-r|--region REGION]"
    return 1
  fi
  
  if [[ "$_OPT_SHOW" == "true" ]]; then
    _show_aws_cmd "aws ec2 get-console-output --instance-id $instance_id --region $region --query 'Output' --output text"
    return 0
  fi
  
  _blue "Getting console output for instance: $instance_id in region: $region"
  aws ec2 get-console-output --instance-id "$instance_id" --region "$region" --query 'Output' --output text 2>/dev/null || \
    aws ec2 get-console-output --instance-id "$instance_id" --region "$region"
}

# List EC2 instances
# Usage: ec2-list [-r|--region REGION] [--filters FILTERS...] [-h|--help] [--show]
ec2-list() {
  _OPT_REGION="${_DEFAULT_REGION}"
  _OPT_FILTERS=()
  _OPT_HELP=false
  _OPT_SHOW=false
  
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -r|--region)
        if [[ -z "${2:-}" ]]; then
          _red "Error: --region requires a value"
          return 1
        fi
        _OPT_REGION="$2"
        shift 2
        ;;
      --filters)
  shift
        while [[ $# -gt 0 ]] && [[ "$1" != -* ]]; do
          _OPT_FILTERS+=("$1")
          shift
        done
        ;;
      -h|--help)
        _OPT_HELP=true
        shift
        ;;
      --show)
        _OPT_SHOW=true
        shift
        ;;
      --)
        shift
        _OPT_FILTERS+=("$@")
        break
        ;;
      -*)
        _red "Error: Unknown option: $1"
        echo "Usage: ec2-list [-r|--region REGION] [--filters FILTERS...]"
        return 1
        ;;
      *)
        _OPT_FILTERS+=("$1")
        shift
        ;;
    esac
  done
  
  if [[ "$_OPT_HELP" == "true" ]]; then
    echo "Usage: ec2-list [-r|--region REGION] [--filters FILTERS...] [-h|--help] [--show]"
    echo ""
    echo "Options:"
    echo "  -r, --region REGION       AWS region (default: ${_DEFAULT_REGION})"
    echo "  --filters FILTERS         AWS EC2 filters (e.g., Name=instance-state-name,Values=running)"
    echo "  -h, --help                Show this help message"
    echo "  --show                    Show the AWS CLI command without executing it"
    echo ""
    echo "Examples:"
    echo "  ec2-list"
    echo "  ec2-list -r us-east-1"
    echo "  ec2-list --filters Name=instance-state-name,Values=running"
    echo "  ec2-list -r us-east-1 --filters Name=tag:Environment,Values=prod"
    echo ""
    echo "AWS Documentation: ${_DOCS_EC2_DESCRIBE_INSTANCES}"
    return 0
  fi
  
  local region="${_OPT_REGION}"
  
  _blue "Listing EC2 instances in region: $region"
  if [[ ${#_OPT_FILTERS[@]} -gt 0 ]]; then
    aws ec2 describe-instances --region "$region" --filters "${_OPT_FILTERS[@]}" | \
      jq -r '.Reservations[].Instances[] | "\(.InstanceId) | \(.State.Name) | \(.InstanceType) | \(.PrivateIpAddress // "N/A") | \(.PublicIpAddress // "") | \(.Tags[]? | select(.Key=="Name") | .Value // "N/A")"' 2>/dev/null || \
      aws ec2 describe-instances --region "$region" --filters "${_OPT_FILTERS[@]}"
  else
    aws ec2 describe-instances --region "$region" | \
      jq -r '.Reservations[].Instances[] | "\(.InstanceId) | \(.State.Name) | \(.InstanceType) | \(.PrivateIpAddress // "N/A") | \(.PublicIpAddress // "") | \(.Tags[]? | select(.Key=="Name") | .Value // "N/A")"' 2>/dev/null || \
      aws ec2 describe-instances --region "$region"
  fi
}

# Get EC2 instance logs from CloudWatch Logs (if configured)
# Usage: ec2-logs [-i|--instance-id INSTANCE_ID] [-g|--log-group GROUP] [-r|--region REGION] [-f|--follow] [-h|--help]
ec2-logs() {
  _parse_ec2_opts "$@"
  
  if [[ "$_OPT_HELP" == "true" ]]; then
    echo "Usage: ec2-logs [-i|--instance-id INSTANCE_ID] [-g|--log-group GROUP] [-r|--region REGION] [-f|--follow] [-h|--help] [--show]"
    echo ""
    echo "Options:"
    echo "  -i, --instance-id ID      EC2 instance ID (required)"
    echo "  -g, --log-group GROUP     CloudWatch log group name (default: /aws/ec2/instance)"
    echo "  -r, --region REGION       AWS region (default: ${_DEFAULT_REGION})"
    echo "  -f, --follow              Follow log output (like tail -f)"
    echo "  -h, --help                Show this help message"
    echo "  --show                    Show the AWS CLI command without executing it"
    echo ""
    echo "Examples:"
    echo "  ec2-logs -i i-1234567890abcdef0"
    echo "  ec2-logs --instance-id i-1234567890abcdef0 --log-group /aws/ec2/my-app --follow"
    echo "  ec2-logs -i i-1234567890abcdef0 -r us-east-1 -f"
    echo "  ec2-logs -i i-1234567890abcdef0 --show"
    echo ""
    echo "AWS Documentation: ${_DOCS_LOGS_TAIL}"
    return 0
  fi
  
  local instance_id="${_OPT_INSTANCE_ID}"
  local log_group="${_OPT_LOG_GROUP}"
  local region="${_OPT_REGION}"
  local follow_flag=""
  
  if [[ -z "$instance_id" ]]; then
    _red "Error: Instance ID is required"
    echo "Usage: ec2-logs [-i|--instance-id INSTANCE_ID] [-g|--log-group GROUP] [-r|--region REGION] [-f|--follow]"
    return 1
  fi
  
  if [[ "$_OPT_SHOW" == "true" ]]; then
    local cmd="aws logs tail $log_group --filter-pattern $instance_id --region $region"
    if [[ "$_OPT_FOLLOW" == "true" ]]; then
      cmd="$cmd --follow"
    fi
    _show_aws_cmd "$cmd"
    return 0
  fi
  
  if [[ "$_OPT_FOLLOW" == "true" ]]; then
    follow_flag="--follow"
  fi
  
  _blue "Getting logs for instance: $instance_id from log group: $log_group in region: $region"
  aws logs tail "$log_group" --filter-pattern "$instance_id" --region "$region" $follow_flag 2>/dev/null || \
    _yellow "Log group not found or no logs available. Try: ec2-console-output $instance_id"
}

# ==============================================================================
# VPC Functions
# ==============================================================================

# List VPCs
# Usage: vpc-list [region] [--show]
vpc-list() {
  local region="${1:-${_DEFAULT_REGION}}"
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${2:-}" == "--show" ]]; then
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
    _show_aws_cmd "aws ec2 describe-vpcs --region $region"
    return 0
  fi
  
  _blue "Listing VPCs in region: $region"
  aws ec2 describe-vpcs --region "$region" | jq -r '.Vpcs[] | "\(.VpcId) | \(.CidrBlock) | \(.Tags[]? | select(.Key=="Name") | .Value // "N/A")"' 2>/dev/null || \
    aws ec2 describe-vpcs --region "$region"
}

# List subnets in a VPC
# Usage: vpc-list-subnets <vpc-id> [region] [--show]
vpc-list-subnets() {
  local vpc_id="${1}"
  local region="${2:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${3:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$vpc_id" ]]; then
    _red "Error: VPC ID is required"
    echo "Usage: vpc-list-subnets <vpc-id> [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws ec2 describe-subnets --filters \"Name=vpc-id,Values=$vpc_id\" --region $region"
    return 0
  fi
  
  _blue "Listing subnets in VPC: $vpc_id in region: $region"
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --region "$region" | \
    jq -r '.Subnets[] | "\(.SubnetId) | \(.CidrBlock) | \(.AvailabilityZone) | \(.Tags[]? | select(.Key=="Name") | .Value // "N/A")"' 2>/dev/null || \
    aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --region "$region"
}

# ==============================================================================
# RDS Functions
# ==============================================================================

# List RDS instances
# Usage: rds-list [region] [--show]
rds-list() {
  local region="${1:-${_DEFAULT_REGION}}"
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${2:-}" == "--show" ]]; then
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
    _show_aws_cmd "aws rds describe-db-instances --region $region"
    return 0
  fi
  
  _blue "Listing RDS instances in region: $region"
  aws rds describe-db-instances --region "$region" | \
    jq -r '.DBInstances[] | "\(.DBInstanceIdentifier) | \(.Engine) | \(.DBInstanceStatus) | \(.Endpoint.Address)"' 2>/dev/null || \
    aws rds describe-db-instances --region "$region"
}

# ==============================================================================
# ECS Functions
# ==============================================================================

# List ECS clusters
# Usage: ecs-list-clusters [region] [--show]
ecs-list-clusters() {
  local region="${1:-${_DEFAULT_REGION}}"
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${2:-}" == "--show" ]]; then
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
    _show_aws_cmd "aws ecs list-clusters --region $region --query 'clusterArns[]' --output text"
    return 0
  fi
  
  _blue "Listing ECS clusters in region: $region"
  aws ecs list-clusters --region "$region" --query 'clusterArns[]' --output text 2>/dev/null || \
    aws ecs list-clusters --region "$region"
}

# List ECS services in a cluster
# Usage: ecs-list-services <cluster-name> [region] [--show]
ecs-list-services() {
  local cluster="${1}"
  local region="${2:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${3:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$cluster" ]]; then
    _red "Error: Cluster name is required"
    echo "Usage: ecs-list-services <cluster-name> [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws ecs list-services --cluster $cluster --region $region --query 'serviceArns[]' --output text"
    return 0
  fi
  
  _blue "Listing services in cluster: $cluster in region: $region"
  aws ecs list-services --cluster "$cluster" --region "$region" --query 'serviceArns[]' --output text 2>/dev/null || \
    aws ecs list-services --cluster "$cluster" --region "$region"
}

# Describe ECS service
# Usage: ecs-describe-service <cluster-name> <service-name> [region] [--show]
ecs-describe-service() {
  local cluster="${1}"
  local service="${2}"
  local region="${3:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${4:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$cluster" ]] || [[ -z "$service" ]]; then
    _red "Error: Cluster name and service name are required"
    echo "Usage: ecs-describe-service <cluster-name> <service-name> [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws ecs describe-services --cluster $cluster --services $service --region $region --output json"
    return 0
  fi
  
  _blue "Describing service: $service in cluster: $cluster in region: $region"
  aws ecs describe-services --cluster "$cluster" --services "$service" --region "$region" --output json 2>/dev/null || \
    aws ecs describe-services --cluster "$cluster" --services "$service" --region "$region"
}

# List ECS tasks in a cluster/service
# Usage: ecs-list-tasks <cluster-name> [service-name] [region] [--show]
ecs-list-tasks() {
  local cluster="${1}"
  local service="${2:-}"
  local region="${3:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${4:-}" == "--show" ]] || [[ "$service" == "--show" ]]; then
    show_flag=true
    if [[ "$service" == "--show" ]]; then
      service=""
      region="${_DEFAULT_REGION}"
    elif [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$cluster" ]]; then
    _red "Error: Cluster name is required"
    echo "Usage: ecs-list-tasks <cluster-name> [service-name] [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    local cmd="aws ecs list-tasks --cluster $cluster --region $region --query 'taskArns[]' --output text"
    if [[ -n "$service" ]]; then
      cmd="aws ecs list-tasks --cluster $cluster --service-name $service --region $region --query 'taskArns[]' --output text"
    fi
    _show_aws_cmd "$cmd"
    return 0
  fi
  
  _blue "Listing tasks in cluster: $cluster in region: $region"
  if [[ -n "$service" ]]; then
    aws ecs list-tasks --cluster "$cluster" --service-name "$service" --region "$region" --query 'taskArns[]' --output text 2>/dev/null || \
      aws ecs list-tasks --cluster "$cluster" --service-name "$service" --region "$region"
  else
    aws ecs list-tasks --cluster "$cluster" --region "$region" --query 'taskArns[]' --output text 2>/dev/null || \
      aws ecs list-tasks --cluster "$cluster" --region "$region"
  fi
}

# Describe ECS task
# Usage: ecs-describe-task <cluster-name> <task-id> [region] [--show]
ecs-describe-task() {
  local cluster="${1}"
  local task="${2}"
  local region="${3:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${4:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$cluster" ]] || [[ -z "$task" ]]; then
    _red "Error: Cluster name and task ID are required"
    echo "Usage: ecs-describe-task <cluster-name> <task-id> [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws ecs describe-tasks --cluster $cluster --tasks $task --region $region --output json"
    return 0
  fi
  
  _blue "Describing task: $task in cluster: $cluster in region: $region"
  aws ecs describe-tasks --cluster "$cluster" --tasks "$task" --region "$region" --output json 2>/dev/null || \
    aws ecs describe-tasks --cluster "$cluster" --tasks "$task" --region "$region"
}

# Update ECS service (e.g., force new deployment)
# Usage: ecs-update-service <cluster-name> <service-name> [region] [--force-new-deployment] [--show]
ecs-update-service() {
  local cluster="${1}"
  local service="${2}"
  local region="${3:-${_DEFAULT_REGION}}"
  local force_flag="${4:-}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${4:-}" == "--show" ]] || [[ "${5:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    elif [[ "${4:-}" == "--show" ]]; then
      force_flag=""
    fi
  fi
  
  # Check if region parameter is actually --force-new-deployment flag
  if [[ "$region" == "--force-new-deployment" ]]; then
    force_flag="--force-new-deployment"
    region="${_DEFAULT_REGION}"
  fi
  
  if [[ -z "$cluster" ]] || [[ -z "$service" ]]; then
    _red "Error: Cluster name and service name are required"
    echo "Usage: ecs-update-service <cluster-name> <service-name> [region] [--force-new-deployment] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    local cmd="aws ecs update-service --cluster $cluster --service $service --region $region"
    if [[ "$force_flag" == "--force-new-deployment" ]]; then
      cmd="$cmd --force-new-deployment"
    fi
    cmd="$cmd --output json"
    _show_aws_cmd "$cmd"
    return 0
  fi
  
  _blue "Updating service: $service in cluster: $cluster in region: $region"
  
  if [[ "$force_flag" == "--force-new-deployment" ]]; then
    aws ecs update-service --cluster "$cluster" --service "$service" --region "$region" --force-new-deployment --output json 2>/dev/null || \
      aws ecs update-service --cluster "$cluster" --service "$service" --region "$region" --force-new-deployment
  else
    aws ecs update-service --cluster "$cluster" --service "$service" --region "$region" --output json 2>/dev/null || \
      aws ecs update-service --cluster "$cluster" --service "$service" --region "$region"
  fi
}

# Stop ECS task
# Usage: ecs-stop-task <cluster-name> <task-id> [region] [reason] [--show]
ecs-stop-task() {
  local cluster="${1}"
  local task="${2}"
  local region="${3:-${_DEFAULT_REGION}}"
  local reason="${4:-}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${4:-}" == "--show" ]] || [[ "${5:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    elif [[ "${4:-}" == "--show" ]]; then
      reason=""
    fi
  fi
  
  # Check if region parameter is actually a reason
  if [[ "$region" != "${_DEFAULT_REGION}" ]] && [[ ! "$region" =~ ^[a-z]+-[a-z]+-[0-9]+$ ]] && [[ "$region" != "--show" ]]; then
    reason="$region"
    region="${_DEFAULT_REGION}"
  fi
  
  if [[ -z "$cluster" ]] || [[ -z "$task" ]]; then
    _red "Error: Cluster name and task ID are required"
    echo "Usage: ecs-stop-task <cluster-name> <task-id> [region] [reason] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    local cmd="aws ecs stop-task --cluster $cluster --task $task --region $region"
    if [[ -n "$reason" ]]; then
      cmd="$cmd --reason \"$reason\""
    fi
    cmd="$cmd --output json"
    _show_aws_cmd "$cmd"
    return 0
  fi
  
  _blue "Stopping task: $task in cluster: $cluster in region: $region"
  
  if [[ -n "$reason" ]]; then
    aws ecs stop-task --cluster "$cluster" --task "$task" --region "$region" --reason "$reason" --output json 2>/dev/null || \
      aws ecs stop-task --cluster "$cluster" --task "$task" --region "$region" --reason "$reason"
  else
    aws ecs stop-task --cluster "$cluster" --task "$task" --region "$region" --output json 2>/dev/null || \
      aws ecs stop-task --cluster "$cluster" --task "$task" --region "$region"
  fi
}

# ==============================================================================
# App Runner Functions
# ==============================================================================

# List App Runner services
# Usage: apprunner-list-services [region] [--show]
apprunner-list-services() {
  local region="${1:-${_DEFAULT_REGION}}"
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${2:-}" == "--show" ]]; then
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
    _show_aws_cmd "aws apprunner list-services --region $region --query 'ServiceSummaryList[].ServiceArn' --output text"
    return 0
  fi
  
  _blue "Listing App Runner services in region: $region"
  aws apprunner list-services --region "$region" --query 'ServiceSummaryList[].ServiceArn' --output text 2>/dev/null || \
    aws apprunner list-services --region "$region"
}

# Describe App Runner service
# Usage: apprunner-describe-service <service-name-or-arn> [region] [--show]
apprunner-describe-service() {
  local service="${1}"
  local region="${2:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${3:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$service" ]]; then
    _red "Error: Service name or ARN is required"
    echo "Usage: apprunner-describe-service <service-name-or-arn> [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws apprunner describe-service --service-arn $service --region $region --output json"
    return 0
  fi
  
  _blue "Describing App Runner service: $service in region: $region"
  aws apprunner describe-service --service-arn "$service" --region "$region" --output json 2>/dev/null || \
    aws apprunner describe-service --service-arn "$service" --region "$region"
}

# List App Runner operations for a service
# Usage: apprunner-list-operations <service-name-or-arn> [region] [--show]
apprunner-list-operations() {
  local service="${1}"
  local region="${2:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${3:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$service" ]]; then
    _red "Error: Service name or ARN is required"
    echo "Usage: apprunner-list-operations <service-name-or-arn> [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws apprunner list-operations --service-arn $service --region $region --output json"
    return 0
  fi
  
  _blue "Listing operations for service: $service in region: $region"
  aws apprunner list-operations --service-arn "$service" --region "$region" --output json 2>/dev/null || \
    aws apprunner list-operations --service-arn "$service" --region "$region"
}

# Pause App Runner service
# Usage: apprunner-pause-service <service-name-or-arn> [region] [--show]
apprunner-pause-service() {
  local service="${1}"
  local region="${2:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${3:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$service" ]]; then
    _red "Error: Service name or ARN is required"
    echo "Usage: apprunner-pause-service <service-name-or-arn> [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws apprunner pause-service --service-arn $service --region $region --output json"
    return 0
  fi
  
  _yellow "Warning: This will pause the App Runner service and stop processing requests"
  read -p "Are you sure you want to pause service '$service'? (yes/no): " confirm
  
  if [[ "$confirm" != "yes" ]]; then
    _blue "Operation cancelled"
    return 0
  fi
  
  _blue "Pausing App Runner service: $service in region: $region"
  aws apprunner pause-service --service-arn "$service" --region "$region" --output json 2>/dev/null || \
    aws apprunner pause-service --service-arn "$service" --region "$region"
}

# Resume App Runner service
# Usage: apprunner-resume-service <service-name-or-arn> [region] [--show]
apprunner-resume-service() {
  local service="${1}"
  local region="${2:-${_DEFAULT_REGION}}"
  local show_flag=false
  
  # Check for --show flag
  if [[ "$region" == "--show" ]] || [[ "${3:-}" == "--show" ]]; then
    show_flag=true
    if [[ "$region" == "--show" ]]; then
      region="${_DEFAULT_REGION}"
    fi
  fi
  
  if [[ -z "$service" ]]; then
    _red "Error: Service name or ARN is required"
    echo "Usage: apprunner-resume-service <service-name-or-arn> [region] [--show]"
    return 1
  fi
  
  if [[ "$show_flag" == "true" ]]; then
    _show_aws_cmd "aws apprunner resume-service --service-arn $service --region $region --output json"
    return 0
  fi
  
  _blue "Resuming App Runner service: $service in region: $region"
  aws apprunner resume-service --service-arn "$service" --region "$region" --output json 2>/dev/null || \
    aws apprunner resume-service --service-arn "$service" --region "$region"
}

# ==============================================================================
# IAM Functions
# ==============================================================================

# Get current AWS identity
# Usage: aws-whoami [--show]
aws-whoami() {
  # Check for --show flag
  if [[ "${1:-}" == "--show" ]]; then
    _show_aws_cmd "aws sts get-caller-identity --output json"
    return 0
  fi
  
  _blue "Current AWS identity:"
  aws sts get-caller-identity --output json 2>/dev/null || \
    aws sts get-caller-identity
}

# ==============================================================================
# S3 Functions
# ==============================================================================

# List S3 buckets
# Usage: s3-list [--show]
s3-list() {
  # Check for --show flag
  if [[ "${1:-}" == "--show" ]]; then
    _show_aws_cmd "aws s3 ls"
    return 0
  fi
  
  _blue "Listing S3 buckets:"
  aws s3 ls 2>/dev/null || \
    _yellow "Unable to list S3 buckets"
}

# ==============================================================================
# Helper Functions
# ==============================================================================

# Show all available functions
aws-help() {
  _green "Available AWS utility functions:"
  echo ""
  _yellow "Note: All functions support --show parameter to display the AWS CLI command without executing it"
  echo ""
  _blue "EKS Functions:"
  echo "  eks-update-config [-c|--cluster CLUSTER] [-r|--region REGION] [-h|--help] [--show]"
  echo "    Update kubeconfig for EKS cluster"
  echo "  eks-list-addons [-c|--cluster CLUSTER] [-r|--region REGION] [-h|--help] [--show]"
  echo "    List EKS addons"
  echo "  eks-automode-status [cluster] [region] [--show]   - Check if auto mode is enabled"
  echo "  eks-automode-enabled [cluster] [region] [--show]  - Enable EKS auto mode"
  echo "  eks-automode-disabled [cluster] [region] [--show]  - Disable EKS auto mode"
  echo "  eks-describe [cluster] [region] [--show]          - Describe EKS cluster"
  echo "  eks-list [region] [--show]                        - List all EKS clusters"
  echo "  eks-list-nodegroups [cluster] [region] [--show]   - List node groups"
  echo ""
  _blue "ECR Functions:"
  echo "  ecr-list [region] [--show]                        - List ECR repositories"
  echo "  ecr-list-images [-n|--name REPO] [-r|--region REGION] [-h|--help] [--show]"
  echo "    List images in repository"
  echo "  ecr-login [region] [--show]                       - Login to ECR"
  echo ""
  _blue "EC2 Functions:"
  echo "  ec2-userdata [-i|--instance-id ID] [-r|--region REGION] [-h|--help] [--show]"
  echo "    Get EC2 user data"
  echo "  ec2-describe [-i|--instance-id ID] [-r|--region REGION] [-h|--help] [--show]"
  echo "    Describe EC2 instance"
  echo "  ec2-console-output [-i|--instance-id ID] [-r|--region REGION] [-h|--help] [--show]"
  echo "    Get console output (logs)"
  echo "  ec2-list [-r|--region REGION] [--filters FILTERS...] [-h|--help] [--show]"
  echo "    List EC2 instances"
  echo "  ec2-logs [-i|--instance-id ID] [-g|--log-group GROUP] [-r|--region REGION] [-f|--follow] [-h|--help] [--show]"
  echo "    Get CloudWatch logs"
  echo ""
  _blue "VPC Functions:"
  echo "  vpc-list [region] [--show]                        - List VPCs"
  echo "  vpc-list-subnets <vpc-id> [region] [--show]       - List subnets in VPC"
  echo ""
  _blue "RDS Functions:"
  echo "  rds-list [region] [--show]                        - List RDS instances"
  echo ""
  _blue "ECS Functions:"
  echo "  ecs-list-clusters [region] [--show]               - List ECS clusters"
  echo "  ecs-list-services <cluster> [region] [--show]    - List services in cluster"
  echo "  ecs-describe-service <cluster> <service> [region] [--show] - Describe ECS service"
  echo "  ecs-list-tasks <cluster> [service] [region] [--show] - List tasks in cluster/service"
  echo "  ecs-describe-task <cluster> <task-id> [region] [--show] - Describe ECS task"
  echo "  ecs-update-service <cluster> <service> [region] [--force-new-deployment] [--show] - Update service"
  echo "  ecs-stop-task <cluster> <task-id> [region] [reason] [--show] - Stop task"
  echo ""
  _blue "App Runner Functions:"
  echo "  apprunner-list-services [region] [--show]         - List App Runner services"
  echo "  apprunner-describe-service <service> [region] [--show] - Describe App Runner service"
  echo "  apprunner-list-operations <service> [region] [--show] - List operations for service"
  echo "  apprunner-pause-service <service> [region] [--show] - Pause App Runner service"
  echo "  apprunner-resume-service <service> [region] [--show] - Resume App Runner service"
  echo ""
  _blue "Other Functions:"
  echo "  aws-whoami [--show]                                - Show current AWS identity"
  echo "  s3-list [--show]                                   - List S3 buckets"
  echo "  aws-help                                  - Show this help message"
  echo ""
  _blue "Kubernetes Tools Installation:"
  echo "  install-k8s-tools [--plugins]                      - Install kubectl, krew, helm, kustomize"
  echo "    Options:"
  echo "      --plugins, -p    Also install kubectl plugins (ns, ctx, history, images)"
  echo "    Examples:"
  echo "      install-k8s-tools                    # Install all tools"
  echo "      install-k8s-tools --plugins           # Install tools + plugins"
  echo ""
  _blue "Infrastructure Tools:"
  echo "  tfenv, packer, fzf                                 - Automatically installed if missing"
  echo "  'k' alias                                          - kubectl alias with autocompletion"
  echo "    Examples:"
  echo "      k get pods                                      # Same as 'kubectl get pods'"
  echo "      k get <TAB>                                     # Autocompletion works"
  echo "      Ctrl+R                                          # fzf history search"
  echo "      Ctrl+T                                          # fzf file search"
  echo "      Alt+C                                           # fzf directory navigation"
  echo ""
  _yellow "Default region: ${_DEFAULT_REGION}"
  _yellow "Default cluster: ${_DEFAULT_CLUSTER}"
  echo ""
  _green "Set environment variables to override defaults:"
  echo "  export AWS_DEFAULT_REGION=us-east-1"
  echo "  export AWS_EKS_CLUSTER=my-cluster"
  echo ""
  _green "Kubernetes tools auto-installation (enabled by default):"
  echo "  To disable auto-installation, set:"
  echo "  export KUBECTL_AUTO_INSTALL=false"
  echo "  export KREW_AUTO_INSTALL=false"
  echo "  export HELM_AUTO_INSTALL=false"
  echo "  export KUSTOMIZE_AUTO_INSTALL=false"
  echo ""
  _green "Infrastructure tools auto-installation (enabled by default):"
  echo "  To disable auto-installation, set:"
  echo "  export TFENV_AUTO_INSTALL=false"
  echo "  export PACKER_AUTO_INSTALL=false"
  echo "  export FZF_AUTO_INSTALL=false"
  echo ""
  _green "Kubectl alias 'k' auto-setup (enabled by default):"
  echo "  To disable auto-setup, set:"
  echo "  export KUBECTL_ALIAS_AUTO_SETUP=false"
}

# Export functions
export -f eks-update-config eks-list-addons eks-automode-status eks-automode-enabled eks-automode-disabled eks-describe eks-list eks-list-nodegroups
export -f ecr-list ecr-list-images ecr-login
export -f ec2-userdata ec2-describe ec2-console-output ec2-list ec2-logs
export -f vpc-list vpc-list-subnets
export -f rds-list
export -f ecs-list-clusters ecs-list-services ecs-describe-service ecs-list-tasks ecs-describe-task ecs-update-service ecs-stop-task
export -f apprunner-list-services apprunner-describe-service apprunner-list-operations apprunner-pause-service apprunner-resume-service
export -f aws-whoami s3-list aws-help install-k8s-tools

# Show help on source
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  # Script is being sourced
  _green "✓ AWS utilities loaded for Ubuntu. Type 'aws-help' for available commands."
fi

