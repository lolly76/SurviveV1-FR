# PLAN-federated-search : recherche indexée instantanée + résultats plein texte dans les articles

**Rang : n° 2.**

## Objectif

`/search` parcourt actuellement l'arborescence du stockage **à chaque requête** (jusqu'à
500 000 fichiers, plafonnés par `_MAX_FILES_CHECKED`) et ne compare que les noms de fichiers.
Sur un disque de 800 Go plein, connecté en USB, cela prend plusieurs secondes par requête,
consomme un créneau de la limite de 30/min en E/S, et ne trouve rien à l'intérieur des
articles.

Après ce changement :

1. Un **index SQLite FTS5** de tous les noms de fichiers est construit en arrière-plan et
   rafraîchi périodiquement → la recherche par nom répond en < 50 ms.
2. La page de résultats gagne une seconde section, **« Dans les articles »**, alimentée par le
   même point d'accès plein texte de Kiwix que PLAN-ai-rag.

Effet de levier : la recherche est la porte d'entrée d'une base de connaissances ; elle est
aujourd'hui la page la plus lente et la plus faible. Cela ouvre aussi la voie à un futur
filtrage par catégorie.

**Note de dépendance :** implémenter d'abord PLAN-ai-rag — réutiliser tel quel son
utilitaire `_kiwix_search()`. En cas d'exécution isolée de ce plan, copier l'étape 1 de
PLAN-ai-rag dans ce travail.

## Fichiers exacts à modifier

| Fichier | Changement |
|---------|------------|
| `web/server.py` | constructeur d'index + fonctions de requête ; réécrire la route `search()` |
| `web/templates/search.html` | deux sections de résultats ; pied de page de fraîcheur de l'index |
| `tests/test_smoke.sh` | assertions liées à l'index |
| `CLAUDE.md` | documenter le fichier d'index et la cadence de reconstruction |

## Ordre de mise en œuvre

1. **Emplacement de l'index** : `INDEX_DB = STORAGE_PATH / ".search_index.db"` (fichier caché,
   à côté de `.kiwix_library.xml`, exclu des parcours car `_safe_walk` ignore déjà les fichiers
   cachés).

2. **Schéma** (à créer avec le module standard `sqlite3`) :
   ```sql
   CREATE VIRTUAL TABLE IF NOT EXISTS files USING fts5(
       name, path UNINDEXED, ext UNINDEXED, size_mb UNINDEXED,
       tokenize = "unicode61 tokenchars '-'"
   );
   CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
   ```
   À l'insertion, stocker `name` avec les tirets bas et les points remplacés par des espaces
   (`re.sub(r"[_.]", " ", f.stem)`) pour que `Where_There_Is_No_Doctor` corresponde à la
   requête « doctor ». Conserver le nom de fichier d'origine dans `path`.

3. **`_rebuild_search_index()`** : parcourir avec le `_safe_walk(STORAGE_PATH)` existant,
   insérer par lots de 500 lignes par transaction dans un **échange de table temporaire** :
   construire dans `files_new`, puis `DROP TABLE files; ALTER TABLE files_new RENAME TO files;`
   dans une seule transaction pour que les lecteurs ne voient jamais un index à moitié
   construit. Enregistrer `meta['built_at'] = datetime.now().isoformat()` et `meta['count']`.
   Protéger les reconstructions concurrentes par un `threading.Lock` au niveau du module +
   `sqlite3.connect(..., timeout=30)`.

4. **Rafraîchissement en arrière-plan** : à l'import,
   `threading.Thread(target=_index_refresher, daemon=True).start()` au niveau du module, avec
   6 h d'attente entre reconstructions (boucle `time.sleep`), la première construction
   retardée de 60 s après le démarrage pour que le démarrage reste rapide. Reconstruire AUSSI
   à la demande quand `search()` constate que la base est absente.

5. **`_query_search_index(q, limit=50)`** : ouvrir une **connexion par appel** (les objets
   SQLite ne sont pas sûrs entre fils Flask). Assainir la requête FTS : retirer tous les
   caractères sauf `[a-zA-Z0-9 -]`, puis ajouter `*` au dernier mot pour la correspondance par
   préfixe. Requête :
   `SELECT name, path, ext, size_mb FROM files WHERE files MATCH ? LIMIT ?`.
   Sur `sqlite3.OperationalError` (syntaxe FTS invalide), renvoyer `[]`, jamais un 500.

