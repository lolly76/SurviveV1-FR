#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Main Installer
# Raspberry Pi 5 (64-bit Bookworm) + AI Hat (Hailo-8L)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
SURVIVE_CONFIG="$REPO_DIR/config/survive.conf"

# Load or create config. survive.conf is machine-specific and untracked; the
# wizard writes it, and a bare clone starts from the shipped example.
if [[ ! -f "$SURVIVE_CONFIG" ]] && [[ -f "${SURVIVE_CONFIG}.example" ]]; then
    cp "${SURVIVE_CONFIG}.example" "$SURVIVE_CONFIG"
fi
if [[ -f "$SURVIVE_CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$SURVIVE_CONFIG"
else
    bash "$SCRIPT_DIR/first_run.sh"
    # shellcheck source=/dev/null
    source "$SURVIVE_CONFIG"
fi

LOG_FILE="/var/log/survive_install.log"
exec > >(tee -a "$LOG_FILE") 2>&1

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# With `set -e`, any unchecked failure aborts the script. Without this trap that
# abort is SILENT — the installer just returns to the prompt mid-step, which is
# impossible to diagnose. Always say what died and where.
_on_error() {
    local rc=$1 line=$2 cmd=$3
    error "Échec de l'installation (code ${rc}) à la ligne ${line} : ${cmd}"
    error "Journal complet : $LOG_FILE"
    error "Corrigez le problème ci-dessus, puis relancez : sudo bash setup/install.sh"
}
trap '_on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

require_root() {
    [[ $EUID -eq 0 ]] || { error "Lancez avec sudo : sudo bash $0"; exit 1; }
}

# ── Enable and start everything ───────────────────────────────────────────────
enable_core_services() {
    info "Activation des services au démarrage (et démarrage immédiat)..."
    systemctl daemon-reload
    local units=(survive-dashboard kiwix ollama martin-tiles calibre-web)
    if command -v kolibri &>/dev/null || [[ -x /opt/survive/venv/bin/kolibri ]]; then
        units+=(kolibri)
    fi
    local u
    for u in "${units[@]}"; do
        systemctl reset-failed "$u" 2>/dev/null || true
        systemctl enable "$u" 2>/dev/null || true
        if systemctl restart "$u" 2>/dev/null; then
            success "$u démarré"
        else
            warn "$u n'a pas démarré — vérifiez : journalctl -u $u -n 20"
        fi
    done
}

# ── Banner ────────────────────────────────────────────────────────────────────
banner() {
cat << 'EOF'
  ____                  _           __     ____
 / ___| _   _ _ ____   _(_)_   _____\ \   / /_ \
 \___ \| | | | '__\ \ / / \ \ / / _ \ \ / /  / /
  ___) | |_| | |   \ V /| |\ V /  __/ \ V /  / /
 |____/ \__,_|_|    \_/ |_| \_/ \___|  \_/  /_/

   Base de connaissances de survie hors ligne — Édition française, Raspberry Pi 5
EOF
}

# ── System update ─────────────────────────────────────────────────────────────
update_system() {
    # Guard: apt needs several GB of headroom on the root filesystem. The
    # classic way this fills up is content/models downloaded while the storage
    # drive was NOT mounted — those files land on the SD card under the
    # /mnt/survive directory and are then HIDDEN by the real mount.
    local free_mb
    free_mb=$(df -Pm / | awk 'NR==2 {print $4}')
    if (( free_mb < 2048 )); then
        error "Seulement ${free_mb} Mo libres sur le système de fichiers racine — apt a besoin d'environ 2 Go."
        error "Causes fréquentes et solutions :"
        error "  sudo apt-get clean                        # vider le cache des paquets .deb"
        error "  # Fichiers cachés SOUS le point de montage du stockage (téléchargement précoce) :"
        error "  sudo mount --bind / /tmp/rootview && sudo du -sh /tmp/rootview/mnt/survive"
        error "  sudo rm -rf /tmp/rootview/mnt/survive/* && sudo umount /tmp/rootview"
        error "  du -sh ~/.ollama /usr/share/ollama        # modèles d'IA égarés sur la carte SD"
        exit 1
    fi

    info "Mise à jour des paquets système..."
    apt-get update -qq
    apt-get upgrade -y -qq
    success "Système à jour"
}

# ── Core dependencies ─────────────────────────────────────────────────────────
install_core_deps() {
    info "Installation des dépendances de base..."
    apt-get install -y -qq \
        git curl wget aria2 rsync \
        python3 python3-pip python3-venv python3-dev \
        ffmpeg vlc \
        nginx \
        sqlite3 \
        zstd xz-utils p7zip-full \
        poppler-utils \
        ufw \
        jq \
        htop iotop \
        tmux \
        avahi-daemon \
        samba samba-common-bin \
        ntfs-3g exfatprogs \
        rclone \
        chrony \
        fuse3
    success "Dépendances de base installées"
}

# ── NTP time server for hotspot clients ───────────────────────────────────────
configure_chrony() {
    info "Configuration de chrony pour fournir l'heure aux appareils du point d'accès Wi-Fi..."
    if [[ -d /etc/chrony/conf.d ]] && [[ -f "$REPO_DIR/config/chrony-survive.conf" ]]; then
        install -m 644 "$REPO_DIR/config/chrony-survive.conf" \
            /etc/chrony/conf.d/survive.conf
        systemctl restart chrony 2>/dev/null || systemctl restart chronyd 2>/dev/null || true
        success "chrony fournit l'heure à 10.42.0.0/24 (fonctionne sans réseau)"
    else
        info "chrony conf.d absent -- configuration du serveur NTP ignorée"
    fi
}

# ── Python virtual environment ────────────────────────────────────────────────
setup_python_env() {
    info "Création de l'environnement virtuel Python..."
    VENV_DIR="/opt/survive/venv"
    python3 -m venv "$VENV_DIR"
    source "$VENV_DIR/bin/activate"
    pip install -q --upgrade pip
    pip install -q -r "$REPO_DIR/requirements.txt"
    success "Environnement Python prêt dans $VENV_DIR"
}

# ── yt-dlp ────────────────────────────────────────────────────────────────────
# Minimum version covers:
#   CVE-2024-38519  — output-template extension bypass (fixed 2024.07.01)
#   CVE-2025-54072  — --exec injection
#   CVE-2026-26331  — --netrc-cmd command injection (fixed 2026.02.21)
MIN_YTDLP_VERSION="2026.02.21"

install_ytdlp() {
    info "Installation de yt-dlp..."
    curl -sL -o /usr/local/bin/yt-dlp \
        "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp"
    chmod 0755 /usr/local/bin/yt-dlp
    command -v yt-dlp &>/dev/null || { error "Échec de l'installation de yt-dlp"; exit 1; }
    local ver
    ver="$(yt-dlp --version 2>/dev/null)"
    if [[ "$(printf '%s\n%s\n' "$MIN_YTDLP_VERSION" "$ver" | sort -V | head -1)" \
          != "$MIN_YTDLP_VERSION" ]]; then
        warn "yt-dlp $ver < $MIN_YTDLP_VERSION requis (correctifs de sécurité)"
    fi
    success "yt-dlp installé ($ver)"
}

# ── Kiwix tools ───────────────────────────────────────────────────────────────
install_kiwix() {
    info "Installation des outils Kiwix..."
    if command -v kiwix-serve &>/dev/null && command -v kiwix-manage &>/dev/null; then
        success "Outils Kiwix déjà présents"
        return
    fi

    # Preferred: the distro package — signed, maintained, and matched to the OS.
    if apt-get install -y -qq kiwix-tools && command -v kiwix-serve &>/dev/null; then
        success "Outils Kiwix installés depuis apt"
        return
    fi

    warn "kiwix-tools indisponible via apt — repli sur la version du projet Kiwix"
    # kiwix-tools is NOT on download.openzim.org any more (that host now carries
    # only libzim/zim-tools). The unversioned filename below always resolves to
    # the current release, so this cannot rot the way a pinned version does.
    local url="https://download.kiwix.org/release/kiwix-tools/kiwix-tools_linux-aarch64.tar.gz"
    local tmp
    tmp=$(mktemp -d)
    # No -q: a download failure must be visible, not silent.
    if ! wget -O "$tmp/kiwix-tools.tar.gz" "$url"; then
        rm -rf "$tmp"
        error "Impossible de télécharger les outils Kiwix depuis :"
        error "  $url"
        error "Vérifiez l'accès à Internet, puis relancez : sudo bash setup/install.sh"
        exit 1
    fi
    tar -xzf "$tmp/kiwix-tools.tar.gz" -C "$tmp"
    cp "$tmp"/kiwix-tools_*/kiwix-serve /usr/local/bin/
    cp "$tmp"/kiwix-tools_*/kiwix-manage /usr/local/bin/
    cp "$tmp"/kiwix-tools_*/kiwix-search /usr/local/bin/ 2>/dev/null || true
    chmod +x /usr/local/bin/kiwix-*
    rm -rf "$tmp"
    command -v kiwix-serve &>/dev/null || { error "Échec de l'installation de kiwix-serve"; exit 1; }
    command -v kiwix-manage &>/dev/null || { error "Échec de l'installation de kiwix-manage"; exit 1; }
    success "Outils Kiwix installés"
}

# ── Kolibri (Khan Academy offline) ───────────────────────────────────────────
install_kolibri() {
    info "Installation de Kolibri..."
    if command -v kolibri &>/dev/null || [[ -x /opt/survive/venv/bin/kolibri ]]; then
        success "Kolibri déjà installé"
        return 0
    fi

    # Try the vendor installer, then pip. Neither is guaranteed: Kolibri
    # historically lags new Python releases, and this OS ships Python 3.13.
    if wget -q "https://learningequality.org/r/kolibri-install-pi" -O /tmp/kolibri_install.sh \
       && [[ -s /tmp/kolibri_install.sh ]]; then
        bash /tmp/kolibri_install.sh || true
    else
        warn "Impossible de récupérer le script d'installation de Kolibri"
    fi
    if ! command -v kolibri &>/dev/null; then
        /opt/survive/venv/bin/pip install -q kolibri || true
    fi

    # Report the truth. This previously printed "Kolibri installed"
    # unconditionally, so a failed install looked like a success and the
    # dashboard tile stayed DOWN with no explanation.
    if command -v kolibri &>/dev/null || [[ -x /opt/survive/venv/bin/kolibri ]]; then
        success "Kolibri installé"
        return 0
    fi
    warn "Kolibri n'a PAS été installé (souvent un conflit de version de Python —"
    warn "ce système a Python $(python3 -V 2>&1 | awk '{print $2}'))."
    warn "La tuile Éducation restera à l'arrêt. Le contenu Khan Academy existe aussi"
    warn "sous forme de ZIM Kiwix, qui ne demande aucun service supplémentaire."
    return 1
}

# ── Calibre + Calibre-Web ─────────────────────────────────────────────────────
install_calibre() {
    info "Installation de Calibre..."
    apt-get install -y -qq calibre || {
        wget -nv -O- https://download.calibre-ebook.com/linux-installer.sh | bash /dev/stdin
    }

    info "Installation de Calibre-Web..."
    /opt/survive/venv/bin/pip install -q calibreweb

    # Build the Calibre library from any ebooks already downloaded. Safe no-op
    # if none exist yet — books_pdfs.sh rebuilds it after each download.
    bash "$(dirname "${BASH_SOURCE[0]}")/../scripts/build_ebook_library.sh" || true
    success "Calibre + Calibre-Web installés"
}

# ── Martin tile server (offline maps) ─────────────────────────────────────────
install_martin() {
    if command -v martin &>/dev/null; then
        success "Martin déjà installé ($(command -v martin))"
        return 0
    fi
    info "Installation du serveur de tuiles Martin..."

    # Do NOT pin a version: the previously hardcoded v0.14.3 asset is gone from
    # GitHub (404), which is why the maps tile never came up. Ask the API for
    # the current release and pick whichever asset matches this architecture.
    local arch_pat="aarch64"
    [[ "$(uname -m)" == "aarch64" ]] || arch_pat="$(uname -m)"
    local url
    url=$(curl -fsSL --max-time 60 \
            https://api.github.com/repos/maplibre/martin/releases/latest 2>/dev/null \
          | grep -oE '"browser_download_url": *"[^"]+"' \
          | cut -d'"' -f4 \
          | grep -iE "linux" | grep -iE "${arch_pat}|arm64" \
          | grep -E '\.tar\.gz$' | head -1) || true

    if [[ -z "$url" ]]; then
        warn "Impossible de déterminer une version de Martin pour $(uname -m)."
        warn "Installez-le à la main depuis https://github.com/maplibre/martin/releases"
        warn "puis relancez : sudo bash scripts/generate_services.sh"
        return 1
    fi

    info "Téléchargement de $(basename "$url")"
    local tmp
    tmp=$(mktemp -d)
    if wget -q -O "$tmp/martin.tar.gz" "$url"; then
        tar -xzf "$tmp/martin.tar.gz" -C "$tmp"
        # The archive layout varies between releases; find the binary.
        local bin
        bin=$(find "$tmp" -type f -name martin -perm -u+x | head -1)
        [[ -n "$bin" ]] || bin=$(find "$tmp" -type f -name martin | head -1)
        if [[ -n "$bin" ]]; then
            install -m 0755 "$bin" /usr/local/bin/martin
            success "Martin installé ($(/usr/local/bin/martin --version 2>&1 | head -1))"
        else
            warn "Aucun binaire martin dans l'archive"
        fi
    else
        warn "Échec du téléchargement de Martin : $url"
    fi
    rm -rf "$tmp"
    command -v martin &>/dev/null
}

# ── Jellyfin (video streaming) ────────────────────────────────────────────────
install_jellyfin() {
    info "Installation du serveur multimédia Jellyfin..."
    curl -fsSL https://repo.jellyfin.org/install-debuntu.sh | bash || {
        warn "Le script d'installation de Jellyfin a échoué, essai de la méthode manuelle..."
        curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key \
            | gpg --dearmor -o /usr/share/keyrings/jellyfin.gpg
        echo "deb [signed-by=/usr/share/keyrings/jellyfin.gpg arch=arm64] \
            https://repo.jellyfin.org/ubuntu jammy main" \
            > /etc/apt/sources.list.d/jellyfin.list
        apt-get update -qq && apt-get install -y -qq jellyfin
    }
    success "Jellyfin installé"
}

