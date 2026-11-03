#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Ollama setup and model management
# Optimized for Raspberry Pi 5 (4 GB default). Hailo-8L does NOT accelerate
# LLMs -- only Hailo-10H (AI HAT+ 2) does. Ollama always runs on CPU here.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
MODELS_DIR="$STORAGE_PATH/ai_models/ollama"
export OLLAMA_MODELS="$MODELS_DIR"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}[OLLAMA]${NC} $*"; }
success() { echo -e "${GREEN}[OLLAMA]${NC} $*"; }
warn()    { echo -e "${YELLOW}[OLLAMA]${NC} $*"; }

mkdir -p "$MODELS_DIR"

# ── Detect total RAM in MB (used to gate model selection) ─────────────────────
total_ram_mb() {
    awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0
}

# ── Warn if Hailo hardware is present but cannot accelerate LLMs ──────────────
detect_hailo() {
    if command -v hailortcli &>/dev/null; then
        local hw
        hw=$(hailortcli fw-control identify 2>/dev/null | awk -F: '/Device Architecture/ {print $2}' | tr -d ' ')
        if [[ -n "$hw" ]]; then
            info "Périphérique Hailo détecté : $hw"
            if [[ "$hw" == *"HAILO8"* ]] && [[ "$hw" != *"HAILO10"* ]]; then
                warn "Le Hailo-8L ne peut pas accélérer les LLM (vision uniquement, 13 TOPS)."
                warn "Ollama tournera sur le processeur. Voir docs/ai_hat_setup.md."
            fi
        fi
    fi
}

# ── Ensure Ollama is running ──────────────────────────────────────────────────
start_ollama() {
    # OLLAMA_MODELS is a SERVER-side variable. Pulling against a server that
    # was started with a different models directory silently writes there —
    # which is how the vendor's ollama.service (models in
    # /usr/share/ollama/.ollama) ends up filling the SD card. So: verify the
    # running server's directory and restart it if it disagrees.
    local pid running_dir
    pid=$(pgrep -x ollama | head -1 || true)
    if [[ -n "$pid" ]]; then
        running_dir=$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
                      | sed -n 's/^OLLAMA_MODELS=//p' | head -1)
        if [[ "$running_dir" != "$MODELS_DIR" ]]; then
            warn "Ollama tourne avec ses modèles dans ${running_dir:-/usr/share/ollama/.ollama (par défaut)}"
            warn "Redémarrage sur $MODELS_DIR pour que les modèles aillent sur votre disque de stockage"
            systemctl stop ollama 2>/dev/null || true
            pkill -x ollama 2>/dev/null || true
            sleep 2
            if pgrep -x ollama &>/dev/null; then
                warn "Impossible d'arrêter le serveur en cours — relancez ce script avec sudo,"
                warn "sinon les modèles seront écrits dans ${running_dir:-la carte SD}."
            fi
        fi
    fi

    if ! pgrep -x ollama &>/dev/null; then
        info "Démarrage du serveur Ollama (modèles : $MODELS_DIR)..."
        OLLAMA_MODELS="$MODELS_DIR" ollama serve &>/var/log/survive_ollama.log &
        sleep 4
    fi
    if curl -s http://localhost:11434 &>/dev/null; then
        success "Ollama est en marche"
    else
        warn "Ollama n'est peut-être pas encore prêt -- attente..."
        sleep 5
    fi
}

# ── Pull the model matching this Pi's RAM ─────────────────────────────────────
# CPU-only inference (Hailo-8L accelerates vision, not LLMs). Exactly ONE
# primary model is pulled, chosen by RAM, plus a 1.3 GB fast fallback:
#
#  < 6 GB RAM   gemma4:e2b            8-12 tok/s
#  6-8 GB       gemma4:e4b            3-5  tok/s
#  8-14 GB      gemma3:12b-it-q4_K_M  1-2  tok/s
#  >= 14 GB     gemma4:12b            1-3  tok/s   (16 GB Pi 5)
#  always       llama3.2:1b           fast answers when the primary is too slow
pull_models() {
    local ram_mb
    ram_mb=$(total_ram_mb)
    info "RAM totale détectée : ${ram_mb} Mo"

    # ONE model per RAM tier. These gates used to be cumulative, so a 16 GB Pi
    # downloaded every tier -- 35 GB of models where ~9 GB was wanted, and the
    # extras can never be loaded at once anyway (they exceed RAM).
    local primary
    if   (( ram_mb >= 14336 )); then primary="gemma4:12b"
    elif (( ram_mb >= 8192  )); then primary="gemma3:12b-it-q4_K_M"
    elif (( ram_mb >= 6144  )); then primary="gemma4:e4b"
    else                             primary="gemma4:e2b"
    fi

    # One tiny model always comes along: it answers in seconds when the primary
    # is too slow for an urgent question, and covers a failed primary download.
    local fallback="llama3.2:1b"

    local models=("$primary" "$fallback")
    if [[ "${PULL_ALL:-false}" == "true" ]]; then
        models=("gemma4:12b" "gemma3:12b-it-q4_K_M" "gemma4:e4b" "gemma3:4b" \
                "gemma4:e2b" "$fallback")
        warn "--all demandé : téléchargement de tous les niveaux (~35 Go)"
    else
        info "Niveau selon la RAM -> $primary  (+ $fallback en secours rapide)"
        info "Utilisez « --all » pour récupérer tous les niveaux."
    fi

    local free_gb
    free_gb=$(df -BG "$MODELS_DIR" | tail -1 | awk '{print $4}' | tr -d 'G')
    if [[ "$free_gb" =~ ^[0-9]+$ ]] && (( free_gb < 15 )); then
        warn "Seulement ${free_gb} Go libres dans $MODELS_DIR -- les téléchargements risquent d'échouer"
    fi

    for model in "${models[@]}"; do
        info "Téléchargement de $model..."
        OLLAMA_MODELS="$MODELS_DIR" ollama pull "$model" \
            && success "$model téléchargé" \
            || warn "$model : échec -- vérifiez l'espace disque"
    done
}

