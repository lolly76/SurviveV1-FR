#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Téléchargeur de contenus éducatifs Kolibri
# Télécharge la chaîne Khan Academy en français pour une utilisation hors ligne
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config not found at $_CONF -- using defaults" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
KOLIBRI_HOME="$STORAGE_PATH/kolibri"

while [[ $# -gt 0 ]]; do
    case $1 in
        --storage) STORAGE_PATH="$2"; KOLIBRI_HOME="$2/kolibri"; shift 2 ;;
        *) shift ;;
    esac
done

export KOLIBRI_HOME
mkdir -p "$KOLIBRI_HOME"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}[KOLIBRI]${NC} $*"; }
success() { echo -e "${GREEN}[KOLIBRI]${NC} $*"; }
warn()    { echo -e "${YELLOW}[KOLIBRI]${NC} $*"; }

# ── Identifiants de chaînes Kolibri ──────────────────────────────────────────
# Chaîne Khan Academy en français (arbres thématiques France + Belgique :
# mathématiques, sciences, informatique, économie, etc.). Identifiant relevé
# dans la documentation du projet openzim/khan-chef (chaîne Kolibri publiée).
# Autres chaînes : https://studio.learningequality.org/ (catalogue Kolibri).
KHAN_CHANNELS=(
    "878ec2e6f88c5c268b1be6f202833cd4"  # Khan Academy (Français)
)

# ── Import d'une chaîne ─────────────────────────────────────────────────────
import_channel() {
    local name="$1"
    local channel_id="$2"

    info "Import : $name ($channel_id)"
    kolibri manage importchannel network "$channel_id" 2>/dev/null || {
        warn "Impossible d'importer la chaîne $name"
        return 0
    }

    info "Import du contenu : $name"
    kolibri manage importcontent network "$channel_id" 2>/dev/null || {
        warn "L'import du contenu a échoué pour $name"
        return 0
    }

    success "Importé : $name"
}

# ── Start Kolibri server briefly for import ───────────────────────────────────
start_kolibri() {
    info "Démarrage de Kolibri..."
    kolibri start --background 2>/dev/null
    sleep 5
}

stop_kolibri() {
    info "Arrêt de Kolibri..."
    kolibri stop 2>/dev/null || true
}

# ── Programme principal ───────────────────────────────────────────────────────
main() {
    info "Début du téléchargement du contenu Kolibri vers : $KOLIBRI_HOME"

    # Initialiser Kolibri si ce n'est pas déjà fait
    kolibri manage migrate 2>/dev/null || true
    kolibri manage createdefaultfacility 2>/dev/null || true

    start_kolibri

    # Khan Academy en français (le plus précieux pour l'apprentissage)
    for channel_id in "${KHAN_CHANNELS[@]}"; do
        import_channel "Khan Academy (Français)" "$channel_id"
    done

    stop_kolibri

    success "Téléchargement du contenu Kolibri terminé"
    info "Emplacement du contenu : $KOLIBRI_HOME"
    info "Accès : http://localhost:8082 (une fois les services démarrés)"
    du -sh "$KOLIBRI_HOME" 2>/dev/null || true
}

main "$@"
