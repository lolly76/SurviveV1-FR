#!/usr/bin/env bash
# =============================================================================
# SurviveV1 — AI query CLI
# Utilisation : bash ai/query.sh "Comment purifier de l'eau ?"
#        bash ai/query.sh --model phi3:mini "Comment immobiliser une fracture ?"
# =============================================================================

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
_CONF="$REPO_DIR/config/survive.conf"
[[ -f "$_CONF" ]] || _CONF="${_CONF}.example"   # fall back to shipped defaults
if [[ ! -f "$_CONF" ]]; then echo "[WARN] Config introuvable : $_CONF -- valeurs par défaut" >&2; else source "$_CONF"; fi

STORAGE_PATH="${SURVIVE_STORAGE_PATH:-/mnt/survive}"
export OLLAMA_MODELS="${OLLAMA_MODELS:-$STORAGE_PATH/ai_models/ollama}"

MODEL="${SURVIVE_AI_MODEL:-survive}"
INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model|-m) MODEL="$2"; shift 2 ;;
        --interactive|-i) INTERACTIVE=true; shift ;;
        *) QUERY="$*"; break ;;
    esac
done

# ── Check Ollama ──────────────────────────────────────────────────────────────
if ! curl -sf http://localhost:11434 &>/dev/null; then
    echo "Démarrage d'Ollama..."
    ollama serve &>/dev/null &
    sleep 3
fi

# ── Fallback model if 'survive' not installed ──────────────────────────────────
if ! ollama list 2>/dev/null | grep -q "^${MODEL}"; then
    # Try to find any installed model
    FALLBACK=$(ollama list 2>/dev/null | tail -n +2 | head -1 | awk '{print $1}')
    if [[ -n "$FALLBACK" ]]; then
        echo "Modèle « $MODEL » introuvable, utilisation de $FALLBACK"
        MODEL="$FALLBACK"
    else
        echo "Aucun modèle d'IA installé. Lancez : bash ai/setup_ollama.sh"
        exit 1
    fi
fi

# ── Retrieve context from the local Kiwix library (RAG) ────────────────────────
# Best-effort: if kiwix-serve is down or returns nothing, we fall through to a
# plain query so the assistant still works.
KIWIX_PORT="${PORT_KIWIX:-8081}"

get_context() {
    local q="$1" encoded
    encoded=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "$q" 2>/dev/null) \
        || return 1
    curl -sf --max-time 3 \
        "http://localhost:${KIWIX_PORT}/search?pattern=${encoded}&pageLength=3&format=xml" 2>/dev/null \
    | python3 -c '
import sys, re
import xml.etree.ElementTree as ET
try:
    root = ET.fromstring(sys.stdin.read())
except Exception:
    sys.exit(0)
tag = re.compile(r"<[^>]+>")
out = []
for item in root.iter("item"):
    title = (item.findtext("title") or "").strip()
    desc = re.sub(r"\s+", " ", tag.sub(" ", item.findtext("description") or "")).strip()
    if title:
        out.append(f"- {title}: {desc}")
print("\n".join(out[:3]))
' 2>/dev/null
}

# ── Interactive mode ──────────────────────────────────────────────────────────
if [[ "$INTERACTIVE" == "true" ]] || [[ -z "${QUERY:-}" ]]; then
    echo "Assistant IA SurviveV1 (modèle : $MODEL)"
    echo "Tapez « exit » ou Ctrl+C pour quitter"
    echo ""
    exec ollama run "$MODEL"
fi

# ── Single query ──────────────────────────────────────────────────────────────
echo ""
echo "Question : $QUERY"
echo "Modèle : $MODEL"
echo "─────────────────────────────────────"

CONTEXT=$(get_context "$QUERY" || true)
if [[ -n "$CONTEXT" ]]; then
    echo "(réponse appuyée sur $(printf '%s\n' "$CONTEXT" | grep -c '^- ') article(s) de référence de votre bibliothèque)"
    echo ""
    PROMPT="Extraits de référence de la bibliothèque hors ligne :
${CONTEXT}

En t'appuyant sur les extraits ci-dessus lorsqu'ils sont pertinents, réponds de façon concise : ${QUERY}"
else
    PROMPT="$QUERY"
fi
ollama run "$MODEL" "$PROMPT"
