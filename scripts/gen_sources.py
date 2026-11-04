#!/usr/bin/env python3
"""Génère la section « Sources utilisées » du README à partir des scripts de téléchargement.

Usage :
    python3 scripts/gen_sources.py            # affiche le bloc Markdown
    python3 scripts/gen_sources.py --write    # met à jour README.md entre les repères
    python3 scripts/gen_sources.py --check    # code 1 si README.md n'est pas à jour

La liste est construite depuis download/*.sh (appels dl_file, dl_who, dl_channel,
dl_playlist, download_zim, tableaux associatifs, entrées « URL|fichier ») : ajouter une
source dans un script la fait apparaître ici, et tests/test_sources.py échoue tant que
le README n'a pas été régénéré (--write). Les éléments qui ne passent pas par ces appels
(outils installés, cartes, BDPM…) sont décrits dans la table STATIC ci-dessous.
"""
import glob
import os
import re
import sys
from urllib.parse import unquote, urlparse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BEGIN = "<!-- SOURCES:BEGIN (généré par scripts/gen_sources.py — ne pas modifier à la main) -->"
END = "<!-- SOURCES:END -->"

Q = r'"((?:[^"\\]|\\.)*)"'

GAPS_TITLES = {
    "dl_advanced_medicine": "Médecine avancée et en milieu isolé",
    "dl_obstetrics": "Obstétrique",
    "dl_dental": "Soins dentaires",
    "dl_mental_health": "Santé mentale",
    "dl_sanitation": "Assainissement",
    "dl_animal_husbandry": "Élevage",
    "dl_seed_saving": "Semences",
    "dl_beekeeping": "Apiculture",
    "dl_blacksmithing": "Forge",
    "dl_primitive_skills": "Savoir-faire traditionnels",
    "dl_fermentation_brewing": "Fermentation et brassage",
    "dl_permaculture": "Permaculture et agroforesterie",
    "dl_water_systems": "Eau",
    "dl_security": "Sécurité",
    "dl_community_economics": "Résilience communautaire",
    "dl_morse_radio": "Morse et radio",
    "dl_hesperian_bundle": "Hesperian (lot)",
    "dl_peace_corps_library": "Bibliothèque technique du Peace Corps",
}
BOOKS_EN_TITLES = {
    "en_dl_military_manuals": "Manuels militaires américains",
    "en_dl_medical_refs": "Références médicales",
    "en_dl_agriculture": "Agriculture et alimentation",
    "en_dl_engineering": "Ingénierie et construction",
    "en_dl_radio": "Radioamateur et communications",
    "en_dl_homesteading": "Vie autonome et bricolage",
    "en_dl_standard_ebooks": "Livres du domaine public (anglais)",
}
MENTAL_TITLES = {
    "dl_pfa": "Premiers secours psychologiques (français)",
    "en_dl_pfa": "Premiers secours psychologiques (anglais)",
    "en_dl_disaster_psych": "Psychologie des catastrophes (anglais)",
    "en_dl_resilience": "Résilience (anglais)",
    "en_dl_grief": "Deuil (anglais)",
}
VIDEO_TITLES = {
    "survival": "Survie et bushcraft", "medical": "Médical et premiers secours",
    "food": "Alimentation et potager", "farming": "Culture et permaculture",
    "shelter": "Habitat", "energy": "Énergie", "tools": "Outils et bricolage",
    "skills": "Savoir-faire", "preparedness": "Radio et préparation",
    "animal_husbandry": "Élevage", "water": "Eau",
}
ZIM_FLAGS = {
    "dl_wikipedia": "`CONTENT_WIKIPEDIA` / `CONTENT_WIKIPEDIA_NOPIC`",
    "dl_wikibooks": "`CONTENT_WIKIBOOKS`",
    "dl_ifix": "`CONTENT_IFIX`",
    "dl_stackexchange": "`CONTENT_STACKEXCHANGE`",
    "dl_gutenberg": "`CONTENT_GUTENBERG`",
    "dl_khan": "`CONTENT_KHAN_ZIM`",
    "dl_medical": "toujours",
    "dl_ted": "toujours",
    "dl_expansion": "`CONTENT_EXPANSION`",
    "dl_expansion_en": "`CONTENT_EXPANSION_EN` (pack English, désactivé par défaut)",
}

