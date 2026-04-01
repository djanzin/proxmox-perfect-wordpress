#!/usr/bin/env bash
# =============================================================================
#  WordPress LXC Creator for Proxmox VE
#  Creates an unprivileged LXC (Ubuntu 24.04 or Debian 13) and installs
#  WordPress inside it using djanzin/perfect-wordpress
# =============================================================================
# Usage:
#   bash create-wordpress-lxc.sh
#
# Tested on: Proxmox VE 8.x
# Requires:  pct, pveam (Proxmox host only)
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

# ─── Colour helpers ───────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; exit 1; }
section() { echo -e "\n${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; \
            echo -e "${BOLD}${CYAN}  $*${RESET}"; \
            echo -e "${BOLD}${CYAN}══════════════════════════════════════════${RESET}"; }

# ─── Root & Proxmox check ─────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Bitte als root ausführen: sudo bash $0"
command -v pct   &>/dev/null || error "pct nicht gefunden — dieses Script muss auf dem Proxmox-Host ausgeführt werden."
command -v pveam &>/dev/null || error "pveam nicht gefunden — Proxmox VE 8.x erforderlich."

# ─── Sprachauswahl ────────────────────────────────────────────────────────────
echo -e "\n${BOLD}Sprache / Language:${RESET}"
echo -e "  1) Deutsch  ${CYAN}[Standard / Default]${RESET}"
echo -e "  2) English"
read -rp "$(echo -e "${BOLD}Auswahl / Choice [1/2]:${RESET} ")" _lang_ui
[[ "${_lang_ui}" == "2" ]] && ENGLISH=true || ENGLISH=false

# ─── Language strings ─────────────────────────────────────────────────────────
if [[ "$ENGLISH" == true ]]; then
  L_SECTION_LXC="LXC Configuration"
  L_SECTION_WP="WordPress Configuration"
  L_SECTION_SUMMARY="Summary"
  L_SECTION_CREATE="Create LXC"
  L_SECTION_INSTALL="Install WordPress"
  L_CONFIRM="Start installation? [y/N]"
  L_ABORTED="Installation aborted."
  L_PROMPT_OS="Operating system: 1) Ubuntu 24.04  2) Debian 13 (Trixie) [1]"
  L_PROMPT_CTID="Container ID (e.g. 100)"
  L_ERR_CTID="Container ID must be a number."
  L_ERR_CTID_EXISTS="Container ID already in use."
  L_PROMPT_HOSTNAME="Hostname (e.g. wordpress)"
  L_PROMPT_ROOT_PASS="LXC root password"
  L_PROMPT_ROOT_PASS2="Confirm root password"
  L_ERR_PASS_EMPTY="Password cannot be empty."
  L_ERR_PASS_MATCH="Passwords do not match."
  L_PROMPT_CORES="CPU cores [2]"
  L_PROMPT_RAM="RAM in MB [2048]"
  L_PROMPT_DISK="Disk size in GB [20]"
  L_PROMPT_STORAGE="Selection or storage name"
  L_PROMPT_BRIDGE="Network bridge [vmbr0]"
  L_PROMPT_MAC="MAC address (e.g. BC:24:11:AA:BB:CC, leave empty for auto)"
  L_PROMPT_IP_MODE="Network: 1) DHCP  2) Static IP [1]"
  L_PROMPT_IP="IP address with prefix (e.g. 192.168.1.100/24)"
  L_PROMPT_GW="Gateway (e.g. 192.168.1.1)"
  L_PROMPT_DNS="DNS server [8.8.8.8]"
  L_PROMPT_DOMAIN="Domain (e.g. example.com)"
  L_ERR_DOMAIN="Domain cannot be empty."
  L_PROMPT_EMAIL="Admin e-mail"
  L_ERR_EMAIL="E-mail cannot be empty."
  L_PROMPT_TITLE="Site title [My WordPress Site]"
  L_PROMPT_ADMIN_USER="WP admin username [admin]"
  L_PROMPT_PHP="PHP version (8.1/8.2/8.3/8.4/8.5) [8.3]"
  L_PROMPT_MEMORY="PHP memory limit (128M/256M/512M/1024M) [256M]"
  L_PROMPT_LANG="WordPress language [de_DE]"
  L_PROMPT_TIMEZONE="Timezone [Europe/Berlin]"
  L_PROMPT_REVERSEPROXY="Behind a reverse proxy (NPM/Traefik/Cloudflare)? [y/N]"
  L_PROMPT_SSL="Install SSL via Let's Encrypt? [y/N]"
  L_PROMPT_PHPMYADMIN="Install phpMyAdmin? [y/N]"
  L_PROMPT_FILEBROWSER="Install FileBrowser? [y/N]"
  L_OS_LABEL="OS"
  L_CTID_LABEL="Container ID"
  L_HOSTNAME_LABEL="Hostname"
  L_CORES_LABEL="CPU cores"
  L_RAM_LABEL="RAM"
  L_DISK_LABEL="Disk"
  L_STORAGE_LABEL="Storage"
  L_BRIDGE_LABEL="Bridge"
  L_MAC_LABEL="MAC address"
  L_IP_LABEL="IP"
  L_DOMAIN_LABEL="Domain"
  L_PHP_LABEL="PHP version"
  L_MEMORY_LABEL="Memory limit"
  L_SSL_LABEL="SSL"
  L_RP_LABEL="Reverse proxy"
  L_PMA_LABEL="phpMyAdmin"
  L_FB_LABEL="FileBrowser"
  L_TEMPLATE_DOWNLOAD="Downloading template..."
  L_TEMPLATE_OK="Template ready"
  L_LXC_CREATING="Creating LXC container..."
  L_LXC_OK="LXC container created."
  L_LXC_STARTING="Starting container..."
  L_LXC_WAIT="Waiting for container to boot..."
  L_LXC_READY="Container ready."
  L_WP_INSTALLING="Installing WordPress inside container..."
  L_CREDS_COPY="Copying credentials to Proxmox host..."
  L_CREDS_SAVED="Credentials saved"
  L_CREDS_MANUAL="Could not copy credentials — fetch manually"
  L_DONE="Setup complete"
  L_SITE_URL="Website URL"
  L_ADMIN_URL="WordPress Admin"
  L_CREDS_FILE="Credentials file"
  L_AUTO="auto"
else
  L_SECTION_LXC="LXC Konfiguration"
  L_SECTION_WP="WordPress Konfiguration"
  L_SECTION_SUMMARY="Zusammenfassung"
  L_SECTION_CREATE="LXC erstellen"
  L_SECTION_INSTALL="WordPress installieren"
  L_CONFIRM="Jetzt installieren? [j/N]"
  L_ABORTED="Installation abgebrochen."
  L_PROMPT_OS="Betriebssystem: 1) Ubuntu 24.04  2) Debian 13 (Trixie) [1]"
  L_PROMPT_CTID="Container-ID (z.B. 100)"
  L_ERR_CTID="Container-ID muss eine Zahl sein."
  L_ERR_CTID_EXISTS="Container-ID bereits vergeben."
  L_PROMPT_HOSTNAME="Hostname (z.B. wordpress)"
  L_PROMPT_ROOT_PASS="LXC Root-Passwort"
  L_PROMPT_ROOT_PASS2="Root-Passwort bestätigen"
  L_ERR_PASS_EMPTY="Passwort darf nicht leer sein."
  L_ERR_PASS_MATCH="Passwörter stimmen nicht überein."
  L_PROMPT_CORES="CPU-Kerne [2]"
  L_PROMPT_RAM="RAM in MB [2048]"
  L_PROMPT_DISK="Disk-Größe in GB [20]"
  L_PROMPT_STORAGE="Auswahl oder Storage-Name"
  L_PROMPT_BRIDGE="Netzwerk-Bridge [vmbr0]"
  L_PROMPT_MAC="MAC-Adresse (z.B. BC:24:11:AA:BB:CC, leer lassen für automatisch)"
  L_PROMPT_IP_MODE="Netzwerk: 1) DHCP  2) Statische IP [1]"
  L_PROMPT_IP="IP-Adresse mit Präfix (z.B. 192.168.1.100/24)"
  L_PROMPT_GW="Gateway (z.B. 192.168.1.1)"
  L_PROMPT_DNS="DNS-Server [8.8.8.8]"
  L_PROMPT_DOMAIN="Domain (z.B. example.com)"
  L_ERR_DOMAIN="Domain darf nicht leer sein."
  L_PROMPT_EMAIL="Admin E-Mail"
  L_ERR_EMAIL="E-Mail darf nicht leer sein."
  L_PROMPT_TITLE="Site-Titel [My WordPress Site]"
  L_PROMPT_ADMIN_USER="WP Admin-Benutzername [admin]"
  L_PROMPT_PHP="PHP-Version (8.1/8.2/8.3/8.4/8.5) [8.3]"
  L_PROMPT_MEMORY="PHP Memory Limit (128M/256M/512M/1024M) [256M]"
  L_PROMPT_LANG="WordPress-Sprache [de_DE]"
  L_PROMPT_TIMEZONE="Zeitzone [Europe/Berlin]"
  L_PROMPT_REVERSEPROXY="Hinter einem Reverse Proxy (NPM/Traefik/Cloudflare)? [j/N]"
  L_PROMPT_SSL="SSL via Let's Encrypt installieren? [j/N]"
  L_PROMPT_PHPMYADMIN="phpMyAdmin installieren? [j/N]"
  L_PROMPT_FILEBROWSER="FileBrowser installieren? [j/N]"
  L_OS_LABEL="Betriebssystem"
  L_CTID_LABEL="Container-ID"
  L_HOSTNAME_LABEL="Hostname"
  L_CORES_LABEL="CPU-Kerne"
  L_RAM_LABEL="RAM"
  L_DISK_LABEL="Disk"
  L_STORAGE_LABEL="Storage"
  L_BRIDGE_LABEL="Bridge"
  L_MAC_LABEL="MAC-Adresse"
  L_IP_LABEL="IP"
  L_DOMAIN_LABEL="Domain"
  L_PHP_LABEL="PHP-Version"
  L_MEMORY_LABEL="Memory Limit"
  L_SSL_LABEL="SSL"
  L_RP_LABEL="Reverse Proxy"
  L_PMA_LABEL="phpMyAdmin"
  L_FB_LABEL="FileBrowser"
  L_TEMPLATE_DOWNLOAD="Template wird heruntergeladen..."
  L_TEMPLATE_OK="Template bereit"
  L_LXC_CREATING="LXC Container wird erstellt..."
  L_LXC_OK="LXC Container erstellt."
  L_LXC_STARTING="Container wird gestartet..."
  L_LXC_WAIT="Warte bis Container gebootet ist..."
  L_LXC_READY="Container bereit."
  L_WP_INSTALLING="WordPress wird im Container installiert..."
  L_CREDS_COPY="Zugangsdaten auf Proxmox-Host kopieren..."
  L_CREDS_SAVED="Zugangsdaten gespeichert"
  L_CREDS_MANUAL="Zugangsdaten konnten nicht kopiert werden — bitte manuell abrufen"
  L_DONE="Setup abgeschlossen"
  L_SITE_URL="Website-URL"
  L_ADMIN_URL="WordPress Admin"
  L_CREDS_FILE="Zugangsdaten-Datei"
  L_AUTO="automatisch"
fi

# =============================================================================
# LXC KONFIGURATION
# =============================================================================
section "$L_SECTION_LXC"

# Betriebssystem
read -rp "$(echo -e "${BOLD}${L_PROMPT_OS}:${RESET} ")" _os_choice
case "${_os_choice:-1}" in
  2) CT_OS="debian";  CT_OS_LABEL="Debian 13 (Trixie)"; CT_OS_TYPE="debian" ;;
  *) CT_OS="ubuntu";  CT_OS_LABEL="Ubuntu 24.04 LTS";   CT_OS_TYPE="ubuntu" ;;
