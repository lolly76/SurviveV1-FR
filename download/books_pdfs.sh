#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Téléchargeur de livres et de PDF
# Télécharge des ressources de survie francophones libres ou du domaine public
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config not found at $_CONF -- using defaults" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
BOOKS_DIR="$STORAGE_PATH/books"
PDF_DIR="$STORAGE_PATH/pdfs"
LOG_DIR="$STORAGE_PATH/.logs"

while [[ $# -gt 0 ]]; do
    case $1 in
        --storage) STORAGE_PATH="$2"; BOOKS_DIR="$2/books"; PDF_DIR="$2/pdfs"; LOG_DIR="$2/.logs"; shift 2 ;;
        *) shift ;;
    esac
done

mkdir -p "$BOOKS_DIR"/{medicine,survival,agriculture,engineering,reference,fiction,skills}
mkdir -p "$PDF_DIR"/{military_manuals,homesteading,medicine,construction,farming,radio,legal}
# Dossiers alignés sur les identifiants de catégories du tableau de bord
mkdir -p "$PDF_DIR"/{medical,food,community,survival,energy,shelter,communication}
mkdir -p "$LOG_DIR"

FAILED_LOG="$LOG_DIR/failed_downloads.log"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}[BOOKS]${NC} $*"; }
success() { echo -e "${GREEN}[BOOKS]${NC} $*"; }
warn()    { echo -e "${YELLOW}[BOOKS]${NC} $*"; }

# ── Download with retry ───────────────────────────────────────────────────────

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

dl_file() {
    local name="$1"
    local url="$2"
    local dest="$3"
    local filename="${4:-$(basename "$url")}"

    if [[ -f "$dest/$filename" ]]; then
        info "[$name] Déjà présent, ignoré"
        return 0
    fi

    info "Téléchargement : $name"
    if _fetch_with_fallback "$url" "$dest/$filename" "$name"; then
        success "$name → $dest/$filename"
    else
        warn "$name : échec du téléchargement — téléchargement manuel possible"
        echo "$(date '+%Y-%m-%d %H:%M:%S') FAILED [$name] $url" >> "$FAILED_LOG"
    fi
}

# ── Préparation aux crises : documents officiels français ─────────────────────
dl_officiel() {
    info "=== Documents officiels (préparation aux crises) ==="
    local DIR="$PDF_DIR/community"

    # Guide « Tous responsables » (SGDSN / gouvernement) : se préparer à
    # 72 heures d'autonomie, kit d'urgence, conduite à tenir en cas de crise.
    dl_file "Guide « Tous responsables » (SGDSN)" \
        "https://www.ecologie.gouv.fr/sites/default/files/documents/SGDSN_Guide_Tous%20responsables.pdf" \
        "$DIR" "SGDSN_Guide_Tous_responsables.pdf"
}

# ── Références médicales (Hesperian, en français) ─────────────────────────────
# Hesperian publie « Là où il n'y a pas de docteur » (nouvelle édition 2014)
# par chapitres, en accès libre. Les noms de fichiers peuvent changer : en cas
# d'échec, voir https://languages.hesperian.org/pages/fr/pdf.html
dl_medical_refs() {
    info "=== Références médicales (Hesperian, FR) ==="
    local DIR="$PDF_DIR/medical"
    local H="https://www.hesperian.org/wp-content/uploads/pdf/fr_nwtnd_2014/fr_nwtnd_2014"

    dl_file "Là où il n'y a pas de docteur — sommaire" "${H}_fm.pdf" "$DIR" "Hesperian_LOIPD_00_sommaire.pdf"
    dl_file "Là où il n'y a pas de docteur — ch. 15 Douleurs au ventre, diarrhées, vers" "${H}_15.pdf" "$DIR" "Hesperian_LOIPD_15_ventre_diarrhees.pdf"
    dl_file "Là où il n'y a pas de docteur — ch. 26 Grossesse et accouchement" "${H}_26.pdf" "$DIR" "Hesperian_LOIPD_26_grossesse_accouchement.pdf"
    dl_file "Là où il n'y a pas de docteur — ch. 27 Nouveau-nés et allaitement" "${H}_27.pdf" "$DIR" "Hesperian_LOIPD_27_nouveau-nes.pdf"
    dl_file "Là où il n'y a pas de docteur — ch. 28 Prendre soin des enfants" "${H}_28.pdf" "$DIR" "Hesperian_LOIPD_28_enfants.pdf"
    dl_file "Là où il n'y a pas de docteur — ch. 31 Bien s'alimenter" "${H}_31.pdf" "$DIR" "Hesperian_LOIPD_31_alimentation.pdf"
    dl_file "Là où il n'y a pas de docteur — ch. 32 Eau et assainissement" "${H}_32.pdf" "$DIR" "Hesperian_LOIPD_32_eau_assainissement.pdf"

    local W="https://hesperian.org/wp-content/uploads/pdf/fr_wwd_2024/fr_wwd_2024"
    dl_file "Manuel de santé des femmes handicapées — Grossesse" "${W}_10.pdf" "$DIR" "Hesperian_MSFH_10_grossesse.pdf"
    dl_file "Manuel de santé des femmes handicapées — Travail et accouchement" "${W}_11.pdf" "$DIR" "Hesperian_MSFH_11_accouchement.pdf"
    dl_file "Manuel de santé des femmes handicapées — Prendre soin de votre bébé" "${W}_12.pdf" "$DIR" "Hesperian_MSFH_12_bebe.pdf"
}

