#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — Détection du matériel et résolution des modules
#
# Usage :
#   bash scripts/detect_hardware.sh            # lignes CLE=valeur (à sourcer / eval)
#   bash scripts/detect_hardware.sh --table    # tableau lisible
#   bash scripts/detect_hardware.sh --json     # JSON
#
# Chaque module a un réglage SURVIVE_MODULE_<NOM> = auto | on | off
# (config/survive.conf). « auto » active le module seulement si le matériel le
# permet ; « on » force ; « off » désactive. Résultat : MOD_<NOM>=on|off
# (MOD_AI peut aussi valoir « remote » si SURVIVE_OLLAMA_HOST pointe ailleurs)
# et MOD_<NOM>_WHY = raison en français.
#
# HW_SYSROOT (tests) : préfixe appliqué à /proc, /sys et /etc.
# HW_FORCE_* (tests) : HW_FORCE_WIFI_AP=yes|no|unknown remplace l'appel à `iw`.
# Ce script ne modifie rien et ne demande pas root.
# =============================================================================
# Les variables MOD_*/HW_* sont lues par indirection (${!k}) : SC2034 sans objet ici.
# shellcheck disable=SC2034
set -uo pipefail

R="${HW_SYSROOT:-}"
MODE="env"
case "${1:-}" in
    --table) MODE="table" ;;
    --json)  MODE="json" ;;
    ""|--env) ;;
    *) echo "Usage : $0 [--env|--table|--json]" >&2; exit 2 ;;
esac

# ── Chargement facultatif de la configuration ────────────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
# shellcheck disable=SC1090
[[ -f "$_CONF" ]] && source "$_CONF" 2>/dev/null

# ── Faits matériels ──────────────────────────────────────────────────────────
HW_ARCH="${HW_FORCE_ARCH:-$(uname -m)}"

HW_RAM_MB=$(awk '/MemTotal/ {print int($2/1024)}' "$R/proc/meminfo" 2>/dev/null)
HW_RAM_MB="${HW_RAM_MB:-0}"

if [[ -n "${SURVIVE_PLATFORM:-}" ]]; then
    HW_PLATFORM="$SURVIVE_PLATFORM"
elif grep -qi "raspberry pi" "$R/proc/device-tree/model" 2>/dev/null; then
    HW_PLATFORM="pi"
else
    HW_PLATFORM="generic"
fi

HW_CPU_MODEL=$(awk -F': *' '/model name|Model name|^Hardware/ {print $2; exit}' "$R/proc/cpuinfo" 2>/dev/null)
HW_CPU_MODEL="${HW_CPU_MODEL:-inconnu}"

# AVX2 : exigé par Ollama sur x86. Sur ARM64 (NEON) la question ne se pose pas.
case "$HW_ARCH" in
    x86_64|amd64)
        if grep -qwi "avx2" "$R/proc/cpuinfo" 2>/dev/null; then HW_AVX2="yes"; else HW_AVX2="no"; fi ;;
    *) HW_AVX2="n/a" ;;
esac

# Batterie / portable
HW_BATTERY="no"
for b in "$R"/sys/class/power_supply/BAT*; do
    [[ -e "$b" ]] && HW_BATTERY="yes" && break
done
HW_CHASSIS=$(cat "$R/sys/class/dmi/id/chassis_type" 2>/dev/null || echo "")
HW_LAPTOP="no"
case "$HW_CHASSIS" in
    8|9|10|11|14|30|31|32) HW_LAPTOP="yes" ;;   # portable, notebook, tablette, etc.
esac
[[ "$HW_BATTERY" == "yes" && "$HW_PLATFORM" != "pi" ]] && HW_LAPTOP="yes"

