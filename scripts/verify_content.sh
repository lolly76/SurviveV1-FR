#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Verify downloaded content is what it claims to be
#
# Sites that block or relocate a file frequently answer with an HTML error
# page and HTTP 200. Saved under the requested name, those files look fine in
# a listing and only reveal themselves when something tries to open them —
# which, on a survival device, could be the moment you actually need them.
#
#   bash scripts/verify_content.sh            # report only
#   bash scripts/verify_content.sh --delete   # report and remove bad files
#
# Deleted files are re-fetched by re-running the download scripts, which now
# validate magic bytes and fall back to the Wayback Machine.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
_ENV_STORAGE="${SURVIVE_STORAGE_PATH:-}"
if [[ -f "$_CONF" ]]; then source "$_CONF"; fi
STORAGE_PATH="${_ENV_STORAGE:-${SURVIVE_STORAGE_PATH:-/mnt/survive}}"

DELETE=false
[[ "${1:-}" == "--delete" ]] && DELETE=true

GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[VERIFY]${NC} $*"; }
success() { echo -e "${GREEN}[VERIFY]${NC} $*"; }
warn()    { echo -e "${YELLOW}[VERIFY]${NC} $*"; }
error()   { echo -e "${RED}[VERIFY]${NC} $*" >&2; }

# Return 0 when the file's leading bytes match its extension.
is_valid() {
    local f="$1"
    [[ -s "$f" ]] || return 1
    case "${f,,}" in
        *.pdf)
            [[ "$(head -c 4 "$f" 2>/dev/null)" == "%PDF" ]] ;;
        *.epub|*.azw3|*.zip)
            [[ "$(head -c 2 "$f" 2>/dev/null)" == "PK" ]] ;;
        *.mobi)
            head -c 68 "$f" 2>/dev/null | grep -q "BOOKMOBI" ;;
        *.zim)
            # ZIM magic is 0x005A494D ("\0ZIM") in the first four bytes.
            head -c 4 "$f" 2>/dev/null | grep -q "ZIM" ;;
        *.mbtiles)
            # MBTiles is a SQLite database.
            [[ "$(head -c 15 "$f" 2>/dev/null)" == "SQLite format 3" ]] ;;
        *.pmtiles)
            [[ "$(head -c 7 "$f" 2>/dev/null)" == "PMTiles" ]] ;;
        *)
            return 0 ;;
    esac
}

info "Vérification des contenus dans $STORAGE_PATH ..."
[[ "$DELETE" == "true" ]] && warn "--delete : les fichiers invalides SERONT supprimés" \
                          || info "(rapport seulement — ajoutez --delete pour les supprimer)"
echo ""

total=0; bad=0
declare -a BAD_FILES=()
while IFS= read -r -d '' f; do
    total=$((total + 1))
    if ! is_valid "$f"; then
        bad=$((bad + 1))
        BAD_FILES+=("$f")
        echo "  INVALIDE ${f#"$STORAGE_PATH"/}"
    fi
done < <(find "$STORAGE_PATH" \
              \( -iname '*.pdf' -o -iname '*.epub' -o -iname '*.mobi' \
                 -o -iname '*.azw3' -o -iname '*.zim' -o -iname '*.mbtiles' -o -iname '*.pmtiles' \) \
              -type f -print0 2>/dev/null)

echo ""
if (( bad == 0 )); then
    success "Les $total fichiers de contenu sont valides."
    exit 0
fi

warn "$bad fichier(s) sur $total ne correspondent pas à leur extension."
warn "Ce sont presque toujours des pages d'erreur HTML enregistrées lors d'un"
warn "téléchargement bloqué ou déplacé — elles ne peuvent être ni ouvertes ni indexées."

if [[ "$DELETE" == "true" ]]; then
    for f in "${BAD_FILES[@]}"; do rm -f "$f"; done
    success "$bad fichier(s) invalide(s) supprimé(s)."
    echo ""
    info "Retéléchargez-les (désormais avec contrôle des octets magiques + repli Wayback) :"
    info "  bash download/books_pdfs.sh    --storage $STORAGE_PATH"
    info "  bash download/gaps_content.sh  --storage $STORAGE_PATH"
    info "  bash download/mental_health.sh --storage $STORAGE_PATH"
else
    echo ""
    info "Supprimez-les avec :  bash scripts/verify_content.sh --delete"
fi
exit 1
