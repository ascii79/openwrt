#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# Odoo 19 Community
# OCA Must-Have Modules Downloader
#
# Pure Bash
# No Python
# No Docker checks
# No Odoo module installation
#
# ============================================================

ODOO_VERSION="19.0"

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ============================================================
# Paths
# ============================================================

OCA_DIR="${BASE_DIR}/addons/OCA"

CONFIG_DIR="${BASE_DIR}/config"
ODOO_CONF="${CONFIG_DIR}/odoo.conf"

REPORT_DIR="${BASE_DIR}/oca-reports"
TMP_DIR="${BASE_DIR}/.oca-tmp"

LOG_FILE="${REPORT_DIR}/install.log"

# Odoo's built-in addons directory
ODOO_CORE_ADDONS="/usr/lib/python3/dist-packages/odoo/addons"

# ============================================================
# Official OCA Must-Have pages
# ============================================================

PAGES=(
    "https://www.odoo-community.org/list-of-must-have-oca-modules"
    "https://www.odoo-community.org/list-of-must-have-oca-accounting-modules"
    "https://www.odoo-community.org/list-of-must-have-sales-modules"
    "https://www.odoo-community.org/list-of-must-have-modules-for-purchases"
    "https://www.odoo-community.org/list-of-must-have-oca-stock-modules"
)

# ============================================================
# Reports
# ============================================================

ALL_MODULES="${REPORT_DIR}/all-modules.txt"
ALL_REPOS="${REPORT_DIR}/all-repositories.txt"

FOUND_MODULES="${REPORT_DIR}/modules-19.0.txt"
MISSING_MODULES="${REPORT_DIR}/modules-not-available-19.0.txt"

DOWNLOADED_REPOS="${REPORT_DIR}/repositories-downloaded.txt"
SKIPPED_REPOS="${REPORT_DIR}/repositories-skipped.txt"

# ============================================================
# Create directories
# ============================================================

mkdir -p \
    "${OCA_DIR}" \
    "${CONFIG_DIR}" \
    "${REPORT_DIR}" \
    "${TMP_DIR}"

touch "${LOG_FILE}"

# ============================================================
# Logging
# ============================================================

log()
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_FILE}"
}

die()
{
    log "ERROR: $*"
    exit 1
}

# ============================================================
# Cleanup
# ============================================================