# ── Ollama (local LLM) ────────────────────────────────────────────────────────
install_ollama() {
    info "Installation d'Ollama pour l'IA locale..."
    curl -fsSL https://ollama.ai/install.sh | sh
    command -v ollama &>/dev/null || { error "Échec de l'installation d'Ollama"; exit 1; }

    # The vendor installer registers its own ollama.service running as the
    # 'ollama' system user, whose models live in /usr/share/ollama/.ollama —
    # on the SD CARD. OLLAMA_MODELS is read by the SERVER, so exporting it for
    # `ollama pull` does NOT redirect a server that is already running; models
    # silently fill the boot disk (8-14 GB) until apt runs out of space.
    # Retire the vendor unit here; install_services() then installs ours, which
    # points OLLAMA_MODELS at the storage drive.
    if systemctl list-unit-files ollama.service &>/dev/null; then
        info "Désactivation de l'ollama.service d'origine (ses modèles rempliraient la carte SD)"
        systemctl disable --now ollama.service 2>/dev/null || true
    fi
    success "Ollama installé"
}

# ── Storage setup ─────────────────────────────────────────────────────────────
setup_storage() {
    STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
    info "Préparation du stockage dans $STORAGE_PATH..."

    mkdir -p "$STORAGE_PATH"/{zim,videos,books,pdfs,maps,kolibri,ai_models,misc}
    mkdir -p "$STORAGE_PATH"/.sync

    # Symlink data directory
    ln -sfn "$STORAGE_PATH" "$REPO_DIR/data"

    # Set permissions
    chown -R "$SUDO_USER:$SUDO_USER" "$STORAGE_PATH" 2>/dev/null || \
    chown -R "pi:pi" "$STORAGE_PATH" 2>/dev/null || true

    success "Stockage configuré dans $STORAGE_PATH"
}

