#!/usr/bin/env python3
"""
SurviveV1-FR — Récupération lente et reprenable des notices officielles (BDPM).

Pour chaque spécialité du fichier CIS_bdpm.txt (Base de données publique des
médicaments, ANSM/HAS/UNCAM), télécharge la page « RCP / notice » du site
https://base-donnees-publique.medicaments.gouv.fr et en extrait les rubriques
utiles hors ligne : indications, posologie, contre-indications, mises en garde,
interactions. Le résultat est écrit dans $STORAGE/drugs/notices/<CIS>.json.

Bonnes manières (le site ne publie pas de flux de masse pour ces textes) :
  - identification claire (User-Agent), une seule requête à la fois ;
  - pause entre deux requêtes (SURVIVE_DRUGS_NOTICE_DELAY, 3 s par défaut) ;
  - reprise : les CIS déjà traités ne sont jamais redemandés ;
  - arrêt propre après plusieurs échecs consécutifs ou sur 429/403 répétés ;
  - SURVIVE_DRUGS_NOTICE_MAX limite le nombre de pages par exécution (0 = tout).

Les textes ne sont PAS modifiés (licence ouverte : ne pas altérer les données) :
on ne fait que découper la page en rubriques.

Usage :
    python3 scripts/fetch_drug_notices.py [--storage /mnt/survive] [--max N] [--delay S]
"""

import argparse
import html
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

BASE_URL = "https://base-donnees-publique.medicaments.gouv.fr/affichageDoc.php"
USER_AGENT = ("SurviveV1-FR/1.0 (base de connaissances hors ligne personnelle; "
              "https://github.com/lolly76/SurviveV1-FR)")
FIELD_CAP = 30_000
MAX_CONSECUTIVE_FAILURES = 5

_BLOCK_TAGS = {"p", "div", "br", "li", "tr", "h1", "h2", "h3", "h4", "h5", "h6",
               "section", "article", "table", "ul", "ol", "dt", "dd"}
_SKIP_TAGS = {"script", "style", "noscript", "head", "nav", "footer", "form",
              "button", "select"}


