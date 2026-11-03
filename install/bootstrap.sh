#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Amorçage en un clic
#
# Utilisation (sur un Raspberry Pi 5 tout neuf) :
#   curl -fsSL https://raw.githubusercontent.com/lolly76/SurviveV1-FR/main/install/bootstrap.sh | bash
#
# Le script :
#   1. Vérifie la configuration minimale (aarch64, Bookworm, Internet)
#   2. Installe git s'il manque
#   3. Clone le dépôt
#   4. Lance l'assistant d'installation interactif
#
# Valeurs par défaut modifiables par variables d'environnement :
#   SURVIVE_REPO   - URL du dépôt Git  (défaut : https://github.com/lolly76/SurviveV1-FR.git)
#   SURVIVE_BRANCH - Branche ou étiquette  (défaut : main)
#   SURVIVE_DIR    - Dossier de clonage    (défaut : /home/$SUDO_USER/SurviveV1 ou ~/SurviveV1)
# =============================================================================
set -euo pipefail

SURVIVE_REPO="${SURVIVE_REPO:-https://github.com/lolly76/SurviveV1-FR.git}"
SURVIVE_BRANCH="${SURVIVE_BRANCH:-main}"

# Dossier de clonage : on préfère le dossier personnel de l'utilisateur appelant,
# pour que les fichiers clonés en root n'appartiennent pas à root par erreur.
REAL_USER="${SUDO_USER:-${USER:-pi}}"
REAL_HOME=$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6 || echo "/home/$REAL_USER")
SURVIVE_DIR="${SURVIVE_DIR:-${REAL_HOME}/SurviveV1}"

# ── Couleurs ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "  ${BLUE}→${NC}  $*"; }
ok()    { echo -e "  ${GREEN}✓${NC}  $*"; }
warn()  { echo -e "  ${YELLOW}!${NC}  $*"; }
die()   { echo -e "\n${RED}[ERREUR]${NC} $*" >&2; exit 1; }

# ── Bannière ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔════════════════════════════════════════════╗"
echo "  ║  SurviveV1-FR — Survie hors ligne (FR)    ║"
echo "  ║      Installateur en un clic              ║"
echo "  ╚════════════════════════════════════════════╝"
echo -e "${NC}"
echo ""

# ── Étape 1 : configuration minimale ───────────────────────────────────────
info "Vérification de la configuration requise..."

# Architecture : ARM 64 bits obligatoire
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" ]]; then
    die "Architecture non prise en charge : ${ARCH}\n" \
        "  SurviveV1 est conçu pour le Raspberry Pi 5 (aarch64).\n" \
        "  Raspberry Pi OS 64 bits est requis."
fi
ok "Architecture : ${ARCH}"

# RAM : avertissement en dessous de 4 Go
RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
if (( RAM_MB < 3800 )); then
    warn "RAM : ${RAM_MB} Mo — 4 Go minimum recommandés (certains services peuvent être lents)"
else
    ok "RAM : ${RAM_MB} Mo"
fi

# Système : Raspberry Pi OS Bookworm (Debian 12) ou Trixie (Debian 13)
if grep -qi "bookworm\|trixie" /etc/os-release 2>/dev/null; then
    OS_NAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    ok "Système : Raspberry Pi OS (${OS_NAME})"
elif grep -q "Bullseye\|bullseye" /etc/os-release 2>/dev/null; then
    warn "Système : Bullseye détecté — Bookworm ou plus récent recommandé"
elif grep -q "ID=debian\|ID=raspbian" /etc/os-release 2>/dev/null; then
    OS_NAME=$(. /etc/os-release && echo "$PRETTY_NAME")
    warn "Système : ${OS_NAME} — non testé, peut fonctionner"
else
    die "Système non pris en charge. Raspberry Pi OS (Bookworm) est requis."
fi

# Accès Internet
if ! curl -sf --max-time 10 https://github.com >/dev/null 2>&1; then
    die "Pas d'accès à Internet. SurviveV1 en a besoin pendant l'installation\n" \
        "  (le système fonctionne ensuite 100 %% hors ligne)."
