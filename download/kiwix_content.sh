#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Téléchargeur de fichiers ZIM Kiwix
# Télécharge Wikipédia FR, Wikilivres, iFixit, Gutenberg FR, Khan Academy FR, etc.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config not found at $_CONF -- using defaults" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
ZIM_DIR="$STORAGE_PATH/zim"
ONLY_PACKAGE=""
UPDATE_MODE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --storage) STORAGE_PATH="$2"; ZIM_DIR="$2/zim"; shift 2 ;;
        --resume)  shift ;;  # aria2c --continue=true handles resume automatically
        --update)  UPDATE_MODE=true; shift ;;
        --only)    ONLY_PACKAGE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

mkdir -p "$ZIM_DIR"/{wikipedia,reference,education,medicine,skills,books}

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}[KIWIX]${NC} $*"; }
success() { echo -e "${GREEN}[KIWIX]${NC} $*"; }
warn()    { echo -e "${YELLOW}[KIWIX]${NC} $*"; }

# Failed-downloads log: listed at the end and honoured by the exit code so
# the user/ci notices silent corruption rather than trusting a "done" marker.
FAILED_LOG="$ZIM_DIR/.failed_downloads.log"
: > "$FAILED_LOG" 2>/dev/null || true

mark_failed() { echo "$(date -Iseconds) $1 :: $2" >> "$FAILED_LOG"; }

# Refuse to start a download that cannot fit. A 100% full disk breaks far
# more than the one download (indexes, logs, the running services), so keep
# a safety margin free. Returns 0 when unable to measure — don't block on
# a df quirk.
SPACE_MARGIN_MB="${SURVIVE_SPACE_MARGIN_MB:-10240}"
_space_ok() {
    local need_bytes="$1" avail_kb
    avail_kb=$(df --output=avail -k "$ZIM_DIR" 2>/dev/null | tail -1 | tr -dc '0-9')
    [[ -z "$avail_kb" ]] && return 0
    (( avail_kb * 1024 - need_bytes > SPACE_MARGIN_MB * 1024 * 1024 ))
}

# A real ZIM starts with the magic bytes 5A 49 4D 04 ("ZIM\x04"). A blocked or
# redirected download can reach the exact expected byte count yet be an XML/HTML
# error page — the size check alone (and mirrors without a .sha256 sidecar)
# will not catch it, so validate the magic explicitly. Non-.zim files pass.
_zim_magic_ok() {
    local f="$1"
    [[ "${f,,}" == *.zim ]] || return 0
    [[ "$(head -c 4 "$f" 2>/dev/null | tr -d '\0')" == *ZIM* ]]
}

# Download a ZIM, then validate size and checksum BEFORE treating the download
# as successful. A partial/corrupt file is removed so the next run re-fetches.
# ZIM snapshots carry a build date (…_2026-02.zim) and Kiwix deletes old ones
# from the mirror, so any pinned filename eventually 404s. Given a pinned URL,
# return the same file's newest available build. Falls back to the pinned URL
# (returns non-zero) when the listing can't be fetched — e.g. no internet.
resolve_zim_url() {
    local url="$1" dir base prefix listing latest
    dir="${url%/*}"            # …/zim/wikipedia
    base="${url##*/}"          # wikipedia_en_all_maxi_2024-01.zim
    prefix="${base%_*.zim}"    # wikipedia_en_all_maxi
    prefix="${prefix//./\\.}"  # escape dots (foo.stackexchange.com_en_all)
    listing=$(curl -sL --max-time 30 "$dir/" 2>/dev/null) || return 1
    latest=$(grep -oE "${prefix}_[0-9]{4}-[0-9]{2}\.zim" <<< "$listing" \
             | sort -u | tail -1)
    [[ -n "$latest" ]] || return 1
    echo "$dir/$latest"
}