# Sources qui ne passent pas par les appels analysés ci-dessus.
STATIC = """\
### Cartes (`download/maps.sh`)

- [OpenStreetMap — extraits Geofabrik](https://download.geofabrik.de/) : France (par défaut), Europe, Amérique du Nord, Amérique du Sud, Afrique, Asie, Australie-Océanie, États-Unis et Nouvelle-Angleterre ; [planète entière](https://planet.openstreetmap.org/) en option (`MAP_REGION`).
- [Protomaps — builds de tuiles vectorielles](https://maps.protomaps.com/builds/) (`build.protomaps.com`), extraites avec la commande `pmtiles` ([protomaps/go-pmtiles](https://github.com/protomaps/go-pmtiles)).
- [Protomaps — polices et sprites des cartes](https://protomaps.github.io/basemaps-assets) (`maps/fonts`, `maps/sprites`).
- [Tuiles satellite basse résolution (IIAB)](https://download.iiab.io/content/OSM/vector-tiles/) — surcouche satellite z0–z6.
- [USGS — The National Map](https://apps.nationalmap.gov/downloader/) (API `tnmaccess.nationalmap.gov`, index `prd-tnm.s3.amazonaws.com`) — cartes topographiques américaines, `CONTENT_NPS_MAPS`.
- [npmaps.com](https://npmaps.com/) — cartes PDF des parcs nationaux américains (`CONTENT_NPS_MAPS`, désactivé par défaut).
- [IGN — Géoservices](https://geoservices.ign.fr/telechargement) : non téléchargé automatiquement, mémo de téléchargement manuel.

### Cours et éducation

- [Kolibri — chaîne « Khan Academy (Français) »](https://studio.learningequality.org/) (identifiant `878ec2e6f88c5c268b1be6f202833cd4`), importée depuis Learning Equality (`download/kolibri_content.sh`).
- Kiwix : Khan Academy FR, TED, PhET, Wikiversité, Vikidia (voir « Bibliothèques Kiwix »).

### Médicaments

- [Base de données publique des médicaments (BDPM)](https://base-donnees-publique.medicaments.gouv.fr/) — ministère de la Santé / ANSM : fichiers de base (`download/file/…`) et notices officielles (RCP) récupérées une à une (`download/drug_reference.sh`, `scripts/build_drug_index.py`, `scripts/fetch_drug_notices.py`).

### Transmissions radio (`download/comms.sh`)

- [Meshtastic Web](https://github.com/meshtastic/web) — client web (`releases/latest/download/build.tar`), servi sur le port 8084.
- [MeshCore](https://files.liamcottle.net/MeshCore) — client web et applications Android / Windows (fichiers de Liam Cottle), port 8085.
- Relais radioamateurs : **non inclus** ; vous importez vos propres exports CSV (par exemple RepeaterBook) dans `comms/repeaters/`.

### Dépôt d'applications hors ligne (`download/app_depot.sh`)

- [Kiwix Android](https://download.kiwix.org/release/kiwix-android/) et [Kiwix Desktop](https://download.kiwix.org/release/kiwix-desktop/) (dernières versions du miroir).
- [F-Droid](https://f-droid.org/) (`F-Droid.apk`).
- [VLC pour Windows](https://get.videolan.org/vlc/last/win64/).
- MeshCore Android / Windows (voir « Transmissions radio »).

### Logiciels installés (`setup/`, `ai/`, `requirements.txt`)

- **Système :** paquets Debian / Raspberry Pi OS (git, curl, wget, aria2, rsync, python3, ffmpeg, vlc, nginx, sqlite3, zstd, p7zip, poppler-utils, ufw, jq, avahi, samba, ntfs-3g, exfatprogs, rclone, chrony, fuse3, calibre) ; paquet `hailo-all` du dépôt Raspberry Pi OS pour l'AI Hat.
- **Kiwix :** [kiwix-tools](https://download.kiwix.org/release/kiwix-tools/) (paquet Debian, sinon binaire du projet Kiwix).
- **Intelligence artificielle :** [Ollama](https://ollama.com/) (script d'installation officiel `ollama.ai/install.sh`) et modèles de sa bibliothèque : `gemma4:e2b`, `gemma4:e4b`, `gemma4:12b`, `gemma3:4b`, `gemma3:12b-it-q4_K_M` selon la RAM.
- **Apprentissage :** [Kolibri](https://learningequality.org/kolibri/) (PyPI).
- **Livres :** [Calibre](https://calibre-ebook.com/) (`download.calibre-ebook.com`) et [Calibre-Web](https://github.com/janeczku/calibre-web) (PyPI `calibreweb`).
- **Vidéos :** [Jellyfin](https://jellyfin.org/) (dépôt `repo.jellyfin.org`) et [yt-dlp](https://github.com/yt-dlp/yt-dlp) (GitHub).
- **Cartes :** serveur de tuiles [Martin](https://github.com/maplibre/martin) (versions GitHub `maplibre/martin`) ; bibliothèques intégrées à `web/static/vendor/` : MapLibre GL JS, PMTiles, `@protomaps/basemaps` (licences dans le même dossier).
- **Tableau de bord :** Flask, Flask-WTF, Flask-Limiter, gunicorn, requests, tqdm, PyYAML (voir `requirements.txt`).

### Listes personnelles (aucune source par défaut)

- `config/gaps_extra.list`, `config/pdfs_extra.list`, `config/mental_health_extra.list`, `config/videos_extra.list` : vos propres documents et chaînes, déclarés ligne par ligne.
"""


