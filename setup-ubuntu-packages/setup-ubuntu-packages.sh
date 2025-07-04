#!/bin/bash

set -euo pipefail

# setup-ubuntu-packages.sh
# Configure Ubuntu mirrors and install packages for faster, reliable CI builds

# Mirror configuration (optimized for Zurich/Switzerland datacenters)
PRIMARY_MIRROR="https://mirror.init7.net/ubuntu/"
BACKUP_MIRRORS=(
    "https://ubuntu.ethz.ch/ubuntu/"              # ETH Zurich - local Swiss mirror
    "https://ftp.halifax.rwth-aachen.de/ubuntu/"  # Germany - close to Switzerland
    "https://mirror.math.princeton.edu/pub/ubuntu/" # US fallback
    "https://mirrors.kernel.org/ubuntu/"          # Global CDN fallback
)

# Default configuration
DEFAULT_ENABLE_MIRRORS="true"
DEFAULT_MIRROR_URL="$PRIMARY_MIRROR"
DEFAULT_BACKUP_MIRRORS="https://mirror.math.princeton.edu/pub/ubuntu/,https://ftp.halifax.rwth-aachen.de/ubuntu/,https://mirrors.kernel.org/ubuntu/"
DEFAULT_PACKAGES="git curl"
DEFAULT_EXTRA_PACKAGES=""
DEFAULT_UPDATE_CACHE="true"
DEFAULT_UBUNTU_VERSION=""
DEFAULT_RETRY_COUNT="2"
DEFAULT_CACHE_TIMEOUT="120"
DEFAULT_VERBOSE="false"
DEFAULT_DRY_RUN="false"

# Configuration variables (environment variables take precedence, then defaults)
ENABLE_MIRRORS="${ENABLE_MIRRORS:-${DEFAULT_ENABLE_MIRRORS}}"
MIRROR_URL="${MIRROR_URL:-${DEFAULT_MIRROR_URL}}"
BACKUP_MIRRORS="${BACKUP_MIRRORS:-${DEFAULT_BACKUP_MIRRORS}}"
PACKAGES="${PACKAGES:-${DEFAULT_PACKAGES}}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-${DEFAULT_EXTRA_PACKAGES}}"
UPDATE_CACHE="${UPDATE_CACHE:-${DEFAULT_UPDATE_CACHE}}"
UBUNTU_VERSION="${UBUNTU_VERSION:-${DEFAULT_UBUNTU_VERSION}}"
RETRY_COUNT="${RETRY_COUNT:-${DEFAULT_RETRY_COUNT}}"
CACHE_TIMEOUT="${CACHE_TIMEOUT:-${DEFAULT_CACHE_TIMEOUT}}"
VERBOSE="${VERBOSE:-${DEFAULT_VERBOSE}}"
DRY_RUN="${DRY_RUN:-${DEFAULT_DRY_RUN}}"

# Output variables
MIRROR_CONFIGURED=""
PACKAGES_INSTALLED=""
UBUNTU_CODENAME=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_verbose() {
    if [[ "${VERBOSE}" == "true" ]]; then
        echo -e "${BLUE}🔍 $1${NC}"
    fi
}

