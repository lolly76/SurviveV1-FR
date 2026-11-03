#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Téléchargeur de livres et de PDF
# Télécharge des ressources de survie francophones libres ou du domaine public
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

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
# ══ PACK « ENGLISH » — PDF/livres en anglais (manuels militaires américains, agriculture, ingénierie, radio…) ══
# Repris du projet d'origine, sans équivalent français vérifié. Désactivé par défaut
# (CONTENT_PDFS_EN="Y" pour l'activer).
en_dl_military_manuals() {
    info "=== [EN] US Military Survival Manuals ==="
    local DIR="$PDF_DIR/military_manuals"

    dl_file "FM 21-76 US Army Survival Manual" \
        "https://archive.org/download/milmanual-mcrp-3-02f-fm-21-76-survival/mcrp_3-02f_fm_21-76_survival.pdf" \
        "$DIR" "FM21-76_Army_Survival_Manual.pdf"

    dl_file "ATP 3-50.21 Survival" \
        "https://armypubs.army.mil/epubs/DR_pubs/DR_a/ARN32107-ATP_3-50.21-000-WEB-1.pdf" \
        "$DIR" "ATP_3-50-21_Survival.pdf"

    dl_file "FM 4-25.11 First Aid" \
        "https://archive.org/download/fm-4-25.11-first-aid/FM%204-25.11%20First%20Aid.pdf" \
        "$DIR" "FM4-25-11_First_Aid.pdf"

    dl_file "TC 3-97.61 Military Mountaineering" \
        "https://armypubs.army.mil/epubs/DR_pubs/DR_a/pdf/web/tc3_97x61.pdf" \
        "$DIR" "TC3-97-61_Mountaineering.pdf"

    dl_file "FM 3-05.70 Special Forces Survival" \
        "https://archive.org/download/fm-3-05.70-survival-2002/FM%203-05.70%20Survival%20%202002.pdf" \
        "$DIR" "FM3-05-70_SF_Survival.pdf"

    dl_file "FM 3-05.213 Special Forces Use of Pack Animals" \
        "https://armypubs.army.mil/epubs/DR_pubs/DR_a/pdf/web/fm3_05x213.pdf" \
        "$DIR" "FM3-05-213_Pack_Animals.pdf"

    dl_file "FM 21-10 Field Sanitation" \
        "https://archive.org/download/milmanual-fm-21-10-mcrp-4-11.1d-field-hygiene-and-sanitation/fm_21-10_mcrp_4-11.1d_field_hygiene_and_sanitation.pdf" \
        "$DIR" "FM21-10_Field_Sanitation.pdf"

    dl_file "FM 90-5 Jungle Operations" \
        "https://archive.org/download/milmanual-fm-90-5-jungle-operations/fm_90-5_jungle_operations.pdf" \
        "$DIR" "FM90-5_Jungle_Operations.pdf"

    dl_file "SAS Survival Handbook (excerpt)" \
        "https://www.ibiblio.org/hyperwar/ATO/USAAF/SurvivalManual.pdf" \
        "$DIR" "Survival_Manual_USAAF.pdf"
}

