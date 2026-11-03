"""
SurviveV1 — Constantes partagées du serveur web.
Tous les numéros de port sont ici pour éviter les nombres magiques dispersés dans le code.
"""

# ── Ports des services ──────────────────────────────────────────────────────────────
PORT_DASHBOARD = 8080
PORT_KIWIX     = 8081
PORT_KOLIBRI   = 8082
PORT_CALIBRE   = 8083
PORT_JELLYFIN  = 8096
PORT_MAPS      = 3000
PORT_MESHTASTIC = 8084
PORT_MESHCORE   = 8085
PORT_OLLAMA    = 11434

# ── Registre des services ──────────────────────────────────────────────────────────
# `unit` is the systemd unit name the dashboard's restart button targets; it
# must appear in the /etc/sudoers.d/survive-dashboard allowlist written by
# scripts/install_sudoers.sh. None = no restart button (managed elsewhere).
SERVICES = {
    "kiwix":    {"name": "Wikipédia et livres", "port": PORT_KIWIX,
                 "icon": "📚", "color": "#2980b9", "unit": "kiwix"},
    "kolibri":  {"name": "Khan Academy",      "port": PORT_KOLIBRI,
                 "icon": "🎓", "color": "#27ae60", "unit": "kolibri"},
    "calibre":  {"name": "Livres numériques", "port": PORT_CALIBRE,
                 "icon": "📖", "color": "#8e44ad", "unit": "calibre-web"},
    "jellyfin": {"name": "Vidéos",             "port": PORT_JELLYFIN,
                 "icon": "🎬", "color": "#e74c3c", "unit": "jellyfin"},
    "maps":     {"name": "Cartes hors ligne", "port": PORT_MAPS,
                 "icon": "🗺️", "color": "#f39c12", "unit": "martin-tiles"},
    "ai":       {"name": "Assistant IA",       "port": PORT_OLLAMA,
                 "icon": "🤖", "color": "#16a085", "unit": "ollama"},
    "meshtastic": {"name": "Meshtastic Web",  "port": PORT_MESHTASTIC,
                 "icon": "📡", "color": "#67ea94", "unit": "survive-meshtastic"},
    "meshcore":   {"name": "MeshCore Web",    "port": PORT_MESHCORE,
                 "icon": "📶", "color": "#2ea0d8", "unit": "survive-meshcore"},
}

# ── Budget de contenu ─────────────────────────────────────────────────────────────
CONTENT_BUDGET_GB = 800  # taille totale cible du contenu, en Go

# ── Catégories de téléchargement (progression du tableau de bord) ───────────────────────────────
# IMPORTANT: each `id` MUST equal the first argument of the matching
# run_category call in download/download_all.sh — that literal string is what
# gets written to $STORAGE_PATH/.download_progress. A mismatch makes the
# category read as "pending" forever. `dir` is the storage subdir whose size is
# reported (must be a key produced by _compute_content_stats in server.py).
# NOTE on "dir": several libraries are delivered as Kiwix ZIMs, so their bytes
# live under zim/ and count toward the "kiwix" row — NOT their own row. The
# Gutenberg library (~207 GB) is a ZIM (zim/books/gutenberg_*.zim), so it is
# counted under "Wikipédia, Gutenberg et ZIM"; the separate "E-Books (EPUB)"
# row measures only the small curated EPUB folder (books/). Likewise Khan
# Academy now ships as a ZIM (zim/education/), counted under the kiwix row.
DOWNLOAD_CATEGORIES = [
    {"id": "kiwix",         "name": "Wikipédia, Gutenberg et ZIM", "budget_gb": 600, "dir": "zim"},
    {"id": "videos",        "name": "Vidéos de survie",    "budget_gb": 150, "dir": "videos"},
    {"id": "books",         "name": "Livres (EPUB)",        "budget_gb": 1,   "dir": "books"},
    {"id": "maps",          "name": "Cartes hors ligne",   "budget_gb": 70,  "dir": "maps"},
    {"id": "kolibri",       "name": "Khan Academy (Kolibri)", "budget_gb": 200, "dir": "kolibri"},
    {"id": "gaps",          "name": "Contenus d'experts",  "budget_gb": 15,  "dir": "pdfs"},
    {"id": "mental_health", "name": "Santé mentale",       "budget_gb": 5,   "dir": "pdfs"},
    {"id": "apps",          "name": "Dépôt d'applications", "budget_gb": 2,   "dir": "apps"},
    {"id": "drugs",         "name": "Référence médicaments", "budget_gb": 1,   "dir": "drugs"},
    {"id": "comms",         "name": "Outils de transmission", "budget_gb": 1,   "dir": "comms"},
]