show_usage() {
    cat << EOF
setup-ubuntu-packages.sh

Configure Ubuntu mirrors and install packages for faster, reliable CI builds.

This script reads configuration from environment variables:

Environment Variables:
  ENABLE_MIRRORS           Enable mirror configuration (default: true)
  MIRROR_URL              Primary mirror URL (default: https://mirror.init7.net/ubuntu/)
  BACKUP_MIRRORS          Backup mirror URLs (comma-separated)
  PACKAGES                List of packages to install (space-separated)
  EXTRA_PACKAGES          Additional packages to install (space-separated)
  UPDATE_CACHE            Run apt-get update before installation (default: true)
  UBUNTU_VERSION          Ubuntu version codename (auto-detected if empty)
  RETRY_COUNT             Number of retry attempts (default: 2)
  CACHE_TIMEOUT           Timeout for package operations (default: 120)
  VERBOSE                 Enable verbose logging (default: false)
  DRY_RUN                 Show what would be done without executing (default: false)

Examples:
  PACKAGES="git curl wget" ENABLE_MIRRORS=true ./setup-ubuntu-packages.sh
  PACKAGES="build-essential nodejs" UPDATE_CACHE=false VERBOSE=true ./setup-ubuntu-packages.sh
  ENABLE_MIRRORS=false PACKAGES="python3 python3-pip" DRY_RUN=true ./setup-ubuntu-packages.sh
  MIRROR_URL="https://custom-mirror.com/ubuntu/" PACKAGES="docker.io" ./setup-ubuntu-packages.sh

EOF
}

# Validate configuration
validate_configuration() {
    # Validate numeric values that could cause problems
    if ! [[ "$RETRY_COUNT" =~ ^[0-9]+$ ]] || [[ "$RETRY_COUNT" -lt 1 ]]; then
        log_error "Invalid RETRY_COUNT: $RETRY_COUNT (must be a positive integer)"
        exit 1
    fi

    if ! [[ "$CACHE_TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$CACHE_TIMEOUT" -lt 1 ]]; then
        log_error "Invalid CACHE_TIMEOUT: $CACHE_TIMEOUT (must be a positive integer)"
        exit 1
    fi
}

# Show configuration
show_configuration() {
    log_info "🚀 Ubuntu Package Setup Configuration"
    echo "======================================"
    echo "Mirror settings:"
    echo "  Enable mirrors: $ENABLE_MIRRORS"
    if [[ "$ENABLE_MIRRORS" == "true" ]]; then
        echo "  Primary mirror: $MIRROR_URL"
        echo "  Backup mirrors: $BACKUP_MIRRORS"
    fi
    echo ""
    echo "Package settings:"
    echo "  Update cache: $UPDATE_CACHE"
    echo "  Retry count: $RETRY_COUNT"
    echo "  Operation timeout: ${CACHE_TIMEOUT}s"
    echo "  Ubuntu version: ${UBUNTU_VERSION:-auto-detect}"
    echo "  Verbose logging: $VERBOSE"
    echo "  Dry run: $DRY_RUN"
    echo ""
    echo "Packages to install:"
    if [[ -n "$PACKAGES" ]]; then
        echo "  Base: $PACKAGES"
    else
        echo "  Base: (none specified)"
    fi
    if [[ -n "$EXTRA_PACKAGES" ]]; then
        echo "  Extra: $EXTRA_PACKAGES"
    else
        echo "  Extra: (none specified)"
    fi
    echo "======================================"
}

# Detect Ubuntu version
detect_ubuntu_version() {
    log_verbose "Detecting Ubuntu version..."
    
    if [[ -n "$UBUNTU_VERSION" ]]; then
        UBUNTU_CODENAME="$UBUNTU_VERSION"
        log_info "Using provided Ubuntu codename: $UBUNTU_CODENAME"
    else
        # Auto-detect Ubuntu codename
        UBUNTU_CODENAME=$(lsb_release -sc 2>/dev/null || grep VERSION_CODENAME /etc/os-release | cut -d= -f2 | tr -d '"' || echo "noble")
        log_info "Auto-detected Ubuntu codename: $UBUNTU_CODENAME"
    fi
}

# Configure Ubuntu mirrors
configure_mirrors() {
    if [[ "$ENABLE_MIRRORS" != "true" ]]; then
        log_info "Mirror configuration disabled, skipping..."
        MIRROR_CONFIGURED="disabled"
        return 0
    fi

    log_info "🌍 Configuring Ubuntu mirrors for faster downloads..."
    log_verbose "Primary mirror: $MIRROR_URL"
    log_verbose "Ubuntu codename: $UBUNTU_CODENAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure mirrors with primary: $MIRROR_URL"
        MIRROR_CONFIGURED="dry-run"
        return 0
    fi

    # Backup original sources
    if [[ -f /etc/apt/sources.list ]]; then
        cp /etc/apt/sources.list /etc/apt/sources.list.backup
        log_verbose "Backed up original sources.list"
    fi
    
    # Remove trailing slash if present
    local clean_mirror_url
    clean_mirror_url=$(echo "$MIRROR_URL" | sed 's|/$||')
    
    # Create optimized sources.list with primary mirror
    cat > /etc/apt/sources.list << EOF
# Ubuntu Mirror Configuration - Generated by setup-ubuntu-packages script
# Primary mirror: $clean_mirror_url (optimized for CI efficiency)

# Main repository - prioritize main and universe (most CI packages)
deb $clean_mirror_url $UBUNTU_CODENAME main universe
deb $clean_mirror_url $UBUNTU_CODENAME-updates main universe

# Additional components only if needed
deb $clean_mirror_url $UBUNTU_CODENAME restricted multiverse
deb $clean_mirror_url $UBUNTU_CODENAME-updates restricted multiverse

# Security updates (use same mirror for reliability)
deb $clean_mirror_url $UBUNTU_CODENAME-security main restricted universe multiverse

# Skip backports by default (can be uncommented if needed)
# deb $clean_mirror_url $UBUNTU_CODENAME-backports main restricted universe multiverse
EOF
    
    # Fast path: trust the mirror is working initially
    log_verbose "Mirror configured: $clean_mirror_url"
    MIRROR_CONFIGURED="true"
    
    # Show configured sources for verification
    log_verbose "Configured package sources:"
    if [[ "$VERBOSE" == "true" ]]; then
        grep -E '^deb ' /etc/apt/sources.list | head -5
    fi
}

# Install ca-certificates (if needed)
install_ca_certificates() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_verbose "[DRY RUN] Would ensure ca-certificates are installed"
        return 0
    fi
    
    # Check if ca-certificates are already installed
    if dpkg -l ca-certificates 2>/dev/null | grep -q "^ii"; then
        log_verbose "ca-certificates already installed"
        return 0
    fi
    
    log_info "🔐 Installing ca-certificates..."
    
    # Set environment for non-interactive installation
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none
    
    # Simple install - most modern Ubuntu images have HTTPS support
    apt-get install -yqq --no-install-recommends ca-certificates || {
        log_warning "ca-certificates installation failed, but continuing..."
    }
}