download_zim() {
    local name="$1"
    local url="$2"
    local dest_dir="$3"

    # Swap the pinned build for whatever is currently published.
    local resolved
    if resolved=$(resolve_zim_url "$url"); then
        if [[ "$resolved" != "$url" ]]; then
            info "[$name] Current build: $(basename "$resolved")"
            url="$resolved"
        fi
    else
        warn "[$name] Could not list the mirror — trying the pinned URL"
    fi

    local filename
    filename=$(basename "$url")
    local dest="$dest_dir/$filename"

    # Never download a ZIM we already have. Files may live at a different
    # path than today's layout expects (the directory structure has changed
    # over time), and a re-run must not fetch a second 100+ GB copy of a
    # title it already owns. A file mid-download (an .aria2 sidecar exists)
    # doesn't count — aria2c resumes it below.
    local existing="" cand resumed=false
    while IFS= read -r -d '' cand; do
        [[ -f "$cand.aria2" ]] && continue
        existing="$cand"; break
    done < <(find "$ZIM_DIR" -type f -name "$filename" -print0 2>/dev/null)
    if [[ -n "$existing" ]]; then
        # A file can be truncated yet have no .aria2 control file (crash,
        # disk-full). Only the mirror's content-length says whether it is
        # actually complete; wget -c resumes by size, no control file needed.
        # A size-complete file that isn't a valid ZIM is corrupt (an error
        # page padded to the right length, or a partial resumed over garbage).
        # Delete it and fall through to a clean re-download rather than
        # trusting the byte count.
        if ! _zim_magic_ok "$existing"; then
            warn "[$name] Existing file is not a valid ZIM (bad magic) -- deleting and re-downloading"
            rm -f "$existing" "$existing.aria2" "$existing.aria2__temp"
            existing=""
        fi
    fi
    if [[ -n "$existing" ]]; then
        local remote_sz local_sz
        remote_sz=$(curl -sIL --max-time 30 "$url" 2>/dev/null \
                    | grep -i '^content-length' | tail -1 | tr -dc '0-9' || true)
        local_sz=$(stat -c %s "$existing" 2>/dev/null || echo 0)
        if [[ -z "$remote_sz" ]] || (( local_sz >= remote_sz )); then
            success "[$name] Already downloaded: $existing"
            return 0
        fi
        if ! _space_ok "$(( remote_sz - local_sz ))"; then
            warn "[$name] Not enough free space to finish ($(( (remote_sz - local_sz) / 1024 / 1024 )) MB needed) -- skipping"
            mark_failed "$name" "insufficient disk space"
            return 1
        fi
        info "[$name] Incomplete file ($(( local_sz / 1024 / 1024 )) of $(( remote_sz / 1024 / 1024 )) MB) -- resuming"
        rm -f "$existing.aria2__temp"
        if ! wget -c -q --show-progress --tries=3 -O "$existing" "$url"; then
            warn "[$name] resume failed -- will retry next run"
            mark_failed "$name" "wget resume"
            return 1
        fi
        dest="$existing"   # validate the resumed file below
        resumed=true
    fi

    # Same title, different build date. Keep the copy we have unless the
    # user explicitly asked for updates with --update — silently pulling a
    # fresh build would duplicate huge files.
    if [[ "$resumed" != "true" && "$UPDATE_MODE" != "true" ]]; then
        local prefix_glob="${filename%_*.zim}_[0-9][0-9][0-9][0-9]-[0-9][0-9].zim"
        while IFS= read -r -d '' cand; do
            [[ -f "$cand.aria2" ]] && continue
            existing="$cand"; break
        done < <(find "$ZIM_DIR" -type f -name "$prefix_glob" -print0 2>/dev/null)
        if [[ -n "$existing" ]]; then
            info "[$name] Existing build kept: $existing"
            info "[$name] (re-run with --update to fetch newer builds;"
            info "[$name]  delete the old build afterwards to reclaim space)"
            return 0
        fi
    fi

    if [[ "$resumed" != "true" ]]; then
        local new_sz
        new_sz=$(curl -sIL --max-time 30 "$url" 2>/dev/null \
                 | grep -i '^content-length' | tail -1 | tr -dc '0-9' || true)
        if [[ -n "$new_sz" ]] && ! _space_ok "$new_sz"; then
            warn "[$name] Not enough free space ($(( new_sz / 1024 / 1024 )) MB needed) -- skipping"
            mark_failed "$name" "insufficient disk space"
            return 1
        fi
        info "[$name] Downloading to $dest..."
        local BW_ARGS=()
        [[ "${SURVIVE_BANDWIDTH_LIMIT:-0}" != "0" ]] && BW_ARGS=(--max-overall-download-limit="${SURVIVE_BANDWIDTH_LIMIT}")

        if ! aria2c \
                --continue=true \
                --max-connection-per-server=4 \
                --split=4 \
                --dir="$dest_dir" \
                --out="$filename" \
                --console-log-level=warn \
                --summary-interval=60 \
                "${BW_ARGS[@]}" \
                "$url"; then
            warn "[$name] aria2c exited non-zero -- will retry next run"
            mark_failed "$name" "aria2c exit"
            return 1
        fi
    fi

    # Minimum plausible ZIM is ~1 MB -- anything smaller is a 404 page
    # or a truncated download masquerading as success.
    local sz
    sz=$(stat -c %s "$dest" 2>/dev/null || echo 0)
    if (( sz < 1048576 )); then
        warn "[$name] File too small (${sz} bytes) -- removing stub"
        rm -f "$dest"
        mark_failed "$name" "size=$sz"
        return 1
    fi

    # Magic-byte gate: catches an error page saved (or resumed) at the right
    # size on a mirror that ships no checksum. A ZIM that fails this can never
    # be registered with Kiwix, so delete it rather than keep dead weight.
    if ! _zim_magic_ok "$dest"; then
        warn "[$name] Downloaded file is not a valid ZIM (bad magic) -- removing"
        rm -f "$dest" "$dest.aria2" "$dest.aria2__temp"
        mark_failed "$name" "invalid ZIM magic"
        return 1
    fi

    # Checksum validation: ZIM mirrors publish .sha256 sidecars. A missing
    # sidecar is logged as a warning (network or mirror issue), but a
    # MISMATCH deletes the file so the next run re-downloads cleanly.
    local sha_url="${url%.zim}.sha256"
    local sha_file
    sha_file=$(mktemp)
    if ! wget -q -O "$sha_file" "$sha_url" 2>/dev/null || ! [[ -s "$sha_file" ]]; then
        rm -f "$sha_file"
        # A partial resumed without its aria2 control file can have internal
        # zero-gaps that valid magic bytes won't reveal. With no checksum to
        # catch that, the resumed result is untrustworthy: discard it so the
        # next run downloads the whole file cleanly (aria2 manages its own
        # piece integrity in a single session).
        if [[ "$resumed" == "true" ]]; then
            warn "[$name] Resumed a control-file-less partial and the mirror"
            warn "[$name] has no checksum to verify it -- discarding for a clean re-download"
            rm -f "$dest" "$dest.aria2" "$dest.aria2__temp"
            mark_failed "$name" "unverifiable resume"
            return 1
        fi
        warn "[$name] No checksum sidecar at $sha_url -- size + magic check only"
        success "[$name] Done: $filename (magic OK, no checksum available)"
        return 0
    fi
    # Replace the path in the sidecar with our local filename so sha256sum
    # can find the target file regardless of what the mirror labelled it.
    local expected
    expected=$(awk '{print $1; exit}' "$sha_file")
    echo "$expected  $dest" > "$sha_file"
    if sha256sum -c "$sha_file" &>/dev/null; then
        success "[$name] Checksum OK"
        rm -f "$sha_file"
        return 0
    else
        warn "[$name] Checksum MISMATCH -- deleting corrupt file"
        rm -f "$dest" "$sha_file"
        mark_failed "$name" "checksum mismatch"
        return 1
    fi
}

