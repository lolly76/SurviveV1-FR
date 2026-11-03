#!/usr/bin/env bash
# SurviveV1 — System status overview

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

check_port() {
    local port="$1"
    (echo >/dev/tcp/localhost/"$port") 2>/dev/null && \
        echo -e "${GREEN}● ACTIF${NC}" || \
        echo -e "${RED}● ARRÊT${NC}"
}

echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "${BLUE}    SurviveV1 — État du système${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""

# Services
echo -e "  ${YELLOW}Services :${NC}"
printf "    %-22s %s\n" "Tableau de bord (:8080)" "$(check_port 8080)"
printf "    %-22s %s\n" "Kiwix (:8081)" "$(check_port 8081)"
printf "    %-22s %s\n" "Kolibri (:8082)" "$(check_port 8082)"
printf "    %-22s %s\n" "Calibre (:8083)" "$(check_port 8083)"
printf "    %-22s %s\n" "Jellyfin (:8096)" "$(check_port 8096)"
printf "    %-22s %s\n" "Cartes (:3000)" "$(check_port 3000)"
printf "    %-22s %s\n" "Ollama IA (:11434)" "$(check_port 11434)"
echo ""

# Storage
if [[ -d "$STORAGE_PATH" ]]; then
    echo -e "  ${YELLOW}Stockage ($STORAGE_PATH) :${NC}"
    df -h "$STORAGE_PATH" | tail -1 | awk '{
        printf "    Utilisé : %s / %s (%s)\n", $3, $2, $5
    }'
    echo ""

    # Content inventory
    echo -e "  ${YELLOW}Contenu :${NC}"
    for dir in zim videos books pdfs maps kolibri ai_models; do
        DPATH="$STORAGE_PATH/$dir"
        if [[ -d "$DPATH" ]]; then
            SIZE=$(du -sh "$DPATH" 2>/dev/null | cut -f1)
            COUNT=$(find "$DPATH" -type f 2>/dev/null | wc -l)
            printf "    %-12s %6s  (%d fichiers)\n" "$dir" "$SIZE" "$COUNT"
        else
            printf "    %-12s  ${RED}non téléchargé${NC}\n" "$dir"
        fi
    done
else
    echo -e "  ${RED}Stockage non monté sur $STORAGE_PATH${NC}"
fi

echo ""

# System resources
echo -e "  ${YELLOW}Système :${NC}"
printf "    Temp. CPU :  "
vcgencmd measure_temp 2>/dev/null || cat /sys/thermal/thermal_zone0/temp 2>/dev/null | \
    awk '{printf "%.1f°C\n", $1/1000}' || echo "N/A"
printf "    Mémoire :   "
free -h | awk '/^Mem:/{printf "%s utilisés / %s au total\n", $3, $2}'
printf "    En service : "
uptime -p 2>/dev/null || uptime

echo ""

# AI models
if command -v ollama &>/dev/null; then
    echo -e "  ${YELLOW}Modèles d'IA :${NC}"
    OLLAMA_MODELS="$STORAGE_PATH/ai_models/ollama" \
    ollama list 2>/dev/null | tail -n +2 | \
        awk '{printf "    %-20s %s\n", $1, $3}' || \
        echo "    Aucun modèle installé"
    echo ""
fi

# Network
echo -e "  ${YELLOW}Réseau :${NC}"
printf "    IP locales : "
hostname -I 2>/dev/null || echo "N/A"
printf "    Nom d'hôte : "
hostname 2>/dev/null

echo ""
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo -e "  Interface web : ${GREEN}http://$(hostname -I | awk '{print $1}'):8080${NC}"
echo -e "${BLUE}═══════════════════════════════════════════${NC}"
echo ""