# Update package cache
update_package_cache() {
    if [[ "$UPDATE_CACHE" != "true" ]]; then
        log_info "Package cache update disabled, skipping..."
        return 0
    fi

    log_info "📦 Updating package cache (optimized for CI)..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update package cache"
        return 0
    fi
    
    # Set efficient apt configuration for CI
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none
    
    # Configure apt for faster CI operations
    cat > /etc/apt/apt.conf.d/99ci-optimizations << 'EOF'
// CI Optimizations - Faster package operations
Acquire::Languages "none";
Acquire::GzipIndexes "true";
Acquire::CompressionTypes::Order:: "gz";
APT::Get::Assume-Yes "true";
APT::Get::Install-Recommends "false";
APT::Get::Install-Suggests "false";
APT::Get::Show-Upgraded "false";
DPkg::Use-Pty "0";
quiet "2";
EOF
    
    # Fast path: try update once, fallback to backup mirrors if it fails
    log_verbose "Updating package cache..."
    if timeout "$CACHE_TIMEOUT" apt-get update -qq; then
        log_success "Package cache updated successfully"
    else
        log_warning "Primary mirror failed, trying backup mirrors..."
        
        # Slow path: switch to backup mirrors
        cat > /etc/apt/sources.list << EOF
# Backup Ubuntu mirrors - primary mirror failed
$(for mirror in "${BACKUP_MIRRORS[@]}"; do
    echo "deb $mirror $UBUNTU_CODENAME main restricted universe multiverse"
    echo "deb $mirror $UBUNTU_CODENAME-updates main restricted universe multiverse"
    echo "deb $mirror $UBUNTU_CODENAME-security main restricted universe multiverse"
done)
EOF
        
        # Retry update with backup mirrors
        if timeout "$CACHE_TIMEOUT" apt-get update -qq; then
            log_success "Package cache updated using backup mirrors"
            MIRROR_CONFIGURED="fallback"
        else
            log_error "All mirrors failed"
            return 1
        fi
    fi
}

# Process package lists (handles both space-separated and comma-separated)
process_packages() {
    local input="$1"
    
    if [[ -z "$input" ]]; then
        return 0
    fi
    
    # Convert comma-separated to space-separated and normalize
    echo "$input" | tr ',' ' ' | tr '\n' ' ' | xargs
}

