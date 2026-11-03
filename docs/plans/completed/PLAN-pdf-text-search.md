# PLAN-pdf-text-search : indexer le texte À L'INTÉRIEUR des PDF et EPUB pour la recherche et le RAG

**Rang : n° 1 — à faire en premier.** (Tour 2 ; les plans du tour 1 sont dans docs/plans/completed/)

## Objectif

Le contenu le plus soigneusement choisi du dépôt — ~20 Go de PDF de survie (Où il n'y a pas de
médecin, manuels de terrain militaires, guides Hesperian) plus la bibliothèque d'EPUB — est
invisible pour la recherche plein texte et pour l'IA. La section « Dans les articles » de
`/search` et la récupération RAG de `ai_chat()` n'interrogent **que Kiwix**, qui ne couvre que
les fichiers ZIM. Un utilisateur qui cherche « garrot » ne trouve rien dans le manuel TCCC posé
sur le disque, et l'IA ne peut pas le citer.

Après ce changement : un indexeur autonome extrait le texte de chaque PDF/EPUB dans une seconde
base FTS5 ; `/search` gagne une section « Dans vos documents » avec des extraits en
surbrillance et des liens ancrés sur la page ; `_retrieve_context()` fusionne les meilleurs
morceaux de documents avec les résultats de Kiwix afin que l'IA cite les vrais manuels de
terrain.

## Fichiers exacts à modifier

| Fichier | Changement |
|---------|------------|
| `scripts/index_documents.py` | NOUVEAU — extracteur/indexeur de morceaux autonome (bibliothèque standard + pdftotext) |
| `setup/install.sh` | ajouter `poppler-utils` à la liste des paquets apt |
| `web/server.py` | `_query_doc_index()`, fusion dans `search()` et `_retrieve_context()` |
| `web/templates/search.html` | troisième section de résultats avec extraits |
| `download/books_pdfs.sh`, `download/gaps_content.sh`, `download/mental_health.sh` | lancer l'indexeur après les téléchargements |
| `tests/test_smoke.sh` | assertion de recherche de documents sur un PDF texte créé pour l'occasion |
| `CLAUDE.md`, `docs/API.md` | documenter le second index |

## Ordre de mise en œuvre

