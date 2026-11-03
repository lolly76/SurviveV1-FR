#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Pre-flight checks before install
# Run: bash setup/pre_flight_check.sh
# Exits non-zero if any CRITICAL check fails; warns for non-critical issues.
# =============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass()  { echo -e "  ${GREEN}[PASS]${NC}  $*"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}  $*"; FAILURES=$((FAILURES+1)); }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
info()  { echo -e "  ${BLUE}[INFO]${NC}  $*"; }

FAILURES=0

echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  SurviveV1 — Vérification préalable${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# ── OS / Architecture ─────────────────────────────────────────────────────────
echo "Système et architecture"
if [[ "$(uname -m)" == "aarch64" ]]; then
    pass "Architecture : aarch64 (ARM 64 bits)"
else
    if [[ "$(uname -m)" == "x86_64" ]]; then
        info "Architecture : x86_64 — mode machine de test (VM / PC), étapes propres au Pi ignorées"
    else
        warn "Architecture : $(uname -m) — aarch64 attendu (Raspberry Pi 5, 64 bits)"
    fi
fi

if grep -qi "bookworm\|trixie" /etc/os-release 2>/dev/null; then
    pass "Système : Raspberry Pi OS ($(. /etc/os-release && echo "$VERSION_CODENAME"))"
elif grep -q "Bullseye" /etc/os-release 2>/dev/null; then
    warn "Système : Bullseye — Bookworm ou plus récent recommandé"
else
    OS_ID=$(. /etc/os-release && echo "$PRETTY_NAME")
    warn "Système : $OS_ID — non testé, peut fonctionner"
fi

RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
if [[ "$RAM_MB" -ge 3800 ]]; then
    pass "RAM : ${RAM_MB} Mo"
else
    warn "RAM : ${RAM_MB} Mo — 4 Go recommandés pour faire tourner tous les services"
fi

echo ""

# ── Root / Sudo ───────────────────────────────────────────────────────────────
echo "Droits"
if [[ $EUID -eq 0 ]]; then
    pass "Running as root"
elif sudo -n true 2>/dev/null; then
    pass "sudo available without password"
else
    fail "Ni root ni sudo sans mot de passe — l'installateur exige sudo"
fi

echo ""

# ── Internet connectivity ─────────────────────────────────────────────────────
echo "Réseau"
if ping -c 1 -W 5 8.8.8.8 &>/dev/null; then
    pass "Internet: reachable (ping 8.8.8.8)"
elif ping -c 1 -W 5 1.1.1.1 &>/dev/null; then
    pass "Internet: reachable (ping 1.1.1.1)"
else
    fail "Internet : inaccessible — nécessaire pour télécharger logiciels et contenus"
fi

if ping -c 1 -W 3 download.kiwix.org &>/dev/null 2>&1; then
    pass "Kiwix download server: reachable"
else
    warn "Serveur de téléchargement Kiwix : inaccessible — peut gêner le téléchargement des ZIM"
fi

echo ""

# ── Storage ───────────────────────────────────────────────────────────────────
echo "Stockage"
STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"

if mountpoint -q "$STORAGE_PATH" 2>/dev/null; then
    AVAIL_GB=$(df -BG "$STORAGE_PATH" | tail -1 | awk '{print $4}' | tr -d 'G')
    pass "Storage mounted at $STORAGE_PATH"
    if [[ "$AVAIL_GB" -ge 800 ]]; then
        pass "Available space: ${AVAIL_GB} GB (sufficient for full 800 GB install)"
    elif [[ "$AVAIL_GB" -ge 100 ]]; then
        warn "Espace disponible : ${AVAIL_GB} Go — insuffisant pour l'installation complète (800 Go) ; installation partielle possible"
    else
        fail "Espace disponible : ${AVAIL_GB} Go — au moins 100 Go requis"
    fi
else
    warn "Stockage non monté sur $STORAGE_PATH — montez votre disque avant de lancer les téléchargements"
    # Check root filesystem space instead
    ROOT_AVAIL_GB=$(df -BG / | tail -1 | awk '{print $4}' | tr -d 'G')
    info "Le système racine a ${ROOT_AVAIL_GB} Go libres (les contenus doivent aller sur le disque externe)"
fi

echo ""

# ── Required commands ─────────────────────────────────────────────────────────
echo "Outils requis"
REQUIRED_CMDS=(apt-get systemctl curl wget git python3)
for cmd in "${REQUIRED_CMDS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        pass "$cmd: found"
    else
        fail "$cmd : INTROUVABLE — requis pour l'installation"
    fi
done

echo ""

# ── Optional tools (already installed check) ─────────────────────────────────
echo "Outils facultatifs (préinstallés)"
OPTIONAL_CMDS=(ffmpeg nginx ufw rclone aria2c yt-dlp kiwix-serve ollama)
for cmd in "${OPTIONAL_CMDS[@]}"; do
    if command -v "$cmd" &>/dev/null; then
        pass "$cmd: already installed"
    else
        info "$cmd : non installé (sera installé par setup/install.sh)"
    fi
done

echo ""

# ── Python version ────────────────────────────────────────────────────────────
echo "Python"
PY_VER=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>/dev/null || echo "0.0")
PY_MAJOR=${PY_VER%%.*}
PY_MINOR=${PY_VER##*.}
if [[ "$PY_MAJOR" -ge 3 ]] && [[ "$PY_MINOR" -ge 9 ]]; then
    pass "Python $PY_VER (3.9 ou plus requis)"
else
    fail "Python $PY_VER — Python 3.9 ou plus requis"
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BLUE}════════════════════════════════════════${NC}"
if [[ "$FAILURES" -eq 0 ]]; then
    echo -e "  ${GREEN}Toutes les vérifications critiques sont réussies. Prêt à installer !${NC}"
    echo ""
    echo "  Ensuite : sudo bash setup/install.sh"
else
    echo -e "  ${RED}$FAILURES vérification(s) critique(s) en échec. Corrigez les problèmes ci-dessus avant d'installer.${NC}"
fi
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

exit "$FAILURES"