# Install packages
install_packages() {
    log_info "📦 Installing Ubuntu packages..."
    
    # Process base packages
    local base_packages
    base_packages=$(process_packages "$PACKAGES")
    
    # Process extra packages
    local extra_packages
    extra_packages=$(process_packages "$EXTRA_PACKAGES")
    
    # Combine packages
    local all_packages
    all_packages="$base_packages $extra_packages"
    
    # Remove duplicates and empty entries
    all_packages=$(echo "$all_packages" | tr ' ' '\n' | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | xargs)
    
    if [[ -z "$all_packages" ]]; then
        log_warning "No packages specified for installation"
        PACKAGES_INSTALLED=""
        return 0
    fi
    
    log_verbose "Installing packages: $all_packages"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would install packages: $all_packages"
        PACKAGES_INSTALLED="dry-run: $all_packages"
        return 0
    fi
    
    # Set optimized environment for package installation
    export DEBIAN_FRONTEND=noninteractive
    export APT_LISTCHANGES_FRONTEND=none
    
    # Fast path: try installation once, retry with fallbacks if it fails
    log_verbose "Installing packages: $all_packages"
    if timeout "$CACHE_TIMEOUT" apt-get install -yqq --no-install-recommends $all_packages; then
        log_success "Packages installed successfully"
        PACKAGES_INSTALLED="$all_packages"
    else
        log_warning "Package installation failed, trying with retries..."
        
        # Slow path: retry with cache refresh
        for attempt in $(seq 1 "$RETRY_COUNT"); do
            log_verbose "Retry attempt $attempt of $RETRY_COUNT..."
            
            # Refresh cache and try again
            apt-get update -qq || true
            if timeout "$CACHE_TIMEOUT" apt-get install -yqq --no-install-recommends $all_packages; then
                log_success "Packages installed successfully on retry $attempt"
                PACKAGES_INSTALLED="$all_packages"
                return 0
            fi
            
            if [[ $attempt -lt $RETRY_COUNT ]]; then
                sleep 2
            fi
        done
        
        log_error "Package installation failed after all retries"
        return 1
    fi
}

# Quick verification (only if verbose mode - non-blocking)
verify_installation() {
    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi
    
    # Skip verification unless verbose mode - trust apt's exit code
    if [[ "$VERBOSE" != "true" ]]; then
        log_verbose "Skipping package verification (use VERBOSE=true to enable)"
        return 0
    fi
    
    log_verbose "🔍 Verifying installed packages..."
    
    # Process packages the same way as installation
    local base_packages
    base_packages=$(process_packages "$PACKAGES")
    
    local extra_packages
    extra_packages=$(process_packages "$EXTRA_PACKAGES")
    
    local all_packages
    all_packages="$base_packages $extra_packages"
    all_packages=$(echo "$all_packages" | tr ' ' '\n' | grep -v '^[[:space:]]*$' | sort -u | tr '\n' ' ' | xargs)
    
    if [[ -z "$all_packages" ]]; then
        return 0
    fi
    
    local failed_count=0
    local installed_count=0
    
    for package in $all_packages; do
        # Check if package is installed (handle virtual packages and exact matches)
        if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"; then
            log_verbose "$package: ✅ installed"
            ((installed_count++))
        else
            # Try alternative check for partial matches
            if dpkg -l "*$package*" 2>/dev/null | grep -q "^ii"; then
                log_verbose "$package: ✅ installed (variant)"
                ((installed_count++))
            else
                log_verbose "$package: ❌ not found"
                ((failed_count++))
            fi
        fi
    done
    
    if [[ $failed_count -gt 0 ]]; then
        log_verbose "$failed_count packages not verified, $installed_count verified (some might be virtual packages)"
    else
        log_verbose "All $installed_count packages verified successfully"
    fi
}

# Export outputs for GitHub Actions
export_github_outputs() {
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "configured=${MIRROR_CONFIGURED:-disabled}" >> "$GITHUB_OUTPUT"
        echo "installed=${PACKAGES_INSTALLED:-}" >> "$GITHUB_OUTPUT"
        echo "codename=${UBUNTU_CODENAME:-}" >> "$GITHUB_OUTPUT"
    fi
}

# Show summary
show_summary() {
    log_info "📊 Package Installation Summary"
    echo "================================"
    echo "Ubuntu version: $UBUNTU_CODENAME"
    echo "Mirror configured: ${MIRROR_CONFIGURED:-disabled}"
    echo "Packages requested: $PACKAGES $EXTRA_PACKAGES"
    echo "Packages installed: $PACKAGES_INSTALLED"
    echo "Dry run mode: $DRY_RUN"
    echo "================================"
}

# Main execution function
main() {
    # Check for help request
    if [[ $# -gt 0 && ("$1" == "--help" || "$1" == "-h") ]]; then
        show_usage
        exit 0
    fi
    
    # Reject any other arguments
    if [[ $# -gt 0 ]]; then
        log_error "This script uses environment variables for configuration. Use --help for details."
        exit 1
    fi
    
    validate_configuration
    
    # Show configuration
    show_configuration
    
    # Execute steps
    detect_ubuntu_version
    configure_mirrors
    install_ca_certificates
    update_package_cache
    install_packages
    verify_installation
    export_github_outputs
    show_summary
    
    # Exit with success if we reach here
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed successfully"
    else
        log_success "Setup completed successfully"
    fi
}

# Execute main function with all arguments
main "$@"