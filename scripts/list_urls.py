#!/usr/bin/env python3
"""Liste les URL http(s) réelles écrites dans les scripts de téléchargement.

Utilisé par .github/workflows/url-health.yml. Ignore les adresses factices
(variables shell, localhost, réseau local, exemples).
Utilisation : python3 scripts/list_urls.py download setup sync scripts config
"""
import re
import sys
from pathlib import Path

URL = re.compile(r"""https?://[^\s"'`<>()\\\[\]{}|;,]+""")
SKIP = re.compile(r"\$|localhost|127\.0\.0\.1|10\.42\.|\.local\b|exemple\.fr")


def urls_in(root: Path):
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix in {".png", ".svg", ".ico", ".gz", ".zim"}:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for match in URL.findall(text):
            url = match.rstrip(".:;!?*")
            if SKIP.search(url) or re.fullmatch(r"https?://[^/]*", url):
                continue
            yield url


def main() -> int:
    found = set()
    for arg in sys.argv[1:] or ["."]:
        root = Path(arg)
        if root.exists():
            found.update(urls_in(root))
    print("\n".join(sorted(found)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
