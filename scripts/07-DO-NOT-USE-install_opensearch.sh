#!/bin/bash
# =============================================================================
# OpenSearch Installation Script (Alfresco Search Community backend)
# =============================================================================
# Installs and configures OpenSearch as the search backend for Alfresco
# Content Services 26.2+. Used only when SEARCH_BACKEND=opensearch.
#
# The security plugin is DISABLED and OpenSearch is bound to localhost by
# default, matching the official Alfresco reference deployment. See README.md
# ("Enabling OpenSearch security") for production TLS/authentication setup.
#
# Prerequisites:
# - Run 00-generate-config.sh first (with a profile where SEARCH_BACKEND=opensearch)
# - Run 05-download_alfresco_resources.sh to download the OpenSearch tarball
# - Ubuntu 22.04, 24.04 or 26.04
# - sudo privileges
#
# Usage:
#   bash scripts/07-DO-NOT-USE-install_opensearch.sh
# =============================================================================

# Load common functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
DOWNLOAD_DIR="${SCRIPT_DIR}/../downloads"

# -----------------------------------------------------------------------------
# Main Installation
# -----------------------------------------------------------------------------
main() {
    log_step "Starting OpenSearch installation..."

    # Pre-flight checks
    check_root
    check_sudo
    load_config

    if [ "${SEARCH_BACKEND:-solr}" != "opensearch" ]; then
        log_error "SEARCH_BACKEND is '${SEARCH_BACKEND:-solr}', not 'opensearch'."
        log_error "This script is only for the OpenSearch backend (profile 26.2+)."
        log_error "For the Solr backend, run 07-install_solr.sh instead."
        exit 1
    fi

    check_prerequisites tar

    # Verify prerequisites
    verify_prerequisites

    # Install and configure OpenSearch
    extract_opensearch
    configure_opensearch
    create_systemd_service

    # Set permissions
    set_permissions

    # Enable service
    enable_service

    # Verify installation
    verify_installation

    log_info "OpenSearch installation completed successfully!"
}

# -----------------------------------------------------------------------------
# Verify Prerequisites
# -----------------------------------------------------------------------------
verify_prerequisites() {
    log_step "Verifying prerequisites..."

    local errors=0

    local os_file
    os_file=$(find "$DOWNLOAD_DIR" -name "opensearch-*-linux-*.tar.gz" 2>/dev/null | head -1)

    if [ -z "$os_file" ] || [ ! -f "$os_file" ]; then
        log_error "OpenSearch tarball not found in $DOWNLOAD_DIR"
        log_error "Please run 05-download_alfresco_resources.sh first"
        ((errors++))
    else
        log_info "Found: $(basename "$os_file")"
    fi

    if [ $errors -gt 0 ]; then
        log_error "Prerequisites check failed"
        exit 1
    fi

    log_info "All prerequisites verified"
}

# -----------------------------------------------------------------------------
# Extract OpenSearch
# -----------------------------------------------------------------------------
extract_opensearch() {
    log_step "Extracting OpenSearch..."

    local os_home="${ALFRESCO_HOME}/opensearch"
    local os_file
    os_file=$(find "$DOWNLOAD_DIR" -name "opensearch-*-linux-*.tar.gz" | head -1)

    # Check if already installed
    if [ -d "$os_home" ] && [ -f "$os_home/bin/opensearch" ]; then
        log_info "OpenSearch already installed at $os_home"
        return 0
    fi

    # Extract to temp location first
    local temp_dir="/tmp/opensearch-install"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    log_info "Extracting $(basename "$os_file")..."
    tar -xzf "$os_file" -C "$temp_dir"

    # The tarball extracts to a versioned directory (opensearch-<version>).
    # Use -mindepth 1 so find does not match the temp dir itself, whose name
    # ("opensearch-install") also matches the opensearch-* glob.
    local extracted_dir
    extracted_dir=$(find "$temp_dir" -mindepth 1 -maxdepth 1 -type d -name "opensearch-*" | head -1)

    if [ -n "$extracted_dir" ]; then
        mv "$extracted_dir" "$os_home"
    else
        log_error "Unexpected archive layout; opensearch-* directory not found"
        rm -rf "$temp_dir"
        exit 1
    fi

    rm -rf "$temp_dir"

    log_info "Extracted to: $os_home"
}