def _read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
        return re.sub(r"\\\n\s*", " ", fh.read())


def _who_url(handle):
    return f"https://iris.who.int/handle/{handle}"


def _expand(url, bases):
    """Remplace ${H}/${W} par leur valeur ; renvoie None s'il reste une variable."""
    for k, v in bases.items():
        url = url.replace("${" + k + "}", v)
    return None if "$" in url else url


def _entries():
    """(script, fonction, appel, nom, url) pour chaque source déclarée dans download/*.sh."""
    out = []
    for path in sorted(glob.glob(os.path.join(ROOT, "download", "*.sh"))):
        rel = os.path.relpath(path, ROOT)
        if rel.endswith("download_all.sh"):
            continue
        func = ""
        bases = {}
        for line in _read(rel).split("\n"):
            m = re.match(r'^\s*local ([HW])="([^"]+)"', line)
            if m:
                bases[m.group(1)] = m.group(2)
            m = re.match(r"^(\w+)\(\)\s*\{", line)
            if m:
                func = m.group(1)
            m = re.search(r"\b(dl_file|download_zim)\s+" + Q + r"\s+" + Q, line)
            if m and not m.group(2).startswith("$"):
                url = _expand(m.group(3), bases)
                if url:
                    out.append((rel, func, m.group(1), m.group(2), url))
                continue
            m = re.search(r"\bdl_who\s+" + Q + r"\s+" + Q, line)
            if m and not m.group(1).startswith("$"):
                out.append((rel, func, "dl_who", m.group(1), _who_url(m.group(2))))
                continue
            m = re.search(r"\b(dl_channel|dl_playlist)\s+" + Q + r"\s+" + Q + r"\s+" + Q, line)
            if m and not m.group(3).startswith("$"):
                out.append((rel, func, m.group(1) + ":" + m.group(2), m.group(3), m.group(4)))
                continue
            m = re.search(r'\["([^"]+)"\]="(https?://[^"$]+)"', line)
            if m:
                out.append((rel, func, "array", m.group(1), m.group(2)))
                continue
            m = re.search(r'"(https://www\.gutenberg\.org/ebooks/\d+[^"|]*)\|([^"]+)"', line)
            if m:
                out.append((rel, func, "epub", m.group(2), m.group(1)))
    return out


def _fmt_book(name):
    name = name.rsplit(".", 1)[0].replace("_", " — ", 1).replace("-", " ").replace("_", " ")
    return name.strip()


def _link(label, url):
    label = label.replace("[", "(").replace("]", ")")
    return f"[{label}]({url.replace(' ', '%20')})"


def _zim_prefix(url):
    base = os.path.basename(unquote(urlparse(url).path))
    return re.sub(r"_\d{4}-\d{2}\.zim$", "", base)


