#!/usr/bin/env bash
# =============================================================================
# SurviveV1-FR — Référence des médicaments hors ligne (BDPM)
#
# Source : Base de données publique des médicaments (ANSM, HAS, UNCAM) —
# https://base-donnees-publique.medicaments.gouv.fr — licence ouverte :
# ne pas altérer les données, citer la source et la date de mise à jour.
#
#   1. Télécharge les fichiers BDPM (spécialités, compositions, conditions de
#      prescription) dans $STORAGE/drugs/raw/ (quelques Mo).
#   2. Récupère LENTEMENT et de façon reprenable les notices/RCP officielles de
#      chaque spécialité (indications, posologie, contre-indications, mises en
#      garde, interactions) dans $STORAGE/drugs/notices/. Désactivable avec
#      CONTENT_DRUG_NOTICES="N" ; limitez avec SURVIVE_DRUGS_NOTICE_MAX=500.
#   3. Construit l'index de recherche SQLite lu par la page /drugs.
#
#   bash download/drug_reference.sh --storage /mnt/survive [--index-only]
#
# Relancer le script reprend là où il s'est arrêté (les notices déjà
# récupérées ne sont pas redemandées ; les fichiers BDPM sont rafraîchis).
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
INDEX_ONLY=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --storage) STORAGE_PATH="$2"; shift 2 ;;
        --index-only) INDEX_ONLY=true; shift ;;
        *) shift ;;
    esac
done

RAW_DIR="$STORAGE_PATH/drugs/raw"
LOG_DIR="$STORAGE_PATH/.logs"
mkdir -p "$RAW_DIR" "$LOG_DIR"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}[MÉDICAMENTS]${NC} $*"; }
success() { echo -e "${GREEN}[MÉDICAMENTS]${NC} $*"; }
warn()    { echo -e "${YELLOW}[MÉDICAMENTS]${NC} $*"; }

FAILED_LOG="$LOG_DIR/failed_downloads.log"
BDPM_BASE="https://base-donnees-publique.medicaments.gouv.fr/download/file"
BDPM_FILES=(CIS_bdpm.txt CIS_COMPO_bdpm.txt CIS_CPD_bdpm.txt)

# Un fichier BDPM valide est un TSV : au moins une tabulation sur sa première ligne.
_is_tsv() { head -n 1 "$1" 2>/dev/null | grep -q $'\t'; }

if [[ "$INDEX_ONLY" != true ]]; then
    info "Téléchargement des fichiers BDPM (Base de données publique des médicaments)..."
    for f in "${BDPM_FILES[@]}"; do
        dest="$RAW_DIR/$f"
        tmp="$dest.part"
        if curl -fsSL --retry 3 --max-time 300 -A "SurviveV1-FR (base hors ligne personnelle)" \
                -D "$tmp.hdr" "$BDPM_BASE/$f" -o "$tmp" && _is_tsv "$tmp"; then
            mv "$tmp" "$dest"
            # Date de mise à jour (en-tête Last-Modified si fourni, sinon date du jour).
            if [[ "$f" == "CIS_bdpm.txt" ]]; then
                lm=$(grep -i '^last-modified:' "$tmp.hdr" | head -n1 | cut -d' ' -f2- | tr -d '\r' || true)
                if [[ -n "$lm" ]] && d=$(date -d "$lm" '+%d/%m/%Y' 2>/dev/null); then
                    echo "$d" > "$RAW_DIR/BDPM_DATE"
                else
                    date '+%d/%m/%Y' > "$RAW_DIR/BDPM_DATE"
                fi
            fi
            success "$f"
        else
            warn "[$f] téléchargement impossible — l'ancienne version (si présente) est conservée"
            echo "$(date '+%Y-%m-%d %H:%M:%S') FAILED [bdpm $f] $BDPM_BASE/$f" >> "$FAILED_LOG"
        fi
        rm -f "$tmp" "$tmp.hdr"
    done

    if [[ ! -f "$RAW_DIR/CIS_bdpm.txt" ]]; then
        warn "Fichier des spécialités absent — abandon (pas de connexion ?)"
        exit 1
    fi

    if [[ "${CONTENT_DRUG_NOTICES:-Y}" =~ ^[YyOo] ]]; then
        if command -v python3 &>/dev/null; then
            info "Récupération lente des notices officielles (reprenable ; Ctrl-C sans risque)..."
            nice -n 19 python3 "$REPO_DIR/scripts/fetch_drug_notices.py" --storage "$STORAGE_PATH" \
                || warn "Récupération des notices interrompue — relancez le script pour reprendre"
        fi
    else
        info "Notices désactivées (CONTENT_DRUG_NOTICES=N) : index limité aux noms, compositions et conditions de prescription."
    fi
fi

info "Construction de l'index de recherche des médicaments..."
if command -v python3 &>/dev/null; then
    nice -n 19 python3 "$REPO_DIR/scripts/build_drug_index.py" --storage "$STORAGE_PATH" \
        || warn "Échec de la construction de l'index"
else
    warn "python3 introuvable — impossible de construire l'index"
fi

success "Référence des médicaments prête : page /drugs du tableau de bord."
