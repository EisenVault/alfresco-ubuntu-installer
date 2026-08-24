#!/bin/bash
# =============================================================================
# Alfresco Resources Download Script
# =============================================================================
# Downloads Alfresco distribution packages from Nexus repository.
#
# Components downloaded:
# - Alfresco Content Services Community Distribution (ZIP)
# - Standalone Share WAR (only when SHARE_VERSION is set; overrides bundled)
# - Alfresco Search Services (ZIP)
# - Alfresco Transform Core AIO (JAR)
#
# Prerequisites:
# - Run 00-generate-config.sh first to create configuration
# - Internet connectivity to nexus.alfresco.com
#
# Usage:
#   bash scripts/05-download_alfresco_resources.sh
# =============================================================================

# Load common functions and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
NEXUS_BASE_URL="https://nexus.alfresco.com/nexus"
NEXUS_BROWSE_URL="${NEXUS_BASE_URL}/service/rest/repository/browse/releases/org/alfresco"
NEXUS_DOWNLOAD_URL="${NEXUS_BASE_URL}/repository/releases/org/alfresco"

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    log_step "Starting Alfresco resources download..."
    
    # Pre-flight checks
    load_config
    install_archive_utilities
    check_prerequisites curl unzip
    
    # Determine versions
    determine_versions
    
    # Create download directory
    create_download_directory
    
    # Download components
    download_alfresco_distribution
    if [ -n "${SHARE_VERSION:-}" ]; then
        download_share_war
    fi
    if [ "${SEARCH_BACKEND:-solr}" = "opensearch" ]; then
        download_opensearch
        download_batch_indexer
    else
        download_search_services
    fi
    download_transform_core
    
    # Verify downloads
    verify_downloads
    
    log_info "All Alfresco resources downloaded successfully!"
}

# -----------------------------------------------------------------------------
# Archive Utilities
# -----------------------------------------------------------------------------
install_archive_utilities() {
    local packages=()

    command -v zip >/dev/null 2>&1 || packages+=(zip)
    command -v unzip >/dev/null 2>&1 || packages+=(unzip)

    if [ "${#packages[@]}" -eq 0 ]; then
        log_info "ZIP utilities are already installed"
        return
    fi

    check_sudo
    log_step "Installing required archive utilities: ${packages[*]}"
    sudo apt-get update
    sudo apt-get install -y "${packages[@]}"
}

# -----------------------------------------------------------------------------
# Determine Versions
# -----------------------------------------------------------------------------
determine_versions() {
    log_step "Determining component versions..."
    
    if [ "${USE_LATEST_VERSIONS:-false}" = "true" ]; then
        log_warn "USE_LATEST_VERSIONS is enabled - fetching latest versions..."
        
        ALFRESCO_VERSION_ACTUAL=$(fetch_latest_nexus_version "alfresco-content-services-community-distribution" "${ALFRESCO_VERSION%.*}")
        ALFRESCO_SEARCH_VERSION_ACTUAL=$(fetch_latest_nexus_version "alfresco-search-services" "${ALFRESCO_SEARCH_VERSION%.*}")
        ALFRESCO_TRANSFORM_VERSION_ACTUAL=$(fetch_latest_nexus_version "alfresco-transform-core-aio" "${ALFRESCO_TRANSFORM_VERSION%.*}")
        
        # Fall back to pinned versions if fetch fails
        ALFRESCO_VERSION_ACTUAL="${ALFRESCO_VERSION_ACTUAL:-$ALFRESCO_VERSION}"
        ALFRESCO_SEARCH_VERSION_ACTUAL="${ALFRESCO_SEARCH_VERSION_ACTUAL:-$ALFRESCO_SEARCH_VERSION}"
        ALFRESCO_TRANSFORM_VERSION_ACTUAL="${ALFRESCO_TRANSFORM_VERSION_ACTUAL:-$ALFRESCO_TRANSFORM_VERSION}"
    else
        ALFRESCO_VERSION_ACTUAL="$ALFRESCO_VERSION"
        ALFRESCO_SEARCH_VERSION_ACTUAL="$ALFRESCO_SEARCH_VERSION"
        ALFRESCO_TRANSFORM_VERSION_ACTUAL="$ALFRESCO_TRANSFORM_VERSION"
    fi
    
    log_info "Alfresco Content Services: ${ALFRESCO_VERSION_ACTUAL}"
    if [ -n "${SHARE_VERSION:-}" ]; then
        log_info "Share (standalone WAR):    ${SHARE_VERSION}"
    fi
    if [ "${SEARCH_BACKEND:-solr}" = "opensearch" ]; then
        log_info "Search backend:            OpenSearch ${OPENSEARCH_VERSION}"
        log_info "Batch Indexer:             ${BATCH_INDEXER_VERSION}"
    else
        log_info "Alfresco Search Services:  ${ALFRESCO_SEARCH_VERSION_ACTUAL}"
    fi
    log_info "Alfresco Transform Core:   ${ALFRESCO_TRANSFORM_VERSION_ACTUAL}"
}

