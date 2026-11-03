#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Contenus « experts » complémentaires (version française)
# Couvre : médecine avancée, obstétrique, dentaire, assainissement, élevage,
#         semences, forge, fermentation, apiculture, sécurité, communauté, etc.
# Les listes de documents sont dans config/gaps_extra.list (voir ci-dessous).
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config not found at $_CONF -- using defaults" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
PDF_DIR="$STORAGE_PATH/pdfs"
VIDEO_DIR="$STORAGE_PATH/videos"
LOG_DIR="$STORAGE_PATH/.logs"

while [[ $# -gt 0 ]]; do
    case $1 in
        --storage) STORAGE_PATH="$2"; shift 2 ;;
        *) shift ;;
    esac
done

mkdir -p "$PDF_DIR"/{medicine_advanced,obstetrics,dental,sanitation,animal_husbandry,\
blacksmithing,fermentation,beeswax,seeds,security,psychology,community,water_systems,\
primitive_skills,permaculture,economics,radio}
mkdir -p "$VIDEO_DIR"/{primitive_skills,fermentation,blacksmithing,animal_husbandry,security}
mkdir -p "$LOG_DIR"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}[GAPS]${NC} $*"; }
success() { echo -e "${GREEN}[GAPS]${NC} $*"; }
warn()    { echo -e "${YELLOW}[GAPS]${NC} $*"; }

FAILED_LOG="$LOG_DIR/failed_downloads.log"


# Many .gov/.org sites now reject non-browser clients (HTTP 403) or have moved
# files (404). Two mitigations, in order:
#   1. present a normal browser User-Agent
#   2. fall back to the Wayback Machine, which keeps byte-identical snapshots
#      ("id_" returns the original file, without the archive toolbar)
SURVIVE_UA="Mozilla/5.0 (X11; Linux aarch64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"

_fetch() {  # _fetch <url> <dest-file>
    wget -q --show-progress --tries=3 --timeout=60 \
        --user-agent="$SURVIVE_UA" -O "$2" "$1"
}

# A blocked or moved request often returns an HTML page with HTTP 200. Saving
# that as a .pdf/.epub hides the failure until someone opens it — Standard
# Ebooks did exactly this, producing six "books" that were XHTML pages and
# made Calibre fail with "File is not a zip file".
_is_valid_download() {
    [[ -s "$1" ]] || return 1
    local magic
    case "${1,,}" in
        *.pdf)
            [[ "$(head -c 4 "$1" 2>/dev/null)" == "%PDF" ]] ;;
        *.epub|*.mobi|*.azw3|*.zip)
            # EPUB/AZW3 are ZIP containers -> "PK"; MOBI starts with its own
            # header, so accept either rather than rejecting valid files.
            magic=$(head -c 2 "$1" 2>/dev/null)
            [[ "$magic" == "PK" ]] || head -c 68 "$1" 2>/dev/null | grep -q "BOOKMOBI" ;;
        *)
            return 0 ;;   # unknown type: size check only
    esac
}

# Try the original URL, then its most recent Wayback snapshot.
_fetch_with_fallback() {  # _fetch_with_fallback <url> <dest-file> <name>
    if _fetch "$1" "$2" && _is_valid_download "$2"; then
        return 0
    fi
    rm -f "$2"
    echo "  [$3] direct download failed -- trying the Wayback Machine..." >&2
    if _fetch "https://web.archive.org/web/2id_/$1" "$2" && _is_valid_download "$2"; then
        return 0
    fi
    rm -f "$2"
    return 1
}

# WHO moved its repository (IRIS) to DSpace 7 in 2024: the old
# apps.who.int/iris/bitstream/... links now return the web app's HTML shell
# instead of the PDF. Resolve handle -> item -> ORIGINAL bundle -> first PDF
# bitstream through the public REST API; fall back to the old URL (and its
# Wayback copy) if the API is unreachable.
who_pdf_url() {  # who_pdf_url <handle e.g. 10665/44615> <fallback-url>
    local handle="$1" fallback="$2" api="https://iris.who.int/server/api" item bundle bs
    item=$(curl -sL --max-time 30 -A "$SURVIVE_UA" "$api/pid/find?id=hdl:$handle" 2>/dev/null \
           | grep -oE '"uuid" *: *"[0-9a-f-]{36}"' | head -1 | grep -oE '[0-9a-f-]{36}' || true)
    [[ -n "$item" ]] || { echo "$fallback"; return 0; }
    bundle=$(curl -sL --max-time 30 -A "$SURVIVE_UA" "$api/core/items/$item/bundles" 2>/dev/null \
             | tr -d '\n ' | grep -oE '"uuid":"[0-9a-f-]{36}","name":"ORIGINAL"' | grep -oE '[0-9a-f-]{36}' || true)
    [[ -n "$bundle" ]] || { echo "$fallback"; return 0; }
    bs=$(curl -sL --max-time 30 -A "$SURVIVE_UA" "$api/core/bundles/$bundle/bitstreams" 2>/dev/null \
         | tr -d '\n ' | grep -oE '"uuid":"[0-9a-f-]{36}","name":"[^"]+\.pdf"' | head -1 | grep -oE '^"uuid":"[0-9a-f-]{36}' | grep -oE '[0-9a-f-]{36}' || true)
    [[ -n "$bs" ]] || { echo "$fallback"; return 0; }
    echo "$api/core/bitstreams/$bs/content"
}

dl_who() {  # dl_who <name> <handle> <old-url> <dest-dir> <filename>
    dl_file "$1" "$(who_pdf_url "$2" "$3")" "$4" "$5"
}

