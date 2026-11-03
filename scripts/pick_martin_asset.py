#!/usr/bin/env python3
"""Choisit l'archive binaire de Martin adaptée à l'architecture.

Lit sur l'entrée standard la réponse JSON de
https://api.github.com/repos/maplibre/martin/releases et affiche l'URL de
l'archive .tar.gz Linux correspondant à l'architecture donnée.

Pourquoi ne pas utiliser /releases/latest : le dépôt publie aussi des versions
d'autres composants (mbtiles, martin-core…) et la version « latest » peut être
un tag sans aucun binaire (constaté : martin-v1.16.0, 0 fichier joint). On
parcourt donc les versions, on garde celles dont le tag commence par « martin-v »
et qui ont une archive pour cette architecture, en préférant les versions
stables aux préversions.

Utilisation : curl -s .../releases?per_page=50 | python3 pick_martin_asset.py aarch64
Code de sortie 1 (rien affiché) si aucune archive ne convient.
"""
import json
import re
import sys


def pick(releases, arch: str):
    """URL de l'archive, ou None. `arch` : sortie de `uname -m`."""
    arch = {"arm64": "aarch64", "amd64": "x86_64"}.get(arch, arch)
    want = re.compile(rf"^martin-{re.escape(arch)}-unknown-linux-gnu\.tar\.gz$")
    stable, pre = None, None
    for rel in releases:
        if rel.get("draft") or not str(rel.get("tag_name", "")).startswith("martin-v"):
            continue
        for asset in rel.get("assets", []):
            if want.match(asset.get("name", "")):
                url = asset.get("browser_download_url")
                if rel.get("prerelease"):
                    pre = pre or url
                else:
                    stable = stable or url
                break
        if stable:
            break
    return stable or pre


def main() -> int:
    try:
        releases = json.load(sys.stdin)
    except json.JSONDecodeError:
        return 1
    if not isinstance(releases, list):  # p. ex. limite de requêtes GitHub atteinte
        return 1
    url = pick(releases, sys.argv[1] if len(sys.argv) > 1 else "aarch64")
    if not url:
        return 1
    print(url)
    return 0


if __name__ == "__main__":
    sys.exit(main())
