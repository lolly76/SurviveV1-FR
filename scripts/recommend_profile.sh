#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Profil de contenu conseillé selon l'espace disponible
# Usage : bash scripts/recommend_profile.sh <go_libres> [--systeme]
#   --systeme : le stockage est sur le disque du système (mode « dossier ») ;
#               on garde une marge de sécurité de 20 Go ou 15 % si plus grande,
#               pour ne jamais remplir le disque où tourne Debian.
# Affiche : leger | moyen | complet | insuffisant
# =============================================================================
set -euo pipefail

FREE="${1:-}"
[[ "$FREE" =~ ^[0-9]+$ ]] || { echo "Usage : $0 <go_libres> [--systeme]" >&2; exit 2; }

if [[ "${2:-}" == "--systeme" ]]; then
    margin=$(( FREE * 15 / 100 ))
    (( margin < 20 )) && margin=20
    FREE=$(( FREE - margin ))
    (( FREE < 0 )) && FREE=0
fi

if   (( FREE >= 900 )); then echo complet
elif (( FREE >= 300 )); then echo moyen
elif (( FREE >= 80 ));  then echo leger
else                         echo insuffisant
fi