en_dl_medical_refs() {
    info "=== [EN] Medical References ==="
    local DIR="$BOOKS_DIR/medicine"

    # Hesperian now gates its own PDFs behind an email form — use the
    # freely-mirrored copies on archive.org instead.
    dl_file "Where There Is No Doctor (Hesperian)" \
        "https://archive.org/download/where-there-is-no-doctor/Where%20There%20Is%20No%20Doctor.pdf" \
        "$DIR" "Where_There_Is_No_Doctor.pdf"

    dl_file "Where There Is No Dentist" \
        "https://archive.org/download/Where_There_is_no_Dentist/Where_There_is_no_Dentist.pdf" \
        "$DIR" "Where_There_Is_No_Dentist.pdf"

    dl_file "A Book for Midwives" \
        "https://archive.org/download/ABookForMidwives/26.SusanKlien-ABookForMidwives.pdf" \
        "$DIR" "A_Book_for_Midwives.pdf"

    dl_file "Helping Children Who Are Blind" \
        "https://store.hesperian.org/prod/pdf/A250E.pdf" \
        "$DIR" "Helping_Children_Blind.pdf"

    dl_file "Merck Veterinary Manual (online guide)" \
        "https://www.msdvetmanual.com/Content/Whitepaper/MVM_Whitepaper.pdf" \
        "$DIR" "Merck_Veterinary_Guide.pdf"

    dl_file "Emergency Preparedness and Response (CDC)" \
        "https://www.cdc.gov/niosh/docs/2004-101/pdfs/2004-101.pdf" \
        "$DIR" "CDC_Emergency_Preparedness.pdf"

    dl_file "Combat Casualty Care Manual" \
        "https://www.usso.med.navy.mil/sites/usso/files/2018-12/tccc-guidelines.pdf" \
        "$DIR" "TCCC_Guidelines.pdf" || warn "TCCC Manual: try manual download"
}

en_dl_agriculture() {
    info "=== [EN] Agriculture & Food Production ==="
    local DIR="$BOOKS_DIR/agriculture"

    # USDA resources (Public Domain)
    dl_file "USDA Home Canning Guide" \
        "https://nchfp.uga.edu/publications/publications_usda.html" \
        "$DIR" "USDA_Home_Canning_Guide.pdf" || true

    dl_file "Square Foot Gardening Manual" \
        "https://extension.sdstate.edu/sites/default/files/2020-06/P-00003.pdf" \
        "$DIR" "Square_Foot_Gardening.pdf"

    dl_file "Organic Farming Guide (ATTRA)" \
        "https://attra.ncat.org/product/beginning-farmer.pdf" \
        "$DIR" "Beginning_Farmer_Guide.pdf"

    dl_file "Permaculture Design Manual (excerpt)" \
        "https://holmgren.com.au/downloads/Essence_of_Pc_EN.pdf" \
        "$DIR" "Permaculture_Essence.pdf"

    dl_file "Small-Scale Chicken Keeping" \
        "https://extension.psu.edu/programs/betterkidcare/news/2018/small-scale-chicken-keeping" \
        "$DIR" "Chicken_Keeping.pdf" || true

    dl_file "Wild Edible Plants Guide (USDA)" \
        "https://www.fs.usda.gov/Internet/FSE_DOCUMENTS/stelprdb5444952.pdf" \
        "$DIR" "Wild_Edible_Plants_USDA.pdf"

    dl_file "Food Preservation Methods" \
        "https://nchfp.uga.edu/how/store/uga_freeze_dry.pdf" \
        "$DIR" "Food_Preservation.pdf"
}

en_dl_engineering() {
    info "=== [EN] Engineering & Construction ==="
    local DIR="$PDF_DIR/construction"

    dl_file "Tiny House Building Guide" \
        "https://www.huduser.gov/portal/publications/pdf/HousingFirst_TinyHomes.pdf" \
        "$DIR" "Tiny_Houses_Guide.pdf"

    dl_file "Earthship Construction Manual" \
        "https://www.earthship.com/earthship-construction.pdf" \
        "$DIR" "Earthship_Construction.pdf" || warn "Earthship manual: see earthship.com"

    dl_file "Solar Power System Design Guide" \
        "https://www.nrel.gov/docs/fy03osti/31146.pdf" \
        "$DIR" "NREL_Solar_System_Design.pdf"

    dl_file "Wind Energy Basics" \
        "https://www.nrel.gov/docs/fy01osti/29492.pdf" \
        "$DIR" "NREL_Wind_Energy_Basics.pdf"

    dl_file "Water System Design Guide" \
        "https://www.nrcs.usda.gov/sites/default/files/2022-10/NEH_210-600.pdf" \
        "$DIR" "NRCS_Water_System_Design.pdf"

    dl_file "Composting Guide (EPA)" \
        "https://www.epa.gov/sites/default/files/2016-01/documents/master_composter_manual.pdf" \
        "$DIR" "EPA_Composting_Guide.pdf"
}