fi
ok "Internet : connecté"

echo ""

# ── Étape 2 : vérifier que git est installé ───────────────────────────────────────────
if ! command -v git &>/dev/null; then
    info "git introuvable — installation..."
    # apt est nécessaire, donc les droits root aussi
    if [[ $EUID -ne 0 ]]; then
        sudo apt-get update -qq && sudo apt-get install -y -qq git
    else
        apt-get update -qq && apt-get install -y -qq git
    fi
    ok "git installé"
else
    ok "git: $(git --version)"
fi

# ── Étape 3 : cloner ou mettre à jour le dépôt ────────────────────────────────────
echo ""
info "Dépôt : ${SURVIVE_REPO}  (branche : ${SURVIVE_BRANCH})"
info "Dossier de clonage : ${SURVIVE_DIR}"
echo ""

if [[ -d "${SURVIVE_DIR}/.git" ]]; then
    warn "Le dépôt existe déjà dans ${SURVIVE_DIR}"
    ask_update() {
        echo -en "  ${BOLD}Mettre à jour vers la dernière version de ${SURVIVE_BRANCH} ? [O/n]${NC} "
        # Avec `curl | bash`, stdin est le tube du script (épuisé), pas le clavier :
        # on lit directement le terminal, avec « oui » par défaut.
        read -r ans < /dev/tty 2>/dev/null || ans=o
        if [[ "${ans:-o}" =~ ^[YyOo] ]]; then
            git -C "${SURVIVE_DIR}" fetch origin
            git -C "${SURVIVE_DIR}" checkout "${SURVIVE_BRANCH}"
            git -C "${SURVIVE_DIR}" pull --ff-only origin "${SURVIVE_BRANCH}"
            ok "Dépôt mis à jour"
        else
            info "Utilisation du dépôt existant"
        fi
    }
    ask_update
else
    info "Clonage de SurviveV1..."
    git clone --branch "${SURVIVE_BRANCH}" --depth 1 \
        "${SURVIVE_REPO}" "${SURVIVE_DIR}" \
        || die "Échec du clonage du dépôt. Vérifiez votre réseau et réessayez."
    # Corriger les droits : le clonage s'est fait en root mais les fichiers doivent appartenir à l'utilisateur
    if [[ $EUID -eq 0 ]] && [[ -n "$REAL_USER" ]] && id "$REAL_USER" &>/dev/null; then
        chown -R "${REAL_USER}:${REAL_USER}" "${SURVIVE_DIR}"
    fi
    ok "Dépôt cloné dans ${SURVIVE_DIR}"
fi

# ── Étape 4 : lancer l'assistant ─────────────────────────────────────────────────
echo ""
info "Lancement de l'assistant d'installation..."
echo ""

WIZARD="${SURVIVE_DIR}/install/wizard.sh"
[[ -f "$WIZARD" ]] || die "Assistant introuvable (${WIZARD}) — le clonage est peut-être incomplet."
chmod +x "$WIZARD"

# Passage en root pour l'assistant (apt, systemd, etc. l'exigent).
#
# La gestion de stdin est critique : avec `curl | bash`, stdin est le tube qui
# a transporté ce script, déjà en fin de fichier — tous les `read` interactifs
# de l'assistant échoueraient aussitôt (et `set -e` l'arrêterait en silence dès
# la première question). On lui donne donc le vrai terminal.
SUDO_CMD=()
[[ $EUID -ne 0 ]] && SUDO_CMD=(sudo)
if [[ -t 0 ]]; then
    exec "${SUDO_CMD[@]}" bash "$WIZARD"
elif [[ -r /dev/tty ]]; then
    exec "${SUDO_CMD[@]}" bash "$WIZARD" < /dev/tty
else
    die "Aucun terminal interactif disponible pour l'assistant.\n" \
        "  Lancez-le directement :  cd ${SURVIVE_DIR} && sudo bash install/wizard.sh"
fi
