# PLAN-unit-tests : suite pytest pour la logique pure du serveur

**Rang : n° 5.**

## Objectif

L'assurance qualité se résume à 23 assertions de fumée « boîte noire » contre un serveur en
marche — excellentes pour les contrats de routes, aveugles à la logique qui porte désormais le
plus de risque : assainissement des requêtes FTS, budget du prompt RAG, analyse XML des
réponses de Kiwix, calcul de l'état des téléchargements, retrait des codes ANSI, validation de
l'historique (une fois PLAN-chat-memory livré). Chaque fonctionnalité récente a été vérifiée à
la main avec des scripts ad hoc ensuite jetés ; ce plan transforme ces bancs d'essai jetables
en suite `pytest` permanente, branchée sur la CI.

## Fichiers exacts à modifier

| Fichier | Changement |
|---------|------------|
| `tests/test_server_unit.py` | NOUVEAU — la suite |
| `tests/conftest.py` | NOUVEAU — environnement + fixture d'import |
| `requirements-dev.txt` | NOUVEAU — `pytest`, `pylint` |
| `.github/workflows/test.yml` | lancer pytest dans le job `python` |
| `Makefile` | cible `unit` ; `test` devient lint + unit + smoke |
| `CLAUDE.md` | mise à jour de la section des commandes de test |

## Ordre de mise en œuvre

1. **`tests/conftest.py`** — le problème d'import est toute l'astuce :
   `web/server.py` lit `SURVIVE_STORAGE_PATH` **à l'import** et démarre un fil de
   rafraîchissement en arrière-plan dès l'import. Donc :
   ```python
   import os, sys, pytest
   from pathlib import Path

   @pytest.fixture(scope="session")
   def server(tmp_path_factory):
       storage = tmp_path_factory.mktemp("storage")
       os.environ["SURVIVE_STORAGE_PATH"] = str(storage)
       sys.path.insert(0, str(Path(__file__).parent.parent / "web"))
       import server as srv          # le premier import se fait ICI, après la définition de l'environnement
       return srv
   ```
   Le fil de rafraîchissement dort plus de 60 s avant sa première construction : il est donc
   inerte pendant toute la durée des tests — ne pas chercher à le tuer, simplement ne pas
   l'attendre. Portée « session » : un seul import ; recharger le module à chaque test refait
   l'enregistrement des routes Flask et échoue avec « View function mapping is overwriting ».

2. **`tests/test_server_unit.py`** — regroupé par fonctionnalité, ~25 tests :
   - `_strip_html` : balises retirées, contenu de script/style supprimé, espaces réduits,
     balises `<b>` de surbrillance de Kiwix retirées.
   - `_kiwix_path` : URL absolue → chemin+fragment ; chemin déjà relatif inchangé ;
     entrée vide/None.
   - `_build_rag_prompt` : aucun article → contient le message d'absence d'articles de
     référence ; avec articles → lignes numérotées `[1]`, `[2]` et phrase de consigne.
   - Entrées de `_fts_sanitize`/`_query_search_index` : bombe de syntaxe `water AND "`,
     unicode, chaîne vide, entrée de 200 caractères — via un vrai
     `_rebuild_search_index()` sur des fichiers créés dans le stockage temporaire
     (5 fichiers dont `Where_There_Is_No_Doctor.pdf`), puis vérifier que « doctor » trouve,
     que le préfixe `doct` trouve et que la bombe renvoie `[]`.
   - `_index_meta` : base absente → `{built_at: None, count: 0}` ; après reconstruction →
     nombre correct.
   - `_compute_download_status` : pas de fichier de progression → tout en attente ; écrire
     `kiwix\n` + une ligne inconnue `garbage\n` → kiwix terminé, garbage ignoré ; fin de
     journal pleine de codes ANSI nettoyée (reprendre les octets exacts de la session de
     débogage du tour 1) ; journal > 500 octets → seule la fin est lue (construire un journal
     de 10 Ko).
   - `_sources_for` : substitution de l'hôte.
   - Client de test Flask (`server.app.test_client()`) : traversée de chemin du type
     `/serve/../../etc/passwd` → 403/404, `/health` → 200, `/api/ai/chat` avec un mauvais
     content-type → 415, mauvais nom de modèle `../evil` → 400. (Ni Ollama ni Kiwix
     nécessaires — tout se joue avant le flux.)
   - Regex du nom de modèle : paramétrer les valides (`survive`, `gemma4:12b`, `a.b-c_d:1`) et
     les invalides (`a/b`, 101 caractères, vide, `a b`).
3. **`requirements-dev.txt`** : `pytest>=7`, `pylint>=3`. La CI installe
   `-r requirements.txt -r requirements-dev.txt`.
4. **CI** : dans le job `python`, après pylint, ajouter
   `python -m pytest tests/ -q --tb=short`. pytest ignore `test_smoke.sh` automatiquement
   (ce n'est pas un fichier .py).
5. **Makefile** : `unit: ; python3 -m pytest tests/ -q` et enchaîner
   `test: lint unit smoke`.

## Cas limites qu'un modèle moins attentif manquerait

- **Piège de l'ordre d'import** : importer `server` en haut du fichier de test s'exécute avant
  la fixture d'environnement — chaque test indexe alors le vrai `/mnt/survive` du développeur
  ou le dossier `data/` du dépôt. L'import différé dans la fixture est la seule raison d'être
  de conftest.py. Ne jamais faire `from server import X` au niveau du module.
- **Un seul import par session** : `importlib.reload(server)` réenregistre les routes sur le
  même objet Flask → `AssertionError: View function mapping...`. Fixture à portée session,
  pas à portée fonction.
- **Le fil de rafraîchissement et tmp_path** : pytest supprime les dossiers temporaires en fin
  de session ; si l'exécution dépasse ~60 s, la première construction du fil vise un dossier
  encore existant (sans conséquence), mais ne jamais vérifier des fichiers que le fil peut
  créer — les tests ne doivent pas courir contre lui. Garder la suite sous la minute (elle
  durera ~5 s).
- **Pollution de `_TTLCache` entre tests** : `_downloads_cache` mémorise pendant 15 s — les
  tests qui modifient `.download_progress` doivent appeler directement la fonction de
  *calcul* (`_compute_download_status()`), jamais l'enveloppe en cache. Idem pour les
  statistiques de contenu (TTL 60 s) : créer tous les fichiers AVANT le premier appel, ou
  appeler `_compute_content_stats` directement.
- **CRLF de style Windows dans les fichiers de progression** : `read_text().splitlines()`
  gère `\r\n` ; écrire une entrée avec `\r\n` dans le test pour verrouiller ce comportement.
- **La CI n'a pas de commande `sqlite3`** (découvert au tour 1) — toutes les vérifications de
  base passent par le module Python `sqlite3`, jamais par `subprocess`.

## Critères d'acceptation

1. `python3 -m pytest tests/ -q` → tout passe, < 30 s, aucun accès réseau (le vérifier une
   fois Wi-Fi coupé / dans le bac à sable de la CI).
2. `make test` enchaîne lint → unit → smoke et se termine avec le code 0.
3. Le workflow de CI montre l'étape pytest au vert sur la branche.
4. Supprimer le corps de `_ANSI_RE.sub` (contrôle par mutation) fait échouer au moins un
   test — c'est-à-dire que la suite protège réellement le retrait des codes ANSI.
5. Les tests de fumée existants restent intacts et au vert (23/23).
