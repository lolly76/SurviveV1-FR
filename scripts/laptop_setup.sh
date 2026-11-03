#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Réglages propres aux portables (appelé par setup/install.sh)
# Usage : sudo bash scripts/laptop_setup.sh <lid:on|off> <battery:on|off>
#  - lid     : la fermeture du capot ne met plus la machine en veille
#                (sinon les services s'arrêtent dès que le portable est refermé)
#  - battery : rien à installer ; le tableau de bord lit /sys/class/power_supply
# =============================================================================
set -euo pipefail

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}[PORTABLE]${NC} $*"; }
success() { echo -e "${GREEN}[PORTABLE]${NC} $*"; }
warn()    { echo -e "${YELLOW}[PORTABLE]${NC} $*"; }

LID="${1:-off}"
BATTERY="${2:-off}"
LOGIND_DROPIN="${LOGIND_DROPIN_DIR:-/etc/systemd/logind.conf.d}/survive-portable.conf"

if [[ "$LID" == "on" ]]; then
    [[ $EUID -eq 0 ]] || { echo "Lancez avec sudo" >&2; exit 1; }
    mkdir -p "$(dirname "$LOGIND_DROPIN")"
    cat > "$LOGIND_DROPIN" <<'CONF'
# Généré par SurviveV1 (scripts/laptop_setup.sh) : le portable reste allumé capot fermé.
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
CONF
    # Prise en compte au prochain démarrage ; un redémarrage de logind peut fermer
    # la session graphique, donc on ne le force pas.
    success "Capot fermé : la machine ne se met plus en veille (effectif au prochain démarrage)"
    info "Retour arrière : sudo rm $LOGIND_DROPIN"
fi

if [[ "$BATTERY" == "on" ]]; then
    success "Batterie détectée : elle sert d'onduleur de secours (état visible sur la page État)"
    warn "Conseil BIOS : limiter la charge à ~80 % (si disponible) prolonge la vie d'une batterie reconditionnée."
fi
