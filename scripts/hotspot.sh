#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Grid-down Wi-Fi hotspot mode
#
# Turns the Pi into its own Wi-Fi access point so phones/laptops can reach the
# knowledge base with NO router or grid power — the exact scenario this device
# exists for. Uses NetworkManager (Raspberry Pi OS Bookworm default).
#
#   sudo bash scripts/hotspot.sh enable    # start AP  (SSID from survive.conf)
#   sudo bash scripts/hotspot.sh disable   # back to normal Wi-Fi client mode
#        bash scripts/hotspot.sh status    # AP state + connected client count
#
# While the AP is active the dashboard lives at http://10.42.0.1:8080
# (NetworkManager 'shared' mode always assigns the Pi 10.42.0.1).
# The connection is created with autoconnect=no ON PURPOSE: a reboot returns
# the Pi to normal Wi-Fi — a dead-man switch against locking yourself out of a
# headless box. To make AP mode persistent across reboots (an informed choice):
#   sudo nmcli connection modify survive-hotspot connection.autoconnect yes
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
# Env overrides win over the conf's baked-in values (same pattern as
# build_ebook_library.sh).
_ENV_SSID="${SURVIVE_HOTSPOT_SSID:-}"
_ENV_PASS="${SURVIVE_HOTSPOT_PASS:-}"
if [[ -f "$_CONF" ]]; then source "$_CONF"; fi
SSID="${_ENV_SSID:-${SURVIVE_HOTSPOT_SSID:-SurviveV1}}"
PASS="${_ENV_PASS:-${SURVIVE_HOTSPOT_PASS:-survive2026}}"

CON_NAME="survive-hotspot"
ACTION="${1:-status}"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[HOTSPOT]${NC} $*"; }
success() { echo -e "${GREEN}[HOTSPOT]${NC} $*"; }
warn()    { echo -e "${YELLOW}[HOTSPOT]${NC} $*"; }
error()   { echo -e "${RED}[HOTSPOT]${NC} $*" >&2; }

# status must work (exit 0) even on NetworkManager-less boxes — it is called
# from other scripts under `set -e`.
if ! command -v nmcli &>/dev/null; then
    if [[ "$ACTION" == "status" ]]; then
        info "NetworkManager indisponible — point d'accès non pris en charge sur ce système"
        exit 0
    fi
    error "NetworkManager (nmcli) est requis — c'est le réglage par défaut de Raspberry Pi OS"
    error "Bookworm. Les anciens systèmes basés sur dhcpcd ne sont pas pris en charge."
    exit 1
fi

hotspot_active() {
    nmcli -t -f NAME connection show --active 2>/dev/null | grep -qx "$CON_NAME"
}

# NetworkManager's shared mode runs a DHCP+DNS server (dnsmasq) on wlan0, but
# ufw denies incoming by default and silently drops the client's DHCP request
# — the phone then shows "IP configuration error" / "Failed to obtain IP
# address". Open DHCP (67/udp) and DNS (53) plus the dashboard on the AP
# interface only, so the normal network's rules are untouched.
AP_IFACE="wlan0"
# Ports opened on the AP interface only: DHCP(67), DNS(53), dashboard(8080),
# HTTP(80) for the captive portal, NTP(123) for offline time sync.
AP_PORTS_UDP=(67 53 123)
AP_PORTS_TCP=(53 80 8080)
firewall_open_ap() {
    command -v ufw &>/dev/null || return 0
    ufw status 2>/dev/null | grep -q "^Status: active" || return 0
    info "Ouverture DHCP/DNS/HTTP/NTP/tableau de bord sur $AP_IFACE pour les clients du point d'accès..."
    local p
    for p in "${AP_PORTS_UDP[@]}"; do
        ufw allow in on "$AP_IFACE" to any port "$p" proto udp >/dev/null 2>&1 || true
    done
    for p in "${AP_PORTS_TCP[@]}"; do
        ufw allow in on "$AP_IFACE" to any port "$p" proto tcp >/dev/null 2>&1 || true
    done
    ufw reload >/dev/null 2>&1 || true
}
firewall_close_ap() {
    command -v ufw &>/dev/null || return 0
    ufw status 2>/dev/null | grep -q "^Status: active" || return 0
    local p
    for p in "${AP_PORTS_UDP[@]}"; do
        ufw delete allow in on "$AP_IFACE" to any port "$p" proto udp >/dev/null 2>&1 || true
    done
    for p in "${AP_PORTS_TCP[@]}"; do
        ufw delete allow in on "$AP_IFACE" to any port "$p" proto tcp >/dev/null 2>&1 || true
    done
    ufw reload >/dev/null 2>&1 || true
}

# Wildcard DNS + NTP option for the captive portal. Written into the
# shared-mode dnsmasq drop-in dir (NOT dnsmasq.d/, which is only read in
# client mode) BEFORE the connection comes up, so NM's freshly-spawned
# dnsmasq picks it up. address=/#/10.42.0.1 answers EVERY hostname with the
# Pi, so any OS connectivity probe lands on our nginx:80 -> dashboard and the
# phone pops its captive-portal sign-in. Only AP clients are affected; the
# Pi's own resolver is untouched.
CAPTIVE_DNSMASQ="/etc/NetworkManager/dnsmasq-shared.d/80-survive-captive.conf"
captive_portal_enable() {
    mkdir -p "$(dirname "$CAPTIVE_DNSMASQ")"
    cat > "$CAPTIVE_DNSMASQ" <<'EOF'
# SurviveV1 captive portal: resolve all names to the Pi so client OS
# connectivity checks trigger the sign-in page. Managed by scripts/hotspot.sh.
address=/#/10.42.0.1
dhcp-option=option:ntp-server,10.42.0.1
EOF
}
captive_portal_disable() {
    rm -f "$CAPTIVE_DNSMASQ"
}

