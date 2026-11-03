#!/usr/bin/env bash
# =============================================================================
# SurviveV1-FR — Assistant de configuration du premier lancement
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$REPO_DIR/config/survive.conf"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()   { echo -e "${BLUE}[?]${NC} $*"; }
prompt() { echo -e "${YELLOW}>>>${NC} $*"; }

echo ""
echo -e "${GREEN}=== SurviveV1 — Configuration du premier lancement ===${NC}"
echo ""

# ── Storage path ──────────────────────────────────────────────────────────────
info "Où stocker les contenus ? (SSD USB recommandé)"
echo "  Exemples : /mnt/survive, /media/pi/SURVIVE, /home/pi/survive"
read -rp "  Chemin de stockage [/mnt/survive] : " STORAGE_PATH
STORAGE_PATH="${STORAGE_PATH:-/mnt/survive}"

# ── Storage device ────────────────────────────────────────────────────────────
echo ""
info "Périphériques disponibles :"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null | grep -E "disk|part" | head -20
echo ""
read -rp "  Périphérique à monter (p. ex. /dev/sda1) ou SKIP pour utiliser le chemin existant : " STORAGE_DEV
STORAGE_DEV="${STORAGE_DEV:-SKIP}"

# ── Content budget ────────────────────────────────────────────────────────────
echo ""
info "Budget de stockage (Go) ? Par défaut 800"
read -rp "  Budget [800] : " STORAGE_BUDGET_GB
STORAGE_BUDGET_GB="${STORAGE_BUDGET_GB:-800}"

# ── Content selection ─────────────────────────────────────────────────────────
echo ""
info "Choisissez les contenus à télécharger (o/n pour chacun) :"
read -rp "  Wikipédia FR complète (~52 Go) ?               [O/n] : " DL_WIKIPEDIA
read -rp "  Wikipédia FR sans images (~12 Go) ?            [o/N] : " DL_WIKIPEDIA_NOPIC
read -rp "  Wikilivres, Wikivoyage, Wikisource, Wiktionnaire (~17 Go) ? [O/n] : " DL_WIKIBOOKS
read -rp "  Stack Exchange (langue française, <1 Go) ?     [O/n] : " DL_STACKEXCHANGE
read -rp "  Projet Gutenberg, livres FR (~15 Go) ?         [O/n] : " DL_GUTENBERG
read -rp "  Khan Academy FR via Kolibri (~200 Go) ?        [O/n] : " DL_KOLIBRI
read -rp "  Vidéos de survie / autonomie (~150 Go) ?       [O/n] : " DL_VIDEOS
read -rp "  Cartes OpenStreetMap hors ligne, France (~5 Go) ? [O/n] : " DL_MAPS
read -rp "  PDF et manuels sélectionnés (~20 Go) ?         [O/n] : " DL_PDFS
read -rp "  Modèles d'IA pour Ollama (~50 Go) ?            [O/n] : " DL_AI_MODELS
read -rp "  Guides de réparation iFixit FR (~3,5 Go) ?     [O/n] : " DL_IFIX

DL_WIKIPEDIA="${DL_WIKIPEDIA:-Y}"
DL_WIKIPEDIA_NOPIC="${DL_WIKIPEDIA_NOPIC:-N}"
DL_WIKIBOOKS="${DL_WIKIBOOKS:-Y}"
DL_STACKEXCHANGE="${DL_STACKEXCHANGE:-Y}"
DL_GUTENBERG="${DL_GUTENBERG:-Y}"
DL_KOLIBRI="${DL_KOLIBRI:-Y}"
DL_VIDEOS="${DL_VIDEOS:-Y}"
DL_MAPS="${DL_MAPS:-Y}"
DL_PDFS="${DL_PDFS:-Y}"
DL_AI_MODELS="${DL_AI_MODELS:-Y}"
DL_IFIX="${DL_IFIX:-Y}"