# Wi-Fi : interface + prise en charge du mode point d'accès
HW_WIFI_IFACE=""
for d in "$R"/sys/class/net/*; do
    [[ -d "$d/wireless" || -d "$d/phy80211" ]] && { HW_WIFI_IFACE="$(basename "$d")"; break; }
done
if [[ -z "$HW_WIFI_IFACE" ]]; then
    HW_WIFI_AP="no"
elif [[ -n "${HW_FORCE_WIFI_AP:-}" ]]; then
    HW_WIFI_AP="$HW_FORCE_WIFI_AP"
elif command -v iw >/dev/null 2>&1; then
    if iw list 2>/dev/null | awk '/Supported interface modes/,/Band|Supported commands/' | grep -qE '^\s*\* AP\s*$'; then
        HW_WIFI_AP="yes"
    else
        HW_WIFI_AP="no"
    fi
else
    HW_WIFI_AP="unknown"
fi

# Hailo (AI Hat)
HW_HAILO="no"
if compgen -G "$R/dev/hailo*" >/dev/null 2>&1; then
    HW_HAILO="yes"
elif command -v lspci >/dev/null 2>&1 && lspci 2>/dev/null | grep -qi hailo; then
    HW_HAILO="yes"
fi

# Système d'exploitation
HW_OS_ID=$(. "$R/etc/os-release" 2>/dev/null && echo "${ID:-inconnu}")
HW_OS_CODENAME=$(. "$R/etc/os-release" 2>/dev/null && echo "${VERSION_CODENAME:-inconnu}")

# ── Résolution des modules ───────────────────────────────────────────────────
# resolve NOM "réglage" auto_on(0/1) raison_auto_on raison_auto_off
resolve() {
    local name="$1" setting="${2:-auto}" auto_ok="$3" why_on="$4" why_off="$5" state why
    case "$setting" in
        on|ON|true)   state="on";  why="forcé (SURVIVE_MODULE_${name}=on)" ;;
        off|OFF|false) state="off"; why="désactivé (SURVIVE_MODULE_${name}=off)" ;;
        *)
            if [[ "$auto_ok" == "1" ]]; then state="on"; why="$why_on"
            else state="off"; why="$why_off"; fi ;;
    esac
    printf -v "MOD_${name}" '%s' "$state"
    printf -v "MOD_${name}_WHY" '%s' "$why"
}

# IA locale
ai_ok=1; ai_why_on="matériel suffisant"; ai_why_off=""
if [[ "$HW_AVX2" == "no" ]]; then
    ai_ok=0; ai_why_off="processeur sans AVX2 (Ollama ne peut pas tourner)"
elif (( HW_RAM_MB < 3500 )); then
    ai_ok=0; ai_why_off="RAM insuffisante (${HW_RAM_MB} Mo, 4 Go minimum)"
fi
resolve AI "${SURVIVE_MODULE_AI:-auto}" "$ai_ok" "$ai_why_on" "$ai_why_off"
# Un Ollama distant (machine plus puissante) remplace l'IA locale.
if [[ -n "${SURVIVE_OLLAMA_HOST:-}" ]]; then
    printf -v MOD_AI '%s' "remote"
    printf -v MOD_AI_WHY '%s' "Ollama distant : ${SURVIVE_OLLAMA_HOST}"
fi

resolve HAILO "${SURVIVE_MODULE_HAILO:-auto}" \
    "$([[ "$HW_PLATFORM" == "pi" && "$HW_HAILO" == "yes" ]] && echo 1 || echo 0)" \
    "AI Hat Hailo détecté" \
    "$([[ "$HW_PLATFORM" != "pi" ]] && echo "pas un Raspberry Pi" || echo "aucun AI Hat détecté")"

resolve PI_USB "${SURVIVE_MODULE_PI_USB:-auto}" \
    "$([[ "$HW_PLATFORM" == "pi" ]] && echo 1 || echo 0)" \
    "Raspberry Pi" "pas un Raspberry Pi"

resolve HOTSPOT "${SURVIVE_MODULE_HOTSPOT:-auto}" \
    "$([[ "$HW_WIFI_AP" == "yes" || "$HW_WIFI_AP" == "unknown" ]] && echo 1 || echo 0)" \
    "$([[ "$HW_WIFI_AP" == "yes" ]] && echo "Wi-Fi ${HW_WIFI_IFACE} compatible point d'accès" || echo "Wi-Fi ${HW_WIFI_IFACE} (mode AP non vérifié : iw absent)")" \
    "$([[ -z "$HW_WIFI_IFACE" ]] && echo "aucune carte Wi-Fi" || echo "la carte Wi-Fi ne gère pas le mode point d'accès")"

resolve LID "${SURVIVE_MODULE_LID:-auto}" \
    "$([[ "$HW_LAPTOP" == "yes" ]] && echo 1 || echo 0)" \
    "portable détecté (la fermeture du capot ne doit pas couper les services)" "pas un portable"

resolve BATTERY "${SURVIVE_MODULE_BATTERY:-auto}" \
    "$([[ "$HW_BATTERY" == "yes" ]] && echo 1 || echo 0)" \
    "batterie détectée (sert d'onduleur de secours)" "aucune batterie"

MODULES=(AI HAILO PI_USB HOTSPOT LID BATTERY)
FACTS=(HW_PLATFORM HW_ARCH HW_CPU_MODEL HW_RAM_MB HW_AVX2 HW_LAPTOP HW_BATTERY
       HW_WIFI_IFACE HW_WIFI_AP HW_HAILO HW_OS_ID HW_OS_CODENAME)

# ── Sortie ───────────────────────────────────────────────────────────────────
# Guillemets doubles avec échappement de \ " $ ` : sourçable en bash, lisible par shlex.
q() { local v="$1"; v="${v//\\/\\\\}"; v="${v//\"/\\\"}"; v="${v//\$/\\\$}"; v="${v//\`/\\\`}"; printf '"%s"' "$v"; }
case "$MODE" in
    env)
        for k in "${FACTS[@]}"; do printf '%s=%s\n' "$k" "$(q "${!k}")"; done
        for m in "${MODULES[@]}"; do
            v="MOD_$m"; w="MOD_${m}_WHY"
            printf '%s=%s\n%s=%s\n' "$v" "$(q "${!v}")" "$w" "$(q "${!w}")"
        done ;;
    table)
        printf '\nMatériel : %s — %s — %s Mo RAM — %s\n' "$HW_PLATFORM" "$HW_ARCH" "$HW_RAM_MB" "$HW_CPU_MODEL"
        printf 'Système  : %s %s\n\n' "$HW_OS_ID" "$HW_OS_CODENAME"
        printf '  %-10s %-8s %s\n' "Module" "État" "Raison"
        for m in "${MODULES[@]}"; do
            v="MOD_$m"; w="MOD_${m}_WHY"
            printf '  %-10s %-8s %s\n' "$m" "${!v}" "${!w}"
        done
        echo ""
        echo "Pour corriger : SURVIVE_MODULE_<NOM>=on|off|auto dans config/survive.conf" ;;
    json)
        "${BASH_SOURCE[0]}" --env | python3 -c '
import json, shlex, sys
kv = {}
for line in sys.stdin:
    k, _, v = line.rstrip("\n").partition("=")
    parts = shlex.split(v)
    kv[k] = parts[0] if parts else ""
mods = {}
for k, v in kv.items():
    if k.startswith("MOD_") and not k.endswith("_WHY"):
        mods[k[4:]] = {"state": v, "why": kv.get(k + "_WHY", "")}
hw = {k: v for k, v in kv.items() if k.startswith("HW_")}
print(json.dumps({"hardware": hw, "modules": mods}, ensure_ascii=False, indent=2))
' ;;
esac