1. **`scripts/index_documents.py`** (python3, bibliothèque standard seulement + binaire
   `pdftotext`) :
   - Base : `$STORAGE/.content_index.db` — distincte de `.search_index.db` pour que la lente
     construction du contenu ne bloque jamais l'échange rapide de l'index des noms de fichiers.
   - Schéma :
     ```sql
     CREATE VIRTUAL TABLE IF NOT EXISTS chunks USING fts5(
         text, path UNINDEXED, page UNINDEXED, title UNINDEXED);
     CREATE TABLE IF NOT EXISTS indexed_files(
         path TEXT PRIMARY KEY, mtime REAL, chunks INTEGER);
     ```
   - Parcourir `pdfs/` et `books/` (réutiliser la logique de `_safe_walk` — la copier ; le
     script ne doit PAS importer server.py, qui démarre des fils à l'import).
   - **Incrémental** : ignorer les fichiers dont `(path, mtime)` correspond à
     `indexed_files` ; supprimer les lignes périmées des fichiers modifiés ou disparus
     (`DELETE FROM chunks WHERE path = ?` avant de les rajouter).
   - Extraction PDF : `subprocess.run(["pdftotext", "-layout", path, "-"],
     capture_output=True, timeout=120)`. Les pages arrivent séparées par un saut de page `\f`
     — `stdout.split("\f")` donne gratuitement les numéros de page.
   - Extraction EPUB : `zipfile.ZipFile` → chaque membre `*.xhtml`/`*.html` → retirer les
     balises avec la même approche par regex que `_strip_html` de server.py. Numéro de page :
     utiliser plutôt l'indice dans l'ordre du « spine ».
   - Découpage : par page, couper en morceaux d'environ 1500 caractères aux limites de
     paragraphe ; `title` = nom de fichier sans extension avec `[_.]` → espace (même
     normalisation que l'index des noms de fichiers).
   - Tourner avec la sémantique de `nice -n 19` : appeler `os.nice(19)` au démarrage — une
     reconstruction complète prend plus d'une heure sur un Pi et ne doit pas priver Ollama ou
     le tableau de bord de ressources.
   - Ligne de commande : `--storage PATH` (par défaut la variable d'environnement
     `SURVIVE_STORAGE_PATH`, puis le motif survive.conf), `--rebuild` (tout supprimer d'abord).
     Afficher une ligne de bilan : `indexed N files, S chunks, skipped M unchanged`.

2. **`_query_doc_index(query, limit=5)` dans server.py** : même forme que
   `_query_search_index` — connexion sqlite par appel vers
   `STORAGE_PATH / ".content_index.db"`, même assainissement des mots (réutiliser la regex
   existante — la factoriser en `_fts_sanitize(query)` utilisée par les deux), requête :
   ```sql
   SELECT title, path, page, snippet(chunks, 0, '', '', '…', 12)
   FROM chunks WHERE chunks MATCH ? LIMIT ?
   ```
   REMARQUE : le premier argument de `snippet()` est le nom de la table FTS et l'indice de
   colonne 0 désigne `text`. Marqueurs d'ouverture/fermeture vides — la mise en évidence se
   fait sans injecter de HTML. Renvoie `[{title, path, page, snippet}]` ; `None` si la base est
   absente ; `[]` sur OperationalError (reprendre exactement le contrat de l'index des noms de
   fichiers).

3. **Route `search()`** : ajouter `doc_results = _query_doc_index(query) or []` et le passer au
   modèle.

4. **`_retrieve_context()`** : après la recherche Kiwix, appeler
   `_query_doc_index(query, limit=2)` ; ajouter les résultats sous la forme
   `{"title": f"{title} (p.{page})", "path": None, "snippet": snippet,
   "text": snippet}`. **Budget de contexte** : garder le total à 3 articles Kiwix × 2000
   caractères ; quand des morceaux de documents sont présents, utiliser 2 Kiwix × 2000 + 2
   morceaux × ~1500 — toujours sous le budget de ~7,5k caractères pour `num_ctx 4096`. Les
   sources des résultats de documents doivent renvoyer vers `/serve/<path>#page=N` (les
   visionneuses PDF des navigateurs respectent `#page=`) ; adapter `_sources_for` pour
   utiliser une clé `url` préconstruite quand `path` vaut None.

5. **`search.html`** : troisième section « Dans vos documents » — lien
   `/serve/{{ d.path }}#page={{ d.page }}`, titre + pastille `p.{{ d.page }}` + extrait
   (échappement automatique de Jinja, pas de `|safe`).

6. **Scripts de téléchargement** : ajouter
   `command -v pdftotext >/dev/null && python3 "$REPO_DIR/scripts/index_documents.py" --storage "$STORAGE_PATH" || true`
   à la fin de `main()` dans les trois scripts qui récupèrent des PDF/EPUB.

## Cas limites qu'un modèle moins attentif manquerait

- **Ne PAS importer server.py depuis l'indexeur** — l'importer démarre le fil démon de
  rafraîchissement de l'index et instancie Flask ; l'indexeur doit être un script autonome
  (copier les deux petits utilitaires dont il a besoin).
- **PDF numérisés/images** : pdftotext renvoie un texte vide — les enregistrer quand même dans
  `indexed_files` avec `chunks=0`, sinon ils seront réanalysés à chaque exécution pour
  toujours. (L'OCR est explicitement hors périmètre.)
- **PDF chiffrés** : pdftotext sort avec un code non nul — intercepter, enregistrer, ignorer.
  Ne jamais laisser un seul mauvais fichier tuer l'exécution (`try/except` par fichier,
  journaliser et continuer).
- **Délai de `subprocess`** : un PDF mal formé de 500 Mo peut bloquer poppler ; le délai de
  120 s + le try/except par fichier sont porteurs.
- **Arguments de `snippet()` en FTS5** : l'indice de colonne (0) ne compte que les vraies
  colonnes de la table FTS ; les colonnes UNINDEXED comptent quand même dans l'ordre — le
  texte est la colonne 0 ici car déclaré en premier. Se tromper renvoie des fragments de
  chemin en guise d'« extraits ».
- **Octets NUL** : la sortie de pdftotext peut contenir `\x00`, que le TEXT de sqlite refuse
  au milieu d'une chaîne avec certains pilotes — `text.replace("\x00", "")` avant l'insertion.
- **L'indexeur tourne en root depuis les scripts de téléchargement** mais le serveur tourne en
  `pi` sous systemd — `chmod 644` la base (ou chown pi) après la construction, sinon le
  tableau de bord obtient `sqlite3.OperationalError: unable to open database file`
  uniquement en production.
- **Les ancres `#page=N`** fonctionnent dans les visionneuses intégrées de Chromium/Firefox
  mais pas dans toutes ; le lien doit quand même ouvrir le PDF sans l'ancre — il se dégrade
  proprement par construction, mais ne pas faire de 404 quand page vaut None (EPUB).
- **Interaction du budget de contexte avec PLAN-chat-memory** (tour 2, n° 2) : si les deux
  sont livrés, historique + RAG doivent se partager le budget `num_ctx` — les extraits RAG ont
  la priorité ; rogner d'abord l'historique.

## Critères d'acceptation

1. Générer un PDF d'exemple dans l'environnement de test (pas besoin de poppler pour le
   *créer*) : `python3 -c "..."` écrivant un PDF minimal d'une page contenant la chaîne
   littérale `zzyzxtourniquet` (un mot à l'abri de toute collision), le placer sous
   `/tmp/survive_test/pdfs/`, lancer
   `python3 scripts/index_documents.py --storage /tmp/survive_test`.
   Alors `curl "localhost:18080/search?q=zzyzxtourniquet"` renvoie HTTP 200 et le corps
   contient le nom du fichier PDF et `p.1`.
2. Relancer l'indexeur affiche `skipped 1 unchanged` et se termine en < 1 s.
3. `_query_doc_index('water AND "')` renvoie `[]`, pas une exception.
4. Avec un Kiwix simulé + un index de documents créé pour l'occasion, POST `/api/ai/chat` a
   des sources incluant une entrée dont l'url contient `/serve/` et `#page=`.
5. Tous les tests de fumée passent ; pylint ≥ 9,5 sur server.py ; l'indexeur lui-même passe
   `pylint scripts/index_documents.py --fail-under=7.0` avec les désactivations standard du
   dépôt.
