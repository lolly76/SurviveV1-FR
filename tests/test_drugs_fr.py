"""Tests de la référence des médicaments BDPM (données synthétiques, aucun accès réseau)."""
import importlib.util
import json
import sqlite3
import sys
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent / "scripts"


def _load(name):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


build_drug_index = _load("build_drug_index")
fetch_drug_notices = _load("fetch_drug_notices")

PAGE = """<html><head><title>x</title><script>var a=1;</script></head><body>
<nav>Accueil Glossaire</nav>
<h3>DOLIPRANE 1000 mg, comprimé</h3>
<p>1. DENOMINATION DU MEDICAMENT</p>
<p>4.1. Indications thérapeutiques</p><p>4.2. Posologie et mode d'administration</p>
<h5>4.1. Indications thérapeutiques</h5>
<p>Traitement symptomatique des douleurs d'intensité légère à modérée et/ou de la fièvre.</p>
<h5>4.2. Posologie et mode d'administration</h5>
<p>Adulte et enfant de plus de 50 kg : 1 comprimé, 3 fois par jour.</p>
<h5>4.3. Contre-indications</h5>
<p>Hypersensibilité au paracétamol.</p>
<h5>4.4. Mises en garde spéciales et précautions d'emploi</h5>
<p>Ne pas dépasser 3 g par jour sans avis médical.</p>
<h5>4.5. Interactions avec d'autres médicaments</h5>
<p>Warfarine : surveillance de l'INR.</p>
<h5>4.6. Fertilité, grossesse et allaitement</h5>
<p>Utilisable.</p>
</body></html>"""

NOTICE_ONLY = """<body><p>Que contient cette notice ?</p>
<p>1. QU'EST-CE QUE X ET DANS QUELS CAS EST-IL UTILISE ?</p><p>Contre la douleur.</p>
<p>2. QUELLES SONT LES INFORMATIONS A CONNAITRE AVANT DE PRENDRE X ?</p><p>Ne pas prendre si allergie.</p>
<p>3. COMMENT PRENDRE X ?</p><p>1 comprimé par jour.</p>
<p>4. QUELS SONT LES EFFETS INDESIRABLES EVENTUELS ?</p><p>Rares.</p></body>"""


def test_parse_rcp_sections():
    rec = fetch_drug_notices.parse_notice_html(PAGE)
    assert rec["origine"] == "rcp"
    assert "fièvre" in rec["indications"]
    assert "3 fois par jour" in rec["dosage"]
    assert "Hypersensibilité" in rec["contraindications"]
    assert "3 g par jour" in rec["warnings"]
    assert "INR" in rec["interactions"]
    assert "Utilisable" not in rec["interactions"]   # s'arrête à la rubrique 4.6
    assert "var a" not in rec["indications"]         # scripts ignorés


def test_parse_notice_fallback():
    rec = fetch_drug_notices.parse_notice_html(NOTICE_ONLY)
    assert rec["origine"] == "notice"
    assert "douleur" in rec["indications"]
    assert "allergie" in rec["warnings"]
    assert "1 comprimé" in rec["dosage"]
    assert "Rares" not in rec["dosage"]


def test_parse_empty_page():
    assert fetch_drug_notices.parse_notice_html("<html><body>Rien</body></html>")["origine"] == ""


def _write_bdpm(storage: Path, encoding="utf-8"):
    raw = storage / "drugs" / "raw"
    raw.mkdir(parents=True)
    spec = [
        "60234100\tDOLIPRANE 1000 mg, comprimé\tcomprimé\torale\tAutorisation active\tProcédure nationale"
        "\tCommercialisée\t01/01/2000\t\t\tSANOFI\tNon",
        "60000001\tCODOLIPRANE, comprimé\tcomprimé\torale\tAutorisation active\tProcédure nationale"
        "\tCommercialisée\t01/01/2001\t\t\tSANOFI\tNon",
        "60000002\tRETIRE 5 mg\tgélule\torale\tAutorisation abrogée\tProcédure nationale"
        "\tNon commercialisée\t01/01/2001\t\t\tX\tNon",
    ]
    compo = [
        "60234100\tcomprimé\t02202\tPARACÉTAMOL\t1000 mg\tun comprimé\tSA\t1",
        "60234100\tcomprimé\t99999\tEXCIPIENT\t5 mg\tun comprimé\tFT\t1",
        "60000001\tcomprimé\t02202\tPARACÉTAMOL\t400 mg\tun comprimé\tSA\t1",
        "60000001\tcomprimé\t01234\tCODÉINE\t20 mg\tun comprimé\tSA\t2",
    ]
    cpd = ["60000001\tliste I"]
    (raw / "CIS_bdpm.txt").write_bytes("\n".join(spec).encode(encoding))
    (raw / "CIS_COMPO_bdpm.txt").write_bytes("\n".join(compo).encode(encoding))
    (raw / "CIS_CPD_bdpm.txt").write_bytes("\n".join(cpd).encode(encoding))
    (raw / "BDPM_DATE").write_text("29/09/2026", encoding="utf-8")
    notices = storage / "drugs" / "notices"
    notices.mkdir()
    (notices / "60234100.json").write_text(json.dumps(
        {"cis": "60234100", "origine": "rcp", "indications": "Douleurs et fièvre.",
         "dosage": "1 comprimé", "contraindications": "", "warnings": "", "interactions": "Warfarine"},
        ensure_ascii=False), encoding="utf-8")


