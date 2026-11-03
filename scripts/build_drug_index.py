#!/usr/bin/env python3
"""
SurviveV1-FR — Index hors ligne de la référence des médicaments (BDPM).

Construit $STORAGE/.drug_index.db (SQLite FTS5) à partir de :
  - $STORAGE/drugs/raw/CIS_bdpm.txt, CIS_COMPO_bdpm.txt, CIS_CPD_bdpm.txt
    (Base de données publique des médicaments — ANSM, HAS, UNCAM, licence ouverte) ;
  - $STORAGE/drugs/notices/<CIS>.json (rubriques extraites des RCP/notices par
    scripts/fetch_drug_notices.py ; facultatif, l'index fonctionne sans).

Les données ne sont pas modifiées ; la source et la date de mise à jour sont
conservées dans chaque ligne (colonnes source_date et cis) pour l'affichage.

Le schéma garde les colonnes historiques (brand_name, generic_name, purpose,
indications…) pour que le tableau de bord n'ait pas à changer de requêtes :
  brand_name        dénomination de la spécialité
  generic_name      substance(s) active(s)
  active_ingredient substance(s) active(s) avec dosage
  purpose           forme pharmaceutique et voie(s) d'administration
  indications / dosage / contraindications / warnings / interactions
                    rubriques 4.1 à 4.5 du RCP (ou de la notice à défaut)
  otc_or_rx         « Sur ordonnance » ou « Sans ordonnance »
  effective_time    date d'AMM

Usage :
    python3 scripts/build_drug_index.py [--storage /mnt/survive]
"""

import argparse
import json
import os
import re
import sqlite3
from pathlib import Path

FIELD_CAP = 30_000

# Nature de prescription : tout ce qui n'est pas « sans condition » est vendu sur ordonnance.
_RX_RE = re.compile(r"liste\s+(i|ii)\b|stup[ée]fiant|prescription|ordonnance|r[ée]serv", re.I)


def default_storage() -> str:
    """SURVIVE_STORAGE_PATH l'emporte ; puis survive.conf ; puis /mnt/survive."""
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
    """Lignes d'un fichier BDPM (TSV). UTF-8 si valide, sinon ISO-8859-1."""
    data = path.read_bytes()
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        text = data.decode("latin-1")
    for line in text.splitlines():
        if line.strip():
            yield line.split("\t")


def _col(row: list, idx: int) -> str:
    return row[idx].strip() if len(row) > idx else ""


