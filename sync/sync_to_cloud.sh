#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Sync content to cloud storage
# Usage: bash sync/sync_to_cloud.sh [remote] [--category videos] [--dry-run]
#
# Examples:
#   bash sync/sync_to_cloud.sh gdrive
#   bash sync/sync_to_cloud.sh dropbox --category pdfs
#   bash sync/sync_to_cloud.sh s3 --dry-run
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
REMOTE="${1:-gdrive}"
REMOTE_PATH="${SURVIVE_CLOUD_PATH:-SurviveV1}"
CATEGORY=""
DRY_RUN=false
BANDWIDTH=""  # e.g. "10M" to limit to 10MB/s

shift 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --category) CATEGORY="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=true; shift ;;
        --bw)       BANDWIDTH="$2"; shift 2 ;;
        --remote-path) REMOTE_PATH="$2"; shift 2 ;;
        *) shift ;;
    esac
done

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[SYNC→CLOUD]${NC} $*"; }
success() { echo -e "${GREEN}[SYNC→CLOUD]${NC} $*"; }
warn()    { echo -e "${YELLOW}[SYNC→CLOUD]${NC} $*"; }
error()   { echo -e "${RED}[SYNC→CLOUD]${NC} $*" >&2; }

LOG_FILE="$STORAGE_PATH/.logs/sync_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

# ── Check remote ──────────────────────────────────────────────────────────────
check_remote() {
    if ! rclone listremotes 2>/dev/null | grep -q "^${REMOTE}:"; then
        error "Stockage « $REMOTE » non configuré. Lancez : bash sync/setup_rclone.sh $REMOTE"
        exit 1
    fi
    success "Stockage « $REMOTE » configuré"
}

# ── Sync function ─────────────────────────────────────────────────────────────
sync_dir() {
    local local_dir="$1"
    local remote_dir="$2"
    local label="$3"

    if [[ ! -d "$local_dir" ]]; then
        warn "$label : $local_dir n'existe pas, ignoré"
        return
    fi

    local size
    size=$(du -sh "$local_dir" 2>/dev/null | cut -f1)
    info "Synchronisation de $label ($size) → $REMOTE:$REMOTE_PATH/$remote_dir"

    local FLAGS=(
        --progress
        --log-file="$LOG_FILE"
        --log-level INFO
        --transfers 4
        --checkers 8
        --drive-chunk-size 128M
        --retries 3
        --low-level-retries 10
        --stats 60s
    )

    if [[ "$DRY_RUN" == "true" ]]; then
        FLAGS+=(--dry-run)
    fi

    if [[ -n "$BANDWIDTH" ]]; then
        FLAGS+=(--bwlimit "$BANDWIDTH")
    fi

    rclone sync "$local_dir" \
        "$REMOTE:$REMOTE_PATH/$remote_dir" \
        "${FLAGS[@]}" \
    && success "$label synchronisé" \
    || warn "La synchronisation de $label a rencontré des erreurs — voir $LOG_FILE"
}

# ── Size check ────────────────────────────────────────────────────────────────
check_cloud_quota() {
    info "Vérification du quota de stockage cloud..."
    rclone about "$REMOTE:" 2>/dev/null || warn "Impossible de vérifier le quota"
}

# ── Main sync ─────────────────────────────────────────────────────────────────
main() {
    info "Synchronisation SurviveV1 → Cloud"
    info "Stockage : $REMOTE | Chemin : $REMOTE_PATH | Simulation : $DRY_RUN"
    echo ""

    check_remote
    check_cloud_quota

    if [[ -n "$CATEGORY" ]]; then
        # Sync only specified category
        sync_dir "$STORAGE_PATH/$CATEGORY" "$CATEGORY" "$CATEGORY"
    else
        # Sync all categories
        echo ""
        info "Synchronisation de toutes les catégories..."
        echo ""

        # PDFs and books are highest priority (smallest, most useful)
        sync_dir "$STORAGE_PATH/pdfs"  "pdfs"  "PDFs & Manuals"
        sync_dir "$STORAGE_PATH/books" "books" "Books & EPUBs"

        # ZIM files (large)
        sync_dir "$STORAGE_PATH/zim"   "zim"   "Kiwix ZIM files"

        # Videos (very large — may want to skip or do separately)
        FREE_REMOTE=$(rclone about "$REMOTE:" --json 2>/dev/null | \
            python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('free',0)//(1024**3))" \
            2>/dev/null || echo "0")

        if [[ "$FREE_REMOTE" -gt 50 ]]; then
            sync_dir "$STORAGE_PATH/videos" "videos" "Survival Videos"
        else
            warn "Moins de 50 Go libres sur $REMOTE — vidéos ignorées"
            warn "Lancez avec : bash sync/sync_to_cloud.sh $REMOTE --category videos"
        fi

        sync_dir "$STORAGE_PATH/maps"  "maps"  "Offline Maps"
    fi

    echo ""
    success "Synchronisation terminée. Journal : $LOG_FILE"

    # Show remote usage after sync
    info "Stockage cloud après synchronisation :"
    rclone about "$REMOTE:" 2>/dev/null || true
}

main