# ── Catalogue Kiwix (toujours la dernière version disponible) ────────────────
# Les URLs pointent vers le miroir de téléchargement de Kiwix. Les ZIM datés
# sont automatiquement remplacés par leur dernière version (resolve_zim_url).
# Version FR : on privilégie les ZIM en français. Les rares ressources sans
# équivalent français sont regroupées dans des options « EN » désactivées par
# défaut (CONTENT_STACKEXCHANGE_EN, CONTENT_EXPANSION_EN).
KIWIX_MIRROR="https://download.kiwix.org/zim"

# ── Wikipédia ─────────────────────────────────────────────────────────────────
dl_wikipedia() {
    [[ -n "$ONLY_PACKAGE" ]] && [[ "$ONLY_PACKAGE" != "wikipedia" ]] && return

    if [[ "${CONTENT_WIKIPEDIA:-Y}" =~ [Yy] ]]; then
        info "=== Wikipédia FR (complète, avec images) ==="
        # Wikipédia FR complète avec images : ~52 Go
        download_zim "Wikipédia FR" \
            "$KIWIX_MIRROR/wikipedia/wikipedia_fr_all_maxi_2026-05.zim" \
            "$ZIM_DIR/wikipedia"
    fi

    if [[ "${CONTENT_WIKIPEDIA_NOPIC:-N}" =~ [Yy] ]]; then
        info "=== Wikipédia FR (sans images) ==="
        # Version sans images : ~12 Go
        download_zim "Wikipédia FR (sans images)" \
            "$KIWIX_MIRROR/wikipedia/wikipedia_fr_all_nopic_2026-05.zim" \
            "$ZIM_DIR/wikipedia"
    fi
}