def _create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE drugs (
            id INTEGER PRIMARY KEY,
            brand_name TEXT, generic_name TEXT, active_ingredient TEXT,
            purpose TEXT, indications TEXT, warnings TEXT, dosage TEXT,
            contraindications TEXT, interactions TEXT,
            otc_or_rx TEXT, effective_time TEXT,
            cis TEXT, titulaire TEXT, conditions TEXT, source_date TEXT,
            notice_origin TEXT
        );
        -- Tables FTS5 à contenu externe (content=drugs) : pas de texte dupliqué.
        -- drug_names : recherche par médicament ; drug_uses : par symptôme.
        CREATE VIRTUAL TABLE drug_names USING fts5(
            brand_name, generic_name, active_ingredient,
            content='drugs', content_rowid='id');
        CREATE VIRTUAL TABLE drug_uses USING fts5(
            purpose, indications,
            content='drugs', content_rowid='id');
        """
    )


def _compositions(raw_dir: Path) -> dict:
    """CIS -> (substances, substances avec dosage). Seuls les composants « SA » (substance active)."""
    comp: dict = {}
    path = raw_dir / "CIS_COMPO_bdpm.txt"
    if not path.exists():
        return comp
    for row in read_bdpm(path):
        # 0 CIS, 1 élément pharmaceutique, 2 code substance, 3 dénomination,
        # 4 dosage, 5 référence de dosage, 6 nature (SA/FT), 7 n° de liaison
        if len(row) < 7 or _col(row, 6) != "SA":
            continue
        name, dose, ref = _col(row, 3), _col(row, 4), _col(row, 5)
        entry = comp.setdefault(row[0], ([], []))
        if name and name not in entry[0]:
            entry[0].append(name)
        label = name + (f" {dose}" if dose else "") + (f" ({ref})" if ref and dose else "")
        if label and label not in entry[1]:
            entry[1].append(label)
    return comp


def _conditions(raw_dir: Path) -> dict:
    cpd: dict = {}
    path = raw_dir / "CIS_CPD_bdpm.txt"
    if path.exists():
        for row in read_bdpm(path):
            if len(row) >= 2:
                cpd.setdefault(row[0], []).append(row[1].strip())
    return cpd


def _notice(notices_dir: Path, cis: str) -> dict:
    try:
        return json.loads((notices_dir / f"{cis}.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _source_date(raw_dir: Path) -> str:
    try:
        return (raw_dir / "BDPM_DATE").read_text(encoding="utf-8").strip()
    except OSError:
        return ""


def build(storage: str) -> int:
    raw_dir = Path(storage) / "drugs" / "raw"
    notices_dir = Path(storage) / "drugs" / "notices"
    spec_file = raw_dir / "CIS_bdpm.txt"
    if not spec_file.exists():
        print(f"[MÉDICAMENTS] CIS_bdpm.txt introuvable dans {raw_dir} — "
              "lancez download/drug_reference.sh")
        return 0

    db_path = Path(storage) / ".drug_index.db"
    tmp_path = db_path.with_suffix(".db.new")
    tmp_path.unlink(missing_ok=True)
    conn = sqlite3.connect(str(tmp_path))
    _create_schema(conn)

    comp = _compositions(raw_dir)
    cpd = _conditions(raw_dir)
    source_date = _source_date(raw_dir)

    rows = []
    for row in read_bdpm(spec_file):
        # 0 CIS, 1 dénomination, 2 forme, 3 voies (;), 4 statut AMM, 5 procédure,
        # 6 commercialisation, 7 date AMM, 8 statut BDM, 9 n° autorisation UE,
        # 10 titulaire(s), 11 surveillance renforcée
        if len(row) < 8 or not row[0].isdigit():
            continue
        if "active" not in _col(row, 4).lower():
            continue  # AMM abrogée, retirée, etc. : hors de l'index
        cis = row[0]
        substances, doses = comp.get(cis, ([], []))
        forme = _col(row, 2)
        voies = _col(row, 3).replace(";", ", ")
        purpose = forme + (f" · voie {voies}" if voies else "")
        notice = _notice(notices_dir, cis)
        conditions = " ; ".join(cpd.get(cis, []))
        rx = "Sur ordonnance" if _RX_RE.search(conditions) else "Sans ordonnance"
        rows.append((
            _col(row, 1), " + ".join(substances).lower(), "\n".join(doses), purpose,
            (notice.get("indications") or "")[:FIELD_CAP],
            (notice.get("warnings") or "")[:FIELD_CAP],
            (notice.get("dosage") or "")[:FIELD_CAP],
            (notice.get("contraindications") or "")[:FIELD_CAP],
            (notice.get("interactions") or "")[:FIELD_CAP],
            rx, _col(row, 7), cis, _col(row, 10).replace(";", ", "), conditions,
            source_date, notice.get("origine", ""),
        ))

    conn.executemany(
        "INSERT INTO drugs (brand_name, generic_name, active_ingredient, purpose, "
        "indications, warnings, dosage, contraindications, interactions, otc_or_rx, "
        "effective_time, cis, titulaire, conditions, source_date, notice_origin) "
        "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)", rows)
    conn.execute(
        "INSERT INTO drug_names(rowid, brand_name, generic_name, active_ingredient) "
        "SELECT id, brand_name, generic_name, active_ingredient FROM drugs")
    conn.execute(
        "INSERT INTO drug_uses(rowid, purpose, indications) "
        "SELECT id, purpose, indications FROM drugs")
    conn.commit()
    with_text = conn.execute(
        "SELECT COUNT(*) FROM drugs WHERE indications != '' OR dosage != ''").fetchone()[0]
    conn.close()

    os.replace(tmp_path, db_path)  # échange atomique : le tableau de bord ne lit jamais un index à moitié fait
    print(f"[MÉDICAMENTS] {len(rows)} spécialités indexées, dont {with_text} avec texte de notice "
          f"({db_path.stat().st_size // (1024 * 1024)} Mo)")
    return len(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description="Construit l'index hors ligne des médicaments.")
    parser.add_argument("--storage", default=default_storage())
    args = parser.parse_args()
    try:
        os.nice(19)
    except (AttributeError, OSError):
        pass
    build(args.storage)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
