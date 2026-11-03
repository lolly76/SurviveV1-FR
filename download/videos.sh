#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Téléchargeur de vidéos de survie avec yt-dlp
# Télécharge des chaînes et playlists YouTube francophones sélectionnées
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config not found at $_CONF -- using defaults" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
VIDEO_DIR="$STORAGE_PATH/videos"
QUALITY="${VIDEO_QUALITY:-720}"  # 480, 720, 1080
LOG_DIR="$STORAGE_PATH/.logs"

while [[ $# -gt 0 ]]; do
    case $1 in
        --storage) STORAGE_PATH="$2"; VIDEO_DIR="$2/videos"; shift 2 ;;
        --quality) QUALITY="$2"; shift 2 ;;
        *) shift ;;
    esac
done

mkdir -p "$VIDEO_DIR"/{survival,medical,food,water,shelter,energy,tools,farming,skills,preparedness,animal_husbandry,psychology}
mkdir -p "$LOG_DIR"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()    { echo -e "${BLUE}[VIDEO]${NC} $*"; }
success() { echo -e "${GREEN}[VIDEO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[VIDEO]${NC} $*"; }
error()   { echo -e "${RED}[VIDEO]${NC} $*" >&2; }

check_disk_space() {
    local required_gb="${1:-50}"
    local available_gb
    if ! available_gb=$(df -BG "$STORAGE_PATH" 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G'); then
        error "Impossible de vérifier l'espace disque sur $STORAGE_PATH"; exit 1
    fi
    if ! [[ "$available_gb" =~ ^[0-9]+$ ]]; then
        error "Sortie de df inattendue : '$available_gb'"; exit 1
    fi
    info "Espace disque : ${available_gb} Go disponibles (minimum requis : ${required_gb} Go)"
    if (( available_gb < required_gb )); then
        error "Moins de ${required_gb} Go libres sur $STORAGE_PATH. Arrêt des téléchargements vidéo."
        exit 1
    fi
}

# Verify downloaded videos have non-trivial size; record broken/empty files
# to the failed log so the user knows which channels/playlists need a re-run.
check_downloads() {
    local failed_log="$LOG_DIR/videos_failed.log"
    : > "$failed_log"
    local broken=0
    # Treat files < 100 KB as broken (trailing .part leftovers, 0-byte stubs).
    while IFS= read -r -d '' f; do
        local sz
        sz=$(stat -c %s "$f" 2>/dev/null || echo 0)
        if (( sz < 102400 )); then
            echo "$(date -Iseconds) SIZE=$sz $f" >> "$failed_log"
            broken=$((broken + 1))
        fi
    done < <(find "$VIDEO_DIR" -type f \( -name "*.mp4" -o -name "*.part" \) -print0)
    if (( broken > 0 )); then
        warn "$broken fichier(s) vidéo cassé(s) ou partiel(s) détecté(s). Voir $failed_log"
    fi
    return 0
}

# ── yt-dlp download function ──────────────────────────────────────────────────
dl_playlist() {
    local category="$1"
    local name="$2"
    local url="$3"
    local dest="$VIDEO_DIR/$category"

    info "[$category] $name"
    local BW_ARGS=()
    [[ "${SURVIVE_BANDWIDTH_LIMIT:-0}" != "0" ]] && BW_ARGS=(--limit-rate "${SURVIVE_BANDWIDTH_LIMIT}")
    # Security flags:
    # --restrict-filenames : strip path separators / specials from remote-controlled
    #                        %(playlist_title)s / %(title)s before they hit disk.
    # --no-exec            : ignore any remote-injected post-processor commands.
    # --no-config          : ignore attacker-plantable config files in the cwd.
    # --no-overwrites      : never overwrite existing files (prevents clobber).
    # --socket-timeout     : unblock hung sockets so the script can continue.
    # Per-file success is verified downstream by check_downloads().
    yt-dlp "${YTDLP_AUTH[@]}" \
        --format "bestvideo[height<=${QUALITY}][ext=mp4]+bestaudio[ext=m4a]/best[height<=${QUALITY}][ext=mp4]/best" \
        --merge-output-format mp4 \
        --embed-thumbnail \
        --embed-metadata \
        --add-metadata \
        --write-info-json \
        --write-thumbnail \
        --restrict-filenames \
        --no-exec \
        --no-config \
        --no-overwrites \
        --socket-timeout 30 \
        --download-archive "$LOG_DIR/${category}_archive.txt" \
        --output "$dest/%(playlist_title)s/%(playlist_index)s - %(title)s.%(ext)s" \
        --ignore-errors \
        --no-warnings \
        --concurrent-fragments 4 \
        --throttled-rate 1M \
        "${BW_ARGS[@]}" \
        "$url" \
    && success "[$category] $name terminé" \
    || warn "[$category] $name : erreurs (certaines vidéos peuvent être bloquées géographiquement)"
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
    local category="$1"
    local name="$2"
    local url="$3"
    local max="${4:-100}"  # max videos per channel

    info "[$category] Chaîne : $name (max $max vidéos)"
    local BW_ARGS=()
    [[ "${SURVIVE_BANDWIDTH_LIMIT:-0}" != "0" ]] && BW_ARGS=(--limit-rate "${SURVIVE_BANDWIDTH_LIMIT}")
    yt-dlp "${YTDLP_AUTH[@]}" \
        --format "bestvideo[height<=${QUALITY}][ext=mp4]+bestaudio[ext=m4a]/best[height<=${QUALITY}]/best" \
        --merge-output-format mp4 \
        --embed-metadata \
        --write-info-json \
        --restrict-filenames \
        --no-exec \
        --no-config \
        --no-overwrites \
        --socket-timeout 30 \
        --download-archive "$LOG_DIR/${category}_archive.txt" \
        --output "$VIDEO_DIR/$category/%(channel)s/%(title)s.%(ext)s" \
        --playlist-end "$max" \
        --ignore-errors \
        --no-warnings \
        "${BW_ARGS[@]}" \
        "$url" \
    && success "[$category] $name terminé" \
    || warn "[$category] $name : quelques erreurs"
}

# ── Contenu francophone sélectionné ───────────────────────────────────────────
# Chaînes en français, adresses vérifiées (identifiants /channel/UC… stables).
# Point de départ : ajoutez vos propres sources sans toucher au script, une par
# ligne, dans config/videos_extra.list :
#     catégorie|nom|url|nombre_max     (nombre_max facultatif, 100 par défaut)
# Catégories : survival medical food water shelter energy tools farming skills
#              preparedness animal_husbandry psychology
# Une URL contenant « playlist? » est téléchargée comme playlist, sinon comme
# chaîne. Les lignes vides et celles commençant par # sont ignorées.

# Survie et bushcraft
dl_survival() {
    info "=== Survie et bushcraft ==="
    dl_channel "survival" "Invictus France — Bushcraft & Survie" \
        "https://www.youtube.com/channel/UCKPcuCK3FyZvIDS0gB842Yg/videos" 100
    dl_channel "survival" "Alban Cambe — Bushcraft & navigation naturelle" \
        "https://www.youtube.com/channel/UCu0B8D0Xa8NWSMidJGS_wMw/videos" 100
    dl_channel "survival" "Sankhoï — Survie Bushcraft" \
        "https://www.youtube.com/channel/UCphU_Qd6MzWFGQ-arUPm6Wg/videos" 100
    dl_channel "survival" "Skol Louarn — Bushcraft, survie, rando" \
        "https://www.youtube.com/channel/UCHFG1iDURjUcA6ViSdsILiQ/videos" 100
}

# Médical et premiers secours
dl_medical() {
    info "=== Médical et premiers secours ==="
    dl_playlist "medical" "Croix-Rouge française — Formations premiers secours" \
        "https://www.youtube.com/playlist?list=PL9tJFzSvOEC1Si34LO1PsMMdxemHeP42A"
}

# Alimentation, potager et conservation
dl_food() {
    info "=== Alimentation et potager ==="
    dl_channel "food" "Popote et Potager" \
        "https://www.youtube.com/channel/UCiusFKWbx0TV8t9WM1GLizA/videos" 150
    dl_channel "farming" "École de permaculture du Bec Hellouin" \
        "https://www.youtube.com/channel/UCzgsQwiy6sKt6Ne9aDXGc5Q/videos" 150
}

# Abri et construction
dl_shelter() {
    info "=== Abri et construction ==="
    dl_channel "shelter" "Maison-Construction.com" \
        "https://www.youtube.com/@maison-construction/videos" 100
}

# Énergie
dl_energy() {
    info "=== Énergie ==="
    dl_channel "energy" "L'énergie partout" \
        "https://www.youtube.com/channel/UCKTJiNMMxk2W0CpOxPLoUkQ/videos" 100
}

# Outils, réparation et basses technologies
dl_tools() {
    info "=== Outils, réparation et low-tech ==="
    dl_channel "tools" "Le Coin des Bricoleurs" \
        "https://www.youtube.com/@LECOINDESBRICOLEURS/videos" 100
    dl_channel "tools" "Fix Ta Maison" \
        "https://www.youtube.com/@fixtamaison/videos" 100
    dl_channel "tools" "Robert Longechal" \
        "https://www.youtube.com/user/robertlongechal/videos" 50
    dl_channel "skills" "Low-tech Lab" \
        "https://www.youtube.com/channel/UCu6mFdACj_quODcUujiT62Q/videos" 100
}

# Radio et préparation
dl_preparedness() {
    info "=== Radio et préparation ==="
    dl_channel "preparedness" "Radioamateur par F4HTZ" \
        "https://www.youtube.com/@radio.f4htz/videos" 100
    dl_playlist "preparedness" "Cours de préparation à la licence radioamateur (F4KLH)" \
        "https://www.youtube.com/playlist?list=PLjg_1YSBWRdtxJ1YgU-0--RgE0Q0hTWRy"
}

# Sources supplémentaires de l'utilisateur (config/videos_extra.list)
dl_extra() {
    local list="$REPO_DIR/config/videos_extra.list"
    [[ -f "$list" ]] || return 0
    info "=== Sources supplémentaires ($list) ==="
    local category name url max
    while IFS='|' read -r category name url max; do
        [[ -z "${category// }" || "$category" == \#* ]] && continue
        if [[ -z "${name:-}" || -z "${url:-}" ]]; then
            warn "Ligne ignorée (format : catégorie|nom|url|max) : $category"; continue
        fi
        if [[ ! -d "$VIDEO_DIR/$category" ]]; then
            warn "Catégorie inconnue « $category » — ligne ignorée"; continue
        fi
        if [[ "$url" == *"playlist?"* ]]; then
            dl_playlist "$category" "$name" "$url"
        else
            dl_channel "$category" "$name" "$url" "${max:-100}"
        fi
    done < "$list"
}

# ── Programme principal ───────────────────────────────────────────────────────
main() {
    info "Début des téléchargements vidéo vers $VIDEO_DIR"
    info "Qualité : ${QUALITY}p"
    check_disk_space 50

    if [[ "${CONTENT_VIDEOS:-Y}" =~ [Yy] ]]; then
        dl_survival
        dl_medical
        dl_food
        dl_shelter
        dl_energy
        dl_tools
        dl_preparedness
        dl_extra
    fi

    check_downloads
    success "Téléchargement des vidéos terminé"
    du -sh "$VIDEO_DIR" 2>/dev/null || true
    info "Remarque : relancez pour récupérer les nouvelles vidéos (le fichier d'archive évite les doublons)"
}

main "$@"
