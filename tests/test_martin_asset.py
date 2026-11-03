"""Choix de l'archive Martin dans la liste des versions GitHub."""
import importlib.util
from pathlib import Path

_spec = importlib.util.spec_from_file_location(
    "pick_martin_asset", Path(__file__).parent.parent / "scripts" / "pick_martin_asset.py")
pick_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pick_mod)


def _rel(tag, names, pre=False, draft=False):
    return {"tag_name": tag, "prerelease": pre, "draft": draft,
            "assets": [{"name": n, "browser_download_url": f"https://x/{tag}/{n}"} for n in names]}


GNU_A = "martin-aarch64-unknown-linux-gnu.tar.gz"
FULL_A = "martin-aarch64-unknown-linux-gnu-full.tar.gz"
GNU_X = "martin-x86_64-unknown-linux-gnu.tar.gz"


def test_skips_latest_without_binaries():
    """Cas réel : la version la plus récente n'a aucun fichier joint."""
    rels = [_rel("martin-v1.16.0", []), _rel("mbtiles-v0.21.2", [GNU_A]),
            _rel("martin-v1.15.0", [FULL_A, GNU_A])]
    assert pick_mod.pick(rels, "aarch64") == f"https://x/martin-v1.15.0/{GNU_A}"


def test_ignores_other_components_and_full_builds():
    rels = [_rel("mbtiles-v0.21.2", [GNU_A]), _rel("martin-v1.0.0", [FULL_A])]
    assert pick_mod.pick(rels, "aarch64") is None


def test_prefers_stable_over_prerelease():
    rels = [_rel("martin-v2.0.0-beta.5", [GNU_A], pre=True), _rel("martin-v1.15.0", [GNU_A])]
    assert pick_mod.pick(rels, "aarch64").endswith("martin-v1.15.0/" + GNU_A)


def test_prerelease_as_last_resort_and_arch_alias():
    rels = [_rel("martin-v2.0.0-beta.5", [GNU_A, GNU_X], pre=True)]
    assert pick_mod.pick(rels, "x86_64").endswith(GNU_X)
    assert pick_mod.pick(rels, "arm64").endswith(GNU_A)
