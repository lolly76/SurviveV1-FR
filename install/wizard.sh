#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Assistant d'installation interactif
# Appelé par install/bootstrap.sh une fois le dépôt cloné.
# Peut aussi être lancé directement : sudo bash install/wizard.sh
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$REPO_DIR/config/survive.conf"

# ── Couleurs ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

banner()  { echo -e "${BOLD}${BLUE}$*${NC}"; }
header()  { echo -e "\n${BOLD}${CYAN}── $* ──────────────────────────────────────${NC}"; }
ok()      { echo -e "  ${GREEN}✓${NC}  $*"; }
info()    { echo -e "  ${BLUE}→${NC}  $*"; }
warn()    { echo -e "  ${YELLOW}!${NC}  $*"; }
ask()     { echo -en "  ${BOLD}$*${NC} "; }
die()     { echo -e "\n${RED}[ERREUR]${NC} $*" >&2; exit 1; }
error()   { echo -e "  ${RED}✗${NC}  $*" >&2; }

# Les arrêts dus à `set -e` sont silencieux : on indique toujours quoi et où.
_on_error() {
    echo -e "\n${RED}[ERREUR]${NC} L'assistant a échoué (code $1) à la ligne $2 : $3" >&2
}
trap '_on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

# ── Écran : accueil ───────────────────────────────────────────────────────────
show_welcome() {
    clear
    echo ""
    echo -e "${BOLD}${GREEN}"
    cat << 'BANNER'
  ____                  _           __     ____
 / ___| _   _ _ ____   _(_)_   _____\ \   / /_ \
 \___ \| | | | '__\ \ / / \ \ / / _ \ \ / /  / /
  ___) | |_| | |   \ V /| |\ V /  __/ \ V /  / /
 |____/ \__,_|_|    \_/ |_| \_/ \___|  \_/  /_/
BANNER
    echo -e "${NC}"
    banner "  Base de connaissances de survie hors ligne — Assistant d'installation"
    echo ""
    echo -e "  ${DIM}Installe : tableau de bord · Wikipédia · assistant IA · cartes · guides médicaux${NC}"
    echo ""

    # Afficher le matériel détecté
    local ram_mb
    ram_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    local ram_tier
    if (( ram_mb >= 14336 )); then ram_tier="16 Go — gemma4:12b (meilleure qualité)"
    elif (( ram_mb >= 6144 )); then  ram_tier="8 Go  — gemma4:e4b (bonne qualité)"
    else                             ram_tier="4 Go  — gemma4:e2b (base rapide)"
    fi

    info "RAM système :  ${ram_mb} Mo  →  palier du modèle d'IA : ${ram_tier}"
    info "Architecture :  $(uname -m)"
    info "Système :      $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || echo "inconnu")"
    echo ""
    ask "Appuyez sur ENTRÉE pour commencer, ou Ctrl+C pour annuler."
    read -r _
}

# ── Écran : choix du disque de stockage ─────────────────────────────────────────
CHOSEN_DEV=""
CHOSEN_MOUNT="/mnt/survive"

# Disques physiques qui portent le système (/) : jamais proposés au formatage.
system_disks() {
    local src
    src=$(findmnt -n -o SOURCE / 2>/dev/null) || return 0
    [[ -n "$src" ]] || return 0
    lsblk -nsl -o NAME,TYPE "$src" 2>/dev/null | awk '$2=="disk" {print $1}'
}

