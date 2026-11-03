#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Start all services
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[START]${NC} $*"; }
success() { echo -e "${GREEN}[START]${NC} $*"; }
warn()    { echo -e "${YELLOW}[START]${NC} $*"; }
error()   { echo -e "${RED}[START]${NC} $*" >&2; }

preflight_check() {
    # Verify storage is mounted and has at least 100MB free
    if ! mountpoint -q "$STORAGE_PATH" 2>/dev/null; then
        if [[ "$STORAGE_PATH" != "/mnt/survive" ]]; then
            info "Le stockage $STORAGE_PATH n'est pas un montage séparé — on continue"
        else
            warn "Disque de stockage non monté sur $STORAGE_PATH"
            warn "Certains services risquent de ne pas démarrer correctement. Montez d'abord votre disque :"
            warn "  sudo mount /dev/sda1 /mnt/survive"
        fi
    fi

    local free_kb
    free_kb=$(df -k "$STORAGE_PATH" 2>/dev/null | tail -1 | awk '{print $4}') || free_kb=0
    if [[ "$free_kb" -lt 102400 ]]; then
        warn "Moins de 100 Mo libres sur $STORAGE_PATH — les services risquent de ne pas pouvoir écrire leurs journaux"
    fi
}

# Detect if running as root (systemctl) or user (direct)
USE_SYSTEMD=false
[[ $EUID -eq 0 ]] && USE_SYSTEMD=true
command -v systemctl &>/dev/null && systemctl list-units &>/dev/null && USE_SYSTEMD=true

start_service() {
    local name="$1"
    local unit="${2:-$1}"
    local desc="${3:-$name}"

    if [[ "$USE_SYSTEMD" == "true" ]]; then
        if systemctl is-enabled "$unit" &>/dev/null; then
            systemctl start "$unit" && success "$desc démarré" || warn "$desc n'a pas démarré"
        else
            warn "$unit n'est pas installé comme service systemd — démarrage manuel"
            start_manual "$name"
        fi
    else
        start_manual "$name"
    fi
}