case "$ACTION" in
    enable)
        [[ $EUID -eq 0 ]] || { error "lancez avec sudo : sudo bash scripts/hotspot.sh enable"; exit 1; }

        # WPA-PSK requires 8-63 characters; nmcli's own error is cryptic.
        if (( ${#PASS} < 8 || ${#PASS} > 63 )); then
            error "Le mot de passe du point d'accès doit faire 8 à 63 caractères (${#PASS} fournis)."
            error "Définissez SURVIVE_HOTSPOT_PASS dans config/survive.conf"
            exit 1
        fi

        # Wi-Fi country unset → AP channel selection can fail silently.
        if command -v iw &>/dev/null && iw reg get 2>/dev/null | grep -q "country 00"; then
            warn "Le pays du Wi-Fi n'est pas défini — si le point d'accès ne démarre pas, lancez :"
            warn "  sudo raspi-config nonint do_wifi_country FR   (ou votre pays, p. ex. FR)"
        fi

        # Enabling the AP tears down any wlan0 client connection — if this
        # session came in over that Wi-Fi, it will drop. Require confirmation.
        WIFI_ACTIVE=$(nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null \
            | awk -F: '$2 == "802-11-wireless" && $3 == "wlan0" {print $1}' || true)
        if [[ -n "${SSH_CONNECTION:-}" ]] && [[ -n "$WIFI_ACTIVE" ]] && [[ "${2:-}" != "--force" ]]; then
            warn "Vous semblez connecté en SSH alors que wlan0 est un client Wi-Fi"
            warn "(réseau : $WIFI_ACTIVE). Activer le point d'accès COUPERA cette liaison."
            warn "Si vous perdez l'accès : branchez un câble Ethernet ou redémarrez — le point d'accès"
            warn "ne démarre pas automatiquement au démarrage."
            echo -en "  ${YELLOW}Tapez « oui » pour continuer :${NC} "
            read -r CONFIRM
            [[ "$CONFIRM" == "yes" || "$CONFIRM" == "oui" ]] || { info "annulé"; exit 1; }
        fi

        rfkill unblock wifi 2>/dev/null || true
        nmcli radio wifi on

        info "Création du point d'accès « $SSID » sur wlan0..."
        nmcli connection delete "$CON_NAME" 2>/dev/null || true
        # Write the captive-portal DNS drop-in BEFORE bringing the connection
        # up — NM spawns its shared-mode dnsmasq at that moment and reads the
        # file once.
        captive_portal_enable
        # band bg = 2.4 GHz: works in every regulatory domain, every phone
        # supports it, and it penetrates walls — the right disaster trade-off.
        # ipv4.method shared = NM runs DHCP+NAT; the Pi is always 10.42.0.1.
        nmcli connection add type wifi ifname wlan0 con-name "$CON_NAME" \
            autoconnect no ssid "$SSID" \
            802-11-wireless.mode ap 802-11-wireless.band bg \
            ipv4.method shared ipv6.method disabled \
            wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PASS" >/dev/null
        nmcli connection up "$CON_NAME" >/dev/null
        firewall_open_ap

        HOSTNAME_LABEL="${SURVIVE_HOTSPOT_SSID:-$SSID}"
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║        Point d'accès hors réseau ACTIF           ║${NC}"
        echo -e "${GREEN}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${GREEN}║${NC} Réseau Wi-Fi :   ${HOSTNAME_LABEL}"
        echo -e "${GREEN}║${NC} Mot de passe :   ${PASS}"
        echo -e "${GREEN}║${NC} Tableau de bord : http://10.42.0.1:8080"
        echo -e "${GREEN}║${NC}                 http://${SURVIVE_HOSTNAME:-survive}.local:8080"
        echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
        echo ""
        info "Désactivation : sudo bash scripts/hotspot.sh disable"
        info "Un redémarrage remet aussi le Pi sur le Wi-Fi normal (sécurité automatique)."
        ;;

    disable)
        [[ $EUID -eq 0 ]] || { error "lancez avec sudo : sudo bash scripts/hotspot.sh disable"; exit 1; }
        if hotspot_active; then
            nmcli connection down "$CON_NAME" >/dev/null 2>&1 || true
        fi
        nmcli connection delete "$CON_NAME" >/dev/null 2>&1 || true
        firewall_close_ap
        captive_portal_disable
        success "Point d'accès désactivé — reconnexion aux réseaux Wi-Fi connus (le cas échéant)"
        ;;

    status)
        if hotspot_active; then
            CLIENTS=$(iw dev wlan0 station dump 2>/dev/null | grep -c "^Station" || true)
            success "Point d'accès ACTIF — SSID « $SSID », tableau de bord sur http://10.42.0.1:8080"
            info "Clients connectés : ${CLIENTS:-0}"
        else
            info "Point d'accès inactif (mode client Wi-Fi normal)"
            info "Activation : sudo bash scripts/hotspot.sh enable"
        fi
        ;;

    *)
        error "Utilisation : bash scripts/hotspot.sh {enable|disable|status}"
        exit 1
        ;;
esac