# -----------------------------------------------------------------------------
# Fetch Latest Version from Nexus
# -----------------------------------------------------------------------------
fetch_latest_nexus_version() {
    local artifact=$1
    local version_series=${2:-}
    local browse_url="${NEXUS_BROWSE_URL}/${artifact}/"

    local versions
    versions=$(curl -s "$browse_url" \
        | sed -n 's/.*<a href="\(.*\)\/">.*/\1/p' \
        | grep -E '^[0-9]+(\.[0-9]+)*$' \
        || true)

    # A profile defines a compatibility series, e.g. 26.1 or 5.4. Do not
    # silently upgrade to a different Alfresco/component release line.
    if [ -n "$version_series" ]; then
        local escaped_series=${version_series//./\\.}
        versions=$(printf '%s\n' "$versions" | grep -E "^${escaped_series}\\.[0-9]+$" || true)
    fi

    printf '%s\n' "$versions" | sort -V | tail -n 1
}

# -----------------------------------------------------------------------------
# Create Download Directory
# -----------------------------------------------------------------------------
create_download_directory() {
    log_step "Creating download directory..."
    
    DOWNLOAD_DIR="${SCRIPT_DIR}/../downloads"
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        mkdir -p "$DOWNLOAD_DIR"
        log_info "Created directory: $DOWNLOAD_DIR"
    else
        log_info "Download directory exists: $DOWNLOAD_DIR"
    fi
}

# -----------------------------------------------------------------------------
# Download File with Progress
# -----------------------------------------------------------------------------
download_file() {
    local url=$1
    local dest_file=$2
    local description=$3
    
    local filename
    filename=$(basename "$dest_file")
    
    # Check if file already exists and is valid
    if [ -f "$dest_file" ] && [ -s "$dest_file" ]; then
        log_info "Already downloaded: $filename"
        return 0
    fi
    
    log_info "Downloading $description..."
    log_info "  URL: $url"
    log_info "  Destination: $dest_file"
    
    # Download with progress bar
    local http_code
    http_code=$(curl -L \
        --progress-bar \
        --output "$dest_file" \
        --write-out "%{http_code}" \
        "$url")
    
    # Check HTTP status
    if [ "$http_code" -ne 200 ]; then
        log_error "Download failed with HTTP status: $http_code"
        rm -f "$dest_file"
        return 1
    fi
    
    # Verify file is not empty
    if [ ! -s "$dest_file" ]; then
        log_error "Downloaded file is empty: $filename"
        rm -f "$dest_file"
        return 1
    fi
    
    # Display file size
    local file_size
    file_size=$(du -h "$dest_file" | cut -f1)
    log_info "Downloaded: $filename ($file_size)"
    
    return 0
}

# -----------------------------------------------------------------------------
# Download Alfresco Content Services Distribution
# -----------------------------------------------------------------------------
download_alfresco_distribution() {
    log_step "Downloading Alfresco Content Services Community Distribution..."
    
    local artifact="alfresco-content-services-community-distribution"
    local version="$ALFRESCO_VERSION_ACTUAL"
    local filename="${artifact}-${version}.zip"
    local url="${NEXUS_DOWNLOAD_URL}/${artifact}/${version}/${filename}"
    local dest_file="${DOWNLOAD_DIR}/${filename}"
    
    if ! download_file "$url" "$dest_file" "Alfresco Content Services ${version}"; then
        log_error "Failed to download Alfresco Content Services"
        exit 1
    fi

    # File downloaded successfully
}

# -----------------------------------------------------------------------------
# Download standalone Share WAR
# -----------------------------------------------------------------------------
# Alfresco publishes Share as a standalone WAR at
# org/alfresco/share/<version>/share-<version>.war. When SHARE_VERSION is set
# (e.g. the 26.2 profile), this WAR overrides the share.war bundled in the ACS
# distribution, allowing Share to be patched independently of ACS. This is used
# to ship the secure 26.2.1 Share line over the insecure 26.2.0 bundled build.
download_share_war() {
    log_step "Downloading standalone Share WAR..."

    local artifact="share"
    local version="$SHARE_VERSION"
    local filename="share-${version}.war"
    local url="${NEXUS_DOWNLOAD_URL}/${artifact}/${version}/${filename}"
    local dest_file="${DOWNLOAD_DIR}/${filename}"

    if ! download_file "$url" "$dest_file" "Share ${version}"; then
        log_error "Failed to download standalone Share WAR"
        exit 1
    fi

    # File downloaded successfully
}

# -----------------------------------------------------------------------------
# Download Alfresco Search Services
# -----------------------------------------------------------------------------
download_search_services() {
    log_step "Downloading Alfresco Search Services..."
    
    local artifact="alfresco-search-services"
    local version="$ALFRESCO_SEARCH_VERSION_ACTUAL"
    local filename="${artifact}-${version}.zip"
    local url="${NEXUS_DOWNLOAD_URL}/${artifact}/${version}/${filename}"
    local dest_file="${DOWNLOAD_DIR}/${filename}"
    
    if ! download_file "$url" "$dest_file" "Alfresco Search Services ${version}"; then
        log_error "Failed to download Alfresco Search Services"
        exit 1
    fi
    
    # File downloaded successfully

}

# -----------------------------------------------------------------------------
# Download OpenSearch (Alfresco Search Community backend)
# -----------------------------------------------------------------------------
download_opensearch() {
    log_step "Downloading OpenSearch..."

    # Map dpkg architecture to OpenSearch tarball naming (x64 / arm64)
    local dpkg_arch os_arch
    dpkg_arch=$(dpkg --print-architecture)
    case "$dpkg_arch" in
        amd64) os_arch="x64" ;;
        arm64) os_arch="arm64" ;;
        *)
            log_error "Unsupported architecture for OpenSearch: $dpkg_arch"
            exit 1
            ;;
    esac

    local version="$OPENSEARCH_VERSION"
    local filename="opensearch-${version}-linux-${os_arch}.tar.gz"
    local url="https://artifacts.opensearch.org/releases/bundle/opensearch/${version}/${filename}"
    local dest_file="${DOWNLOAD_DIR}/${filename}"

    if ! download_file "$url" "$dest_file" "OpenSearch ${version} (${os_arch})"; then
        log_error "Failed to download OpenSearch"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Download Alfresco Elasticsearch Batch Indexing distribution
