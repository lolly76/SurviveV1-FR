#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Appliquer un profil de contenu (léger / moyen / complet)
# Usage : bash scripts/apply_profile.sh <leger|moyen|complet> [fichier.conf]
# Réécrit (ou ajoute) les clés CONTENT_* et SURVIVE_BUDGET_GB du profil dans
# config/survive.conf (ou le fichier donné). Les autres lignes sont conservées.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:-}"
CONF="${2:-$REPO_DIR/config/survive.conf}"
PFILE="$REPO_DIR/config/profiles/${PROFILE}.conf"

if [[ ! "$PROFILE" =~ ^[a-z]+$ || ! -f "$PFILE" ]]; then
    echo "Usage : $0 <leger|moyen|complet> [fichier.conf]" >&2
    exit 2
fi
[[ -f "$CONF" ]] || touch "$CONF"

while IFS= read -r line; do
    [[ "$line" =~ ^([A-Z_]+)=\"(.*)\"$ ]] || continue
    key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
    if grep -q "^${key}=" "$CONF"; then
        sed -i "s|^${key}=.*|${key}=\"${val}\"|" "$CONF"
    else
        echo "${key}=\"${val}\"" >> "$CONF"
    fi
done < "$PFILE"

echo "Profil « ${PROFILE} » appliqué à ${CONF}"
