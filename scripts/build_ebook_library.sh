#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Build/refresh the Calibre e-book library
#
# Calibre-Web (cps) cannot serve a plain folder of EPUBs — it needs a real
# Calibre library (a metadata.db created by calibredb). This script builds that
# library from every ebook under books/ and is safe to re-run after each
# download (idempotent via --automerge=ignore).
#
# Usage: bash scripts/build_ebook_library.sh
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
# Capture an explicitly-set env override before sourcing the conf, so a caller
# (or test) passing SURVIVE_STORAGE_PATH= wins over the conf's baked-in default.
_ENV_STORAGE="${SURVIVE_STORAGE_PATH:-}"
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

STORAGE_PATH="${_ENV_STORAGE:-${SURVIVE_STORAGE_PATH:-/mnt/survive}}"
BOOKS_DIR="$STORAGE_PATH/books"
LIBRARY="$BOOKS_DIR/calibre-library"

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[EBOOK]${NC} $*"; }
success() { echo -e "${GREEN}[EBOOK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[EBOOK]${NC} $*"; }
error()   { echo -e "${RED}[EBOOK]${NC} $*" >&2; }

# ── Preconditions ─────────────────────────────────────────────────────────────
if ! command -v calibredb &>/dev/null; then
    error "calibredb introuvable. Installez d'abord Calibre :  sudo apt-get install -y calibre"
    exit 1
fi

mkdir -p "$BOOKS_DIR"

# calibredb cannot write the library while calibre-web holds it open — pause it.
CALIBRE_WAS_RUNNING=false
if command -v systemctl &>/dev/null && systemctl is-active --quiet calibre-web 2>/dev/null; then
    CALIBRE_WAS_RUNNING=true
    info "Calibre-Web mis en pause pendant la mise à jour de la bibliothèque..."
    systemctl stop calibre-web 2>/dev/null || true
fi
restore_calibre() {
    if [[ "$CALIBRE_WAS_RUNNING" == "true" ]]; then
        info "Redémarrage de Calibre-Web..."
        systemctl start calibre-web 2>/dev/null || true
    fi
}
trap restore_calibre EXIT

# ── Add ebooks (idempotent) ───────────────────────────────────────────────────
# --automerge=ignore skips books already present, so re-runs add only new files.
# Prune the library dir itself so we never re-ingest Calibre's own copies.
info "Recherche de livres numériques dans $BOOKS_DIR..."
mapfile -d '' EBOOKS < <(
    find "$BOOKS_DIR" -path "$LIBRARY" -prune -o \
        -type f \( -iname '*.epub' -o -iname '*.mobi' -o -iname '*.azw3' \) -print0
)

if [[ ${#EBOOKS[@]} -eq 0 ]]; then
    warn "Aucun livre numérique trouvé dans $BOOKS_DIR pour l'instant."
    # Calibre-Web refuses to start against a directory with no metadata.db
    # ("new db is invalid"), so create a valid empty library rather than
    # leaving the service unusable. --empty adds a formatless placeholder
    # record, which is what forces the database into existence.
    if [[ ! -f "$LIBRARY/metadata.db" ]]; then
        info "Création d'une bibliothèque Calibre vide pour que Calibre-Web puisse démarrer..."
        mkdir -p "$LIBRARY"
        calibredb add --with-library="$LIBRARY" --empty \
            --title "SurviveV1 placeholder (delete once you add books)" \
            >/dev/null 2>&1 || warn "Impossible d'initialiser une bibliothèque vide"
    fi
    [[ -f "$LIBRARY/metadata.db" ]] && ok_msg="ready" || ok_msg="NOT created"
    warn "Bibliothèque $LIBRARY : $ok_msg"
    warn "Ajoutez du contenu avec :  bash download/books_pdfs.sh"
    exit 0
fi

info "Import de ${#EBOOKS[@]} livre(s) numérique(s) dans la bibliothèque (les doublons sont ignorés)..."
calibredb add --with-library="$LIBRARY" --automerge=ignore -- "${EBOOKS[@]}" \
    || { error "Échec de calibredb add"; exit 1; }

# Ownership: the systemd unit runs cps as User=pi, which needs write access.
_SVC_USER="${SUDO_USER:-pi}"
if [[ "$(id -u)" -eq 0 ]] && id "$_SVC_USER" &>/dev/null; then
    chown -R "$_SVC_USER:$_SVC_USER" "$LIBRARY"
fi

COUNT=$(calibredb --with-library="$LIBRARY" list 2>/dev/null | tail -n +2 | wc -l)
success "Bibliothèque prête : ${COUNT} livre(s) dans $LIBRARY"
echo ""
info "Dans Calibre-Web (http://<hôte>:8083), au premier lancement, indiquez la base de données :"
info "emplacement :  $LIBRARY"
info "Identifiants par défaut :  admin / admin123  — changez-les immédiatement."