# ── Alimentation et agriculture ───────────────────────────────────────────────
dl_agriculture() {
    info "=== Alimentation et agriculture ==="
    local DIR="$PDF_DIR/food"

    dl_file "Séchage solaire des fruits et légumes (GRET)" \
        "https://gret.org/wp-content/uploads/2021/11/GP-08_Sechage-solaire-des-fruits-et-legumes.pdf" \
        "$DIR" "GRET_Sechage_solaire_fruits_legumes.pdf"
}

# ── Livres du domaine public en français (Projet Gutenberg) ──────────────────
dl_gutenberg_fr() {
    info "=== Projet Gutenberg : livres en français ==="
    local DIR="$BOOKS_DIR/reference"

    # Les URLs Gutenberg se terminent par .epub3.images : le nom de fichier de
    # destination est donc donné explicitement (entrées « URL|fichier »).
    EBOOKS=(
        "https://www.gutenberg.org/ebooks/14287.epub3.images|jules-verne_l-ile-mysterieuse.epub"
    )

    for entry in "${EBOOKS[@]}"; do
        local url="${entry%%|*}" fname="${entry##*|}"
        dl_file "${fname%.epub}" "$url" "$DIR" "$fname"
    done
}

# ── Sources supplémentaires de l'utilisateur (config/pdfs_extra.list) ────────
# Format, une ligne par document :  dossier|nom|url|fichier.pdf
# « dossier » est un sous-dossier de pdfs/ (medical, food, community, survival,
# energy, shelter, communication, …). Les lignes vides et les # sont ignorées.
dl_extra() {
    local list="$REPO_DIR/config/pdfs_extra.list"
    [[ -f "$list" ]] || return 0
    info "=== Documents supplémentaires ($list) ==="
    local folder name url fname
    while IFS='|' read -r folder name url fname; do
        [[ -z "${folder// }" || "$folder" == \#* ]] && continue
        if [[ -z "${name:-}" || -z "${url:-}" ]]; then
            warn "Ligne ignorée (format : dossier|nom|url|fichier) : $folder"; continue
        fi
        # Un dossier ne doit pas pouvoir sortir de pdfs/
        if [[ ! "$folder" =~ ^[A-Za-z0-9_-]+$ ]]; then
            warn "Nom de dossier invalide « $folder » — ligne ignorée"; continue
        fi
        mkdir -p "$PDF_DIR/$folder"
        dl_file "$name" "$url" "$PDF_DIR/$folder" "${fname:-$(basename "$url")}"
    done < "$list"
}

# ── Programme principal ───────────────────────────────────────────────────────
main() {
    info "Début du téléchargement des livres et PDF..."

    dl_officiel
    dl_medical_refs
    dl_agriculture
    dl_gutenberg_fr
    dl_extra

    success "Téléchargement des livres et PDF terminé"
    info "PDF : $PDF_DIR"
    info "Livres : $BOOKS_DIR"
    du -sh "$PDF_DIR" "$BOOKS_DIR" 2>/dev/null || true

    # Rafraîchir la bibliothèque Calibre-Web pour que les nouveaux livres
    # apparaissent sans manipulation manuelle.
    if command -v calibredb &>/dev/null; then
        bash "$REPO_DIR/scripts/build_ebook_library.sh" || true
    fi

    # Indexer le texte des nouveaux documents (recherche du tableau de bord
    # et récupération pour l'assistant IA).
    python3 "$REPO_DIR/scripts/index_documents.py" --storage "$STORAGE_PATH" || true
}

main "$@"
