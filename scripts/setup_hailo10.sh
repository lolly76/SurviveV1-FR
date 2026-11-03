#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Hailo AI HAT setup (Hailo-8/8L and Hailo-10H)
#
# Raspberry Pi OS ships TWO separate Hailo stacks, and installing the wrong
# one fails silently: the kernel module loads but never binds the device
# (no /dev/hailo0, "Hailo devices not found"), because each driver only
# knows its own PCI IDs:
#
#   hailo-all      -> HailoRT 4.x  -> Hailo-8 / 8L   (PCI 1e60:2864)
#   hailo-h10-all  -> HailoRT 5.x  -> Hailo-10H      (PCI 1e60:45c4)
#
# This script detects which chip is present and installs the matching stack.
#
#   sudo bash scripts/setup_hailo10.sh
# =============================================================================
set -euo pipefail

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[HAILO]${NC} $*"; }
success() { echo -e "${GREEN}[HAILO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[HAILO]${NC} $*"; }
error()   { echo -e "${RED}[HAILO]${NC} $*" >&2; }

[[ $EUID -eq 0 ]] || { error "Lancez avec sudo : sudo bash $0"; exit 1; }

# ── Detect the chip ───────────────────────────────────────────────────────────
PCI_LINE=$(lspci -nn 2>/dev/null | grep -i hailo || true)
if [[ -z "$PCI_LINE" ]]; then
    error "Aucun périphérique Hailo sur le bus PCIe."
    error "Vérifiez que le HAT est bien enfiché et que le PCIe est activé, puis redémarrez."
    exit 1
fi
info "Détecté : $PCI_LINE"

case "$PCI_LINE" in
    *45c4*) CHIP="hailo10"; META="hailo-h10-all"; WRONG_META="hailo-all"
            WRONG_PKGS=(hailo-all hailort hailort-pcie-driver python3-hailort) ;;
    *2864*) CHIP="hailo8";  META="hailo-all";     WRONG_META="hailo-h10-all"
            WRONG_PKGS=(hailo-h10-all h10-hailort h10-hailort-pcie-driver python3-h10-hailort) ;;
    *)      error "Identifiant PCI Hailo non reconnu dans : $PCI_LINE"
            error "Consultez https://www.raspberrypi.com/documentation/ pour votre modèle."
            exit 1 ;;
esac
info "Famille de puce : $CHIP  ->  bon paquet : $META"

# ── Remove the mismatched stack if present ────────────────────────────────────
REMOVED=false
for pkg in "${WRONG_PKGS[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        [[ "$REMOVED" == "false" ]] && info "Suppression de la pile $WRONG_META inadaptée..."
        apt-get remove -y -qq "$pkg" || true
        REMOVED=true
    fi
done
[[ "$REMOVED" == "true" ]] && apt-get autoremove -y -qq || true

# ── Install the matching stack ────────────────────────────────────────────────
info "Installation de $META ..."
apt-get update -qq
apt-get install -y "$META"

# Hailo's LLM tooling for the 10H (source package "hailo-ollama") is being
# rolled out through the same archive — install it when available.
if [[ "$CHIP" == "hailo10" ]]; then
    if apt-get install -y hailo-gen-ai-model-zoo 2>/dev/null; then
        success "hailo-gen-ai-model-zoo installé (outils LLM de Hailo)"
    else
        info "hailo-gen-ai-model-zoo pas encore installable — revérifiez après"
        info "  sudo apt update   dans quelques semaines ; la prise en charge des LLM sur NPU"
        info "  du 10H est déployée via ce paquet."
    fi
fi

# ── Verify ────────────────────────────────────────────────────────────────────
echo ""
info "Vérification de la correspondance pilote <-> périphérique..."
if modinfo hailo_pci 2>/dev/null | grep -qi "$( [[ $CHIP == hailo10 ]] && echo 45C4 || echo 2864 )"; then
    success "Le pilote prend en charge l'identifiant PCI de cette puce"
else
    warn "modinfo n'affiche pas encore l'identifiant PCI attendu (le module noyau peut"
    warn "être reconstruit via DKMS au prochain démarrage)."
fi

echo ""
success "Installation terminée — REDÉMARRAGE NÉCESSAIRE pour charger le nouveau pilote :"
echo "    sudo reboot"
echo ""
info "Après le redémarrage, vérifiez avec :"
echo "    ls -l /dev/hailo0"
echo "    hailortcli fw-control identify"
echo ""
if [[ "$CHIP" == "hailo10" ]]; then
    info "À quoi s'attendre avec le Hailo-10H :"
    info " - Les usages de vision (détection d'objets, etc.) fonctionnent via rpicam/TAPPAS."
    info " - Votre installation Ollama EXISTANTE reste sur le CPU — HailoRT est un"
    info "   environnement distinct ; le déport des LLM passe par les paquets hailo-gen-ai,"
    info "   pas par une accélération transparente d'Ollama."
fi
