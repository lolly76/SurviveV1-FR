"""Tests des profils de contenu (apply_profile.sh) et du profil conseillé (recommend_profile.sh)."""
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
APPLY = ROOT / "scripts" / "apply_profile.sh"
RECO = ROOT / "scripts" / "recommend_profile.sh"
PROFILES = ["leger", "moyen", "complet"]


def _conf(path):
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r'^([A-Z_]+)="(.*)"$', line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def _apply(profile, conf):
    return subprocess.run(["bash", str(APPLY), profile, str(conf)], capture_output=True, text=True, check=False)


@pytest.mark.parametrize("profile", PROFILES)
def test_profiles_define_the_same_keys(profile):
    ref = set(_conf(ROOT / "config/profiles/complet.conf"))
    assert set(_conf(ROOT / f"config/profiles/{profile}.conf")) == ref


def test_apply_overwrites_and_keeps_other_lines(tmp_path):
    conf = tmp_path / "survive.conf"
    conf.write_text('SURVIVE_HOSTNAME="mabox"\nCONTENT_KOLIBRI="Y"\nSURVIVE_BUDGET_GB="800"\n', encoding="utf-8")
    assert _apply("leger", conf).returncode == 0
    c = _conf(conf)
    assert c["SURVIVE_HOSTNAME"] == "mabox"          # ligne étrangère conservée
    assert c["CONTENT_KOLIBRI"] == "N"               # remplacée
    assert c["SURVIVE_BUDGET_GB"] == "60"
    assert c["CONTENT_WIKIPEDIA_NOPIC"] == "Y"       # ajoutée
    assert conf.read_text(encoding="utf-8").count("CONTENT_KOLIBRI=") == 1


def test_apply_is_idempotent(tmp_path):
    conf = tmp_path / "survive.conf"
    _apply("moyen", conf)
    first = conf.read_text(encoding="utf-8")
    _apply("moyen", conf)
    assert conf.read_text(encoding="utf-8") == first


def test_apply_rejects_unknown_profile(tmp_path):
    res = _apply("../etc/passwd", tmp_path / "x.conf")
    assert res.returncode == 2


def test_light_profile_is_lighter_than_full():
    assert _conf(ROOT / "config/profiles/leger.conf")["CONTENT_VIDEOS"] == "N"
    assert _conf(ROOT / "config/profiles/complet.conf")["CONTENT_VIDEOS"] == "Y"


@pytest.mark.parametrize("args,expected", [
    (["1000"], "complet"), (["500"], "moyen"), (["120"], "leger"), (["30"], "insuffisant"),
    (["100", "--systeme"], "leger"),       # 100 - 20 de marge = 80
    (["95", "--systeme"], "insuffisant"),  # 95 - 20 = 75
    (["1000", "--systeme"], "moyen"),      # marge de 15 % : 850 Go < 900
])
def test_recommend(args, expected):
    out = subprocess.run(["bash", str(RECO), *args], capture_output=True, text=True, check=False).stdout.strip()
    assert out == expected


def test_recommend_rejects_garbage():
    assert subprocess.run(["bash", str(RECO), "abc"], capture_output=True, check=False).returncode == 2
