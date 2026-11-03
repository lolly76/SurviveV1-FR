#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Téléchargeur « santé mentale et premiers secours psychologiques »
# Couvre : psychologie des catastrophes, deuil, résilience, PSP, santé mentale communautaire
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
PDF_DIR="$STORAGE_PATH/pdfs/psychology"
VIDEO_DIR="$STORAGE_PATH/videos/psychology"
LOG_DIR="$STORAGE_PATH/.logs"

while [[ $# -gt 0 ]]; do
    case $1 in
        --storage) STORAGE_PATH="$2"; PDF_DIR="$2/pdfs/psychology"; VIDEO_DIR="$2/videos/psychology"; shift 2 ;;
        *) shift ;;
    esac
done

mkdir -p "$PDF_DIR" "$VIDEO_DIR" "$LOG_DIR"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}[MENTAL]${NC} $*"; }
success() { echo -e "${GREEN}[MENTAL]${NC} $*"; }
warn()    { echo -e "${YELLOW}[MENTAL]${NC} $*"; }

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
    echo "  [$3] téléchargement direct impossible -- essai via la Wayback Machine..." >&2
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
    local name="$1" url="$2" dest="$3"
    local filename="${4:-$(basename "$url" | tr '?&=' '_')}"
    [[ -f "$dest/$filename" ]] && { info "[$name] Déjà présent"; return 0; }
    info "Téléchargement : $name"
    if _fetch_with_fallback "$url" "$dest/$filename" "$name"; then
        success "$name enregistré"
    else
        warn "$name : échec"
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
    echo "[WARN] Aucun identifiant YouTube configuré (SURVIVE_YTDLP_COOKIES /" >&2
    echo "[WARN] SURVIVE_YTDLP_BROWSER dans survive.conf). Les vidéos bloquées seront" >&2
    echo "[WARN] ignorées -- voir docs/TROUBLESHOOTING.md." >&2
fi

dl_channel() {
    local name="$1" url="$2" max="${3:-100}"
    info "[VIDÉO] $name (max $max)"
    local BW_ARGS=()
    [[ "${SURVIVE_BANDWIDTH_LIMIT:-0}" != "0" ]] && BW_ARGS=(--limit-rate "${SURVIVE_BANDWIDTH_LIMIT}")
    yt-dlp "${YTDLP_AUTH[@]}" \
        --format "bestvideo[height<=720][ext=mp4]+bestaudio/best[height<=720]/best" \
        --merge-output-format mp4 \
        --embed-metadata \
        --download-archive "$LOG_DIR/psychology_archive.txt" \
        --output "$VIDEO_DIR/%(channel)s/%(title)s.%(ext)s" \
        --playlist-end "$max" \
        --ignore-errors --no-warnings \
        "${BW_ARGS[@]}" "$url" \
        && success "$name terminé" || warn "$name : erreurs"
}

# ── Premiers secours psychologiques (PSP) en français ────────────────────────
dl_pfa() {
    info "=== Premiers secours psychologiques (PSP) ==="
    # Guide de l'OMS / War Trauma Foundation / World Vision (édition française)
    dl_file "OMS — Les premiers secours psychologiques : guide pour les acteurs de terrain" \
        "https://terrorvictimresponse.ca/wp-content/uploads/9789242548204_fre.pdf" \
        "$PDF_DIR" "OMS_Premiers_secours_psychologiques_guide_terrain.pdf"
    # Modules de formation PSP du Centre de référence PS de la Fédération
    # internationale des sociétés de la Croix-Rouge (mhpsshub.org)
    dl_file "PSP — module 2" \
        "https://mhpsshub.org/wp-content/uploads/2020/11/12007_psc_pfa_modul2_T2_fr_FR_high-res.pdf" \
        "$PDF_DIR" "PSP_module_2.pdf"
    dl_file "PSP — module 3" \
        "https://mhpsshub.org/wp-content/uploads/2020/11/12007_psc_pfa_modul3_T2_fr_FR_high-res.pdf" \
        "$PDF_DIR" "PSP_module_3.pdf"
    dl_file "PSP — module 4 : soutien en groupes" \
        "https://mhpsshub.org/wp-content/uploads/2020/02/Premiers-Secour-Psychologique-Soutien-en-groupes-Module-4-1.pdf" \
        "$PDF_DIR" "PSP_module_4_groupes.pdf"
}

# ── Sources supplémentaires de l'utilisateur ──────────────────────────────────
# config/mental_health_extra.list :  nom|url|fichier.pdf   (# = commentaire)
dl_extra() {
    local list="$REPO_DIR/config/mental_health_extra.list"
    [[ -f "$list" ]] || return 0
    local name url fname
    while IFS='|' read -r name url fname; do
        [[ -z "${name// }" || "$name" == \#* ]] && continue
        [[ -n "${url:-}" ]] || { warn "Ligne ignorée : $name"; continue; }
        dl_file "$name" "$url" "$PDF_DIR" "${fname:-$(basename "$url")}"
    done < "$list"
}

# ── Programme principal ───────────────────────────────────────────────────────
main() {
    info "Téléchargement des contenus de santé mentale et de PSP..."

    dl_pfa
    dl_extra

    success "Téléchargement des contenus de santé mentale terminé"
    info "PDF : $PDF_DIR"
    du -sh "$PDF_DIR" 2>/dev/null || true

    # Indexer le texte des nouveaux documents (recherche et assistant IA).
    python3 "$REPO_DIR/scripts/index_documents.py" --storage "$STORAGE_PATH" || true
}

main "$@"