# ── Nginx configuration ───────────────────────────────────────────────────────
configure_nginx() {
    info "Configuration du proxy inverse Nginx..."
    cp "$REPO_DIR/config/nginx.conf" /etc/nginx/sites-available/survive
    ln -sfn /etc/nginx/sites-available/survive /etc/nginx/sites-enabled/survive
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl reload nginx
    success "Nginx configuré"
}

# ── Firewall ──────────────────────────────────────────────────────────────────
configure_firewall() {
    info "Configuration du pare-feu..."
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw allow 80/tcp   # nginx (primary access point)
    ufw allow 443/tcp  # nginx TLS
    ufw allow 8080/tcp # dashboard (direct access)
    ufw allow 445/tcp  # samba file sharing
    # The dashboard's tiles and nav links send the browser DIRECTLY to each
    # service's port, so these must be reachable from the LAN. (An earlier
    # version blocked them "nginx-only", which made every service except the
    # dashboard appear dead from any other device.)
    ufw allow 8081/tcp # kiwix (wikipedia/books)
    ufw allow 8082/tcp # kolibri (khan academy)
    ufw allow 8083/tcp # calibre-web (e-books)
    ufw allow 8096/tcp # jellyfin (videos)
    ufw allow 3000/tcp # martin (offline maps)
    # 11434 (ollama) stays closed: the dashboard proxies all AI traffic, and
    # the raw Ollama API has no authentication.
    # Allow from loopback for inter-service communication
    ufw allow in on lo
    ufw --force enable
    success "Pare-feu configuré (port Ollama fermé, services accessibles depuis le réseau local)"
}