en_dl_radio() {
    info "=== [EN] Ham Radio & Communications ==="
    local DIR="$PDF_DIR/radio"

    dl_file "ARRL Handbook excerpt (legal free chapters)" \
        "http://www.arrl.org/files/file/Technology/tis/info/pdf/0111qex017.pdf" \
        "$DIR" "ARRL_Basics.pdf"

    dl_file "Amateur Radio Emergency Communications" \
        "https://www.arrl.org/files/file/ARESHandbook2015.pdf" \
        "$DIR" "ARES_Handbook.pdf"

    dl_file "FCC Technician License Study Guide" \
        "https://ncvec.org/downloads/2022-2026%20Tech%20Pool%20w%20Errata.pdf" \
        "$DIR" "FCC_Technician_Study_Guide.pdf"
}

en_dl_homesteading() {
    info "=== [EN] Homesteading & DIY ==="
    local DIR="$PDF_DIR/homesteading"

    dl_file "The Encyclopedia of Country Living (excerpt)" \
        "https://www.nps.gov/articles/000/upload/Basic-Wilderness-Skills.pdf" \
        "$DIR" "Wilderness_Skills_NPS.pdf"

    dl_file "Foxfire Series excerpts (public domain)" \
        "https://docslib.org/doc/12279028/the-foxfire-book.pdf" \
        "$DIR" "Foxfire_Book.pdf" || warn "Foxfire: download manually from archive.org"

    dl_file "Herbal Medicine Guide (PubMed)" \
        "https://www.ncbi.nlm.nih.gov/books/NBK92766/pdf/Bookshelf_NBK92766.pdf" \
        "$DIR" "Herbal_Medicine_Guide.pdf"
}

en_dl_standard_ebooks() {
    info "=== [EN] Standard Ebooks (free, public domain) ==="
    local DIR="$BOOKS_DIR/reference"

    # Standard Ebooks provides free, high-quality public domain books
    # Project Gutenberg direct EPUBs. Standard Ebooks now serves its book
    # page (application/xhtml+xml) instead of the file to non-browser clients,
    # which silently produced HTML files named *.epub.
    EBOOKS=(
        "https://www.gutenberg.org/ebooks/2009.epub3.images|charles-darwin_on-the-origin-of-species.epub"
        "https://www.gutenberg.org/ebooks/205.epub3.images|henry-david-thoreau_walden.epub"
        "https://www.gutenberg.org/ebooks/1268.epub3.images|jules-verne_the-mysterious-island.epub"
        "https://www.gutenberg.org/ebooks/215.epub3.images|jack-london_the-call-of-the-wild.epub"
        "https://www.gutenberg.org/ebooks/76.epub3.images|mark-twain_adventures-of-huckleberry-finn.epub"
        "https://www.gutenberg.org/ebooks/521.epub3.images|daniel-defoe_robinson-crusoe.epub"
    )

    for entry in "${EBOOKS[@]}"; do
        # entries are "URL|filename" — Gutenberg's URLs end in .epub3.images,
        # so the destination name is given explicitly.
        local url="${entry%%|*}" fname="${entry##*|}"
        dl_file "${fname%.epub}" "$url" "$DIR" "$fname"
    done
}

dl_english_pack() {
    [[ "${CONTENT_PDFS_EN:-N}" =~ [YyOo] ]] || { info "Pack English désactivé (CONTENT_PDFS_EN=N)"; return 0; }
    info "######## PACK ENGLISH — PDF/livres en anglais (manuels militaires américains, agriculture, ingénierie, radio…) ########"
    en_dl_military_manuals
    en_dl_medical_refs
    en_dl_agriculture
    en_dl_engineering
    en_dl_radio
    en_dl_homesteading
    en_dl_standard_ebooks
}

main() {
    info "Début du téléchargement des livres et PDF..."

    dl_officiel
    dl_medical_refs
    dl_agriculture
    dl_gutenberg_fr
    dl_extra
    dl_english_pack

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
