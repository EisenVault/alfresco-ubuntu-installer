#!/bin/bash
# =============================================================================
# Alfresco Elasticsearch Batch Indexing Installation Script
# =============================================================================
# Installs the Alfresco Elasticsearch Batch Indexing application (a standalone
# Spring Boot fat JAR) as a systemd service. It continuously reindexes the
# Alfresco repository into OpenSearch by polling the repository database.
# Used only when SEARCH_BACKEND=opensearch (Alfresco 26.2+).
#
# Prerequisites:
# - Run 00-generate-config.sh first (profile with SEARCH_BACKEND=opensearch)
# - Run 02-install_java.sh to install Java
# - Run 05-download_alfresco_resources.sh to download the distribution ZIP
# - Run 06-install_alfresco.sh and 07-DO-NOT-USE-install_opensearch.sh
# - Ubuntu 22.04, 24.04 or 26.04
# - sudo privileges
#
# Usage:
#   bash scripts/07b-DO-NOT-USE-install_batch_indexer.sh
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
    log_step "Starting Alfresco Batch Indexer installation..."

    # Pre-flight checks
    check_root
    check_sudo
    load_config

    if [ "${SEARCH_BACKEND:-solr}" != "opensearch" ]; then
        log_error "SEARCH_BACKEND is '${SEARCH_BACKEND:-solr}', not 'opensearch'."
        log_error "The batch-indexer is only used with the OpenSearch backend."
        exit 1
    fi

    check_prerequisites unzip

    # Detect architecture for JAVA_HOME
    detect_architecture

    # Verify prerequisites
    verify_prerequisites

    # Install and configure
    extract_batch_indexer
    create_systemd_service

    # Set permissions
    set_permissions

    # Enable service
    enable_service

    # Verify installation
    verify_installation

    log_info "Alfresco Batch Indexer installation completed successfully!"
}

# -----------------------------------------------------------------------------
# Detect System Architecture (for JAVA_HOME)
# -----------------------------------------------------------------------------
detect_architecture() {
    log_step "Detecting system architecture..."

    ARCH=$(dpkg --print-architecture)

    case "$ARCH" in
        amd64)
            JAVA_ARCH="amd64"
            ;;
        arm64)
            JAVA_ARCH="arm64"
            ;;
        *)
            log_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    JAVA_HOME_PATH="/usr/lib/jvm/java-${JAVA_VERSION}-openjdk-${JAVA_ARCH}"

    if [ ! -d "$JAVA_HOME_PATH" ]; then
        log_error "JAVA_HOME not found: $JAVA_HOME_PATH"
        log_error "Please run 02-install_java.sh first"
        exit 1
    fi

    log_info "Using JAVA_HOME: $JAVA_HOME_PATH"
}

# -----------------------------------------------------------------------------
# Verify Prerequisites
# -----------------------------------------------------------------------------
verify_prerequisites() {
    log_step "Verifying prerequisites..."

    local errors=0

    local dist_file
    dist_file=$(find "$DOWNLOAD_DIR" -name "alfresco-elasticsearch-batch-indexing-distribution-*.zip" 2>/dev/null | head -1)

    if [ -z "$dist_file" ] || [ ! -f "$dist_file" ]; then
        log_error "Batch indexer distribution not found in $DOWNLOAD_DIR"
        log_error "Please run 05-download_alfresco_resources.sh first"
        ((errors++))
    else
        log_info "Found: $(basename "$dist_file")"
    fi

    if [ $errors -gt 0 ]; then
        log_error "Prerequisites check failed"
        exit 1
    fi

    log_info "All prerequisites verified"
}

# -----------------------------------------------------------------------------
# Extract Batch Indexer
# -----------------------------------------------------------------------------
extract_batch_indexer() {
    log_step "Extracting Batch Indexer..."

    local bi_home="${ALFRESCO_HOME}/batch-indexer"
    local dist_file
    dist_file=$(find "$DOWNLOAD_DIR" -name "alfresco-elasticsearch-batch-indexing-distribution-*.zip" | head -1)

    # Check if already installed
    if [ -d "$bi_home" ] && find "$bi_home" -maxdepth 1 -name "*-app.jar" | grep -q .; then
        log_info "Batch Indexer already installed at $bi_home"
        return 0
    fi

    local temp_dir="/tmp/batch-indexer-install"
    rm -rf "$temp_dir"
    mkdir -p "$temp_dir"

    log_info "Extracting $(basename "$dist_file")..."
    unzip -q "$dist_file" -d "$temp_dir"

    mkdir -p "$bi_home"

    # The distribution ZIP contains the fat jar at its root (no base directory).
    local app_jar
    app_jar=$(find "$temp_dir" -name "alfresco-elasticsearch-batch-indexing-*-app.jar" | head -1)

    if [ -z "$app_jar" ]; then
        log_error "Batch indexer application jar not found in distribution"
        rm -rf "$temp_dir"
        exit 1
    fi

    cp "$app_jar" "$bi_home/app.jar"
    # Preserve README/licenses for reference if present
    find "$temp_dir" -maxdepth 2 -name "README.md" -exec cp {} "$bi_home/" \; 2>/dev/null || true

    rm -rf "$temp_dir"

    log_info "Installed application jar to: $bi_home/app.jar"
}