# ── Catégories de connaissances ───────────────────────────────────────────────────────
# Static declarative data; used by server routes and templates to enumerate
# content areas. Each entry maps to a storage subdirectory (pdfs/, books/,
# videos/<id>/) and drives the category page and search-result grouping.
CATEGORIES = [
    # ── Survie de base ─────────────────────────────────────────
    {"id": "medical", "name": "Médecine et premiers secours", "icon": "🏥",
     "color": "#e74c3c", "desc": "Médecine d'urgence, premiers secours, TCCC, traumatismes"},
    {"id": "medicine_advanced", "name": "Médecine avancée", "icon": "🩺",
     "color": "#c0392b", "desc": "Chirurgie, obstétrique, soins dentaires et psychiatriques en milieu précaire"},
    {"id": "obstetrics", "name": "Accouchement et sage-femmerie", "icon": "👶",
     "color": "#e91e8c", "desc": "Accouchement d'urgence, sage-femmerie, suivi prénatal sans hôpital"},
    {"id": "dental", "name": "Urgences dentaires", "icon": "🦷",
     "color": "#9b59b6", "desc": "Extraction, abcès, soins sans dentiste"},
    {"id": "psychology", "name": "Santé mentale et psychologie de survie", "icon": "🧠",
     "color": "#8e44ad", "desc": "Premiers secours psychologiques, deuil, résilience, psychologie des catastrophes"},
    # ── Nourriture et eau ──────────────────────────────────────────
    {"id": "food", "name": "Nourriture et eau", "icon": "🌾",
     "color": "#27ae60", "desc": "Agriculture, cueillette, conservation des aliments, purification de l'eau"},
    {"id": "animal_husbandry", "name": "Élevage", "icon": "🐓",
     "color": "#2ecc71", "desc": "Poules, chèvres, bovins, lapins — santé, reproduction, abattage"},
    {"id": "seeds", "name": "Semences paysannes", "icon": "🌱",
     "color": "#1abc9c", "desc": "Conserver et multiplier des semences libres, de génération en génération"},
    {"id": "beeswax", "name": "Apiculture", "icon": "🐝",
     "color": "#f39c12", "desc": "Conduite des ruches, récolte du miel, cire, hydromel, prévention des maladies"},
    {"id": "fermentation", "name": "Fermentation et brassage", "icon": "🍺",
     "color": "#d35400", "desc": "Lactofermentation, bière, hydromel, vinaigre, fromage, teintures"},
    # ── Infrastructures ────────────────────────────────────────
    {"id": "shelter", "name": "Abri et construction", "icon": "🏠",
     "color": "#8e44ad", "desc": "Techniques de construction, maisons autonomes, chalets en rondins, vie hors réseau"},
    {"id": "sanitation", "name": "Assainissement et déchets", "icon": "🚽",
     "color": "#795548", "desc": "Toilettes sèches, compost humain, eaux grises, prévention des maladies"},
    {"id": "water_systems", "name": "Eau : puits et réseaux", "icon": "💧",
     "color": "#2980b9", "desc": "Puits creusés à la main, eau de pluie, filtration, distribution"},
    {"id": "energy", "name": "Énergie et électricité", "icon": "⚡",
     "color": "#f39c12", "desc": "Solaire, éolien, batteries, biogaz, groupes électrogènes"},
    # ── Savoir-faire et artisanat ───────────────────────────────────────
    {"id": "skills", "name": "Savoir-faire en pleine nature", "icon": "🪓",
     "color": "#16a085", "desc": "Feu, orientation, cueillette, pistage, construction d'abris"},
    {"id": "blacksmithing", "name": "Forge et travail du métal", "icon": "⚒️",
     "color": "#607d8b", "desc": "Construction de forge, fabrication d'outils, réparation, coutellerie"},
    {"id": "primitive_skills", "name": "Artisanat traditionnel", "icon": "🧵",
     "color": "#8d6e63", "desc": "Tannage, savon, bougies, fibres, métiers d'autrefois"},
    {"id": "tools", "name": "Outils et réparation", "icon": "🔧",
     "color": "#2980b9", "desc": "Guides iFixit, travail du bois, réparation mécanique"},
    {"id": "permaculture", "name": "Permaculture et forêt-jardin", "icon": "🌳",
     "color": "#4caf50", "desc": "Conception par zones, associations de plantes, forêt-jardin, aménagements hydrauliques"},
    # ── Transmissions et communauté ────────────────────────────
    {"id": "communication", "name": "Transmissions et radio", "icon": "📡",
     "color": "#c0392b", "desc": "Radioamateur, code Morse, programmation CHIRP, fréquences d'urgence"},
    {"id": "security", "name": "Sécurité et défense", "icon": "🛡️",
     "color": "#37474f", "desc": "Défense périmétrique, signaux manuels, sécurité collective"},
    {"id": "community", "name": "Communauté et vie sociale", "icon": "👥",
     "color": "#5c6bc0", "desc": "Gouvernance après effondrement, troc, résolution des conflits"},
    # ── Référence ─────────────────────────────────────────────
    {"id": "education", "name": "Éducation et sciences", "icon": "🔬",
     "color": "#2c3e50", "desc": "Khan Academy, sciences, mathématiques, ingénierie"},
    {"id": "reference", "name": "Référence et livres", "icon": "📚",
     "color": "#7f8c8d", "desc": "Wikipédia, bibliothèque Gutenberg, manuels"},
    {"id": "maps", "name": "Cartes et orientation", "icon": "🗺️",
     "color": "#d35400", "desc": "Cartes hors ligne, cartes topographiques, orientation"},
    {"id": "military", "name": "Manuels militaires", "icon": "⚔️",
     "color": "#2c3e50", "desc": "Survie militaire, manuels de terrain, TCCC"},
    {"id": "videos", "name": "Vidéos pratiques", "icon": "🎬",
     "color": "#8e44ad", "desc": "Vidéos pas à pas de survie et de savoir-faire"},
]
