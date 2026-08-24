#!/bin/bash
# =============================================================================
# Install Alfresco Management Scripts
# =============================================================================
# Installs self-contained copies of the start, stop, and backup scripts in the
# Alfresco home. The matching runtime configuration is copied with them so
# they remain usable even if the installer checkout is later moved or removed.
#
# Usage:
#   bash scripts/16-install_management_scripts.sh
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${SCRIPT_DIR}/common.sh"

main() {
    log_step "Installing Alfresco management scripts..."
    check_sudo
    load_config

    local destination_scripts="${ALFRESCO_HOME}/scripts"
    local destination_config="${ALFRESCO_HOME}/config"
    local script

    sudo install -d -o "${ALFRESCO_USER}" -g "${ALFRESCO_GROUP}" -m 755 \
        "${destination_scripts}" "${destination_config}"

    # common.sh resolves ../config relative to these copied scripts.
    for script in common.sh 11-start_services.sh 12-stop_services.sh 13-backup.sh; do
        sudo install -o "${ALFRESCO_USER}" -g "${ALFRESCO_GROUP}" -m 755 \
            "${SCRIPT_DIR}/${script}" "${destination_scripts}/${script}"
    done

    sudo install -o "${ALFRESCO_USER}" -g "${ALFRESCO_GROUP}" -m 600 \
        "${CONFIG_DIR}/alfresco.env" "${destination_config}/alfresco.env"
    sudo install -o "${ALFRESCO_USER}" -g "${ALFRESCO_GROUP}" -m 644 \
        "${CONFIG_DIR}/versions.conf" "${destination_config}/versions.conf"

    log_info "Management scripts installed in: ${destination_scripts}"
    log_info "  Start:  ${destination_scripts}/11-start_services.sh"
    log_info "  Stop:   ${destination_scripts}/12-stop_services.sh"
    log_info "  Backup: ${destination_scripts}/13-backup.sh"
    log_warn "Rerun this step after changing config/alfresco.env in the installer checkout."
}

main "$@"