# -----------------------------------------------------------------------------
# Configure OpenSearch
# -----------------------------------------------------------------------------
configure_opensearch() {
    log_step "Configuring OpenSearch..."

    local os_home="${ALFRESCO_HOME}/opensearch"
    local config_file="$os_home/config/opensearch.yml"
    local data_dir="$os_home/data"
    local logs_dir="$os_home/logs"

    mkdir -p "$data_dir" "$logs_dir"

    if [ -f "$config_file" ]; then
        backup_file "$config_file"
    fi

    log_info "Writing opensearch.yml (security plugin disabled, bound to localhost)..."

    cat << EOF > "$config_file"
# =============================================================================
# OpenSearch Configuration - Alfresco Search Community
# Generated by Alfresco installer on $(date)
# =============================================================================
cluster.name: alfresco-search
node.name: alfresco-node-1

# Single-node development deployment
discovery.type: single-node

# Bind to localhost only. For remote/multi-node access, change network.host
# and enable the security plugin (see README.md).
network.host: 127.0.0.1
http.port: ${OPENSEARCH_PORT}

# Data and log locations
path.data: ${data_dir}
path.logs: ${logs_dir}

# Security plugin disabled to match the Alfresco reference deployment.
# Enable it with TLS/authentication for production (see README.md).
plugins.security.disabled: true
EOF

    chmod 600 "$config_file"

    # Configure heap via jvm.options.d drop-in (survives package upgrades)
    calculate_memory_allocation
    local jvm_dir="$os_home/config/jvm.options.d"
    mkdir -p "$jvm_dir"
    cat << EOF > "$jvm_dir/heap.options"
-Xms${MEM_OPENSEARCH}m
-Xmx${MEM_OPENSEARCH}m
EOF

    log_info "OpenSearch configured (heap: ${MEM_OPENSEARCH}m)"
}

# -----------------------------------------------------------------------------
# Create Systemd Service
# -----------------------------------------------------------------------------
create_systemd_service() {
    log_step "Creating OpenSearch systemd service..."

    local service_file="/etc/systemd/system/opensearch.service"
    local os_home="${ALFRESCO_HOME}/opensearch"

    if [ -f "$service_file" ]; then
        log_info "OpenSearch service file already exists, updating..."
        backup_file "$service_file"
    fi

    # OpenSearch refuses to run as root; runs as the install user.
    cat << EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=OpenSearch (Alfresco Search Community)
Documentation=https://opensearch.org/docs/
After=network.target

[Service]
Type=simple
User=${ALFRESCO_USER}
Group=${ALFRESCO_GROUP}

Environment="OPENSEARCH_HOME=${os_home}"
Environment="OPENSEARCH_PATH_CONF=${os_home}/config"

ExecStart=${os_home}/bin/opensearch

# Restart on failure
Restart=on-failure
RestartSec=10

# Resource limits recommended for OpenSearch
LimitNOFILE=65536
LimitNPROC=4096
LimitMEMLOCK=infinity
LimitAS=infinity
LimitFSIZE=infinity
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

    sudo chmod 644 "$service_file"

    log_info "Reloading systemd daemon..."
    sudo systemctl daemon-reload

    log_info "Systemd service created"
}

# -----------------------------------------------------------------------------
# Set Permissions
# -----------------------------------------------------------------------------
set_permissions() {
    log_step "Setting file permissions..."

    local os_home="${ALFRESCO_HOME}/opensearch"

    sudo chown -R "${ALFRESCO_USER}:${ALFRESCO_GROUP}" "$os_home"
    chmod +x "$os_home/bin/opensearch"

    log_info "Permissions configured"
}

# -----------------------------------------------------------------------------
# Enable Service
# -----------------------------------------------------------------------------
enable_service() {
    log_step "Enabling OpenSearch service..."

    sudo systemctl enable opensearch

    log_info "OpenSearch service enabled on boot"
}

# -----------------------------------------------------------------------------
# Verify Installation
# -----------------------------------------------------------------------------
verify_installation() {
    log_step "Verifying OpenSearch installation..."

    local os_home="${ALFRESCO_HOME}/opensearch"
    local errors=0

    if [ -d "$os_home" ]; then
        log_info "OpenSearch directory exists: $os_home"
    else
        log_error "OpenSearch directory not found: $os_home"
        ((errors++))
    fi

    local key_files=(
        "bin/opensearch"
        "config/opensearch.yml"
    )

    for file in "${key_files[@]}"; do
        if [ -f "$os_home/$file" ]; then
            log_info "Found: $file"
        else
            log_error "Missing: $file"
            ((errors++))
        fi
    done

    if [ -f "/etc/systemd/system/opensearch.service" ]; then
        log_info "Systemd service file exists"
    else
        log_error "Systemd service file missing"
        ((errors++))
    fi

    if systemctl is-enabled --quiet opensearch 2>/dev/null; then
        log_info "OpenSearch service is enabled"
    else
        log_error "OpenSearch service is not enabled"
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        log_error "Verification failed with $errors error(s)"
        exit 1
    fi

    log_info ""
    log_info "OpenSearch installation summary:"
    log_info "  OpenSearch Home: $os_home"
    log_info "  URL:             http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}"
    log_info "  Security plugin: disabled (localhost only)"
    log_info ""
    log_info "To test OpenSearch connectivity (after starting):"
    log_info "  curl http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cluster/health"
    log_info ""
    log_info "All verifications passed"
}

# -----------------------------------------------------------------------------
# Run Main
# -----------------------------------------------------------------------------
main "$@"
