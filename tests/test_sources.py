"""La section « Sources utilisées » du README doit refléter les scripts de téléchargement."""
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GEN = os.path.join(ROOT, "scripts", "gen_sources.py")


def test_readme_sources_a_jour():
    res = subprocess.run([sys.executable, GEN, "--check"], capture_output=True, text=True, check=False)
    assert res.returncode == 0, res.stderr


def test_sources_sans_variable_shell():
    out = subprocess.run([sys.executable, GEN], capture_output=True, text=True, check=True).stdout
    assert "${" not in out and "$vol" not in out


def test_sources_contient_les_urls_des_scripts():
    out = subprocess.run([sys.executable, GEN], capture_output=True, text=True, check=True).stdout
    for must in ("download.kiwix.org", "geofabrik.de", "base-donnees-publique.medicaments.gouv.fr",
                 "hesperian.org", "youtube.com", "ollama.com", "docs/licenses.md"):
        assert must in out, must
    assert len(re.findall(r"https?://", out)) > 150


def test_sources_zim_et_phase2():
    out = subprocess.run([sys.executable, GEN], capture_output=True, text=True, check=True).stdout
    for must in ("wikipedia_fr_all_maxi", "ted_mul_science", "zimgit-knots_en",
                 "wikipedia_en_all_nopic", "gutenberg_en_all", "mdwiki_en_all_maxi",
                 "khanacademy_en_all", "CONTENT_BASE_EN"):
        assert must in out, must
    assert out.count("| `") >= 30
