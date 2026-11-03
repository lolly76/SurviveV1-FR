#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — rclone cloud storage setup
# Configures Google Drive, Dropbox, S3, and other cloud providers
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${BLUE}[SYNC]${NC} $*"; }
success() { echo -e "${GREEN}[SYNC]${NC} $*"; }
warn()    { echo -e "${YELLOW}[SYNC]${NC} $*"; }

# ── Ensure rclone is installed and meets minimum version ─────────────────────
# 1.73.5 fixes CVE-2026-41179 (unauthenticated backend creation via RC API).
# 1.68.2 fixes symlink privilege escalation with --links + --metadata.
MIN_RCLONE_VERSION="1.73.5"

version_ge() { [ "$(printf '%s\n%s' "$1" "$2" | sort -V | head -1)" = "$2" ]; }

install_rclone() {
    if ! command -v rclone &>/dev/null; then
        info "Installation de rclone..."
        curl -fsSL https://rclone.org/install.sh | bash
    fi
    local current
    current=$(rclone version | head -1 | awk '{print $2}' | tr -d 'v')
    if [[ -n "$current" ]] && ! version_ge "$current" "$MIN_RCLONE_VERSION"; then
        warn "rclone $current < $MIN_RCLONE_VERSION; mise à jour recommandée (CVE-2026-41179)."
    fi
    success "rclone $(rclone version | head -1)"
}

# ── Interactive cloud provider setup ─────────────────────────────────────────
setup_provider() {
    local provider="$1"

    case "$provider" in
        gdrive|google)
            info "Configuration de Google Drive..."
            echo ""
            echo "  Étapes :"
            echo "  1. Lancer : rclone config"
            echo "  2. Choisir : n (nouveau stockage distant)"
            echo "  3. Nom : gdrive"
            echo "  4. Type : 18 (Google Drive)"
            echo "  5. Suivre l'authentification OAuth (Internet nécessaire temporairement)"
            echo "  6. Choisir « Accès complet »"
            echo ""
            echo "  Puis lancer : bash sync/sync_to_cloud.sh gdrive"
            ;;
        dropbox)
            info "Configuration de Dropbox..."
            echo ""
            echo "  Étapes :"
            echo "  1. Lancer : rclone config"
            echo "  2. Choisir : n (nouveau stockage distant)"
            echo "  3. Nom : dropbox"
            echo "  4. Type : 8 (Dropbox)"
            echo "  5. Suivre l'authentification OAuth"
            ;;
        s3|aws)
            info "Configuration d'Amazon S3..."
            echo ""
            read -rp "  Identifiant de clé d'accès AWS : " AWS_KEY
            read -rsp "  Clé secrète AWS : " AWS_SECRET
            echo ""
            read -rp "  Région [eu-west-3] : " AWS_REGION
            AWS_REGION="${AWS_REGION:-eu-west-3}"

            # Secrets passed via a 0600 temp file and --config-str, never on
            # the command line (would leak via ps / shell history / errors).
            local secret_file
            secret_file=$(mktemp) && chmod 600 "$secret_file"
            trap 'shred -u "$secret_file" 2>/dev/null || rm -f "$secret_file"' RETURN
            cat > "$secret_file" <<EOF
[s3]
type = s3
provider = AWS
access_key_id = $AWS_KEY
secret_access_key = $AWS_SECRET
region = $AWS_REGION
EOF
            # Append to rclone's config (keeps existing remotes).
            local rclone_conf
            rclone_conf="$(rclone config file 2>/dev/null | tail -1)"
            rclone_conf="${rclone_conf:-$HOME/.config/rclone/rclone.conf}"
            mkdir -p "$(dirname "$rclone_conf")"
            touch "$rclone_conf" && chmod 600 "$rclone_conf"
            cat "$secret_file" >> "$rclone_conf"
            # Clear the plaintext secrets from the calling shell.
            unset AWS_KEY AWS_SECRET
            success "S3 configuré sous le nom « s3 » dans $rclone_conf (mode 0600)"
            warn "La configuration n'est qu'obscurcie par défaut. Lancez « rclone config » et"
            warn "choisissez « s » (mot de passe de configuration) pour chiffrer les identifiants."
            ;;
        backblaze|b2)
            info "Configuration de Backblaze B2..."
            echo ""
            read -rp "  Identifiant de clé d'application : " B2_KEY
            read -rsp "  Clé d'application : " B2_SECRET
            echo ""
            local secret_file
            secret_file=$(mktemp) && chmod 600 "$secret_file"
            trap 'shred -u "$secret_file" 2>/dev/null || rm -f "$secret_file"' RETURN
            cat > "$secret_file" <<EOF
[b2]
type = b2
account = $B2_KEY
key = $B2_SECRET
EOF
            local rclone_conf
            rclone_conf="$(rclone config file 2>/dev/null | tail -1)"
            rclone_conf="${rclone_conf:-$HOME/.config/rclone/rclone.conf}"
            mkdir -p "$(dirname "$rclone_conf")"
            touch "$rclone_conf" && chmod 600 "$rclone_conf"
            cat "$secret_file" >> "$rclone_conf"
            unset B2_KEY B2_SECRET
            success "Backblaze B2 configuré (mode 0600)"
            warn "Lancez « rclone config » puis « s » pour chiffrer cette configuration."
            ;;
        onedrive)
            info "Configuration de Microsoft OneDrive..."
            echo ""
            echo "  Étapes :"
            echo "  1. Lancer : rclone config"
            echo "  2. Choisir : n (nouveau stockage distant)"
            echo "  3. Nom : onedrive"
            echo "  4. Type : 26 (Microsoft OneDrive)"
            echo "  5. Suivre l'authentification OAuth"
            ;;
        *)
            info "Lancement de la configuration interactive de rclone..."
            rclone config
            ;;
    esac
}

# ── List configured remotes ───────────────────────────────────────────────────
list_remotes() {
    info "Stockages cloud configurés :"
    rclone listremotes 2>/dev/null || echo "  Aucun pour l'instant"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    install_rclone

    if [[ $# -eq 0 ]]; then
        echo ""
        echo "Configuration du stockage cloud pour SurviveV1"
        echo ""
        echo "  Fournisseurs pris en charge :"
        echo "    gdrive    — Google Drive (15 Go gratuits)"
        echo "    dropbox   — Dropbox (2 Go gratuits)"
        echo "    s3        — Amazon S3"
        echo "    b2        — Backblaze B2 (10 Go gratuits)"
        echo "    onedrive  — Microsoft OneDrive (5 Go gratuits)"
        echo "    custom    — Configuration interactive de rclone"
        echo ""
        echo "  Utilisation : bash sync/setup_rclone.sh <fournisseur>"
        echo "  Puis :  bash sync/sync_to_cloud.sh <nom_du_stockage>"
        echo ""
        list_remotes
        return 0
    fi

    setup_provider "${1:-custom}"
    list_remotes
}

main "$@"