# ── Wikilivres + Wikivoyage + Wikisource + Wiktionnaire ──────────────────────
dl_wikibooks() {
    [[ -n "$ONLY_PACKAGE" ]] && [[ "$ONLY_PACKAGE" != "wikibooks" ]] && return
    [[ "${CONTENT_WIKIBOOKS:-Y}" =~ [Yy] ]] || return

    info "=== Wikilivres, Wikivoyage, Wikisource, Wiktionnaire ==="
    download_zim "Wikilivres FR" \
        "$KIWIX_MIRROR/wikibooks/wikibooks_fr_all_maxi_2026-10.zim" \
        "$ZIM_DIR/reference"
    download_zim "Wikivoyage FR" \
        "$KIWIX_MIRROR/wikivoyage/wikivoyage_fr_all_maxi_2026-10.zim" \
        "$ZIM_DIR/reference"
    # Wikisource FR : ~11 Go sans images (15 Go avec) — textes littéraires et
    # documents d'archives ; à désactiver si le disque est juste.
    download_zim "Wikisource FR" \
        "$KIWIX_MIRROR/wikisource/wikisource_fr_all_nopic_2025-09.zim" \
        "$ZIM_DIR/reference"
    download_zim "Wiktionnaire FR" \
        "$KIWIX_MIRROR/wiktionary/wiktionary_fr_all_nopic_2026-08.zim" \
        "$ZIM_DIR/reference"
}

# ── iFixit : guides de réparation ─────────────────────────────────────────────
dl_ifix() {
    [[ -n "$ONLY_PACKAGE" ]] && [[ "$ONLY_PACKAGE" != "ifix" ]] && return
    [[ "${CONTENT_IFIX:-Y}" =~ [Yy] ]] || return

    info "=== iFixit : guides de réparation (FR) ==="
    download_zim "iFixit FR" \
        "$KIWIX_MIRROR/ifixit/ifixit_fr_all_2026-03.zim" \
        "$ZIM_DIR/skills"
}

# ── Stack Exchange ─────────────────────────────────────────────────────────────
# Il n'existe pas de Stack Exchange francophone (hors « French Language »).
# Les sites pratiques en anglais sont donc proposés en option :
# CONTENT_STACKEXCHANGE_EN=Y (≈ 40 Go) ; le site French Language Stack Exchange
# (90 Mo) est toujours téléchargé avec CONTENT_STACKEXCHANGE=Y.
dl_stackexchange() {
    [[ -n "$ONLY_PACKAGE" ]] && [[ "$ONLY_PACKAGE" != "stackexchange" ]] && return
    [[ "${CONTENT_STACKEXCHANGE:-Y}" =~ [Yy] ]] || return

    info "=== Stack Exchange ==="
    download_zim "French Language Stack Exchange" \
        "$KIWIX_MIRROR/stack_exchange/french.stackexchange.com_mul_all_2026-10.zim" \
        "$ZIM_DIR/skills"

    [[ "${CONTENT_STACKEXCHANGE_EN:-N}" =~ [Yy] ]] || return
    info "=== Stack Exchange (EN, option) ==="
    declare -A SE_PACKAGES=(
        ["Super User"]="$KIWIX_MIRROR/stack_exchange/superuser.com_en_all_2026-02.zim"
        ["DIY"]="$KIWIX_MIRROR/stack_exchange/diy.stackexchange.com_en_all_2026-02.zim"
        ["Cooking"]="$KIWIX_MIRROR/stack_exchange/cooking.stackexchange.com_en_all_2026-02.zim"
        ["Ham Radio"]="$KIWIX_MIRROR/stack_exchange/ham.stackexchange.com_en_all_2026-02.zim"
        ["Outdoors"]="$KIWIX_MIRROR/stack_exchange/outdoors.stackexchange.com_en_all_2026-02.zim"
        ["Gardening"]="$KIWIX_MIRROR/stack_exchange/gardening.stackexchange.com_en_all_2026-02.zim"
        ["Medical Sciences"]="$KIWIX_MIRROR/stack_exchange/medicalsciences.stackexchange.com_en_all_2026-02.zim"
        ["Sustainability"]="$KIWIX_MIRROR/stack_exchange/sustainability.stackexchange.com_en_all_2026-02.zim"
        ["Electronics"]="$KIWIX_MIRROR/stack_exchange/electronics.stackexchange.com_en_all_2026-02.zim"
        ["Unix/Linux"]="$KIWIX_MIRROR/stack_exchange/unix.stackexchange.com_en_all_2026-02.zim"
    )

    for name in "${!SE_PACKAGES[@]}"; do
        download_zim "$name" "${SE_PACKAGES[$name]}" "$ZIM_DIR/skills"
    done
}

