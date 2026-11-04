#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Master content download orchestrator
# Usage: bash download_all.sh [--storage /mnt/survive] [--resume] [--dry-run]
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

# ── Argument parsing ──────────────────────────────────────────────────────────
STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
RESUME=false
DRY_RUN=false
CATEGORY=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --storage) STORAGE_PATH="$2"; shift 2 ;;
        --resume)  RESUME=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --only)    CATEGORY="$2"; shift 2 ;;
        *) echo "Option inconnue : $1"; shift ;;
    esac
done

LOG_DIR="$STORAGE_PATH/.logs"
mkdir -p "$LOG_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[DL]${NC} $*"; }
success() { echo -e "${GREEN}[DL]${NC} $*"; }
warn()    { echo -e "${YELLOW}[DL]${NC} $*"; }
error()   { echo -e "${RED}[DL]${NC} $*" >&2; }

section() {
    echo ""
    echo -e "${BLUE}══════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $*${NC}"
    echo -e "${BLUE}══════════════════════════════════════════════${NC}"
}

run_or_dry() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[SIMULATION] $*"
    else
        "$@"
    fi
}

# ── Disk space check ──────────────────────────────────────────────────────────
check_disk_space() {
    # Refuse to write onto the SD card. If the configured storage path is not
    # a real mountpoint, hundreds of GB of downloads land on the root
    # filesystem — and are then HIDDEN under the mount when the drive finally
    # appears, silently filling the card.
    if [[ "$STORAGE_PATH" == /mnt/* ]] && ! mountpoint -q "$STORAGE_PATH"; then
        error "$STORAGE_PATH n'est pas un disque monté — les téléchargements rempliraient la carte SD."
        error "Montez d'abord votre stockage (sudo mount $STORAGE_PATH), ou relancez l'assistant :"
        error "  sudo bash install/wizard.sh"
        exit 1
    fi

    AVAILABLE_GB=$(df -BG "$STORAGE_PATH" | tail -1 | awk '{print $4}' | tr -d 'G')
    BUDGET_GB="${SURVIVE_BUDGET_GB:-800}"
    info "Disponible : ${AVAILABLE_GB} Go | Budget : ${BUDGET_GB} Go"
    if [[ "$AVAILABLE_GB" -lt 50 ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            warn "Moins de 50 Go libres sur $STORAGE_PATH (simulation : on continue)."
        else
            error "Moins de 50 Go libres sur $STORAGE_PATH. Abandon."
            exit 1
        fi
    fi
}

# ── Progress tracking ─────────────────────────────────────────────────────────
PROGRESS_FILE="$STORAGE_PATH/.download_progress"
PROGRESS_LOCK="${PROGRESS_FILE}.lock"
mark_done() {
    (
        flock -x 200
        echo "$1" >> "$PROGRESS_FILE"
    ) 200>"$PROGRESS_LOCK"
}
is_done() {
    (
        flock -s 200
        grep -qxF "$1" "$PROGRESS_FILE" 2>/dev/null
    ) 200>"$PROGRESS_LOCK"
}

# ── Content size estimates ────────────────────────────────────────────────────
print_budget() {
    section "Récapitulatif du budget de téléchargement"
    printf "%-40s %10s\n" "Contenu" "Taille est."
    printf "%-40s %10s\n" "--------" "-----------"
    [[ "${CONTENT_WIKIPEDIA:-Y}" =~ [Yy] ]]      && printf "%-40s %10s\n" "Wikipédia FR (complète)" "~52 Go"
    [[ "${CONTENT_WIKIPEDIA_NOPIC:-N}" =~ [Yy] ]] && printf "%-40s %10s\n" "Wikipédia FR (sans images)" "~12 Go"
    [[ "${CONTENT_WIKIBOOKS:-Y}" =~ [Yy] ]]       && printf "%-40s %10s\n" "Wikilivres, Wikivoyage, Wikisource, Wiktionnaire" "~17 Go"
    [[ "${CONTENT_IFIX:-Y}" =~ [Yy] ]]            && printf "%-40s %10s\n" "iFixit : guides de réparation (FR)" "~3,5 Go"
    [[ "${CONTENT_STACKEXCHANGE:-Y}" =~ [Yy] ]]   && printf "%-40s %10s\n" "Stack Exchange (langue française)" "<1 Go"
    [[ "${CONTENT_STACKEXCHANGE_EN:-N}" =~ [Yy] ]] && printf "%-40s %10s\n" "Stack Exchange (EN, option)" "~40 Go"
    [[ "${CONTENT_GUTENBERG:-Y}" =~ [Yy] ]]       && printf "%-40s %10s\n" "Projet Gutenberg (livres FR)" "~15 Go"
    [[ "${CONTENT_KHAN_ZIM:-Y}" =~ [Yy] ]]        && printf "%-40s %10s\n" "Khan Academy FR (ZIM Kiwix)" "~94 Go"
    [[ "${CONTENT_KOLIBRI:-Y}" =~ [Yy] ]]         && printf "%-40s %10s\n" "Khan Academy (Kolibri)" "~200 Go"
    [[ "${CONTENT_VIDEOS:-Y}" =~ [Yy] ]]          && printf "%-40s %10s\n" "Vidéos de survie" "~150 Go"
    [[ "${CONTENT_MAPS:-Y}" =~ [Yy] ]]            && printf "%-40s %10s\n" "Cartes OpenStreetMap (France par défaut)" "~5 Go"
    [[ "${CONTENT_PDFS:-Y}" =~ [Yy] ]]            && printf "%-40s %10s\n" "PDF + manuels" "~20 Go"
    [[ "${CONTENT_GAPS_EN:-Y}" =~ [Yy] ]]         && printf "%-40s %10s\n" "Contenus experts (pack English)" "~15 Go"
    if [[ "${CONTENT_BASE_EN:-N}" =~ [Yy] ]]; then
        case "${CONTENT_BASE_EN_WIKIPEDIA:-nopic}" in
            maxi)  printf "%-40s %10s\n" "Phase 2 : base anglaise (Wikipédia maxi)" "~130 Go" ;;
            N|n)   printf "%-40s %10s\n" "Phase 2 : base anglaise (sans Wikipédia)" "~15 Go" ;;
            *)     printf "%-40s %10s\n" "Phase 2 : base anglaise (Wikipédia nopic)" "~25 Go" ;;
        esac
        [[ "${CONTENT_BASE_EN_KHAN:-N}" =~ [Yy] ]] && printf "%-40s %10s\n" "Khan Academy EN (ZIM)" "~90 Go"
    fi
    [[ "${CONTENT_AI_MODELS:-Y}" =~ [Yy] ]]       && printf "%-40s %10s\n" "Modèles d'IA (Ollama)" "~50 Go"
    [[ "${CONTENT_NPS_MAPS:-N}" =~ [Yy] ]]        && printf "%-40s %10s\n" "Cartes des parcs nationaux + satellite" "~3 Go"
    [[ "${CONTENT_MESHTASTIC:-Y}" =~ [Yy] ]]      && printf "%-40s %10s\n" "Outils de transmission (Meshtastic web)" "<1 Go"
    printf "%-40s %10s\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "━━━━━━━━━"
    printf "%-40s %10s\n" "Total (approx.)" "~800 Go"
    echo ""
}

# ── Main download dispatcher ──────────────────────────────────────────────────
main() {
    info "Téléchargement des contenus SurviveV1"
    info "Stockage : $STORAGE_PATH"
    info "Reprise : $RESUME | Simulation : $DRY_RUN"

    check_disk_space
    print_budget

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Mode simulation — aucun fichier téléchargé"
        return 0
    fi

    # run_category <name> <enabled Y/N> <script> [extra args...]
    # With --resume, categories recorded in $PROGRESS_FILE are skipped; each
    # category is marked done only after its script exits successfully.
    run_category() {
        local name="$1" enabled="$2" script="$3"
        shift 3
        if [[ -n "$CATEGORY" ]] && [[ "$CATEGORY" != "$name" ]]; then return 0; fi
        if [[ ! "$enabled" =~ [Yy] ]]; then
            info "$name ignoré (désactivé dans survive.conf)"
            return 0
        fi
        if [[ "$RESUME" == "true" ]] && is_done "$name"; then
            info "$name ignoré (déjà terminé — retirez-le de $PROGRESS_FILE pour recommencer)"
            return 0
        fi
        if run_or_dry bash "$REPO_DIR/download/$script" --storage "$STORAGE_PATH" "$@"; then
            [[ "$DRY_RUN" == "true" ]] || mark_done "$name"
        else
            warn "Échec du téléchargement de $name — relancez avec --resume pour reprendre le reste"
        fi
    }

    RESUME_FLAG=()
    [[ "$RESUME" == "true" ]] && RESUME_FLAG=(--resume)

    run_category kiwix         "Y"                          kiwix_content.sh "${RESUME_FLAG[@]}"
    run_category videos        "${CONTENT_VIDEOS:-Y}"       videos.sh
    run_category books         "${CONTENT_GUTENBERG:-Y}"    books_pdfs.sh
    run_category maps          "${CONTENT_MAPS:-Y}"         maps.sh
    run_category kolibri       "${CONTENT_KOLIBRI:-Y}"      kolibri_content.sh
    run_category gaps          "Y"                          gaps_content.sh
    run_category mental_health "Y"                          mental_health.sh
    run_category apps          "${CONTENT_APPS:-Y}"         app_depot.sh
    run_category drugs         "${CONTENT_DRUGS:-Y}"        drug_reference.sh
    run_category comms         "${CONTENT_MESHTASTIC:-Y}"   comms.sh

    # Invalidate the dashboard's filename search index so it rebuilds with the
    # newly downloaded files on the next /search.
    rm -f "$STORAGE_PATH/.search_index.db"

    section "Download Complete"
    df -h "$STORAGE_PATH"
    success "Tous les contenus sélectionnés sont téléchargés dans $STORAGE_PATH"
    info "Démarrer les services : bash scripts/start_services.sh"
}

main "$@"