# ── Select best base model for available RAM ─────────────────────────────────
select_base_model() {
    local ram_mb
    ram_mb=$(total_ram_mb)
    if (( ram_mb >= 14336 )); then
        # 16 GB Pi 5: gemma4:12b — best quality, ~1-3 tok/s (acceptable for
        # survival use where accuracy matters more than speed)
        echo "gemma4:12b"
    elif (( ram_mb >= 6144 )); then
        # 8 GB Pi 5: gemma4:e4b — good quality step-up, 3-5 tok/s
        echo "gemma4:e4b"
    else
        # 4 GB Pi 5: gemma4:e2b — 8-12 tok/s, still Gemma 4 architecture
        echo "gemma4:e2b"
    fi
}

# ── Create survival-optimized Modelfile ──────────────────────────────────────
create_survival_model() {
    local base_model="$1"
    info "Création du modèle de survie à partir de $base_model..."
    local MODELFILE="$REPO_DIR/ai/Modelfile.survival"
    if [[ ! -f "$MODELFILE" ]]; then
        warn "Modelfile introuvable : $MODELFILE -- création du modèle survive ignorée"
        return
    fi
    # Patch the FROM line at build time so the correct base is baked in.
    local TMP_MF
    TMP_MF=$(mktemp)
    sed "s|^FROM .*|FROM ${base_model}|" "$MODELFILE" > "$TMP_MF"
    OLLAMA_MODELS="$MODELS_DIR" ollama create survive -f "$TMP_MF" \
        && success "Modèle « survive » créé (base : $base_model)" \
        || warn "Échec de la création du modèle"
    rm -f "$TMP_MF"
}

# ── Test models ───────────────────────────────────────────────────────────────
test_models() {
    info "Test des modèles installés..."
    MODELS_LIST=$(OLLAMA_MODELS="$MODELS_DIR" ollama list 2>/dev/null | tail -n +2 | awk '{print $1}')

    if [[ -z "$MODELS_LIST" ]]; then
        warn "Aucun modèle installé pour l'instant"
        return
    fi

    echo "Modèles installés :"
    OLLAMA_MODELS="$MODELS_DIR" ollama list

    # Test with the best available model in priority order.
    local TEST_MODEL=""
    for candidate in survive gemma4:e2b llama3.2:1b; do
        if OLLAMA_MODELS="$MODELS_DIR" ollama list 2>/dev/null | grep -q "^${candidate}"; then
            TEST_MODEL="$candidate"
            break
        fi
    done

    if [[ -n "$TEST_MODEL" ]]; then
        info "Test rapide avec $TEST_MODEL..."
        RESPONSE=$(OLLAMA_MODELS="$MODELS_DIR" ollama run "$TEST_MODEL" \
            "En une phrase : comment purifier de l'eau en la faisant bouillir ?" 2>/dev/null || echo "ÉCHEC")
        echo "Réponse : $RESPONSE"
    else
        warn "Aucun modèle testable trouvé"
    fi
}

# ── Print usage ───────────────────────────────────────────────────────────────
print_usage() {
    success "Configuration d'Ollama terminée !"
    echo ""
    echo "  Lister les modèles : ollama list"
    echo "  Discuter avec l'IA : ollama run survive"
    echo "  Question rapide :   ollama run gemma4:e2b 'Comment allumer un feu ?'"
    echo "  Interface web :     http://localhost:8080/ai"
    echo ""
    echo "  Modèles stockés :   $MODELS_DIR"
    du -sh "$MODELS_DIR" 2>/dev/null || true
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    case "${1:-setup}" in
        setup)
            detect_hailo
            start_ollama
            pull_models
            create_survival_model "$(select_base_model)"
            test_models
            print_usage
            ;;
        pull) pull_models ;;
        pull-all) PULL_ALL=true pull_models ;;
        test) start_ollama && test_models ;;
        list) OLLAMA_MODELS="$MODELS_DIR" ollama list ;;
        *) echo "Utilisation : $0 [setup|pull|pull-all|test|list]" ;;
    esac
}

main "$@"