# Réponses françaises : « o/O » = oui, tout le reste (hors vide) = non.
_norm() { case "${1:-}" in [YyOo]*) echo Y ;; "") echo "$2" ;; *) echo N ;; esac; }
DL_WIKIPEDIA=$(_norm "$DL_WIKIPEDIA" Y);       DL_WIKIPEDIA_NOPIC=$(_norm "$DL_WIKIPEDIA_NOPIC" N)
DL_WIKIBOOKS=$(_norm "$DL_WIKIBOOKS" Y);       DL_STACKEXCHANGE=$(_norm "$DL_STACKEXCHANGE" Y)
DL_GUTENBERG=$(_norm "$DL_GUTENBERG" Y);       DL_KOLIBRI=$(_norm "$DL_KOLIBRI" Y)
DL_VIDEOS=$(_norm "$DL_VIDEOS" Y);             DL_MAPS=$(_norm "$DL_MAPS" Y)
DL_PDFS=$(_norm "$DL_PDFS" Y);                 DL_AI_MODELS=$(_norm "$DL_AI_MODELS" Y)
DL_IFIX=$(_norm "$DL_IFIX" Y)

# ── Hostname ──────────────────────────────────────────────────────────────────
echo ""
read -rp "  Nom d'hôte de cet appareil [survive] : " DEVICE_HOSTNAME
DEVICE_HOSTNAME="${DEVICE_HOSTNAME:-survive}"

# ── Write config ──────────────────────────────────────────────────────────────
mkdir -p "$(dirname "$CONFIG_FILE")"
cat > "$CONFIG_FILE" << EOF
# Configuration SurviveV1-FR
# Générée le : $(date)

SURVIVE_STORAGE_PATH="$STORAGE_PATH"
SURVIVE_STORAGE_DEV="$STORAGE_DEV"
SURVIVE_BUDGET_GB="$STORAGE_BUDGET_GB"
SURVIVE_HOSTNAME="$DEVICE_HOSTNAME"

MAP_REGION="france"

# Contenus (Y/O = télécharger, N = ignorer)
CONTENT_WIKIPEDIA="$DL_WIKIPEDIA"
CONTENT_WIKIPEDIA_NOPIC="$DL_WIKIPEDIA_NOPIC"
CONTENT_WIKIBOOKS="$DL_WIKIBOOKS"
CONTENT_STACKEXCHANGE="$DL_STACKEXCHANGE"
CONTENT_GUTENBERG="$DL_GUTENBERG"
CONTENT_KOLIBRI="$DL_KOLIBRI"
CONTENT_VIDEOS="$DL_VIDEOS"
CONTENT_MAPS="$DL_MAPS"
CONTENT_PDFS="$DL_PDFS"
CONTENT_AI_MODELS="$DL_AI_MODELS"
CONTENT_IFIX="$DL_IFIX"
EOF

echo ""
echo -e "${GREEN}Configuration enregistrée dans $CONFIG_FILE${NC}"
echo ""

# ── Mount storage ─────────────────────────────────────────────────────────────
if [[ "$STORAGE_DEV" != "SKIP" ]] && [[ -b "$STORAGE_DEV" ]]; then
    echo "Montage de $STORAGE_DEV sur $STORAGE_PATH..."
    mkdir -p "$STORAGE_PATH"
    FSTYPE=$(blkid -s TYPE -o value "$STORAGE_DEV" 2>/dev/null || echo "ext4")
    mount -t "$FSTYPE" "$STORAGE_DEV" "$STORAGE_PATH"

    # Add to fstab for auto-mount
    PARTUUID=$(blkid -s PARTUUID -o value "$STORAGE_DEV" 2>/dev/null || echo "")
    if [[ -n "$PARTUUID" ]]; then
        echo "PARTUUID=$PARTUUID  $STORAGE_PATH  $FSTYPE  defaults,noatime  0  2" >> /etc/fstab
        echo "Ajouté à /etc/fstab pour le montage automatique"
    fi
fi