def build():  # pylint: disable=too-many-locals,too-many-branches,too-many-statements
    entries = _entries()
    lines = [BEGIN, "", "## Sources utilisées", ""]
    lines += [
        "Liste générée depuis les scripts de téléchargement : chaque ligne est une ressource que "
        "SurviveV1-FR peut récupérer. Rien n'est stocké dans ce dépôt ; les contenus gardent leur "
        "licence d'origine (voir [`docs/licenses.md`](docs/licenses.md)). Les noms de fichiers "
        "Kiwix perdent leur date : c'est toujours la dernière version publiée qui est téléchargée. "
        "**Pack English** = ressource sans équivalent français vérifié, conservée en anglais.",
        "",
    ]

    # --- Kiwix
    lines += ["### Bibliothèques Kiwix (ZIM) — [download.kiwix.org](https://download.kiwix.org/zim/)", "",
              "| Ressource | Fichier ZIM | Activation |", "|---|---|---|"]
    for rel, func, kind, name, url in entries:
        if rel.endswith("kiwix_content.sh") and kind in ("download_zim", "array"):
            if kind == "array" and "stackexchange" not in url:
                continue
            flag = ZIM_FLAGS.get(func, "")
            if kind == "array":
                name = f"Stack Exchange — {name}"
                flag = "`CONTENT_STACKEXCHANGE_EN` (pack English, désactivé par défaut)"
            lines.append(f"| {name} | `{_zim_prefix(url)}` | {flag} |")
    lines.append("")

    # --- Livres et PDF
    lines += ["### Livres et PDF (`download/books_pdfs.sh`)", "", "**En français**", ""]
    seen = set()
    for rel, func, kind, name, url in entries:
        if rel.endswith("books_pdfs.sh") and not func.startswith("en_") and kind in ("dl_file", "epub"):
            label = _fmt_book(name) if kind == "epub" else name
            lines.append(f"- {_link(label, url)}")
    lines += ["", "**Pack English** (`CONTENT_PDFS_EN`, désactivé par défaut)", ""]
    for func, title in BOOKS_EN_TITLES.items():
        items = [(k, n, u) for rel, f, k, n, u in entries
                 if rel.endswith("books_pdfs.sh") and f == func and k in ("dl_file", "epub")]
        if not items:
            continue
        lines.append(f"- *{title}* : " + " · ".join(
            _link(_fmt_book(n) if k == "epub" else n, u) for k, n, u in items))
    lines.append("")

    # --- Contenus experts
    lines += ["### Contenus experts — pack English (`download/gaps_content.sh`, `CONTENT_GAPS_EN`)", ""]
    for func, title in GAPS_TITLES.items():
        docs, vids = [], []
        for rel, f, kind, name, url in entries:
            if not (rel.endswith("gaps_content.sh") and f == func):
                continue
            if kind.startswith("dl_channel") or kind.startswith("dl_playlist"):
                vids.append(_link(name, url))
            elif kind in ("dl_file", "dl_who", "array"):
                docs.append(_link(name, url))
        if func == "dl_blacksmithing":
            docs = [_link("Practical Blacksmithing, vol. 1 à 4 (Richardson)",
                          "https://archive.org/details/practicalblacksmithing01rich")] + docs
        if not (docs or vids):
            continue
        txt = f"- *{title}* : " + " · ".join(docs)
        if vids:
            txt += (" — vidéos : " if docs else "vidéos : ") + " · ".join(vids)
        lines.append(txt)
    lines.append("")

    # --- Santé mentale
    lines += ["### Santé mentale (`download/mental_health.sh`)", ""]
    for func, title in MENTAL_TITLES.items():
        items = [_link(n, u) for rel, f, k, n, u in entries
                 if rel.endswith("mental_health.sh") and f == func and k in ("dl_file", "dl_who")]
        if items:
            suffix = "" if func == "dl_pfa" else " *(pack English, `CONTENT_MENTAL_EN`)*"
            lines.append(f"- *{title}*{suffix} : " + " · ".join(items))
    lines.append("")

    # --- Vidéos
    lines += ["### Vidéos (`download/videos.sh`, téléchargées avec yt-dlp)", ""]
    for pack, prefix, header in (("fr", "dl_", "**En français**"),
                                 ("en", "en_dl_", "**Pack English** (`CONTENT_VIDEOS_EN`, désactivé par défaut)")):
        lines += [header, ""]
        cats = {}
        for rel, func, kind, name, url in entries:
            if not rel.endswith("videos.sh") or not kind.startswith(("dl_channel", "dl_playlist")):
                continue
            is_en = func.startswith("en_")
            if (pack == "en") != is_en:
                continue
            cat = kind.split(":", 1)[1]
            cats.setdefault(cat, []).append(_link(name, url))
        for cat, items in cats.items():
            lines.append(f"- *{VIDEO_TITLES.get(cat, cat)}* : " + " · ".join(items))
        lines.append("")
    del prefix  # pylint: disable=undefined-loop-variable

    lines.append(STATIC.rstrip())
    lines += ["", END]
    return "\n".join(lines) + "\n"


def _splice(readme, block):
    if BEGIN in readme and END in readme:
        head = readme.split(BEGIN)[0]
        tail = readme.split(END, 1)[1]
        return head + block.rstrip("\n") + tail
    marker = "## Licence"
    idx = readme.index(marker)
    return readme[:idx] + block + "\n---\n\n" + readme[idx:]


def main(argv):
    block = build()
    readme_path = os.path.join(ROOT, "README.md")
    if "--write" in argv or "--check" in argv:
        with open(readme_path, encoding="utf-8") as fh:
            current = fh.read()
        updated = _splice(current, block)
        if "--check" in argv:
            if updated != current:
                print("README.md n'est pas à jour : lancez  python3 scripts/gen_sources.py --write",
                      file=sys.stderr)
                return 1
            return 0
        with open(readme_path, "w", encoding="utf-8") as fh:
            fh.write(updated)
        print("README.md mis à jour")
        return 0
    sys.stdout.write(block)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
