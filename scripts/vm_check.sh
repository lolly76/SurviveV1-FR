#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Vérification après installation (VM, PC ou Raspberry Pi)
# Usage : bash scripts/vm_check.sh [--port 8080]
# Affiche PASS / WARN / FAIL pour chaque point et sort avec le code 1 s'il y a
# au moins un FAIL. Ne modifie rien.
# =============================================================================
set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT=8080
[[ "${1:-}" == "--port" && -n "${2:-}" ]] && PORT="$2"

_CONF="$REPO_DIR/config/survive.conf"
# shellcheck disable=SC1090
[[ -f "$_CONF" ]] && source "$_CONF"
STORAGE="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
BASE="http://127.0.0.1:${PORT}"

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; N='\033[0m'
FAILS=0; WARNS=0
pass() { echo -e "  ${G}[PASS]${N} $*"; }
warn() { echo -e "  ${Y}[WARN]${N} $*"; WARNS=$((WARNS+1)); }
fail() { echo -e "  ${R}[FAIL]${N} $*"; FAILS=$((FAILS+1)); }
section() { echo -e "\n${B}── $* ──${N}"; }

http_code() {
    local c
    c=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$1" 2>/dev/null) || true
    echo "${c:-000}"
}

section "Matériel et modules"
bash "$REPO_DIR/scripts/detect_hardware.sh" --table || fail "detect_hardware.sh a échoué"

section "Stockage"
if [[ -d "$STORAGE" ]]; then
    free=$(df -BG --output=avail "$STORAGE" | tail -1 | tr -dc '0-9')
    pass "Stockage : $STORAGE (${free:-?} Go libres, mode ${SURVIVE_STORAGE_MODE:-dedie})"
    for d in zim books pdfs maps; do
        [[ -d "$STORAGE/$d" ]] || warn "Dossier manquant : $STORAGE/$d"
    done
else
    fail "Dossier de stockage introuvable : $STORAGE"
fi

section "Services systemd"
if command -v systemctl >/dev/null 2>&1; then
    for u in survive-dashboard kiwix; do
        if systemctl is-active --quiet "$u"; then pass "$u actif"; else fail "$u inactif — journalctl -u $u -n 30"; fi
    done
    for u in nginx ollama kolibri calibre-web jellyfin martin-tiles; do
        if systemctl is-active --quiet "$u" 2>/dev/null; then pass "$u actif"
        elif systemctl list-unit-files "$u.service" 2>/dev/null | grep -q "$u"; then warn "$u installé mais inactif (normal si le contenu correspondant n'est pas téléchargé)"
        else warn "$u non installé"; fi
    done
else
    warn "systemctl absent — services non vérifiés"
fi

section "Tableau de bord ($BASE)"
[[ "$(http_code "$BASE/health")" == 200 ]] && pass "/health" || fail "/health ne répond pas 200"
for path in / /status /search?q=test /files /drugs /notes /comms /maps /content /apps /ai /api/system /api/status; do
    c=$(http_code "$BASE$path")
    if [[ "$c" == 200 ]]; then pass "$path → 200"; else fail "$path → $c"; fi
done

section "Accès réseau"
c=$(http_code "http://127.0.0.1:80/")
[[ "$c" =~ ^(200|301|302)$ ]] && pass "nginx :80 → $c" || warn "nginx :80 → $c"
if command -v ufw >/dev/null 2>&1; then
    if ufw status 2>/dev/null | grep -q "Status: active"; then pass "pare-feu ufw actif"; else warn "ufw inactif ou illisible (lancez avec sudo pour le détail)"; fi
fi
ip=$(hostname -I 2>/dev/null | awk '{print $1}')
[[ -n "$ip" ]] && echo -e "  ${B}[INFO]${N} Depuis un autre appareil du même réseau : http://${ip}:${PORT}"

section "IA"
state=$(bash "$REPO_DIR/scripts/detect_hardware.sh" 2>/dev/null | sed -n 's/^MOD_AI="\(.*\)"$/\1/p' | head -1)
case "$state" in
    on)     if command -v ollama >/dev/null 2>&1; then pass "IA locale activée, ollama présent"; else warn "IA locale activée mais ollama absent"; fi ;;
    remote) pass "IA déportée (SURVIVE_OLLAMA_HOST)" ;;
    *)      pass "IA locale désactivée par la détection matérielle (attendu sans AVX2 / RAM insuffisante)" ;;
esac

echo ""
echo -e "Bilan : ${FAILS} échec(s), ${WARNS} avertissement(s)."
[[ $FAILS -eq 0 ]]