6. **Réécrire la route `search()`** : essayer d'abord l'index ; si `INDEX_DB` n'existe pas, se
   replier sur la boucle `_safe_walk` actuelle (la garder — c'est le filet de sécurité de
   l'exactitude) et lancer une reconstruction en arrière-plan. Ajouter
   `article_results = _kiwix_search(query, limit=5)` pour la seconde section. Transmettre les
   deux listes plus `index_built_at` au modèle.

7. **`search.html`** : section un « Fichiers » (la grille de cartes existante), section deux
   « Dans les articles » — le titre renvoie vers
   `http://{{ request.host.split(':')[0] }}:{{ PORT_KIWIX }}{{ r.url }}`, afficher l'extrait
   avec `{{ r.snippet }}` (Jinja échappe automatiquement — NE PAS ajouter `|safe` ; les
   extraits de Kiwix contiennent des balises `<b>` qui doivent s'afficher comme du texte ou
   être retirées côté serveur avec la même regex que l'étape 2 de PLAN-ai-rag). Ligne de pied
   de page : « Index de {{ count }} fichiers, construit {{ built_at }} ».

## Cas limites qu'un modèle moins attentif manquerait

- **gunicorn lance 2 processus** (unité systemd) : les deux importent server.py et les deux
  démarreraient des fils de rafraîchissement et se disputeraient la reconstruction. L'échange
  de table temporaire + le verrou rendent cela sûr, mais ÉCHELONNER aussi : attendre
  `60 + (os.getpid() % 30)` s avant la première construction pour qu'ils n'entrent pas en
  collision au démarrage.
- **Affinité de fil de SQLite** : ne jamais réutiliser une connexion entre requêtes ;
  ouvrir/fermer à chaque appel (rapide avec SQLite) ou utiliser `threading.local()`.
- **Injection de syntaxe FTS5** : une saisie comme `water AND "` lève
  `OperationalError: fts5: syntax error` — l'assainissement de l'étape 5 est obligatoire, et
  la clause except est la seconde ligne de défense.
- **Index sur le disque de stockage** : si le disque est démonté, `STORAGE_PATH` se replie sur
  `repo/data` (voir le bloc de configuration de server.py) — le chemin de l'index suit
  automatiquement ; ne pas coder `/mnt/survive` en dur.
- **Index périmé** après un gros téléchargement : 6 h de péremption est acceptable, mais
  `scripts/update_content.sh` et `download/download_all.sh` doivent faire `rm -f
  "$STORAGE_PATH/.search_index.db"` à la fin pour que la recherche suivante déclenche une
  reconstruction (une ligne ajoutée à la fin du programme principal de chaque script).
- **`size_mb` à l'indexation ou au service** : des fichiers peuvent être supprimés après
  l'indexation ; `/serve/<path>` renvoie déjà proprement 404 — ne pas faire de `stat` sur les
  résultats au moment de la requête (cela réintroduirait les E/S que l'on a retirées).
- **Ne pas** indexer `.logs/`, les dossiers cachés, ni la base elle-même — `_safe_walk` exclut
  déjà les fichiers cachés ; le vérifier avec le test d'acceptation.

## Critères d'acceptation

1. Créer 1 000 faux fichiers
   (`mkdir -p /tmp/survive_test/pdfs && for i in $(seq 1000); do touch "/tmp/survive_test/pdfs/file_$i.pdf"; done`),
   démarrer le serveur, attendre l'index, puis :
   `time curl -s "localhost:18080/search?q=file" >/dev/null` se termine en **< 300 ms**
   (contre plusieurs secondes pour le parcours).
2. La recherche de `doctor` trouve un fichier nommé `Where_There_Is_No_Doctor_2021.pdf`.
3. `sqlite3 /tmp/survive_test/.search_index.db "SELECT count(*) FROM files"` correspond au
   nombre de fichiers créés.
4. Une requête `water AND "` (bombe de syntaxe FTS) renvoie HTTP 200 avec zéro résultat de
   fichier.
5. Supprimer le fichier de base, appeler `/search?q=x` → HTTP 200 via le repli par parcours, et
   la base réapparaît en moins de 2 minutes.
6. Tous les tests de fumée passent ; pylint ≥ 9,5.