esac

# Container-ID
while true; do
  read -rp "$(echo -e "${BOLD}${L_PROMPT_CTID}:${RESET} ")" CT_ID
  [[ "$CT_ID" =~ ^[0-9]+$ ]] || { warn "$L_ERR_CTID"; continue; }
  pct status "$CT_ID" &>/dev/null && { warn "$L_ERR_CTID_EXISTS"; continue; }
  break
done

# Hostname
read -rp "$(echo -e "${BOLD}${L_PROMPT_HOSTNAME}:${RESET} ")" CT_HOSTNAME
CT_HOSTNAME="${CT_HOSTNAME:-wordpress}"

# Root-Passwort (mit Bestätigung)
while true; do
  read -rsp "$(echo -e "${BOLD}${L_PROMPT_ROOT_PASS}:${RESET} ")" CT_ROOT_PASS; echo
  [[ -n "$CT_ROOT_PASS" ]] || { warn "$L_ERR_PASS_EMPTY"; continue; }
  read -rsp "$(echo -e "${BOLD}${L_PROMPT_ROOT_PASS2}:${RESET} ")" CT_ROOT_PASS2; echo
  [[ "$CT_ROOT_PASS" == "$CT_ROOT_PASS2" ]] && break
  warn "$L_ERR_PASS_MATCH"
