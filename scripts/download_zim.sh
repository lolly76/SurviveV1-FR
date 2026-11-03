#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Download ONE ZIM file picked in the dashboard's Library page
#
#   bash scripts/download_zim.sh <zim-url> [dest-subdir]
#
# Called detached by web/server.py (POST /api/content/download) and usable by
# hand. Resumable (aria2c or wget -c), validates the ZIM magic bytes, honours
# SURVIVE_BANDWIDTH_LIMIT, keeps a 10 GB free-space margin, then registers
# the file with Kiwix via scripts/rescan_library.sh.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
URL="${1:-}"
SUBDIR="${2:-catalog}"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[ZIM]${NC} $*"; }
success() { echo -e "${GREEN}[ZIM]${NC} $*"; }
warn()    { echo -e "${YELLOW}[ZIM]${NC} $*"; }
error()   { echo -e "${RED}[ZIM]${NC} $*" >&2; }

[[ -n "$URL" ]] || { error "Utilisation : $0 <url-zim> [sous-dossier]"; exit 2; }
case "$URL" in
    https://download.kiwix.org/*|https://lb.download.kiwix.org/*|https://mirror.download.kiwix.org/*) ;;
    *) error "Refus de télécharger hors de download.kiwix.org : $URL"; exit 2 ;;
esac
[[ "$URL" == *.zim ]] || { error "Ce n'est pas une URL .zim : $URL"; exit 2; }
[[ "$SUBDIR" =~ ^[a-z0-9_-]+$ ]] || { error "Sous-dossier de destination invalide : $SUBDIR"; exit 2; }

ZIM_DIR="$STORAGE_PATH/zim"
DEST_DIR="$ZIM_DIR/$SUBDIR"
FILENAME=$(basename "$URL")
DEST="$DEST_DIR/$FILENAME"
mkdir -p "$DEST_DIR"

MARGIN_BYTES=$((10 * 1024 * 1024 * 1024))
_space_ok() {  # _space_ok <bytes-needed>
    local need="$1" free
    free=$(df -B1 --output=avail "$ZIM_DIR" 2>/dev/null | tail -1 | tr -dc '0-9')
    [[ -n "$free" ]] || return 0
    (( free - need > MARGIN_BYTES ))
}

_zim_magic_ok() {
    [[ "$(head -c 4 "$1" 2>/dev/null | tr -d '\0')" == *ZIM* ]]
}

# Already own this title (any build, any subdir)? Then there is nothing to do.
prefix="${FILENAME%_*.zim}"
existing=$(find "$ZIM_DIR" -type f -name "${prefix}_*.zim" ! -name "*.aria2" 2>/dev/null | head -1 || true)
if [[ -n "$existing" ]] && [[ ! -f "$existing.aria2" ]] && _zim_magic_ok "$existing"; then
    remote_sz=$(curl -sIL --max-time 30 "$URL" 2>/dev/null | grep -i '^content-length' | tail -1 | tr -dc '0-9' || true)
    local_sz=$(stat -c %s "$existing" 2>/dev/null || echo 0)
    if [[ "$existing" == "$DEST" ]] && { [[ -z "$remote_sz" ]] || (( local_sz >= remote_sz )); }; then
        success "Déjà téléchargé : $existing"
        exit 0
    fi
    if [[ "$existing" != "$DEST" ]]; then
        success "Une version de ce titre est déjà sur le disque : $existing"
        info "Supprimez-la d'abord si vous voulez la remplacer par $FILENAME"
        exit 0
    fi
fi

# Under `set -e -o pipefail` a grep with no match would abort the script, so
# an unreachable mirror must fall through to the "size unknown" path instead.
remote_sz=$(curl -sIL --max-time 30 "$URL" 2>/dev/null | grep -i '^content-length' | tail -1 | tr -dc '0-9' || true)
if ! curl -sIL --max-time 30 -o /dev/null "$URL" 2>/dev/null; then
    error "Impossible de joindre $URL -- le Pi est-il en ligne ?"
    exit 5
fi
local_sz=0
[[ -f "$DEST" ]] && local_sz=$(stat -c %s "$DEST" 2>/dev/null || echo 0)
if [[ -n "$remote_sz" ]]; then
    need=$(( remote_sz > local_sz ? remote_sz - local_sz : 0 ))
    if ! _space_ok "$need"; then
        error "Espace libre insuffisant : il faut $(( need / 1024 / 1024 )) Mo plus 10 Go de marge"
        exit 3
    fi
    info "Téléchargement de $FILENAME ($(( remote_sz / 1024 / 1024 )) Mo)"
else
    info "Téléchargement de $FILENAME (taille inconnue)"
fi

BW_ARGS=()
if command -v aria2c &>/dev/null; then
    [[ "${SURVIVE_BANDWIDTH_LIMIT:-0}" != "0" ]] && BW_ARGS=(--max-overall-download-limit="${SURVIVE_BANDWIDTH_LIMIT}")
    aria2c -c -x 4 -s 4 --file-allocation=none --summary-interval=15 --console-log-level=warn \
        --max-tries=5 --retry-wait=10 "${BW_ARGS[@]}" -d "$DEST_DIR" -o "$FILENAME" "$URL" \
        || { error "Échec du téléchargement -- relancez pour reprendre"; exit 5; }
else
    [[ "${SURVIVE_BANDWIDTH_LIMIT:-0}" != "0" ]] && BW_ARGS=(--limit-rate="${SURVIVE_BANDWIDTH_LIMIT}")
    wget -c --progress=dot:giga --tries=5 --timeout=60 "${BW_ARGS[@]}" -O "$DEST" "$URL" \
        || { error "Échec du téléchargement -- relancez pour reprendre"; exit 5; }
fi

if ! _zim_magic_ok "$DEST"; then
    error "Le fichier téléchargé n'est pas un ZIM valide -- suppression"
    rm -f "$DEST" "$DEST.aria2"
    exit 4
fi
success "Téléchargement terminé : $DEST"

# Make it visible: register with Kiwix, drop the filename index, restart kiwix.
bash "$REPO_DIR/scripts/rescan_library.sh" --storage "$STORAGE_PATH" || warn "La réanalyse a signalé des erreurs"