# ── Projet Gutenberg (livres en français) ─────────────────────────────────────
dl_gutenberg() {
    [[ -n "$ONLY_PACKAGE" ]] && [[ "$ONLY_PACKAGE" != "gutenberg" ]] && return
    [[ "${CONTENT_GUTENBERG:-Y}" =~ [Yy] ]] || return

    info "=== Projet Gutenberg (livres en français) ==="
    # Le nom daté est remplacé par la dernière version publiée (resolve_zim_url).
    download_zim "Gutenberg FR" \
        "$KIWIX_MIRROR/gutenberg/gutenberg_fr_all_2022-10.zim" \
        "$ZIM_DIR/books"
}

# ── Khan Academy (version Kiwix) ──────────────────────────────────────────────
dl_khan() {
    [[ -n "$ONLY_PACKAGE" ]] && [[ "$ONLY_PACKAGE" != "khan" ]] && return

    info "=== Khan Academy FR (version Kiwix) ==="
    # Remarque : la version Kolibri est préférée (download/kolibri_content.sh).
    # ZIM complet FR : ~94 Go.
    download_zim "Khan Academy FR" \
        "$KIWIX_MIRROR/other/khanacademy_fr_all_2023-03.zim" \
        "$ZIM_DIR/education"
}

# ── Ressources médicales ──────────────────────────────────────────────────────
# MedlinePlus et WikiMed (mdwiki) n'existent qu'en anglais : on s'appuie sur
# le sous-ensemble « médecine » de Wikipédia FR (~0,8 Go avec images), en plus
# de la Wikipédia FR complète. Les guides médicaux PDF sont dans
# download/gaps_content.sh et download/mental_health.sh.
dl_medical() {
    [[ -n "$ONLY_PACKAGE" ]] && [[ "$ONLY_PACKAGE" != "medical" ]] && return

    info "=== Références médicales (FR) ==="
    download_zim "Wikipédia FR — Médecine" \
        "$KIWIX_MIRROR/wikipedia/wikipedia_fr_medicine_maxi_2026-10.zim" \
        "$ZIM_DIR/medicine"
}

# ── Conférences TED ───────────────────────────────────────────────────────────
# Ces ZIM contiennent les vidéos des conférences, lisibles hors ligne dans le
# navigateur. Ils sont multilingues (« mul ») : voix originale, sous-titres
# disponibles dans de nombreuses langues dont le français.
dl_ted() {
    [[ -n "$ONLY_PACKAGE" ]] && [[ "$ONLY_PACKAGE" != "ted" ]] && return

    info "=== Conférences TED (vidéos hors ligne, sous-titres FR) ==="
    download_zim "TED Technology" \
        "$KIWIX_MIRROR/ted/ted_mul_technology_2026-09.zim" \
        "$ZIM_DIR/education"
    download_zim "TED Health Care" \
        "$KIWIX_MIRROR/ted/ted_mul_health-care_2026-09.zim" \
        "$ZIM_DIR/education"
    download_zim "TED Public Health" \
        "$KIWIX_MIRROR/ted/ted_mul_public-health_2026-09.zim" \
        "$ZIM_DIR/education"
    download_zim "TED Mental Health" \
        "$KIWIX_MIRROR/ted/ted_mul_mental-health_2026-09.zim" \
        "$ZIM_DIR/education"
    # Le plus gros et le moins vital — dernier téléchargement de toute
    # l'exécution, pour qu'un disque plein ne coûte que celui-ci.
    download_zim "TED Science" \
        "$KIWIX_MIRROR/ted/ted_mul_science_2026-09.zim" \
        "$ZIM_DIR/education"
}