# -----------------------------------------------------------------------------
download_batch_indexer() {
    log_step "Downloading Alfresco Elasticsearch Batch Indexing..."

    local artifact="alfresco-elasticsearch-batch-indexing-distribution"
    local version="$BATCH_INDEXER_VERSION"
    local filename="${artifact}-${version}.zip"
    local url="${NEXUS_DOWNLOAD_URL}/${artifact}/${version}/${filename}"
    local dest_file="${DOWNLOAD_DIR}/${filename}"

    if ! download_file "$url" "$dest_file" "Batch Indexer ${version}"; then
        log_error "Failed to download Alfresco Elasticsearch Batch Indexing"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Download Alfresco Transform Core
# -----------------------------------------------------------------------------
download_transform_core() {
    log_step "Downloading Alfresco Transform Core..."
    
    local artifact="alfresco-transform-core-aio"
    local version="$ALFRESCO_TRANSFORM_VERSION_ACTUAL"
    local filename="${artifact}-${version}.jar"
    local url="${NEXUS_DOWNLOAD_URL}/${artifact}/${version}/${filename}"
    local dest_file="${DOWNLOAD_DIR}/${filename}"
    
    if ! download_file "$url" "$dest_file" "Alfresco Transform Core ${version}"; then
        log_error "Failed to download Alfresco Transform Core"
        exit 1
    fi
    
    # File downloaded successfully    
}

# -----------------------------------------------------------------------------
# Verify Downloads
# -----------------------------------------------------------------------------
verify_downloads() {
    log_step "Verifying downloaded files..."
    
    local errors=0
    
    # Define expected files (backend-specific search artifacts)
    local expected_files=(
        "${DOWNLOAD_DIR}/alfresco-content-services-community-distribution-${ALFRESCO_VERSION_ACTUAL}.zip"
        "${DOWNLOAD_DIR}/alfresco-transform-core-aio-${ALFRESCO_TRANSFORM_VERSION_ACTUAL}.jar"
    )

    if [ -n "${SHARE_VERSION:-}" ]; then
        expected_files+=(
            "${DOWNLOAD_DIR}/share-${SHARE_VERSION}.war"
        )
    fi

    if [ "${SEARCH_BACKEND:-solr}" = "opensearch" ]; then
        local os_arch
        case "$(dpkg --print-architecture)" in
            amd64) os_arch="x64" ;;
            arm64) os_arch="arm64" ;;
        esac
        expected_files+=(
            "${DOWNLOAD_DIR}/opensearch-${OPENSEARCH_VERSION}-linux-${os_arch}.tar.gz"
            "${DOWNLOAD_DIR}/alfresco-elasticsearch-batch-indexing-distribution-${BATCH_INDEXER_VERSION}.zip"
        )
    else
        expected_files+=(
            "${DOWNLOAD_DIR}/alfresco-search-services-${ALFRESCO_SEARCH_VERSION_ACTUAL}.zip"
        )
    fi

    for file in "${expected_files[@]}"; do
        if [ -f "$file" ] && [ -s "$file" ]; then
            local file_size
            file_size=$(du -h "$file" | cut -f1)
            log_info "$(basename "$file") ($file_size)"
        else
            log_error "Missing or empty: $(basename "$file")"
            ((errors++))
        fi
    done
    
    # Verify ZIP files are valid
    log_info ""
    log_info "Validating archive integrity..."
    
    for file in "${DOWNLOAD_DIR}"/*.zip; do
        if [ -f "$file" ]; then
            if unzip -t "$file" > /dev/null 2>&1; then
                log_info "Valid ZIP: $(basename "$file")"
            else
                log_error "Corrupt ZIP: $(basename "$file")"
                ((errors++))
            fi
        fi
    done
    
    # Verify JAR file is valid
    for file in "${DOWNLOAD_DIR}"/*.jar; do
        if [ -f "$file" ]; then
            if unzip -t "$file" > /dev/null 2>&1; then
                log_info "Valid JAR: $(basename "$file")"
            else
                log_error "Corrupt JAR: $(basename "$file")"
                ((errors++))
            fi
        fi
    done

    # Verify WAR file is valid (standalone Share WAR)
    for file in "${DOWNLOAD_DIR}"/*.war; do
        if [ -f "$file" ]; then
            if unzip -t "$file" > /dev/null 2>&1; then
                log_info "Valid WAR: $(basename "$file")"
            else
                log_error "Corrupt WAR: $(basename "$file")"
                ((errors++))
            fi
        fi
    done
    
    if [ $errors -gt 0 ]; then
        log_error "Verification failed with $errors error(s)"
        log_error "Try deleting the corrupt files and running this script again"
        exit 1
    fi
    
    # Create a manifest file for reference
    create_manifest
    
    log_info ""
    log_info "All downloads verified successfully"
}

# -----------------------------------------------------------------------------
# Create Download Manifest
# -----------------------------------------------------------------------------
create_manifest() {
    local manifest_file="${DOWNLOAD_DIR}/MANIFEST.txt"
    
    cat << EOF > "$manifest_file"
# Alfresco Resources Download Manifest
# Generated: $(date)
# 
# This file documents the versions of Alfresco components downloaded.
# Keep this file for reference during troubleshooting.

Alfresco Content Services: ${ALFRESCO_VERSION_ACTUAL}
$(if [ -n "${SHARE_VERSION:-}" ]; then echo "Share (override):          ${SHARE_VERSION}"; fi)
Search backend:            ${SEARCH_BACKEND:-solr}
$(if [ "${SEARCH_BACKEND:-solr}" = "opensearch" ]; then
    echo "OpenSearch:                ${OPENSEARCH_VERSION}"
    echo "Batch Indexer:             ${BATCH_INDEXER_VERSION}"
else
    echo "Alfresco Search Services:  ${ALFRESCO_SEARCH_VERSION_ACTUAL}"
fi)
Alfresco Transform Core:   ${ALFRESCO_TRANSFORM_VERSION_ACTUAL}

Files:
$(find "${DOWNLOAD_DIR}" -maxdepth 1 \( -name "*.zip" -o -name "*.jar" -o -name "*.war" -o -name "*.tar.gz" \) -exec ls -lh {} \; 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}')

Pinned versions from config/versions.conf:
  ALFRESCO_VERSION=${ALFRESCO_VERSION}
  SHARE_VERSION=${SHARE_VERSION:-}
  SEARCH_BACKEND=${SEARCH_BACKEND:-solr}
  ALFRESCO_SEARCH_VERSION=${ALFRESCO_SEARCH_VERSION}
  OPENSEARCH_VERSION=${OPENSEARCH_VERSION:-}
  BATCH_INDEXER_VERSION=${BATCH_INDEXER_VERSION:-}
  ALFRESCO_TRANSFORM_VERSION=${ALFRESCO_TRANSFORM_VERSION}
  USE_LATEST_VERSIONS=${USE_LATEST_VERSIONS:-false}
EOF
    
    log_info "Created manifest: $manifest_file"
}

# -----------------------------------------------------------------------------
# Run Main
# -----------------------------------------------------------------------------
main "$@"