def test_build_index(tmp_path):
    _write_bdpm(tmp_path)
    assert build_drug_index.build(str(tmp_path)) == 2   # l'AMM abrogée est exclue
    conn = sqlite3.connect(tmp_path / ".drug_index.db")
    conn.row_factory = sqlite3.Row
    doli = conn.execute("SELECT * FROM drugs WHERE cis='60234100'").fetchone()
    assert doli["generic_name"] == "paracétamol"
    assert "1000 mg" in doli["active_ingredient"] and "EXCIPIENT" not in doli["active_ingredient"]
    assert doli["otc_or_rx"] == "Sans ordonnance"
    assert doli["source_date"] == "29/09/2026"
    assert "orale" in doli["purpose"]
    codo = conn.execute("SELECT * FROM drugs WHERE cis='60000001'").fetchone()
    assert codo["otc_or_rx"] == "Sur ordonnance"
    assert codo["generic_name"] == "paracétamol + codéine"
    # Recherche sans accent (FTS5 unicode61) et par symptôme.
    hit = conn.execute("SELECT rowid FROM drug_names WHERE drug_names MATCH 'paracetamol'").fetchall()
    assert len(hit) == 2
    hit = conn.execute("SELECT rowid FROM drug_uses WHERE drug_uses MATCH 'fievre'").fetchall()
    assert len(hit) == 1
    conn.close()


def test_build_index_cp1252(tmp_path):
    _write_bdpm(tmp_path, encoding="cp1252")
    assert build_drug_index.build(str(tmp_path)) == 2


def test_priority_order_free_first(tmp_path):
    _write_bdpm(tmp_path)
    order = fetch_drug_notices.cis_in_priority_order(tmp_path / "drugs" / "raw")
    assert order == ["60234100", "60000001"]   # sans ordonnance d'abord, abrogé exclu


def test_detail_page_shows_attribution_and_date(server, tmp_path):
    import re
    import shutil
    _write_bdpm(tmp_path)
    build_drug_index.build(str(tmp_path))
    shutil.copy(tmp_path / ".drug_index.db", server.DRUG_INDEX_DB)
    try:
        c = server.app.test_client()
        page = c.get("/drugs").get_data(as_text=True)
        token = re.search(r'name="csrf_token" value="([^"]+)"', page).group(1)
        c.post("/drugs/disclaimer", data={"csrf_token": token, "next": "/drugs"})
        found = server._query_drug_index("paracetamol")
        assert len(found) == 2
        cis_row = [d for d in found if d["brand_name"].startswith("DOLIPRANE")][0]
        html = c.get(f"/drugs/{cis_row['id']}").get_data(as_text=True)
        assert "Base de données publique des médicaments" in html
        assert "29/09/2026" in html
        assert "Douleurs et fièvre" in html
        listing = c.get("/drugs?q=paracetamol").get_data(as_text=True)
        assert "29/09/2026" in listing
        inter = c.get(f"/api/drugs/interactions?a={cis_row['id']}&b=warfarine").get_json()
        assert inter["a_label_mentions_b"] is True
    finally:
        server.DRUG_INDEX_DB.unlink(missing_ok=True)


def test_rcp_section_not_cut_by_numeric_body_line():
    """Une ligne de corps commençant par un nombre ne doit pas fermer la rubrique."""
    from fetch_drug_notices import parse_notice_html
    html = ("<p>4.2. Posologie et mode d'administration </p>"
            "<p>10 comprimés par jour au maximum.</p><p>5 mg/kg chez l'enfant.</p>"
            "<p>4.3. Contre-indications </p><p>Allergie.</p>"
            "<p>5. PROPRIETES PHARMACOLOGIQUES</p><p>Autre.</p>")
    out = parse_notice_html(html)
    assert "10 comprimés" in out["dosage"] and "5 mg/kg" in out["dosage"]
    assert out["contraindications"] == "Allergie."