# ── Pack d'extension FR : autonomie, cuisine, éducation ──────────────────────
# Ajouts sélectionnés pour les machines qui ont de la place (~4 Go au total).
dl_expansion() {
    [[ -n "$ONLY_PACKAGE" ]] && [[ "$ONLY_PACKAGE" != "expansion" ]] && return
    [[ "${CONTENT_EXPANSION:-Y}" =~ [Yy] ]] || return

    info "=== Pack d'extension : vie autonome et cuisine ==="
    download_zim "Ekopédia (écologie pratique, autonomie)" \
        "$KIWIX_MIRROR/other/ekopedia_fr_all_maxi_2021-03.zim" \
        "$ZIM_DIR/skills"
    download_zim "Cuisine Libre (recettes)" \
        "$KIWIX_MIRROR/other/cuisinelibre.org_fr_all_2026-08.zim" \
        "$ZIM_DIR/skills"

    info "=== Pack d'extension : éducation ==="
    download_zim "PhET — simulations scientifiques FR" \
        "$KIWIX_MIRROR/phet/phet_fr_all_2026-08.zim" \
        "$ZIM_DIR/education"
    download_zim "Wikiversité FR" \
        "$KIWIX_MIRROR/wikiversity/wikiversity_fr_all_maxi_2026-08.zim" \
        "$ZIM_DIR/education"
    download_zim "Vikidia FR (encyclopédie simplifiée)" \
        "$KIWIX_MIRROR/vikidia/vikidia_fr_all_maxi_2026-09.zim" \
        "$ZIM_DIR/education"
}

# ── Pack d'extension EN (option) : ressources sans équivalent français ───────
# Les collections « zimgit » de Kiwix (catastrophes, eau, secours, nœuds),
# Appropedia et Energypedia n'existent qu'en anglais. ~3 Go au total.
# Activer avec CONTENT_EXPANSION_EN=Y dans config/survive.conf.
dl_expansion_en() {
    [[ -n "$ONLY_PACKAGE" ]] && [[ "$ONLY_PACKAGE" != "expansion_en" ]] && return
    [[ "${CONTENT_EXPANSION_EN:-N}" =~ [Yy] ]] || return

    info "=== Pack d'extension EN : collections de survie (anglais) ==="
    download_zim "Post-disaster Library (EN)" \
        "$KIWIX_MIRROR/other/zimgit-post-disaster_en_2024-05.zim" \
        "$ZIM_DIR/skills"
    download_zim "Emergency Medicine Collection (EN)" \
        "$KIWIX_MIRROR/other/zimgit-medicine_en_2024-08.zim" \
        "$ZIM_DIR/medicine"
    download_zim "Water Purification Collection (EN)" \
        "$KIWIX_MIRROR/other/zimgit-water_en_2024-08.zim" \
        "$ZIM_DIR/skills"
    download_zim "Food Preparation Collection (EN)" \
        "$KIWIX_MIRROR/other/zimgit-food-preparation_en_2025-04.zim" \
        "$ZIM_DIR/skills"
    download_zim "Knots Guide (EN)" \
        "$KIWIX_MIRROR/other/zimgit-knots_en_2024-08.zim" \
        "$ZIM_DIR/skills"
    download_zim "Appropedia (EN)" \
        "$KIWIX_MIRROR/other/appropedia_en_all_maxi_2026-02.zim" \
        "$ZIM_DIR/skills"
    download_zim "Energypedia (EN)" \
        "$KIWIX_MIRROR/other/energypedia_en_all_maxi_2026-06.zim" \
        "$ZIM_DIR/skills"
}

# ── Register all ZIMs with kiwix-serve ───────────────────────────────────────
register_zims() {
    info "Registering ZIM files with Kiwix library..."
    KIWIX_LIBRARY="$STORAGE_PATH/.kiwix_library.xml"

    # Find all downloaded ZIM files and register them
    while IFS= read -r -d '' zimfile; do
        kiwix-manage "$KIWIX_LIBRARY" add "$zimfile" 2>/dev/null || true
    done < <(find "$ZIM_DIR" -name "*.zim" -print0)

    success "Kiwix library updated: $KIWIX_LIBRARY"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    info "Starting Kiwix ZIM downloads..."
    info "Output directory: $ZIM_DIR"

    dl_wikipedia
    dl_wikibooks
    dl_ifix
    dl_stackexchange
    dl_gutenberg
    dl_khan
    dl_medical
    dl_expansion
    dl_expansion_en
    # TED goes last (Science alone is 15 GB): on a nearly-full drive the
    # least-critical content should be what a disk-full failure lands on.
    dl_ted

    register_zims

    if [[ -s "$FAILED_LOG" ]]; then
        warn "Some downloads failed -- see $FAILED_LOG"
        echo "---"
        cat "$FAILED_LOG"
        echo "---"
        info "Re-run this script to retry failed items."
        du -sh "$ZIM_DIR" 2>/dev/null || true
        exit 2
    fi

    success "Kiwix content download complete"
    info "ZIM files: $ZIM_DIR"
    du -sh "$ZIM_DIR" 2>/dev/null || true
}

main "$@"