# Mode « dossier sur le disque du système » : aucun formatage, pour un portable
# à disque unique. Renvoie 0 si l'utilisateur a validé un dossier, 1 sinon.
SYSTEM_FOLDER=false
STORAGE_FREE_GB=0
choose_system_folder() {
    local dir free
    echo ""
    ask "Dossier de stockage [/srv/survive] : "
    read -r dir
    dir="${dir:-/srv/survive}"
    if [[ "$dir" != /* || "$dir" == "/" || "$dir" =~ [[:space:]] ]]; then
        warn "Chemin invalide : indiquez un chemin absolu sans espace (ex. /srv/survive)."
        return 1
    fi
    mkdir -p "$dir" || { warn "Impossible de créer $dir"; return 1; }
    free=$(df -BG --output=avail "$dir" 2>/dev/null | tail -1 | tr -dc '0-9')
    free="${free:-0}"
    info "Espace libre sur le disque du système : ${free} Go"
    if (( free < 80 )); then
        warn "Moins de 80 Go libres : trop juste pour une bibliothèque utile sans risquer de saturer le système."
        return 1
    fi
    echo ""
    warn "Le contenu sera stocké sur le MÊME disque que Debian."
    echo -e "  ${DIM}Un disque plein empêche le système de démarrer correctement : le profil de contenu"
    echo -e "  sera choisi pour garder une marge de sécurité (20 Go ou 15 %).${NC}"
    ask "Utiliser ${dir} ? [o/N] : "
    read -r ans
    [[ "${ans:-n}" =~ ^[YyOo]$ ]] || return 1
    CHOSEN_DEV="SKIP"
    CHOSEN_MOUNT="$dir"
    SYSTEM_FOLDER=true
    STORAGE_FREE_GB="$free"
    return 0
}

choose_storage() {
    header "Stockage"
    echo ""
    echo -e "    ${BOLD}[1]${NC}  Disque dédié ${DIM}(recommandé : SSD USB ou second disque interne)${NC}"
    echo -e "    ${BOLD}[2]${NC}  Dossier sur le disque du système ${DIM}(aucun formatage ; portable à disque unique)${NC}"
    echo ""
    ask "Votre choix [1] : "
    read -r mode
    if [[ "${mode:-1}" == "2" ]]; then
        if choose_system_folder; then
            return
        fi
        warn "Dossier non retenu — retour au choix d'un disque dédié."
    fi
    echo ""

    # Liste des périphériques bloc hors carte SD et hors loop
    local -a devs=()
    local -a sizes=()
    local -a models=()
    while IFS= read -r line; do
        local name size model
        name=$(awk '{print $1}' <<< "$line")
        size=$(awk '{print $2}' <<< "$line")
        model=$(awk '{$1=$2=""; print $0}' <<< "$line" | xargs)
        devs+=("$name")
        sizes+=("$size")
        models+=("$model")
    done < <(lsblk -d -n -o NAME,SIZE,MODEL 2>/dev/null \
             | grep -Ev '^(loop|mmcblk|zram)' || true)

    # Retire le(s) disque(s) du système : on ne propose jamais de formater Debian.
    if mapfile -t _sysdisks < <(system_disks) && [[ ${#_sysdisks[@]} -gt 0 ]]; then
        local -a keep_d=() keep_s=() keep_m=()
        local k d_idx skip
        for d_idx in "${!devs[@]}"; do
            skip=false
            for k in "${_sysdisks[@]}"; do [[ "${devs[$d_idx]}" == "$k" ]] && skip=true; done
            if [[ "$skip" == "false" ]]; then
                keep_d+=("${devs[$d_idx]}"); keep_s+=("${sizes[$d_idx]}"); keep_m+=("${models[$d_idx]}")
            fi
        done
        devs=("${keep_d[@]}"); sizes=("${keep_s[@]}"); models=("${keep_m[@]}")
    fi

    # Vérifier si /mnt/survive est déjà monté
    local already_mounted=false
    if mountpoint -q /mnt/survive 2>/dev/null; then
        already_mounted=true
        local mounted_gb
        mounted_gb=$(df -BG /mnt/survive | tail -1 | awk '{print $2}' | tr -d 'G')
        ok "/mnt/survive est déjà monté (${mounted_gb} Go)"
        echo ""
        ask "Utiliser le montage existant ? [O/n] : "
        read -r ans
        if [[ "${ans:-y}" =~ ^[YyOo]$ ]]; then
            CHOSEN_DEV="SKIP"
            CHOSEN_MOUNT="/mnt/survive"
            return
        fi
    fi

    if [[ ${#devs[@]} -eq 0 ]]; then
        if [[ "$already_mounted" == "true" ]]; then
            CHOSEN_DEV="SKIP"
            CHOSEN_MOUNT="/mnt/survive"
            return
        fi
        warn "Aucun disque dédié détecté (le disque du système n'est jamais proposé)."
        warn "Branchez un SSD et appuyez sur ENTRÉE pour réanalyser, ou Ctrl+C pour quitter"
        warn "(ou relancez l'assistant et choisissez le mode « dossier sur le disque du système »)."
        read -r _
        choose_storage   # un seul appel récursif
        return
    fi

    echo "  Disques détectés :"
    echo ""
    local i=1
    for idx in "${!devs[@]}"; do
        local in_use=""
        if mountpoint -q "/dev/${devs[$idx]}" 2>/dev/null; then
            in_use="${DIM} (monté)${NC}"
        fi
        printf "    ${BOLD}[%d]${NC}  /dev/%-8s  %6s  %s%b\n" \
               "$i" "${devs[$idx]}" "${sizes[$idx]}" "${models[$idx]}" "$in_use"
        i=$(( i + 1 ))
    done
    if [[ "$already_mounted" == "true" ]]; then
        echo ""
        printf "    ${BOLD}[%d]${NC}  Conserver /mnt/survive (déjà monté)\n" "$i"
    fi
    echo ""
    ask "Choisissez le disque [1] : "
    read -r choice
    choice="${choice:-1}"

    if [[ "$already_mounted" == "true" ]] && [[ "$choice" == "$i" ]]; then
        CHOSEN_DEV="SKIP"
        CHOSEN_MOUNT="/mnt/survive"
        return
    fi

    local sel=$(( choice - 1 ))
    if [[ "$sel" -lt 0 ]] || [[ "$sel" -ge "${#devs[@]}" ]]; then
        warn "Choix invalide — ${devs[0]} utilisé par défaut"
        sel=0
    fi

    CHOSEN_DEV="${devs[$sel]}"

    # Point de montage : /mnt/survive par défaut, modifiable
    echo ""
    ask "Point de montage [/mnt/survive] : "
    read -r mp
    CHOSEN_MOUNT="${mp:-/mnt/survive}"
}

# ── Écran : confirmation du formatage ───────────────────────────────────────────────
FORMAT_DRIVE=false

confirm_format() {
    [[ "$CHOSEN_DEV" == "SKIP" ]] && return

    header "Formater le disque"
    echo ""
    local size
    size=$(lsblk -d -n -o SIZE "/dev/$CHOSEN_DEV" 2>/dev/null || echo "?")
    warn "/dev/${CHOSEN_DEV}  (${size})"
    echo ""
    echo -e "  ${DIM}Si ce disque est neuf ou ne contient rien à conserver, le formater"
    echo -e "  en ext4 donne les meilleures performances sous Linux.${NC}"
    echo ""
    ask "Formater /dev/${CHOSEN_DEV} en ext4 ? Cela EFFACE TOUTES LES DONNÉES. [o/N] : "
    read -r ans
    if [[ "${ans:-n}" =~ ^[YyOo]$ ]]; then
        echo ""
        warn "Dernière chance : tapez  formater  pour confirmer, ou appuyez sur ENTRÉE pour ignorer."
        ask "> "
        read -r confirm
        if [[ "$confirm" == "formater" ]]; then
            FORMAT_DRIVE=true
            ok "Le disque sera formaté pendant l'installation."
        else
            info "Formatage ignoré — les données existantes sont conservées."
        fi
    else
        info "Formatage ignoré — les données existantes sont conservées."
    fi
}

# ── Écran : profil de contenu ────────────────────────────────────────────────────
CHOSEN_PROFILE="complet"

choose_profile() {
    header "Profil de contenu"
    echo ""
    local free="$STORAGE_FREE_GB" flag="" rec
    if (( free == 0 )); then
        # Dossier non encore calculé (disque dédié) : mesure après montage impossible
        # ici ; on estime avec la taille du disque choisi, sinon on conseille « complet ».
        if [[ "$CHOSEN_DEV" != "SKIP" ]]; then
            free=$(lsblk -b -d -n -o SIZE "/dev/$CHOSEN_DEV" 2>/dev/null | awk '{printf "%d", $1/1000000000*0.93}')
        elif mountpoint -q "$CHOSEN_MOUNT" 2>/dev/null; then
            free=$(df -BG --output=avail "$CHOSEN_MOUNT" | tail -1 | tr -dc '0-9')
        fi
    fi
    free="${free:-0}"
    [[ "$SYSTEM_FOLDER" == "true" ]] && flag="--systeme"
    rec=$(bash "${REPO_DIR}/scripts/recommend_profile.sh" "$free" $flag 2>/dev/null || echo complet)
    [[ "$rec" == "insuffisant" ]] && rec="leger"
    info "Espace disponible estimé : ${free} Go  →  profil conseillé : ${rec}"
    echo ""
    echo -e "    ${BOLD}[1]${NC}  léger    ${DIM}~60 Go   Wikipédia sans images, cartes, PDF de survie, médicaments${NC}"
    echo -e "    ${BOLD}[2]${NC}  moyen    ${DIM}~250 Go  + Wikipédia complète, livres, Khan Academy (sans vidéos)${NC}"
    echo -e "    ${BOLD}[3]${NC}  complet  ${DIM}~800 Go  + vidéos de survie et Kolibri${NC}"
    echo -e "    ${BOLD}[4]${NC}  test     ${DIM}~6 Go    pour valider l'installation sur une VM (presque rien à télécharger)${NC}"
    echo ""
    local def=3
    [[ "$rec" == "leger" ]] && def=1
    [[ "$rec" == "moyen" ]] && def=2
    ask "Votre choix [${def}] : "
    read -r pc
    case "${pc:-$def}" in
        1) CHOSEN_PROFILE="leger" ;;
        2) CHOSEN_PROFILE="moyen" ;;
        3) CHOSEN_PROFILE="complet" ;;
        4) CHOSEN_PROFILE="test" ;;
        *) warn "Choix invalide — profil conseillé utilisé"; CHOSEN_PROFILE="$rec" ;;
    esac
    ok "Profil retenu : ${CHOSEN_PROFILE}"
}

# ── Écran : nom d'hôte ──────────────────────────────────────────────────────────
CHOSEN_HOSTNAME=""

choose_hostname() {
    header "Nom d'hôte"
    echo ""
    local current
    current=$(hostname 2>/dev/null || echo "raspberrypi")
    info "Nom d'hôte actuel : ${current}"
    info "Votre Pi sera accessible à l'adresse  http://\${hostname}.local:8080"
    echo ""
    ask "Nom d'hôte [survive] : "
    read -r hn
    CHOSEN_HOSTNAME="${hn:-survive}"
    ok "Nom d'hôte défini : ${CHOSEN_HOSTNAME}"
}

# ── Écran : région des cartes ────────────────────────────────────────────────────────
CHOSEN_MAP_REGION="france"

choose_map_region() {
    header "Région des cartes hors ligne"
    echo ""
    echo "  Régions disponibles :"
    echo "    [1] France métropolitaine  (recommandé, ~5 Go)"
    echo "    [2] Europe"
    echo "    [3] Amérique du Nord"
    echo "    [4] Amérique du Sud"
    echo "    [5] Afrique"
    echo "    [6] Asie"
    echo "    [7] Monde entier (toutes les régions, plus de 50 Go)"
    echo "    [8] Ne pas installer les cartes"
    echo ""
    ask "Choisissez la région [1] : "
    read -r r
    case "${r:-1}" in
        1) CHOSEN_MAP_REGION="france" ;;
        2) CHOSEN_MAP_REGION="europe" ;;
        3) CHOSEN_MAP_REGION="north-america" ;;
        4) CHOSEN_MAP_REGION="south-america" ;;
        5) CHOSEN_MAP_REGION="africa" ;;
        6) CHOSEN_MAP_REGION="asia" ;;
        7) CHOSEN_MAP_REGION="world" ;;
        8) CHOSEN_MAP_REGION="none" ;;
        *) CHOSEN_MAP_REGION="france" ;;
    esac
    ok "Région des cartes : ${CHOSEN_MAP_REGION}"
}

# ── Écran : point d'accès Wi-Fi hors réseau (facultatif) ──────────────────────────────────────
CHOSEN_HOTSPOT="n"
CHOSEN_HOTSPOT_SSID="SurviveV1"
CHOSEN_HOTSPOT_PASS="survive2026"

choose_hotspot() {
    header "Point d'accès Wi-Fi hors réseau (facultatif)"
    echo ""
    echo "  En cas de coupure générale, il n'y a plus de box : le Pi peut diffuser son"
    echo "  propre réseau Wi-Fi pour que téléphones et ordinateurs s'y connectent."
    echo ""
    echo "  ATTENTION : activer le point d'accès PLUS TARD déconnecte le Pi du Wi-Fi de"
    echo "  la maison (les deux ne coexistent qu'avec Ethernet). Il n'est PAS activé"
    echo "  pendant l'installation, car les téléchargements ont besoin d'Internet."
    echo "  Cette étape enregistre seulement vos réglages."
    echo ""
    ask "Configurer le point d'accès maintenant ? [o/N] : "
    read -r ans
    if [[ "${ans:-n}" =~ ^[YyOo]$ ]]; then
        CHOSEN_HOTSPOT="y"
        ask "Nom du réseau du point d'accès (SSID) [SurviveV1] : "
        read -r ssid
        CHOSEN_HOTSPOT_SSID="${ssid:-SurviveV1}"
        while true; do
            ask "Mot de passe du point d'accès (8 à 63 caractères) [survive2026] : "
            read -r pass
            pass="${pass:-survive2026}"
            if (( ${#pass} >= 8 && ${#pass} <= 63 )); then
                CHOSEN_HOTSPOT_PASS="$pass"
                break
            fi
            warn "Le mot de passe doit comporter de 8 à 63 caractères."
        done
        ok "Point d'accès : ${CHOSEN_HOTSPOT_SSID} (à activer plus tard avec : sudo bash scripts/hotspot.sh enable)"
    else
        info "Ignoré — les valeurs par défaut sont enregistrées dans survive.conf ; activable à tout moment."
    fi
}

# ── Écran : récapitulatif et confirmation ─────────────────────────────────────────────────
confirm_install() {
    header "Récapitulatif de l'installation"
    echo ""

    local ram_mb
    ram_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    local ai_model
    if (( ram_mb >= 14336 )); then ai_model="gemma4:12b  (1-3 tok/s, meilleure qualité)"
    elif (( ram_mb >= 6144 )); then ai_model="gemma4:e4b  (3-5 tok/s)"
    else                            ai_model="gemma4:e2b  (8-12 tok/s)"
    fi

    if [[ "$SYSTEM_FOLDER" == "true" ]]; then
        info "Stockage :    dossier ${CHOSEN_MOUNT} sur le disque du système (${STORAGE_FREE_GB} Go libres)"
    elif [[ "$CHOSEN_DEV" == "SKIP" ]]; then
        info "Stockage :    ${CHOSEN_MOUNT}  (déjà monté)"
    elif [[ "$FORMAT_DRIVE" == "true" ]]; then
        info "Stockage :    /dev/${CHOSEN_DEV} → ${CHOSEN_MOUNT}  (sera formaté en ext4)"
    else
        info "Stockage :    /dev/${CHOSEN_DEV} → ${CHOSEN_MOUNT}  (données existantes conservées)"
    fi
    info "Contenu :     profil « ${CHOSEN_PROFILE} »"
    info "Nom d'hôte :  ${CHOSEN_HOSTNAME}  (http://${CHOSEN_HOSTNAME}.local:8080)"
    info "Modèle d'IA : ${ai_model}"
    info "Cartes :      ${CHOSEN_MAP_REGION}"
    if [[ "$CHOSEN_HOTSPOT" == "y" ]]; then
        info "Point d'accès : ${CHOSEN_HOTSPOT_SSID}  (à activer après l'installation)"
    fi
    info "Dépôt :       ${REPO_DIR}"
    echo ""
    info "Le téléchargement des contenus (Wikipédia, vidéos, livres) se fait séparément, après l'installation."
    info "Durée d'installation estimée : 15 à 30 minutes."
    echo ""
    ask "Lancer l'installation ? [o/N] : "
    read -r ans
    [[ "${ans:-n}" =~ ^[YyOo]$ ]] || { echo ""; info "Annulé."; exit 0; }
}

# Renvoie le nom de la dernière partition (ex. « sda1 ») d'un disque, ou « »
# s'il n'en a pas. NB : `lsblk -n -o NAME` seul dessine des caractères d'arbre
# (└─sda1) qui donnent un faux chemin /dev/└─sda1 ; le mode brut -r est requis.
_first_partition() {
    lsblk -rno NAME,TYPE "/dev/$1" 2>/dev/null | awk '$2 == "part" { print $1 }' | tail -1
}

# ── Préparation du stockage : formatage et montage ─────────────────────────────────────────────
setup_drive() {
    [[ "$CHOSEN_DEV" == "SKIP" ]] && return

    info "Préparation de /dev/${CHOSEN_DEV} → ${CHOSEN_MOUNT}..."

    if [[ "$FORMAT_DRIVE" == "true" ]]; then
        info "Formatage de /dev/${CHOSEN_DEV} en ext4..."
        # Effacer la table de partitions, créer une GPT et une seule partition ext4
        sgdisk --zap-all "/dev/${CHOSEN_DEV}" 2>/dev/null \
            || wipefs -a "/dev/${CHOSEN_DEV}"
        parted -s "/dev/${CHOSEN_DEV}" mklabel gpt
        parted -s "/dev/${CHOSEN_DEV}" mkpart primary ext4 0% 100%
        partprobe "/dev/${CHOSEN_DEV}" 2>/dev/null || true
        udevadm settle 2>/dev/null || sleep 2
        local part
        part=$(_first_partition "${CHOSEN_DEV}")
        [[ -n "$part" ]] || die "La partition n'est pas apparue sur /dev/${CHOSEN_DEV} après le formatage."
        mkfs.ext4 -F -L survive "/dev/${part}"
        CHOSEN_PART="/dev/${part}"
    else
        # Partition existante si le disque en a une, sinon le périphérique brut.
        local part
        part=$(_first_partition "${CHOSEN_DEV}")
        if [[ -n "$part" ]]; then
            CHOSEN_PART="/dev/${part}"
        else
            CHOSEN_PART="/dev/${CHOSEN_DEV}"
        fi
    fi
    info "Partition utilisée : ${CHOSEN_PART}"

    mkdir -p "${CHOSEN_MOUNT}"

    # Already mounted at the target (e.g. a manual mount from an earlier
    # attempt)? Skip the mount, but still fall through to the /etc/fstab block
    # below — returning here left systems with a working mount that silently
    # did NOT come back after a reboot.
    local already_mounted=false
    if mountpoint -q "${CHOSEN_MOUNT}"; then
        ok "Déjà monté sur ${CHOSEN_MOUNT}"
        already_mounted=true
    fi

    # The drive may already be mounted somewhere else — a manual mount or a
    # desktop automount (commonly /mnt/ssd or /media/<user>/…). Mounting the
    # same device a second time would leave two live paths and a stale fstab
    # line, so relocate it to the SurviveV1 mount point instead.
    local existing
    existing=$(findmnt -nro TARGET --source "${CHOSEN_PART}" 2>/dev/null | head -1 || true)
    if [[ -n "$existing" ]] && [[ "$existing" != "${CHOSEN_MOUNT}" ]]; then
        info "${CHOSEN_PART} est actuellement monté sur ${existing} — déplacement vers ${CHOSEN_MOUNT}"
        if ! umount "$existing" 2>/dev/null; then
            error "Impossible de démonter ${existing} — il est utilisé."
            error "Fermez les programmes et terminaux dans ce dossier (ou redémarrez), puis relancez."
            error "Processus concernés :"; lsof "$existing" 2>/dev/null | head -5 || fuser -vm "$existing" 2>&1 | head -5 || true
            exit 1
        fi
        # A leftover fstab line would send the drive back to the old path on
        # the next boot, silently breaking every service after a reboot.
        if grep -qsE "^[^#].*[[:space:]]${existing}[[:space:]]" /etc/fstab; then
            sed -i -E "s|^([^#].*[[:space:]]${existing}[[:space:]].*)$|# désactivé par l'assistant SurviveV1 : \1|" /etc/fstab
            warn "Ancienne entrée ${existing} commentée dans /etc/fstab"
        fi
    fi

    # Add to /etc/fstab if not already there. The filesystem type is detected
    # rather than assumed — a kept (non-formatted) drive may be ext4, exfat…
    local uuid fstype
    uuid=$(blkid -s UUID -o value "${CHOSEN_PART}" 2>/dev/null || echo "")
    fstype=$(blkid -s TYPE -o value "${CHOSEN_PART}" 2>/dev/null || echo "auto")
    if [[ -n "$uuid" ]]; then
        if ! grep -q "$uuid" /etc/fstab 2>/dev/null; then
            echo "UUID=${uuid}  ${CHOSEN_MOUNT}  ${fstype}  defaults,nofail,noatime  0  2" >> /etc/fstab
            ok "Ajouté à /etc/fstab (montage automatique au démarrage)"
        else
            ok "/etc/fstab monte déjà ce disque automatiquement"
        fi
    else
        warn "${CHOSEN_PART} n'a pas d'UUID — impossible d'ajouter une entrée fiable dans /etc/fstab."
        warn "Le disque ne sera PAS monté automatiquement après un redémarrage."
    fi

    if [[ "$already_mounted" == "true" ]]; then
        return   # nothing to mount; fstab is now in place for the next boot
    fi

    if [[ -n "$uuid" ]]; then
        mount "${CHOSEN_MOUNT}" 2>/dev/null || mount "${CHOSEN_PART}" "${CHOSEN_MOUNT}" || true
    else
        mount "${CHOSEN_PART}" "${CHOSEN_MOUNT}" || true
    fi

    # Verify — never report success on an unmounted drive; every later step
    # (and the whole content download) depends on this actually working.
    if ! mountpoint -q "${CHOSEN_MOUNT}"; then
        error "Échec du montage de ${CHOSEN_PART} sur ${CHOSEN_MOUNT}"
        echo ""
        lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT "/dev/${CHOSEN_DEV}" 2>/dev/null || true
        echo ""
        error "Si le disque n'a pas encore de système de fichiers, relancez l'assistant et choisissez de le formater."
        exit 1
    fi
    ok "Disque monté sur ${CHOSEN_MOUNT} ($(df -h --output=size "${CHOSEN_MOUNT}" | tail -1 | xargs) disponibles)"
}

# ── Mise à jour du nom d'hôte ────────────────────────────────────────────────────────────
setup_hostname() {
    local current
    current=$(hostname 2>/dev/null || echo "")
    [[ "$current" == "$CHOSEN_HOSTNAME" ]] && return

    info "Définition du nom d'hôte : ${CHOSEN_HOSTNAME}..."
    echo "${CHOSEN_HOSTNAME}" > /etc/hostname
    # Update /etc/hosts
    sed -i "s/127\.0\.1\.1.*/127.0.1.1\t${CHOSEN_HOSTNAME}/" /etc/hosts
    hostname "${CHOSEN_HOSTNAME}"
    ok "Nom d'hôte défini (effectif après redémarrage)"
}

# ── Écriture de config/survive.conf ─────────────────────────────────────────────────
write_config() {
    info "Écriture de ${CONF}..."
    local ram_mb
    ram_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    local ai_model="survive"   # always the custom survive model

    # Keep existing config values if file exists; only overwrite what we set
    # Here we regenerate from scratch with wizard values + preserved extras.
    cat > "$CONF" << CONF
# SurviveV1 Configuration
# Généré par : bash install/wizard.sh

# ── Storage ────────────────────────────────────────────────────────────────────
SURVIVE_STORAGE_PATH="${CHOSEN_MOUNT}"
SURVIVE_STORAGE_DEV="${CHOSEN_DEV:-SKIP}"
SURVIVE_STORAGE_MODE="$([[ "$SYSTEM_FOLDER" == "true" ]] && echo dossier || echo dedie)"
SURVIVE_BUDGET_GB="800"
SURVIVE_HOSTNAME="${CHOSEN_HOSTNAME}"

# ── Contenus (Y = télécharger, N = ignorer) ────────────────────────────────────────
CONTENT_WIKIPEDIA="Y"
CONTENT_WIKIPEDIA_NOPIC="N"
CONTENT_WIKIBOOKS="Y"
CONTENT_STACKEXCHANGE="Y"
CONTENT_STACKEXCHANGE_EN="N"
CONTENT_GUTENBERG="Y"
CONTENT_KOLIBRI="Y"
CONTENT_VIDEOS="Y"
CONTENT_MAPS="${CHOSEN_MAP_REGION_FLAG:-Y}"
CONTENT_PDFS="Y"
CONTENT_AI_MODELS="Y"
CONTENT_IFIX="Y"
CONTENT_EXPANSION="Y"
CONTENT_EXPANSION_EN="N"
CONTENT_GAPS_EN="Y"
CONTENT_MESHTASTIC="Y"
CONTENT_MESHCORE="Y"
CONTENT_NPS_MAPS="N"
CONTENT_SATELLITE="Y"

# ── Mise à jour automatique nocturne (voir config/survive.conf.example) ────────
SURVIVE_AUTO_UPDATE="false"
SURVIVE_AUTO_UPDATE_TIME="02:30"
SURVIVE_AUTO_UPDATE_RATE_LIMIT="2097152"

# ── Qualité vidéo (480, 720, 1080) ─────────────────────────────────────────────
VIDEO_QUALITY="720"

# ── AI ─────────────────────────────────────────────────────────────────────────
SURVIVE_AI_MODEL="${ai_model}"

# ── Région des cartes ─────────────────────────────────────────────────────────────────
MAP_REGION="${CHOSEN_MAP_REGION}"

# ── Point d'accès Wi-Fi hors réseau (scripts/hotspot.sh) ───────────────────────────────
SURVIVE_HOTSPOT_SSID="${CHOSEN_HOTSPOT_SSID}"
SURVIVE_HOTSPOT_PASS="${CHOSEN_HOTSPOT_PASS}"

# ── Synchronisation cloud ─────────────────────────────────────────────────────────────────
SURVIVE_CLOUD_REMOTE="gdrive"
SURVIVE_CLOUD_PATH="SurviveV1"

# ── Hailo AI Hat ───────────────────────────────────────────────────────────────
# Le Hailo-8L ne fait que de la vision : il n'accélère pas les LLM d'Ollama.
SKIP_AI_HAT="true"

# ── Limitation de débit (octets/s ; 0 = illimité) ────────────────────────────────
SURVIVE_BANDWIDTH_LIMIT="0"

# ── Délais d'attente du serveur web (secondes) ──────────────────────────────────────────────
SURVIVE_SERVICE_CHECK_TIMEOUT="1"
SURVIVE_OLLAMA_LIST_TIMEOUT="2"
SURVIVE_AI_CHAT_TIMEOUT="60"
CONF

    # Désactiver le téléchargement des cartes si l'utilisateur les a ignorées
    if [[ "${CHOSEN_MAP_REGION}" == "none" ]]; then
        sed -i 's/^CONTENT_MAPS="Y"/CONTENT_MAPS="N"/' "$CONF"
    fi

    # Profil de contenu choisi (écrase les CONTENT_* et le budget ci-dessus)
    bash "${REPO_DIR}/scripts/apply_profile.sh" "${CHOSEN_PROFILE}" "$CONF" >/dev/null
    # La carte « aucune région » reste prioritaire sur le profil
    if [[ "${CHOSEN_MAP_REGION}" == "none" ]]; then
        sed -i 's/^CONTENT_MAPS="Y"/CONTENT_MAPS="N"/' "$CONF"
    fi

    ok "Configuration écrite dans ${CONF}"
}

# ── Vérifications préalables ──────────────────────────────────────────────────────
run_preflight() {
    header "Vérifications préalables"
    echo ""
    SURVIVE_STORAGE_PATH="${CHOSEN_MOUNT}" \
    SURVIVE_STORAGE_MODE="$([[ "$SYSTEM_FOLDER" == "true" ]] && echo dossier || echo dedie)" \
    bash "${REPO_DIR}/setup/pre_flight_check.sh" || {
        echo ""
        warn "Certaines vérifications ont échoué (voir ci-dessus)."
        ask "Continuer malgré tout ? [o/N] : "
        read -r ans
        [[ "${ans:-n}" =~ ^[YyOo]$ ]] || { info "Annulé."; exit 1; }
    }
}

# ── Lancement de l'installateur ─────────────────────────────────────────────────────────
run_installer() {
    header "Installation"
    echo ""
    info "Exécution de setup/install.sh — cela prend 15 à 30 minutes..."
    info "Journal complet : /var/log/survive_install.log"
    echo ""
    SURVIVE_STORAGE_PATH="${CHOSEN_MOUNT}" \
        bash "${REPO_DIR}/setup/install.sh"
}

# ── Mot de passe administrateur ─────────────────────────────────────────────────────────────
setup_admin_password() {
    header "Mot de passe administrateur"
    echo ""
    info "Les invités de votre Wi-Fi consultent tout SANS se connecter."
    info "Un mot de passe administrateur ne sert qu'à mettre à jour les contenus"
    info "et gérer les services depuis le tableau de bord. Vous pouvez le définir"
    info "maintenant ou plus tard avec :"
    info "  python3 ${REPO_DIR}/scripts/set_admin_password.py"
    echo ""
    ask "Définir un mot de passe administrateur maintenant ? [O/n] : "
    read -r ans
    if [[ "${ans:-y}" =~ ^[YyOo]$ ]]; then
        local py="/opt/survive/venv/bin/python3"
        [[ -x "$py" ]] || py="python3"
        "$py" "${REPO_DIR}/scripts/set_admin_password.py" \
            || warn "Mot de passe non défini — lancez set_admin_password.py plus tard"
    else
        info "Ignoré. Le bouton de mise à jour reste verrouillé tant qu'aucun mot de passe n'est défini."
    fi
}

# ── Installation du modèle d'IA ─────────────────────────────────────────────────────────────
run_ai_setup() {
    header "Installation du modèle d'IA"
    echo ""
    info "Téléchargement des modèles d'IA pour votre Pi de ${ram_mb:-0} Mo..."
    info "Cela télécharge de 1,5 à 8 Go selon votre quantité de RAM."
    info "(Vous pouvez l'ignorer et le faire plus tard avec : bash ai/setup_ollama.sh)"
    echo ""
    ask "Installer les modèles d'IA maintenant ? [O/n] : "
    read -r ans
    if [[ "${ans:-y}" =~ ^[YyOo]$ ]]; then
        bash "${REPO_DIR}/ai/setup_ollama.sh" setup || warn "L'installation de l'IA a échoué — relancez-la manuellement plus tard"
    else
        info "Ignoré. À lancer plus tard avec : bash ${REPO_DIR}/ai/setup_ollama.sh setup"
    fi
}

# ── Écran de réussite ────────────────────────────────────────────────────────────
show_success() {
    echo ""
    echo -e "${BOLD}${GREEN}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║   Installation de SurviveV1 terminée !  ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    local ip
    ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "<ip-de-votre-pi>")
    ok "Tableau de bord : http://${CHOSEN_HOSTNAME}.local:8080"
    ok "Par adresse IP :  http://${ip}:8080"
    ok "Assistant IA :     http://${CHOSEN_HOSTNAME}.local:8080/ai"
    echo ""
    info "Prochaines étapes :"
    echo ""
    echo "    1. Télécharger les contenus (Wikipédia, livres, vidéos) :"
    echo "       bash ${REPO_DIR}/download/download_all.sh"
    echo ""
    echo "    2. Démarrer/arrêter les services :"
    echo "       bash ${REPO_DIR}/scripts/start_services.sh"
    echo "       bash ${REPO_DIR}/scripts/stop_services.sh"
    echo ""
    echo "    3. Vérifier l'état des services :"
    echo "       bash ${REPO_DIR}/scripts/status.sh"
    echo ""
    echo "    4. Mode hors réseau (le Pi diffuse son propre Wi-Fi, sans box) :"
    echo "       sudo bash ${REPO_DIR}/scripts/hotspot.sh enable"
    echo ""
    echo -e "  ${DIM}Si survive.local ne fonctionne pas sous Windows, utilisez l'adresse IP ci-dessus.${NC}"
    echo ""
}

# ── Droits root requis ──────────────────────────────────────────────────────────────
require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "Cet assistant doit être lancé en root.\n\n  Relancez avec : sudo bash $0"
    fi
}

# ── Programme principal ──────────────────────────────────────────────────────────────────────
main() {
    require_root

    show_welcome
    choose_storage
    confirm_format
    choose_profile
    choose_hostname
    choose_map_region
    choose_hotspot
    confirm_install

    header "Préparation"
    setup_drive
    setup_hostname
    write_config

    run_preflight
    run_installer
    setup_admin_password

    local ram_mb
    ram_mb=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
    run_ai_setup

    show_success
}

main "$@"
