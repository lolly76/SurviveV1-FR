#!/usr/bin/env bash
# =============================================================================
# SurviveV1 - Raspberry Pi 5 USB SSD stability
# - Enables full USB current delivery (needed for bus-powered SSDs)
# - Offers UAS quirks fallback for buggy USB-SATA/NVMe enclosures
# - Sets up fstrim.timer with a udev allowlist so TRIM passthrough works
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[PI5-STORAGE]${NC} $*"; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

require_root() { [[ $EUID -eq 0 ]] || { error "Lancez avec sudo"; exit 1; }; }

# Pi 5 caps USB at 600 mA by default unless the official 27 W USB-C PD PSU is
# used. Without this, bus-powered SSDs brown out under heavy I/O and remount
# read-only, which can corrupt the content library.
enable_usb_max_current() {
    local cfg=/boot/firmware/config.txt
    [[ -f "$cfg" ]] || cfg=/boot/config.txt
    if [[ ! -f "$cfg" ]]; then
        warn "Aucun config.txt de Pi trouvé ; usb_max_current_enable ignoré"
        return
    fi
    if grep -q '^usb_max_current_enable=1' "$cfg"; then
        success "usb_max_current_enable=1 déjà défini dans $cfg"
        return
    fi
    info "Ajout de usb_max_current_enable=1 à $cfg (redémarrage nécessaire)"
    printf '\n# SurviveV1: allow >600 mA to USB peripherals (requires 27 W PSU)\nusb_max_current_enable=1\n' >> "$cfg"
    warn "Redémarrage nécessaire pour appliquer le courant USB."
}

# Some USB-SATA/NVMe enclosures have buggy UAS firmware. If UAS errors show
# up in dmesg, fall back to plain USB mass-storage (still USB 3.0 speed).
offer_uas_quirks() {
    if dmesg 2>/dev/null | grep -qi 'uas.*abort\|uas.*reset\|xhci.*link.*down'; then
        warn "Erreurs UAS détectées dans dmesg. Envisagez de forcer le mode USB mass-storage."
        local id
        id=$(lsusb | awk -F'ID |[[:space:]]+' '/Mass Storage|ASMedia|JMicron|Realtek/ {for(i=1;i<=NF;i++) if($i~/^[0-9a-f]{4}:[0-9a-f]{4}$/) {print $i; exit}}')
        if [[ -n "$id" ]]; then
            warn "Suggestion : ajoutez 'usb-storage.quirks=${id}:u' à /boot/firmware/cmdline.txt"
            warn "N'appliquez que si vous constatez réellement des erreurs d'E/S liées à UAS."
        fi
    else
        success "Aucune erreur UAS détectée dans dmesg"
    fi
}

# TRIM keeps SSD write performance from degrading as the drive fills toward
# 800 GB. The udev rule whitelists the adapter; the timer runs TRIM weekly.
# WARNING: a small number of USB-SATA adapters claim TRIM support but CORRUPT
# data. Back up before enabling if you are unsure about your adapter.
setup_fstrim() {
    info "Configuration de fstrim.timer..."
    if systemctl list-unit-files | grep -q '^fstrim.timer'; then
        systemctl enable --now fstrim.timer
        success "fstrim.timer activé"
    else
        warn "unité fstrim.timer absente ; installez util-linux pour l'obtenir"
        return
    fi

    # Detect the USB device holding /mnt/survive and emit a udev rule.
    local storage_path="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
    local src
    src=$(findmnt -no SOURCE "$storage_path" 2>/dev/null || true)
    if [[ -z "$src" ]]; then
        warn "Stockage non monté sur $storage_path ; liste TRIM ignorée"
        return
    fi
    local disk
    disk=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)
    [[ -z "$disk" ]] && disk=$(basename "$src" | sed 's/[0-9]*$//')
    local vpd_path="/sys/block/${disk}/device/../../idVendor"
    local pid_path="/sys/block/${disk}/device/../../idProduct"
    if [[ -r "$vpd_path" && -r "$pid_path" ]]; then
        local vendor product
        vendor=$(<"$vpd_path"); product=$(<"$pid_path")
        local rule=/etc/udev/rules.d/10-trim.rules
        cat > "$rule" <<EOF
# SurviveV1: allow TRIM passthrough on the USB SSD hosting /mnt/survive.
# WARNING: some adapters corrupt data on TRIM. Verify before relying on this.
ACTION=="add|change", ATTRS{idVendor}=="$vendor", ATTRS{idProduct}=="$product", \\
  SUBSYSTEM=="scsi_disk", ATTR{provisioning_mode}="unmap"
EOF
        udevadm control --reload
        udevadm trigger
        success "Règle udev TRIM installée pour $vendor:$product"
    else
        warn "Impossible de détecter le fabricant/produit USB de $disk ; règle TRIM ignorée"
    fi
}

main() {
    require_root
    enable_usb_max_current
    offer_uas_quirks
    setup_fstrim
    info "Réglages de stockage du Pi 5 terminés."
}

main "$@"