start_manual() {
    local name="$1"
    case "$name" in
        dashboard)
            info "Démarrage du tableau de bord sur :8080..."
            source /opt/survive/venv/bin/activate 2>/dev/null || true
            cd "$REPO_DIR/web"
            PORT=8080 nohup python3 server.py > /tmp/survive_dashboard.log 2>&1 &
            echo $! > /tmp/survive_dashboard.pid
            success "Tableau de bord démarré (PID $(cat /tmp/survive_dashboard.pid))"
            ;;
        kiwix)
            KIWIX_LIB="$STORAGE_PATH/.kiwix_library.xml"
            if [[ ! -f "$KIWIX_LIB" ]]; then
                warn "Bibliothèque Kiwix introuvable — lancez d'abord les scripts de téléchargement"
                return
            fi
            info "Démarrage de Kiwix sur :8081..."
            # No --address: kiwix-serve 3.x rejects the 0.0.0.0 wildcard.
            nohup kiwix-serve \
                --library "$KIWIX_LIB" \
                --port 8081 \
                > /tmp/kiwix.log 2>&1 &
            echo $! > /tmp/kiwix.pid
            success "Kiwix démarré (PID $(cat /tmp/kiwix.pid))"
            ;;
        ollama)
            info "Démarrage d'Ollama sur :11434..."
            OLLAMA_MODELS="$STORAGE_PATH/ai_models/ollama" \
            nohup ollama serve > /tmp/ollama.log 2>&1 &
            echo $! > /tmp/ollama.pid
            success "Ollama démarré (PID $(cat /tmp/ollama.pid))"
            ;;
        maps)
            MARTIN_CONF="$STORAGE_PATH/maps/martin_config.yaml"
            if [[ ! -f "$MARTIN_CONF" ]]; then
                warn "Configuration des cartes introuvable — lancez d'abord download/maps.sh"
                return
            fi
            if command -v martin &>/dev/null; then
                info "Démarrage du serveur de tuiles Martin sur :3000..."
                nohup martin --config "$MARTIN_CONF" --listen-addresses 0.0.0.0:3000 \
                    > /tmp/martin.log 2>&1 &
                echo $! > /tmp/martin.pid
                success "Cartes démarrées (PID $(cat /tmp/martin.pid))"
            else
                warn "Martin n'est pas installé — cartes ignorées"
            fi
            ;;
        kolibri)
            if command -v kolibri &>/dev/null; then
                info "Démarrage de Kolibri sur :8082..."
                KOLIBRI_HOME="$STORAGE_PATH/kolibri" \
                nohup kolibri start --port 8082 > /tmp/kolibri.log 2>&1 &
                success "Kolibri démarré"
            else
                warn "Kolibri n'est pas installé"
            fi
            ;;
        jellyfin)
            if command -v jellyfin &>/dev/null; then
                info "Démarrage de Jellyfin sur :8096..."
                systemctl start jellyfin 2>/dev/null || \
                nohup jellyfin > /tmp/jellyfin.log 2>&1 &
                success "Jellyfin démarré"
            fi
            ;;
        calibre)
            CPS_BIN=""
            [[ -f /opt/survive/venv/bin/cps ]] && CPS_BIN=/opt/survive/venv/bin/cps
            command -v cps &>/dev/null && CPS_BIN=cps
            if [[ -n "$CPS_BIN" ]]; then
                CALIBRE_LIB="$STORAGE_PATH/books/calibre-library"
                if [[ ! -f "$CALIBRE_LIB/metadata.db" ]]; then
                    warn "Bibliothèque de livres numériques pas encore créée — lancez : bash scripts/build_ebook_library.sh"
                    warn "Calibre-Web affichera son assistant de configuration tant que la bibliothèque n'existe pas."
                fi
                info "Démarrage de Calibre-Web sur :8083..."
                mkdir -p "$CALIBRE_LIB"
                CALIBRE_DBPATH="$CALIBRE_LIB" \
                nohup "$CPS_BIN" -p 8083 -i 127.0.0.1 \
                    > /tmp/calibre.log 2>&1 &
                echo $! > /tmp/calibre.pid
                success "Calibre-Web démarré (PID $(cat /tmp/calibre.pid))"
            else
                warn "Calibre-Web n'est pas installé"
            fi
            ;;
    esac
}

# ── Print access URLs ─────────────────────────────────────────────────────────
print_urls() {
    # Get local IP
    LOCAL_IP=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "localhost")
    HOSTNAME="${SURVIVE_HOSTNAME:-survive}"

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║       Adresses de SurviveV1            ║${NC}"
    echo -e "${GREEN}╠════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC} Tableau :    http://$LOCAL_IP:8080    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}             http://$HOSTNAME.local:8080${GREEN}║${NC}"
    echo -e "${GREEN}║${NC} Wikipédia:   http://$LOCAL_IP:8081    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC} Éducation:   http://$LOCAL_IP:8082    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC} Livres:      http://$LOCAL_IP:8083    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC} Vidéos:      http://$LOCAL_IP:8096    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC} Cartes:      http://$LOCAL_IP:3000    ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC} IA:          http://$LOCAL_IP:8080/ai ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    info "Démarrage des services SurviveV1..."
    preflight_check

    start_manual dashboard
    start_manual kiwix
    start_manual ollama
    start_manual maps
    start_manual kolibri
    start_manual jellyfin
    start_manual calibre

    # Wait up to 15 s for the dashboard to respond before printing URLs
    local retries=30
    while [[ $retries -gt 0 ]]; do
        if curl -sf "http://localhost:8080/health" >/dev/null 2>&1; then break; fi
        sleep 0.5
        retries=$((retries - 1))
    done
    [[ $retries -eq 0 ]] && warn "Le tableau de bord n'a pas répondu en 15 s — les adresses ne sont peut-être pas encore prêtes"

    print_urls

    info "Arrêt :   bash scripts/stop_services.sh"
    info "État :    bash scripts/status.sh"
}

main "$@"
