#!/bin/bash
# =============================================================================
# Security Scanning Dependencies Installation Script
# =============================================================================
# Installs the OS dependencies used by EisenVault's ClamAV and XSS scan scripts.
#
# Usage:
#   bash scripts/17-install_security_scanning.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

install_dependencies() {
    log_step "Installing security scanning dependencies..."

    sudo apt-get update
    sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
        binutils \
        clamav-daemon \
        clamav-freshclam \
        poppler-utils
}

enable_clamav() {
    log_step "Enabling ClamAV daemon..."

    sudo systemctl enable clamav-daemon
    sudo systemctl enable clamav-freshclam
    sudo systemctl restart clamav-freshclam
    sudo systemctl restart clamav-daemon

    if ! sudo systemctl is-active --quiet clamav-daemon; then
        log_error "clamav-daemon did not start. Check: sudo systemctl status clamav-daemon"
        exit 1
    fi

    if ! sudo systemctl is-active --quiet clamav-freshclam; then
        log_error "clamav-freshclam did not start. Check: sudo systemctl status clamav-freshclam"
        exit 1
    fi
}

verify_dependencies() {
    log_step "Verifying security scanning dependencies..."

    local missing=0
    for command_name in clamdscan clamd timeout file pdftotext unzip strings; do
        if command -v "$command_name" >/dev/null 2>&1; then
            log_info "Found $command_name: $(command -v "$command_name")"
        else
            log_error "Required command is unavailable: $command_name"
            missing=1
        fi
    done

    if [ "$missing" -ne 0 ]; then
        exit 1
    fi

    log_info "Security scanning dependencies are ready."
}

main() {
    check_sudo
    install_dependencies
    enable_clamav
    verify_dependencies
}

main "$@"
