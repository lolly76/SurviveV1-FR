#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Update all content to latest versions
# Run this when internet is available to fetch updates
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"

# --scheduled: started by survive-content-update.timer overnight. Differences
# from a manual run: exit 0 quietly when offline, never overlap a manual
# update, run at low priority, and cap bandwidth with
# SURVIVE_AUTO_UPDATE_RATE_LIMIT (bytes/s) instead of SURVIVE_BANDWIDTH_LIMIT.
SCHEDULED=false
for arg in "$@"; do
    [[ "$arg" == "--scheduled" ]] && SCHEDULED=true
done

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}[UPDATE]${NC} $*"; }
success() { echo -e "${GREEN}[UPDATE]${NC} $*"; }
warn()    { echo -e "${YELLOW}[UPDATE]${NC} $*"; }

# Check internet
check_internet() {
    ping -c 1 -W 3 8.8.8.8 &>/dev/null || curl -sfI --max-time 8 https://download.kiwix.org >/dev/null 2>&1 || {
        if [[ "$SCHEDULED" == "true" ]]; then
            info "Mise à jour planifiée : pas d'Internet cette nuit -- ignorée"
            exit 0
        fi
        warn "Pas de connexion Internet. Connectez-vous pour mettre à jour le contenu."
        exit 1
    }
    success "Connexion Internet disponible"
}

setup_scheduled_run() {
    [[ "$SCHEDULED" == "true" ]] || return 0
    local pid_file="$STORAGE_PATH/.logs/update_content.pid" old
    mkdir -p "$STORAGE_PATH/.logs"
    if old=$(cat "$pid_file" 2>/dev/null) && [[ -n "$old" ]] && kill -0 "$old" 2>/dev/null \
       && [[ "$old" != "$$" ]]; then
        info "Mise à jour planifiée : une autre mise à jour (pid $old) est encore en cours -- ignorée"
        exit 0
    fi
    echo "$$" > "$pid_file"   # lets the dashboard show the run as in progress
    renice -n 15 -p $$ >/dev/null 2>&1 || true
    if [[ -n "${SURVIVE_AUTO_UPDATE_RATE_LIMIT:-}" ]] && [[ "${SURVIVE_AUTO_UPDATE_RATE_LIMIT}" != "0" ]]; then
        export SURVIVE_BANDWIDTH_LIMIT="$SURVIVE_AUTO_UPDATE_RATE_LIMIT"
        info "Mise à jour planifiée : débit limité à $(( SURVIVE_AUTO_UPDATE_RATE_LIMIT / 1024 )) KB/s"
    fi
    info "Mise à jour planifiée démarrée le $(date '+%Y-%m-%d %H:%M')"
}