# ── Samba share ───────────────────────────────────────────────────────────────
# SAMBA_HOSTS_ALLOW restricts the share to specified IPs/CIDRs. Default is
# local-only; override in config/survive.conf (e.g. "127.0.0.1 192.168.1.").
configure_samba() {
    info "Configuration de Samba pour le partage de fichiers local..."
    STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
    local hosts_allow="${SAMBA_HOSTS_ALLOW:-127.0.0.1 192.168. 10.}"
    cat > /etc/samba/smb.conf << SAMBA
[global]
   workgroup = SURVIVE
   server string = Serveur de connaissances SurviveV1
   security = user
   map to guest = bad user
   dns proxy = no
   # Only accept connections from trusted local subnets.
   hosts allow = $hosts_allow
   hosts deny = 0.0.0.0/0

[survive]
   path = $STORAGE_PATH
   browseable = yes
   read only = yes
   # Require a real user rather than anonymous guest access.
   guest ok = no
   valid users = @survive
   comment = Base de connaissances de survie
SAMBA
    # Create a 'survive' group and add the default user, if present.
    getent group survive >/dev/null || groupadd survive
    if id pi &>/dev/null; then usermod -aG survive pi; fi
    if [[ -n "${SUDO_USER:-}" ]] && id "$SUDO_USER" &>/dev/null; then
        usermod -aG survive "$SUDO_USER"
    fi
    systemctl restart smbd nmbd
    success "Partage Samba configuré (hôtes autorisés : $hosts_allow)"
    info "Définissez un mot de passe Samba avec : sudo smbpasswd -a <utilisateur>"
}