cleanup()
{
    rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

# ============================================================
# Required commands
# ============================================================

for cmd in curl git grep sed awk sort tr find wc dirname basename; do

    if ! command -v "${cmd}" >/dev/null 2>&1; then
        die "Required command not found: ${cmd}"
    fi

done

# ============================================================
# Start
# ============================================================

log "============================================================"
log "Odoo ${ODOO_VERSION} - OCA Must-Have Downloader"
log "============================================================"

log "Base directory : ${BASE_DIR}"
log "OCA directory  : ${OCA_DIR}"
log "Odoo config    : ${ODOO_CONF}"
log ""

# ============================================================
# Fetch OCA pages
# ============================================================

log "============================================================"
log "Fetching OCA Must-Have pages"
log "============================================================"

PAGE_NUMBER=0

for URL in "${PAGES[@]}"; do

    PAGE_NUMBER=$((PAGE_NUMBER + 1))

    FILE="${TMP_DIR}/page-${PAGE_NUMBER}.html"

    log ""
    log "Fetching:"
    log "  ${URL}"

    if curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --retry 3 \
        --retry-delay 2 \
        --connect-timeout 30 \
        --max-time 120 \
        -A "Mozilla/5.0 OCA-Odoo19-Installer" \
        "${URL}" \
        -o "${FILE}"
    then

        SIZE="$(wc -c < "${FILE}")"

        if [[ "${SIZE}" -lt 1000 ]]; then
            die "Downloaded page appears invalid: ${URL}"
        fi

        log "  OK (${SIZE} bytes)"

    else

        die "Could not fetch OCA page: ${URL}"

    fi

done

# ============================================================
# Extract OCA repositories
# ============================================================

log ""
log "============================================================"
log "Extracting OCA repositories"
log "============================================================"

: > "${ALL_REPOS}"

for FILE in "${TMP_DIR}"/page-*.html; do

    log "Parsing $(basename "${FILE}")"

    grep -Eo \
        'https?://github\.com/OCA/[A-Za-z0-9_.-]+' \
        "${FILE}" \
        2>/dev/null \
        | sed -E 's#https?://github\.com/OCA/##' \
        >> "${ALL_REPOS}" || true

done

sort -u "${ALL_REPOS}" -o "${ALL_REPOS}"

REPO_COUNT="$(grep -c . "${ALL_REPOS}" 2>/dev/null || echo 0)"

log "Repositories discovered: ${REPO_COUNT}"

if [[ "${REPO_COUNT}" -eq 0 ]]; then
    die "No OCA repositories were discovered from the pages."
fi

# ============================================================
# Download OCA repositories
# ============================================================

log ""
log "============================================================"
log "Downloading OCA ${ODOO_VERSION} repositories"
log "============================================================"

: > "${DOWNLOADED_REPOS}"
: > "${SKIPPED_REPOS}"

while IFS= read -r REPO; do

    [[ -z "${REPO}" ]] && continue

    URL="https://github.com/OCA/${REPO}.git"

    TARGET="${OCA_DIR}/${REPO}"

    log ""
    log "Repository: OCA/${REPO}"

    # --------------------------------------------------------
    # Check 19.0 branch
    # --------------------------------------------------------

    if ! git ls-remote \
        --exit-code \
        --heads \
        "${URL}" \
        "${ODOO_VERSION}" \
        >/dev/null 2>&1
    then

        log "  SKIPPED: no ${ODOO_VERSION} branch"

        echo "${REPO}" >> "${SKIPPED_REPOS}"

        continue

    fi

    # --------------------------------------------------------
    # Existing repository
    # --------------------------------------------------------

    if [[ -d "${TARGET}/.git" ]]; then

        log "  Updating existing repository"

        git \
            -C "${TARGET}" \
            fetch \
            --depth=1 \
            origin \
            "${ODOO_VERSION}"

        git \
            -C "${TARGET}" \
            checkout \
            -B "${ODOO_VERSION}" \
            "origin/${ODOO_VERSION}"

        git \
            -C "${TARGET}" \
            reset \
            --hard \
            "origin/${ODOO_VERSION}"

    else

        # ----------------------------------------------------
        # Clone repository
        # ----------------------------------------------------

        log "  Cloning ${ODOO_VERSION}"

        git clone \
            --depth=1 \
            --branch "${ODOO_VERSION}" \
            "${URL}" \
            "${TARGET}"

    fi

    echo "${REPO}" >> "${DOWNLOADED_REPOS}"

done < "${ALL_REPOS}"

# ============================================================
# Find actual Odoo modules
# ============================================================

log ""
log "============================================================"
log "Finding Odoo modules"
log "============================================================"

ACTUAL_MODULES="${TMP_DIR}/actual-modules.txt"

: > "${ACTUAL_MODULES}"

find "${OCA_DIR}" \
    -type f \
    -name "__manifest__.py" \
    -print \
    2>/dev/null \
    | while IFS= read -r MANIFEST; do

        MODULE_DIR="$(dirname "${MANIFEST}")"

        basename "${MODULE_DIR}"

    done \
    | sort -u \
    > "${ACTUAL_MODULES}"

ACTUAL_COUNT="$(grep -c . "${ACTUAL_MODULES}" 2>/dev/null || echo 0)"

log "Actual Odoo modules found: ${ACTUAL_COUNT}"

# ============================================================
# Extract module names from pages
# ============================================================

log ""
log "============================================================"
log "Extracting module names from OCA pages"
log "============================================================"

: > "${ALL_MODULES}"

for FILE in "${TMP_DIR}"/page-*.html; do

    sed \
        -e 's/<\/tr>/\n/gI' \
        -e 's/<\/td>/\t/gI' \
        -e 's/<\/th>/\t/gI' \
        -e 's/<br[^>]*>/\n/gI' \
        "${FILE}" \
        | grep -Eo '\b[a-z][a-z0-9_]{2,100}\b' \
        >> "${ALL_MODULES}" || true

done

# Keep technical-looking module names.
grep '_' "${ALL_MODULES}" \
    2>/dev/null \
    | sort -u \
    > "${ALL_MODULES}.tmp" || true

mv "${ALL_MODULES}.tmp" "${ALL_MODULES}"

# ============================================================
# Exclude demo modules
# ============================================================

DEMO_MODULES=(
    "mis_builder_demo"
)

for DEMO in "${DEMO_MODULES[@]}"; do

    sed -i "/^${DEMO}$/d" "${ALL_MODULES}" 2>/dev/null || true

    sed -i "/^${DEMO}$/d" "${ACTUAL_MODULES}" 2>/dev/null || true

done

# ============================================================
# Match modules
# ============================================================

log ""
log "============================================================"
log "Matching OCA Must-Have modules"
log "============================================================"

: > "${FOUND_MODULES}"
: > "${MISSING_MODULES}"

while IFS= read -r MODULE; do

    [[ -z "${MODULE}" ]] && continue

    if grep -Fxq "${MODULE}" "${ACTUAL_MODULES}"; then

        echo "${MODULE}" >> "${FOUND_MODULES}"

    fi

done < "${ALL_MODULES}"

sort -u "${FOUND_MODULES}" -o "${FOUND_MODULES}"

# ============================================================
# Missing modules
# ============================================================

while IFS= read -r MODULE; do

    [[ -z "${MODULE}" ]] && continue

    if ! grep -Fxq "${MODULE}" "${FOUND_MODULES}"; then

        echo "${MODULE}" >> "${MISSING_MODULES}"

    fi

done < "${ALL_MODULES}"

sort -u "${MISSING_MODULES}" -o "${MISSING_MODULES}"

# ============================================================
# Build OCA addons_path
#
# IMPORTANT:
#
# OCA repositories are structured like:
#
# addons/OCA/account-financial-tools/account_asset_management
#
# Therefore:
#
# /mnt/extra-addons/OCA
#
# itself is NOT an Odoo addons directory.
#
# We add every downloaded OCA repository:
#
# /mnt/extra-addons/OCA/account-financial-tools
# /mnt/extra-addons/OCA/sale-workflow
# etc.
# ============================================================

log ""
log "============================================================"
log "Building OCA addons_path"
log "============================================================"

OCA_ADDONS_PATH=""

while IFS= read -r REPO; do

    [[ -z "${REPO}" ]] && continue

    if [[ -d "${OCA_DIR}/${REPO}" ]]; then

        if [[ -z "${OCA_ADDONS_PATH}" ]]; then

            OCA_ADDONS_PATH="/mnt/extra-addons/OCA/${REPO}"

        else

            OCA_ADDONS_PATH="${OCA_ADDONS_PATH},/mnt/extra-addons/OCA/${REPO}"

        fi

    fi

done < "${DOWNLOADED_REPOS}"

if [[ -z "${OCA_ADDONS_PATH}" ]]; then
    die "No downloaded OCA repositories available for addons_path."
fi

NEW_ADDONS_PATH="${ODOO_CORE_ADDONS},${OCA_ADDONS_PATH}"

log "Odoo addons_path:"
log "${NEW_ADDONS_PATH}"

# ============================================================
# Update ONLY addons_path in config/odoo.conf
# ============================================================

log ""
log "============================================================"
log "Updating Odoo configuration"
log "============================================================"

if [[ -f "${ODOO_CONF}" ]]; then

    log "Existing configuration found:"
    log "  ${ODOO_CONF}"

    # Backup existing configuration.
    cp "${ODOO_CONF}" "${ODOO_CONF}.bak"

    # --------------------------------------------------------
    # Replace existing addons_path
    # --------------------------------------------------------

    if grep -Eq '^[[:space:]]*addons_path[[:space:]]*=' "${ODOO_CONF}"; then

        sed -i \
            -E "s|^[[:space:]]*addons_path[[:space:]]*=.*$|addons_path = ${NEW_ADDONS_PATH}|" \
            "${ODOO_CONF}"

        log "Updated existing addons_path."

    else

        # ----------------------------------------------------
        # addons_path doesn't exist.
        # Add only this setting.
        # ----------------------------------------------------

        printf '\naddons_path = %s\n' "${NEW_ADDONS_PATH}" \
            >> "${ODOO_CONF}"

        log "Added addons_path."

    fi

else

    # --------------------------------------------------------
    # Create minimal configuration.
    # --------------------------------------------------------

    log "Configuration does not exist:"
    log "  ${ODOO_CONF}"

    log "Creating configuration."

    cat > "${ODOO_CONF}" <<EOF
[options]
addons_path = ${NEW_ADDONS_PATH}
EOF

fi

# ============================================================
# Summary
# ============================================================

MODULE_COUNT="$(grep -c . "${ALL_MODULES}" 2>/dev/null || echo 0)"
FOUND_COUNT="$(grep -c . "${FOUND_MODULES}" 2>/dev/null || echo 0)"
MISSING_COUNT="$(grep -c . "${MISSING_MODULES}" 2>/dev/null || echo 0)"
DOWNLOADED_COUNT="$(grep -c . "${DOWNLOADED_REPOS}" 2>/dev/null || echo 0)"
SKIPPED_COUNT="$(grep -c . "${SKIPPED_REPOS}" 2>/dev/null || echo 0)"

log ""
log "============================================================"
log "COMPLETE"
log "============================================================"

log "Odoo version       : ${ODOO_VERSION}"
log "Modules discovered : ${MODULE_COUNT}"
log "Modules found      : ${FOUND_COUNT}"
log "Modules missing    : ${MISSING_COUNT}"
log "Repos downloaded   : ${DOWNLOADED_COUNT}"
log "Repos skipped      : ${SKIPPED_COUNT}"

log ""
log "Odoo configuration:"
log "  ${ODOO_CONF}"

log ""
log "OCA addons:"
log "  ${OCA_DIR}"

log ""
log "Reports:"
log "  ${REPORT_DIR}"

log ""
log "Demo modules excluded:"
log "  mis_builder_demo"

log ""
log "No Odoo modules were installed."

log ""
log "============================================================"