dl_file() {
    local name="$1"
    local url="$2"
    local dest="$3"
    local filename="${4:-$(basename "$url" | tr '?&=' '_')}"

    [[ -f "$dest/$filename" ]] && { info "[$name] Déjà présent"; return 0; }
    info "Téléchargement : $name"
    if _fetch_with_fallback "$url" "$dest/$filename" "$name"; then
        success "$name enregistré"
    else
        warn "$name échec — voir docs/gaps_analysis.md pour un téléchargement manuel"
        echo "$(date '+%Y-%m-%d %H:%M:%S') FAILED [$name] $url" >> "$FAILED_LOG"
    fi
}


# ── YouTube authentication ────────────────────────────────────────────────────
# YouTube now answers many automated requests with "Sign in to confirm you're
# not a bot". Supply credentials via config/survive.conf:
#   SURVIVE_YTDLP_COOKIES="/home/pi/yt_cookies.txt"   # exported cookies file
#   SURVIVE_YTDLP_BROWSER="chromium"                  # or read them live
# Without either, downloads are attempted anyway (some videos still work) and
# blocked items are skipped rather than aborting the run.
_ytdlp_auth_args() {
    if [[ -n "${SURVIVE_YTDLP_COOKIES:-}" ]] && [[ -f "${SURVIVE_YTDLP_COOKIES}" ]]; then
        printf '%s\n--cookies\n%s' "" "${SURVIVE_YTDLP_COOKIES}"
    elif [[ -n "${SURVIVE_YTDLP_BROWSER:-}" ]]; then
        printf '%s\n--cookies-from-browser\n%s' "" "${SURVIVE_YTDLP_BROWSER}"
    fi
}
mapfile -t YTDLP_AUTH < <(_ytdlp_auth_args)
# Drop the leading empty element produced when no auth is configured.
[[ ${#YTDLP_AUTH[@]} -gt 0 ]] && [[ -z "${YTDLP_AUTH[0]}" ]] && YTDLP_AUTH=("${YTDLP_AUTH[@]:1}")
if [[ ${#YTDLP_AUTH[@]} -eq 0 ]]; then
    echo "[WARN] No YouTube credentials configured (SURVIVE_YTDLP_COOKIES /" >&2
    echo "[WARN] SURVIVE_YTDLP_BROWSER in survive.conf). Blocked videos will be" >&2
    echo "[WARN] skipped -- see docs/TROUBLESHOOTING.md 'YouTube bot check'." >&2
fi

dl_channel() {
    local category="$1"; local name="$2"; local url="$3"; local max="${4:-100}"
    info "[VIDEO] $name ($category, max $max videos)"
    yt-dlp "${YTDLP_AUTH[@]}" \
        --format "bestvideo[height<=720][ext=mp4]+bestaudio/best[height<=720]/best" \
        --merge-output-format mp4 \
        --embed-metadata \
        --download-archive "$LOG_DIR/${category}_gaps_archive.txt" \
        --output "$VIDEO_DIR/$category/%(channel)s/%(title)s.%(ext)s" \
        --playlist-end "$max" \
        --ignore-errors --no-warnings \
        "$url" \
        && success "[VIDEO] $name done" \
        || warn "[VIDEO] $name had errors"
}

# ══════════════════════════════════════════════════════════════════════════════
# Contenus experts : aiguillage vers les sources francophones
# ══════════════════════════════════════════════════════════════════════════════
# La version d'origine téléchargeait ici des dizaines de documents anglophones
# (obstétrique, dentaire, élevage, forge, semences, etc.). Faute de sources
# françaises vérifiées une à une, la liste est désormais fournie par
# l'utilisateur dans config/gaps_extra.list, une ligne par document :
#
#     dossier|nom|url|fichier.pdf
#
# « dossier » est un sous-dossier de pdfs/ et correspond à une catégorie du
# tableau de bord : medicine_advanced obstetrics dental sanitation
# animal_husbandry blacksmithing fermentation beeswax seeds security
# psychology community water_systems primitive_skills permaculture economics
# radio. Les lignes vides et celles commençant par # sont ignorées.

dl_extra() {
    local list="$REPO_DIR/config/gaps_extra.list"
    if [[ ! -f "$list" ]]; then
        warn "Aucune liste $list — rien à télécharger"
        return 0
    fi
    local folder name url fname
    while IFS='|' read -r folder name url fname; do
        [[ -z "${folder// }" || "$folder" == \#* ]] && continue
        if [[ -z "${name:-}" || -z "${url:-}" ]]; then
            warn "Ligne ignorée (format : dossier|nom|url|fichier) : $folder"; continue
        fi
        if [[ ! "$folder" =~ ^[A-Za-z0-9_-]+$ ]]; then
            warn "Nom de dossier invalide « $folder » — ligne ignorée"; continue
        fi
        mkdir -p "$PDF_DIR/$folder"
        dl_file "$name" "$url" "$PDF_DIR/$folder" "${fname:-$(basename "$url" | tr '?&=' '_')}"
    done < "$list"
}

# ── Programme principal ───────────────────────────────────────────────────────
main() {
    info "Téléchargeur des contenus experts complémentaires (FR)"
    echo ""

    dl_extra

    success "Téléchargement des contenus experts terminé"
    du -sh "$PDF_DIR" "$VIDEO_DIR" 2>/dev/null || true

    # Indexer le texte des nouveaux documents (recherche et assistant IA).
    python3 "$REPO_DIR/scripts/index_documents.py" --storage "$STORAGE_PATH" || true
}

main "$@"