# ── Install systemd services ──────────────────────────────────────────────────
install_services() {
    info "Installation des services systemd..."
    # The unit files ship with User=pi, but the real login may be anything
    # (Raspberry Pi Imager lets users pick a name). Substitute the invoking
    # user so services actually start on non-'pi' systems.
    local svc_user="${SUDO_USER:-pi}"
    id "$svc_user" &>/dev/null || svc_user="pi"
    for unit in "$REPO_DIR"/systemd/*.service "$REPO_DIR"/systemd/*.timer; do
        [[ -f "$unit" ]] || continue
        sed -e "s/^User=pi$/User=${svc_user}/" \
            -e "s|/home/pi/SurviveV1|${REPO_DIR}|g" "$unit" \
            > "/etc/systemd/system/$(basename "$unit")"
    done
    info "Les services s'exécuteront sous l'utilisateur : ${svc_user}"
    systemctl daemon-reload
    systemctl enable survive-dashboard.service
    systemctl enable kiwix.service
    systemctl enable jellyfin.service 2>/dev/null || true
    systemctl enable kolibri.service 2>/dev/null || true
    systemctl enable calibre-web.service 2>/dev/null || true
    systemctl enable ollama.service 2>/dev/null || true
    systemctl enable martin-tiles.service 2>/dev/null || true
    # Stays inactive (ConditionPathExists) until download/comms.sh has run.
    systemctl enable survive-meshtastic.service 2>/dev/null || true
    systemctl enable survive-meshcore.service 2>/dev/null || true
    success "Services systemd installés"
}

# ── Hailo AI Hat setup ────────────────────────────────────────────────────────
setup_ai_hat() {
    if [[ "${SKIP_AI_HAT:-false}" == "true" ]]; then
        warn "Configuration de l'AI Hat ignorée (SKIP_AI_HAT=true)"
        return
    fi
    info "Configuration de l'AI Hat Hailo..."
    bash "$SCRIPT_DIR/install_ai_hat.sh" || warn "Échec de la configuration de l'AI Hat — voir docs/ai_hat_setup.md"
}

# ── Avahi mDNS ────────────────────────────────────────────────────────────────
configure_avahi() {
    info "Configuration du mDNS (survive.local)..."
    cat > /etc/avahi/services/survive.service << 'XML'
<?xml version="1.0" standalone='no'?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">SurviveV1 sur %h</name>
  <service>
    <type>_http._tcp</type>
    <port>8080</port>
    <txt-record>path=/</txt-record>
  </service>
</service-group>
XML
    systemctl restart avahi-daemon
    success "Accessible sur http://survive.local:8080"
}

# ── Create /opt/survive structure ─────────────────────────────────────────────
setup_opt_survive() {
    info "Préparation de /opt/survive..."
    mkdir -p /opt/survive/{venv,logs,db}
    cp -r "$REPO_DIR/web" /opt/survive/
    cp -r "$REPO_DIR/config" /opt/survive/
    ln -sfn "$REPO_DIR/data" /opt/survive/data
    REAL_USER="${SUDO_USER:-pi}"
    chown -R "$REAL_USER:$REAL_USER" /opt/survive
    success "/opt/survive prêt"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    banner
    require_root

    echo ""
    info "Démarrage de l'installation de SurviveV1..."
    info "Journal : $LOG_FILE"
    echo ""

    update_system
    install_core_deps
    setup_opt_survive
    setup_python_env
    install_ytdlp
    install_kiwix
    install_ollama
    setup_storage
    bash "$SCRIPT_DIR/pi5_storage.sh" || warn "Réglages de stockage du Pi 5 ignorés"
    configure_nginx
    configure_firewall
    configure_samba
    configure_avahi
    configure_chrony
    install_services
    bash "$REPO_DIR/scripts/install_sudoers.sh" \
        || warn "Échec de l'installation de sudoers — les boutons de redémarrage des services seront inactifs"

    # Content services. These were previously commented out, which shipped a
    # dashboard advertising Kolibri, Calibre-Web and Jellyfin on a machine where
    # none of them existed — every one showed "STOPPED" with no explanation.
    # Now gated by the content flags, so disabling a category also skips paying
    # for its (large) dependencies.
    if [[ "${CONTENT_KOLIBRI:-Y}" =~ [Yy] ]]; then
        install_kolibri || warn "Échec de l'installation de Kolibri — la tuile du tableau de bord restera à l'arrêt"
    else
        info "CONTENT_KOLIBRI=N — Kolibri ignoré"
    fi

    if [[ "${CONTENT_GUTENBERG:-Y}" =~ [Yy] ]] || [[ "${CONTENT_PDFS:-Y}" =~ [Yy] ]]; then
        install_calibre || warn "Échec de l'installation de Calibre-Web — la tuile du tableau de bord restera à l'arrêt"
    else
        info "Aucun livre/PDF sélectionné — Calibre-Web ignoré"
    fi

    if [[ "${CONTENT_MAPS:-Y}" =~ [Yy] ]]; then
        install_martin || warn "Échec de l'installation de Martin — la tuile Cartes restera à l'arrêt"
    else
        info "CONTENT_MAPS=N — serveur de tuiles Martin ignoré"
    fi

    if [[ "${CONTENT_VIDEOS:-Y}" =~ [Yy] ]]; then
        install_jellyfin || warn "Échec de l'installation de Jellyfin — la tuile du tableau de bord restera à l'arrêt"
    else
        info "CONTENT_VIDEOS=N — Jellyfin ignoré"
    fi

    # The Hailo stack is hardware-specific (8L vs 10H need different drivers)
    # and cannot accelerate Ollama regardless — see docs/ai_hat_setup.md.
    # setup_ai_hat

    # Regenerate units LAST: binary paths are resolved with `command -v`, so
    # this must happen after Kolibri/Calibre/Jellyfin/Martin are on disk.
    # Running it earlier resolved them as "not installed" and baked in the
    # wrong ExecStart.
    if [[ -x "$REPO_DIR/scripts/generate_services.sh" ]]; then
        bash "$REPO_DIR/scripts/generate_services.sh" || warn "Échec de generate_services.sh"
    fi

    # The installer used to END with "Enable and start with: <commands>" —
    # leaving every service stopped (and, because the vendor Ollama unit
    # shares our unit name, leaving Ollama disabled after we retire the
    # vendor copy). Finish the job instead of assigning homework.
    enable_core_services

    echo ""
    success "============================================"
    success "Installation de SurviveV1 terminée !"
    success "============================================"
    echo ""
    info "Étapes suivantes :"
    echo "  1. Télécharger le contenu :  bash download/download_all.sh"
    echo "  2. Démarrer les services :   bash scripts/start_services.sh"
    echo "  3. Ouvrir le tableau de bord : http://localhost:8080"
    echo "  4. Accès par le réseau :     http://survive.local:8080"
    echo ""
}

main "$@"