class _TextExtractor(HTMLParser):
    """HTML -> lignes de texte (les balises de bloc deviennent des sauts de ligne)."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.parts: list = []
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        if tag in _SKIP_TAGS:
            self._skip += 1
        elif tag in _BLOCK_TAGS:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in _SKIP_TAGS:
            self._skip = max(0, self._skip - 1)
        elif tag in _BLOCK_TAGS:
            self.parts.append("\n")

    def handle_data(self, data):
        if not self._skip:
            self.parts.append(data)


def html_to_lines(raw_html: str) -> list:
    """Texte de la page, une ligne par bloc, espaces normalisés, lignes vides retirées."""
    parser = _TextExtractor()
    parser.feed(raw_html)
    text = html.unescape("".join(parser.parts)).replace("\xa0", " ")
    lines = [re.sub(r"[ \t]+", " ", ln).strip() for ln in text.splitlines()]
    return [ln for ln in lines if ln]


# Rubriques du RCP (résumé des caractéristiques du produit) : numéros normalisés
# au niveau européen, donc stables d'une spécialité à l'autre.
_RCP_SECTIONS = {
    "indications": re.compile(r"^4\s*\.\s*1\s*\.?\s*indications?\s+th[ée]rapeutiques?", re.I),
    "dosage": re.compile(r"^4\s*\.\s*2\s*\.?\s*posologie", re.I),
    "contraindications": re.compile(r"^4\s*\.\s*3\s*\.?\s*contre-?\s*indications?", re.I),
    "warnings": re.compile(r"^4\s*\.\s*4\s*\.?\s*mises?\s+en\s+garde", re.I),
    "interactions": re.compile(r"^4\s*\.\s*5\s*\.?\s*interactions?", re.I),
}
# Fin d'une rubrique RCP : la rubrique 4.x suivante ou la rubrique 5.
# Le point est obligatoire après un numéro de rubrique principal : sans lui,
# une ligne de corps comme « 5 mg/kg » ou « 10 comprimés » couperait la rubrique.
_RCP_NEXT = re.compile(r"^(4\s*\.\s*[1-9]\s*\.?|(?:5|6|7|8|9|10|11|12)\s*\.)\s+\S", re.I)

# Repli sur la notice destinée aux patients (rubriques 1, 2, 3).
_NOTICE_SECTIONS = {
    "indications": re.compile(r"^1\s*\.\s*(qu.est-ce\s+que|what\s+is)", re.I),
    "warnings": re.compile(r"^2\s*\.\s*(quelles\s+sont\s+les\s+informations|"
                           r"informations\s+[àa]\s+conna[iî]tre)", re.I),
    "dosage": re.compile(r"^3\s*\.\s*comment\s+(prendre|utiliser)", re.I),
}
_NOTICE_NEXT = re.compile(r"^[1-6]\s*\.\s*[A-ZÉÈÀÂÊÎÔÛÇ]{3}")


def _collect(lines: list, start_re, end_re) -> str:
    """Meilleure occurrence (la plus longue) d'une rubrique : texte entre son titre et le titre suivant.

    Une table des matières répète les titres sans corps : garder la plus longue
    occurrence évite de prendre la table des matières pour la rubrique.
    """
    best = ""
    for i, line in enumerate(lines):
        if not start_re.match(line):
            continue
        body = []
        for nxt in lines[i + 1:]:
            if end_re.match(nxt):
                break
            body.append(nxt)
        text = "\n".join(body).strip()
        if len(text) > len(best):
            best = text
    return best[:FIELD_CAP]


def parse_notice_html(raw_html: str) -> dict:
    """Découpe une page BDPM en rubriques. Clés : indications, dosage,
    contraindications, warnings, interactions (chaînes vides si absentes) et
    'origine' : 'rcp', 'notice' ou '' selon ce qui a été trouvé."""
    lines = html_to_lines(raw_html)
    out = {k: "" for k in ("indications", "dosage", "contraindications",
                           "warnings", "interactions")}
    for key, start in _RCP_SECTIONS.items():
        out[key] = _collect(lines, start, _RCP_NEXT)
    origine = "rcp" if any(out.values()) else ""
    if not origine:
        for key, start in _NOTICE_SECTIONS.items():
            out[key] = _collect(lines, start, _NOTICE_NEXT)
        origine = "notice" if any(out.values()) else ""
    out["origine"] = origine
    return out


def default_storage() -> str:
    """SURVIVE_STORAGE_PATH, puis survive.conf, puis /mnt/survive."""
    env = os.environ.get("SURVIVE_STORAGE_PATH")
    if env:
        return env
    conf = Path(__file__).resolve().parent.parent / "config" / "survive.conf"
    try:
        for line in conf.read_text(encoding="utf-8").splitlines():
            m = re.match(r'\s*SURVIVE_STORAGE_PATH="?([^"#]+)"?\s*$', line)
            if m:
                return m.group(1).strip()
    except OSError:
        pass
    return "/mnt/survive"


def read_bdpm(path: Path):
    """Lit un fichier BDPM (TSV). Encodage : UTF-8 si valide, sinon Windows-1252 (encodage réel des fichiers BDPM, vérifié : octets 0x80-0x9F présents)."""
    data = path.read_bytes()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("cp1252", errors="replace")
    for line in text.splitlines():
        if line.strip():
            yield line.split("\t")


def cis_in_priority_order(raw_dir: Path) -> list:
    """CIS des spécialités à autorisation active : d'abord celles sans condition de
    prescription (accessibles sans ordonnance, les plus utiles en autonomie), puis le reste."""
    cpd = set()
    cpd_file = raw_dir / "CIS_CPD_bdpm.txt"
    if cpd_file.exists():
        cpd = {row[0] for row in read_bdpm(cpd_file) if len(row) >= 2}
    free, rest = [], []
    for row in read_bdpm(raw_dir / "CIS_bdpm.txt"):
        if len(row) < 7 or not row[0].isdigit():
            continue
        if "active" not in row[4].lower():
            continue
        (rest if row[0] in cpd else free).append(row[0])
    return free + rest


def fetch_one(cis: str, timeout: int = 60):
    """(statut_http, html|None). Ne lève pas pour les erreurs HTTP."""
    url = f"{BASE_URL}?specid={cis}&typedoc=R"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT,
                                               "Accept-Language": "fr"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as exc:
        return exc.code, None
    except (urllib.error.URLError, TimeoutError, OSError):
        return 0, None


def run(storage: str, max_pages: int, delay: float) -> int:
    raw_dir = Path(storage) / "drugs" / "raw"
    out_dir = Path(storage) / "drugs" / "notices"
    if not (raw_dir / "CIS_bdpm.txt").exists():
        print("[MÉDICAMENTS] CIS_bdpm.txt absent — lancez download/drug_reference.sh")
        return 0
    out_dir.mkdir(parents=True, exist_ok=True)
    todo = [c for c in cis_in_priority_order(raw_dir) if not (out_dir / f"{c}.json").exists()]
    if max_pages > 0:
        todo = todo[:max_pages]
    print(f"[MÉDICAMENTS] {len(todo)} notice(s) à récupérer (pause {delay:g} s entre deux requêtes)")

    done = failures = 0
    for cis in todo:
        status, page = fetch_one(cis)
        if status == 200 and page:
            rec = parse_notice_html(page)
            rec["cis"] = cis
            rec["recupere_le"] = time.strftime("%Y-%m-%d")
            tmp = out_dir / f"{cis}.json.tmp"
            tmp.write_text(json.dumps(rec, ensure_ascii=False), encoding="utf-8")
            os.replace(tmp, out_dir / f"{cis}.json")
            done += 1
            failures = 0
        elif status == 404:
            # Pas de page pour cette spécialité : marqueur vide, on ne redemande pas.
            (out_dir / f"{cis}.json").write_text(
                json.dumps({"cis": cis, "origine": ""}), encoding="utf-8")
            failures = 0
        else:
            failures += 1
            print(f"[MÉDICAMENTS] CIS {cis} : échec (HTTP {status or 'réseau'}), "
                  f"{failures}/{MAX_CONSECUTIVE_FAILURES}")
            if failures >= MAX_CONSECUTIVE_FAILURES:
                print("[MÉDICAMENTS] Trop d'échecs consécutifs — arrêt (relancez plus tard, "
                      "la reprise est automatique).")
                break
            time.sleep(delay * (2 ** failures))  # recul exponentiel
            continue
        if done and done % 100 == 0:
            print(f"[MÉDICAMENTS] {done} notices récupérées…")
        time.sleep(delay)
    print(f"[MÉDICAMENTS] Terminé : {done} notice(s) récupérée(s) lors de cette exécution.")
    return done


def main() -> int:
    parser = argparse.ArgumentParser(description="Récupère lentement les notices BDPM.")
    parser.add_argument("--storage", default=default_storage())
    parser.add_argument("--max", type=int,
                        default=int(os.environ.get("SURVIVE_DRUGS_NOTICE_MAX", "0") or 0))
    parser.add_argument("--delay", type=float,
                        default=float(os.environ.get("SURVIVE_DRUGS_NOTICE_DELAY", "3") or 3))
    args = parser.parse_args()
    try:
        os.nice(19)
    except (AttributeError, OSError):
        pass
    run(args.storage, args.max, max(args.delay, 1.0))
    return 0


if __name__ == "__main__":
    sys.exit(main())