main() {
    info "Mise à jour des contenus SurviveV1"
    check_internet
    setup_scheduled_run

    # Update git repo itself — pull whatever branch this clone tracks, never
    # a hardcoded one (the repo may live on main, a fork, or a test branch).
    info "Mise à jour des scripts SurviveV1..."
    local local_branch
    local_branch=$(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "HEAD")
    if [[ "$local_branch" == "HEAD" ]]; then
        warn "Le dépôt est en HEAD détaché -- mise à jour des scripts ignorée"
    elif ! git -C "$REPO_DIR" diff --quiet 2>/dev/null; then
        warn "Le dépôt a des modifications locales non validées -- mise à jour des scripts ignorée"
        warn "(un rebase sur un arbre modifié échoue en cours de route ; validez ou remisez d'abord)"
    else
        git -C "$REPO_DIR" pull --rebase origin "$local_branch" \
            && success "Scripts mis à jour ($local_branch)" || warn "Échec de git pull"
    fi

    # Update yt-dlp
    info "Mise à jour de yt-dlp..."
    yt-dlp --update && success "yt-dlp mis à jour" || warn "Échec de la mise à jour de yt-dlp"

    # Update Ollama models
    if command -v ollama &>/dev/null; then
        info "Recherche de mises à jour des modèles Ollama..."
        OLLAMA_MODELS="$STORAGE_PATH/ai_models/ollama" \
        ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | \
        while read -r model; do
            info "Mise à jour de $model..."
            OLLAMA_MODELS="$STORAGE_PATH/ai_models/ollama" ollama pull "$model" \
                && success "$model mis à jour" || warn "Échec de la mise à jour de $model"
        done
    fi

    # Update new YouTube videos (yt-dlp archive prevents re-downloading)
    if [[ "${CONTENT_VIDEOS:-Y}" =~ [Yy] ]]; then
        info "Recherche de nouvelles vidéos de survie..."
        bash "$REPO_DIR/download/videos.sh" --storage "$STORAGE_PATH" \
            || warn "Le rafraîchissement des vidéos s'est terminé avec des erreurs (voir ci-dessus)"
    fi

    # Fill gaps in the Kiwix library: newly-added catalog items, resumed
    # partials, missing titles. Deliberately NOT --update — replacing an
    # existing 100+ GB build is a manual decision, never a button press.
    info "Rafraîchissement de la bibliothèque Kiwix (contenus nouveaux ou manquants seulement)..."
    bash "$REPO_DIR/download/kiwix_content.sh" --storage "$STORAGE_PATH" \
        || warn "Le rafraîchissement de Kiwix s'est terminé avec des erreurs (voir ci-dessus)"

    # Books and PDFs (existing files are skipped)
    if [[ "${CONTENT_PDFS:-Y}" =~ [Yy] ]]; then
        info "Rafraîchissement des livres et PDF..."
        bash "$REPO_DIR/download/books_pdfs.sh" --storage "$STORAGE_PATH" \
            || warn "books_pdfs terminé avec des erreurs"
        bash "$REPO_DIR/download/gaps_content.sh" --storage "$STORAGE_PATH" \
            || warn "gaps_content terminé avec des erreurs"
        bash "$REPO_DIR/download/mental_health.sh" --storage "$STORAGE_PATH" \
            || warn "mental_health terminé avec des erreurs"
    fi

    # Refresh offline app installers (tracks newest Kiwix/VLC releases)
    if [[ "${CONTENT_APPS:-Y}" =~ [Yy] ]]; then
        info "Rafraîchissement du dépôt d'applications hors ligne..."
        bash "$REPO_DIR/download/app_depot.sh" --storage "$STORAGE_PATH" \
            || warn "app_depot terminé avec des erreurs"
    fi

    # Refresh the Meshtastic web client (skips when already current)
    if [[ "${CONTENT_MESHTASTIC:-Y}" =~ [Yy] ]]; then
        info "Rafraîchissement des outils de transmission..."
        bash "$REPO_DIR/download/comms.sh" --storage "$STORAGE_PATH" \
            || warn "comms terminé avec des erreurs"
    fi

    # Refresh the BDPM drug reference (fichiers rafraîchis ; notices déjà récupérées conservées)
    if [[ "${CONTENT_DRUGS:-Y}" =~ [YyOo] ]]; then
        info "Rafraîchissement de la référence des médicaments..."
        bash "$REPO_DIR/download/drug_reference.sh" --storage "$STORAGE_PATH" \
            || warn "drug_reference terminé avec des erreurs"
    fi

    # Re-register any new ZIM files
    if command -v kiwix-manage &>/dev/null; then
        info "Mise à jour de la bibliothèque Kiwix..."
        KIWIX_LIBRARY="$STORAGE_PATH/.kiwix_library.xml"
        while IFS= read -r -d '' zimfile; do
            kiwix-manage "$KIWIX_LIBRARY" add "$zimfile" 2>/dev/null || true
        done < <(find "$STORAGE_PATH/zim" -name "*.zim" -print0 2>/dev/null)
        success "Bibliothèque Kiwix mise à jour"
    fi

    # Rebuild the dashboard search index against the refreshed content.
    rm -f "$STORAGE_PATH/.search_index.db"

    # Incrementally index new documents for full-text search / AI retrieval.
    if command -v python3 &>/dev/null; then
        info "Mise à jour de l'index des documents..."
        python3 "$REPO_DIR/scripts/index_documents.py" --storage "$STORAGE_PATH" \
            || warn "Échec de l'indexation des documents"
    fi

    # Newly registered ZIMs appear only after kiwix-serve reloads its library.
    # Works unattended only with passwordless sudo; otherwise just say so.
    if sudo -n systemctl restart kiwix 2>/dev/null; then
        success "Kiwix redémarré — le nouveau contenu est disponible"
    else
        info "Redémarrez Kiwix pour voir les nouvelles entrées : sudo systemctl restart kiwix"
    fi

    success "Mise à jour des contenus terminée"
}

main "$@"