# -----------------------------------------------------------------------------
# Create Systemd Service
# -----------------------------------------------------------------------------
create_systemd_service() {
    log_step "Creating Batch Indexer systemd service..."

    local service_file="/etc/systemd/system/batch-indexer.service"
    local bi_home="${ALFRESCO_HOME}/batch-indexer"

    calculate_memory_allocation

    if [ -f "$service_file" ]; then
        log_info "Batch Indexer service file already exists, updating..."
        backup_file "$service_file"
    fi

    # The batch-indexer needs the repository up (it calls the text-extraction
    # endpoint) and OpenSearch up (it writes the index). SERVER_PORT overrides
    # the Spring Boot default of 8080, which collides with Tomcat.
    cat << EOF | sudo tee "$service_file" > /dev/null
[Unit]
Description=Alfresco Elasticsearch Batch Indexing
Documentation=https://github.com/Alfresco/alfresco-elasticsearch-connector
After=network.target tomcat.service opensearch.service
Requires=tomcat.service

[Service]
Type=simple
User=${ALFRESCO_USER}
Group=${ALFRESCO_GROUP}

Environment="JAVA_HOME=${JAVA_HOME_PATH}"
Environment="JAVA_OPTS=-Xms${MEM_BATCH_INDEXER}m -Xmx${MEM_BATCH_INDEXER}m"

# Repository database (indexer reads metadata directly; SELECT-only is enough)
Environment="SPRING_DATASOURCE_URL=jdbc:postgresql://${ALFRESCO_DB_HOST}:${ALFRESCO_DB_PORT}/${ALFRESCO_DB_NAME}"
Environment="SPRING_DATASOURCE_USERNAME=${ALFRESCO_DB_USER}"
Environment="SPRING_DATASOURCE_PASSWORD=${ALFRESCO_DB_PASSWORD}"

# OpenSearch endpoint
Environment="SPRING_ELASTICSEARCH_REST_URIS=http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}"

# Alfresco repository and transform endpoints
Environment="ALFRESCO_ACS_URL=http://${ALFRESCO_HOST}:${ALFRESCO_PORT}"
Environment="ALFRESCO_ACCEPTEDCONTENTMEDIATYPESCACHE_BASEURL=http://${TRANSFORM_HOST}:${TRANSFORM_PORT}/transform/config"

# Shared secret with the repository text-extraction endpoint
Environment="ALFRESCO_CONTENT_TRANSFORM_SHAREDSECRET=${SOLR_SHARED_SECRET}"

# Actuator/HTTP port (Spring Boot default 8080 collides with Tomcat)
Environment="SERVER_PORT=${BATCH_INDEXER_PORT}"

ExecStart=${JAVA_HOME_PATH}/bin/java \$JAVA_OPTS -jar ${bi_home}/app.jar

# Restart on failure
Restart=on-failure
RestartSec=15

# Security hardening
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

    sudo chmod 644 "$service_file"

    log_info "Reloading systemd daemon..."
    sudo systemctl daemon-reload

    log_info "Systemd service created with heap: ${MEM_BATCH_INDEXER}m"
}

# -----------------------------------------------------------------------------
# Set Permissions
# -----------------------------------------------------------------------------
set_permissions() {
    log_step "Setting file permissions..."

    local bi_home="${ALFRESCO_HOME}/batch-indexer"

    sudo chown -R "${ALFRESCO_USER}:${ALFRESCO_GROUP}" "$bi_home"

    log_info "Permissions configured"
}

# -----------------------------------------------------------------------------
# Enable Service
# -----------------------------------------------------------------------------
enable_service() {
    log_step "Enabling Batch Indexer service..."

    sudo systemctl enable batch-indexer

    log_info "Batch Indexer service enabled on boot"
}

# -----------------------------------------------------------------------------
# Verify Installation
# -----------------------------------------------------------------------------
verify_installation() {
    log_step "Verifying Batch Indexer installation..."

    local bi_home="${ALFRESCO_HOME}/batch-indexer"
    local errors=0

    if [ -f "$bi_home/app.jar" ]; then
        log_info "Application jar exists: $bi_home/app.jar"
    else
        log_error "Application jar not found: $bi_home/app.jar"
        ((errors++))
    fi

    if [ -f "/etc/systemd/system/batch-indexer.service" ]; then
        log_info "Systemd service file exists"
    else
        log_error "Systemd service file missing"
        ((errors++))
    fi

    if systemctl is-enabled --quiet batch-indexer 2>/dev/null; then
        log_info "Batch Indexer service is enabled"
    else
        log_error "Batch Indexer service is not enabled"
        ((errors++))
    fi

    if [ $errors -gt 0 ]; then
        log_error "Verification failed with $errors error(s)"
        exit 1
    fi

    log_info ""
    log_info "Batch Indexer installation summary:"
    log_info "  Home:          $bi_home"
    log_info "  Actuator:      http://localhost:${BATCH_INDEXER_PORT}/actuator/health"
    log_info "  OpenSearch:    http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}"
    log_info ""
    log_info "To check indexing (after starting):"
    log_info "  curl http://localhost:${BATCH_INDEXER_PORT}/actuator/health"
    log_info "  curl http://${OPENSEARCH_HOST}:${OPENSEARCH_PORT}/_cat/indices?v"
    log_info ""
    log_info "All verifications passed"
}

# -----------------------------------------------------------------------------
# Run Main
# -----------------------------------------------------------------------------
main "$@"