done

# CPU / RAM / Disk
read -rp "$(echo -e "${BOLD}${L_PROMPT_CORES}:${RESET} ")" CT_CORES
CT_CORES="${CT_CORES:-2}"
read -rp "$(echo -e "${BOLD}${L_PROMPT_RAM}:${RESET} ")" CT_RAM
CT_RAM="${CT_RAM:-2048}"
read -rp "$(echo -e "${BOLD}${L_PROMPT_DISK}:${RESET} ")" CT_DISK
CT_DISK="${CT_DISK:-20}"

# Storage
# Verfügbare Storages mit rootdir-Unterstützung ermitteln und anzeigen
mapfile -t _STORAGES < <(pvesm status --content rootdir 2>/dev/null | awk 'NR>1 {print $1}')
if [[ ${#_STORAGES[@]} -gt 0 ]]; then
  echo -e "${BOLD}${L_STORAGE_LABEL}:${RESET}"
  for i in "${!_STORAGES[@]}"; do
    echo -e "  $((i+1))) ${CYAN}${_STORAGES[$i]}${RESET}"
  done
  read -rp "$(echo -e "${BOLD}${L_PROMPT_STORAGE}:${RESET} ")" _storage_input
  if [[ "$_storage_input" =~ ^[0-9]+$ ]] && (( _storage_input >= 1 && _storage_input <= ${#_STORAGES[@]} )); then
    CT_STORAGE="${_STORAGES[$(( _storage_input - 1 ))]}"
  else
    CT_STORAGE="${_storage_input:-${_STORAGES[0]}}"
  fi
else
  read -rp "$(echo -e "${BOLD}${L_PROMPT_STORAGE}:${RESET} ")" CT_STORAGE
  CT_STORAGE="${CT_STORAGE:-local-lvm}"
fi

# Bridge
read -rp "$(echo -e "${BOLD}${L_PROMPT_BRIDGE}:${RESET} ")" CT_BRIDGE
CT_BRIDGE="${CT_BRIDGE:-vmbr0}"

# MAC-Adresse
read -rp "$(echo -e "${BOLD}${L_PROMPT_MAC}:${RESET} ")" CT_MAC

# Netzwerk
read -rp "$(echo -e "${BOLD}${L_PROMPT_IP_MODE}:${RESET} ")" _ip_mode
if [[ "${_ip_mode:-1}" == "2" ]]; then
  read -rp "$(echo -e "${BOLD}${L_PROMPT_IP}:${RESET} ")"  CT_IP
  read -rp "$(echo -e "${BOLD}${L_PROMPT_GW}:${RESET} ")"  CT_GW
  read -rp "$(echo -e "${BOLD}${L_PROMPT_DNS}:${RESET} ")" CT_DNS
  CT_DNS="${CT_DNS:-8.8.8.8}"
  CT_IP_MODE="static"
else
  CT_IP="dhcp"
  CT_GW=""
  CT_DNS="8.8.8.8"
  CT_IP_MODE="dhcp"
fi

# =============================================================================
# WORDPRESS KONFIGURATION
# =============================================================================
section "$L_SECTION_WP"

# Domain
while true; do
  read -rp "$(echo -e "${BOLD}${L_PROMPT_DOMAIN}:${RESET} ")" WP_DOMAIN
  [[ -n "$WP_DOMAIN" ]] && break
  warn "$L_ERR_DOMAIN"
done

# E-Mail
while true; do
  read -rp "$(echo -e "${BOLD}${L_PROMPT_EMAIL}:${RESET} ")" WP_EMAIL
  [[ -n "$WP_EMAIL" ]] && break
  warn "$L_ERR_EMAIL"
done

# Site-Titel
read -rp "$(echo -e "${BOLD}${L_PROMPT_TITLE}:${RESET} ")" WP_TITLE
WP_TITLE="${WP_TITLE:-My WordPress Site}"

# Admin-User
read -rp "$(echo -e "${BOLD}${L_PROMPT_ADMIN_USER}:${RESET} ")" WP_ADMIN_USER
WP_ADMIN_USER="${WP_ADMIN_USER:-admin}"

# PHP-Version
read -rp "$(echo -e "${BOLD}${L_PROMPT_PHP}:${RESET} ")" WP_PHP
WP_PHP="${WP_PHP:-8.3}"

# Memory Limit
read -rp "$(echo -e "${BOLD}${L_PROMPT_MEMORY}:${RESET} ")" WP_MEMORY
WP_MEMORY="${WP_MEMORY:-256M}"

# Sprache
read -rp "$(echo -e "${BOLD}${L_PROMPT_LANG}:${RESET} ")" WP_LANG
WP_LANG="${WP_LANG:-de_DE}"

# Zeitzone
read -rp "$(echo -e "${BOLD}${L_PROMPT_TIMEZONE}:${RESET} ")" WP_TIMEZONE
WP_TIMEZONE="${WP_TIMEZONE:-Europe/Berlin}"

# Reverse Proxy
read -rp "$(echo -e "${BOLD}${L_PROMPT_REVERSEPROXY}:${RESET} ")" _rp
[[ "${_rp,,}" == "j" || "${_rp,,}" == "y" ]] && REVERSE_PROXY=true || REVERSE_PROXY=false

# SSL (nur fragen wenn kein Reverse Proxy)
if [[ "$REVERSE_PROXY" == false ]]; then
  read -rp "$(echo -e "${BOLD}${L_PROMPT_SSL}:${RESET} ")" _ssl
  [[ "${_ssl,,}" == "j" || "${_ssl,,}" == "y" ]] && INSTALL_SSL=true || INSTALL_SSL=false
else
  INSTALL_SSL=false
fi

# phpMyAdmin
read -rp "$(echo -e "${BOLD}${L_PROMPT_PHPMYADMIN}:${RESET} ")" _pma
[[ "${_pma,,}" == "j" || "${_pma,,}" == "y" ]] && INSTALL_PMA=true || INSTALL_PMA=false

# FileBrowser
read -rp "$(echo -e "${BOLD}${L_PROMPT_FILEBROWSER}:${RESET} ")" _fb
[[ "${_fb,,}" == "j" || "${_fb,,}" == "y" ]] && INSTALL_FB=true || INSTALL_FB=false

# =============================================================================
# ZUSAMMENFASSUNG
# =============================================================================
section "$L_SECTION_SUMMARY"

MAC_DISPLAY="${CT_MAC:-${L_AUTO}}"
IP_DISPLAY="${CT_IP_MODE^^}"
[[ "$CT_IP_MODE" == "static" ]] && IP_DISPLAY="${CT_IP}  GW: ${CT_GW}"

echo -e "  ${BOLD}— LXC —${RESET}"
echo -e "  ${L_OS_LABEL}         : ${CYAN}${CT_OS_LABEL}${RESET}"
echo -e "  ${L_CTID_LABEL}       : ${CYAN}${CT_ID}${RESET}"
echo -e "  ${L_HOSTNAME_LABEL}   : ${CYAN}${CT_HOSTNAME}${RESET}"
echo -e "  ${L_CORES_LABEL}      : ${CYAN}${CT_CORES}${RESET}"
echo -e "  ${L_RAM_LABEL}        : ${CYAN}${CT_RAM} MB${RESET}"
echo -e "  ${L_DISK_LABEL}       : ${CYAN}${CT_DISK} GB${RESET}"
echo -e "  ${L_STORAGE_LABEL}    : ${CYAN}${CT_STORAGE}${RESET}"
echo -e "  ${L_BRIDGE_LABEL}     : ${CYAN}${CT_BRIDGE}${RESET}"
echo -e "  ${L_MAC_LABEL}        : ${CYAN}${MAC_DISPLAY}${RESET}"
echo -e "  ${L_IP_LABEL}         : ${CYAN}${IP_DISPLAY}${RESET}"
echo -e ""
echo -e "  ${BOLD}— WordPress —${RESET}"
echo -e "  ${L_DOMAIN_LABEL}     : ${CYAN}${WP_DOMAIN}${RESET}"
echo -e "  ${L_PHP_LABEL}        : ${CYAN}${WP_PHP}${RESET}"
echo -e "  ${L_MEMORY_LABEL}     : ${CYAN}${WP_MEMORY}${RESET}"
echo -e "  ${L_SSL_LABEL}        : ${CYAN}${INSTALL_SSL}${RESET}"
echo -e "  ${L_RP_LABEL}         : ${CYAN}${REVERSE_PROXY}${RESET}"
echo -e "  ${L_PMA_LABEL}        : ${CYAN}${INSTALL_PMA}${RESET}"
echo -e "  ${L_FB_LABEL}         : ${CYAN}${INSTALL_FB}${RESET}"
echo ""

read -rp "$(echo -e "${BOLD}${L_CONFIRM}${RESET} ")" _confirm
[[ "${_confirm,,}" == "j" || "${_confirm,,}" == "y" ]] || { info "$L_ABORTED"; exit 0; }

# =============================================================================
# TEMPLATE SICHERSTELLEN
# =============================================================================
section "$L_SECTION_CREATE"

TEMPLATE_STORAGE="local"

# Aktuelles Template für gewähltes OS ermitteln
pveam update &>/dev/null
TEMPLATE_NAME=$(pveam available --section system 2>/dev/null \
  | awk -v os="$CT_OS" '$0 ~ os"-"(os=="ubuntu"?"24":"13") {print $2}' \
  | sort -V | tail -1)

[[ -z "$TEMPLATE_NAME" ]] && error "Kein ${CT_OS_LABEL} Template in pveam verfügbar."

if ! pveam list "$TEMPLATE_STORAGE" 2>/dev/null | grep -q "$TEMPLATE_NAME"; then
  info "$L_TEMPLATE_DOWNLOAD ($TEMPLATE_NAME)"
  pveam download "$TEMPLATE_STORAGE" "$TEMPLATE_NAME"
fi
success "$L_TEMPLATE_OK: $TEMPLATE_NAME"

# =============================================================================
# LXC ERSTELLEN
# =============================================================================
info "$L_LXC_CREATING"

# Netzwerk-String aufbauen
if [[ -n "$CT_MAC" ]]; then
  NET_STR="name=eth0,bridge=${CT_BRIDGE},hwaddr=${CT_MAC},ip=${CT_IP}"
else
  NET_STR="name=eth0,bridge=${CT_BRIDGE},ip=${CT_IP}"
fi
[[ "$CT_IP_MODE" == "static" ]] && NET_STR="${NET_STR},gw=${CT_GW}"

pct create "$CT_ID" "${TEMPLATE_STORAGE}:vztmpl/${TEMPLATE_NAME}" \
  --hostname    "$CT_HOSTNAME" \
  --password    "$CT_ROOT_PASS" \
  --memory      "$CT_RAM" \
  --cores       "$CT_CORES" \
  --rootfs      "${CT_STORAGE}:${CT_DISK}" \
  --net0        "$NET_STR" \
  --nameserver  "$CT_DNS" \
  --unprivileged 1 \
  --features    "nesting=1" \
  --ostype      "$CT_OS_TYPE" \
  --start       0

success "$L_LXC_OK"

# vm.overcommit_memory für Redis in LXC-Config setzen (unprivilegierter Container kann sysctl nicht selbst setzen)
echo "lxc.sysctl.vm.overcommit_memory: 1" >> /etc/pve/lxc/${CT_ID}.conf

# Container starten und auf Boot warten
info "$L_LXC_STARTING"
pct start "$CT_ID"

info "$L_LXC_WAIT"
for i in $(seq 1 30); do
  if pct exec "$CT_ID" -- bash -c "systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded'" 2>/dev/null; then
    break
  fi
  sleep 2
done
sleep 3
success "$L_LXC_READY"

# =============================================================================
# WORDPRESS INSTALLIEREN
# =============================================================================
section "$L_SECTION_INSTALL"
info "$L_WP_INSTALLING"

# Flags für non-interaktive Installation zusammenbauen
WP_FLAGS=(
  --domain       "$WP_DOMAIN"
  --email        "$WP_EMAIL"
  --title        "$WP_TITLE"
  --admin-user   "$WP_ADMIN_USER"
  --php          "$WP_PHP"
  --memory       "$WP_MEMORY"
  --lang         "$WP_LANG"
  --timezone     "$WP_TIMEZONE"
  --english
  --yes
)
[[ "$INSTALL_SSL"   == true ]] && WP_FLAGS+=(--ssl)
[[ "$REVERSE_PROXY" == true ]] && WP_FLAGS+=(--reverse-proxy)
[[ "$INSTALL_PMA"   == true ]] && WP_FLAGS+=(--phpmyadmin)
[[ "$INSTALL_FB"    == true ]] && WP_FLAGS+=(--filebrowser)

# Locale + curl + ca-certificates sicherstellen (im frischen LXC Template nicht vorinstalliert)
# LANG=C LC_ALL=C: verhindert, dass das locales-Paket-Postinst update-locale mit dem geerbten
# Host-LANG aufruft und fehlschlägt — Locale erst nach der Installation konfigurieren
pct exec "$CT_ID" -- bash -c \
  "DEBIAN_FRONTEND=noninteractive LANG=C LC_ALL=C apt-get update -qq && \
   DEBIAN_FRONTEND=noninteractive LANG=C LC_ALL=C apt-get install -y -qq curl ca-certificates locales && \
   locale-gen en_US.UTF-8 && \
   echo 'LANG=en_US.UTF-8' > /etc/default/locale"

# Script in den Container laden
pct exec "$CT_ID" -- bash -c \
  "curl -fsSL https://raw.githubusercontent.com/djanzin/perfect-wordpress/main/install-wordpress.sh -o /tmp/install-wp.sh && chmod +x /tmp/install-wp.sh"

# WordPress installieren
# systemd-run führt den Install-Script als transiente systemd-Unit aus — dadurch hat der Prozess
# vollen D-Bus-Zugriff und deb-systemd-invoke kann systemctl korrekt aufrufen (Debian 13 Fix).
pct exec "$CT_ID" -- \
  systemd-run --wait --pipe \
  --setenv "LANG=en_US.UTF-8" \
  --setenv "PATH=/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin" \
  -- /bin/bash /tmp/install-wp.sh "${WP_FLAGS[@]}"

# =============================================================================
# ZUGANGSDATEN AUF PROXMOX-HOST KOPIEREN
# =============================================================================
info "$L_CREDS_COPY"
CREDS_SRC="/root/.wp_install_credentials_${WP_DOMAIN}.txt"
CREDS_DST="/root/.wp_lxc${CT_ID}_credentials_${WP_DOMAIN}.txt"

if pct exec "$CT_ID" -- test -f "$CREDS_SRC" 2>/dev/null; then
  pct pull "$CT_ID" "$CREDS_SRC" "$CREDS_DST" 2>/dev/null && \
    success "$L_CREDS_SAVED: ${CREDS_DST}" || \
    warn "${L_CREDS_MANUAL}: pct pull ${CT_ID} ${CREDS_SRC} ${CREDS_DST}"
else
  warn "${L_CREDS_MANUAL}: pct pull ${CT_ID} ${CREDS_SRC} ${CREDS_DST}"
fi

# =============================================================================
# ABSCHLUSS
# =============================================================================
SITE_PROTO="http"
[[ "$INSTALL_SSL" == true || "$REVERSE_PROXY" == true ]] && SITE_PROTO="https"

echo -e "\n${BOLD}${GREEN}════════════════════════════════════════════════════════${RESET}"
echo -e "${BOLD}${GREEN}  ${L_DONE} — $(date '+%Y-%m-%d %H:%M')${RESET}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${RESET}"
echo -e "  ${BOLD}${L_SITE_URL}:${RESET}   ${SITE_PROTO}://${WP_DOMAIN}"
echo -e "  ${BOLD}${L_ADMIN_URL}:${RESET}  ${SITE_PROTO}://${WP_DOMAIN}/wp-admin"
echo -e "  ${BOLD}${L_CREDS_FILE}:${RESET} ${CREDS_DST}"
echo -e "${BOLD}${GREEN}════════════════════════════════════════════════════════${RESET}\n"
