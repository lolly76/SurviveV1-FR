# PLAN-download-visibility : afficher la progression des téléchargements dans le tableau de bord

**Rang : n° 5.**

## Objectif

`download_all.sh` tourne pendant des **jours**, sans écran, dans tmux. Le seul moyen de savoir
où en est l'acquisition des 800 Go est de se connecter en SSH et de suivre les journaux. Le
tableau de bord — la vitrine du produit — n'affiche rien de la plus longue opération qu'un
nouvel utilisateur vive.

Après ce changement, une carte « Téléchargements » sur `/status` (et une ligne compacte sur la
page d'accueil) montre : quelles catégories sont terminées / en cours / en attente, la taille
par catégorie sur le disque par rapport au budget documenté, et la dernière ligne d'activité
du journal de téléchargement en cours. Les données viennent d'éléments que le téléchargeur
écrit déjà (`.download_progress`, `.logs/*.log`) plus le cache de statistiques de contenu
existant — aucun changement au comportement de la chaîne de téléchargement.

## Fichiers exacts à modifier

| Fichier | Changement |
|---------|------------|
| `web/server.py` | nouveau point d'accès `/api/downloads` + `_compute_download_status()` |
| `web/constants.py` | liste statique `DOWNLOAD_CATEGORIES` (nom, budget_gb, clé de progression, dossier de contenu) |
| `web/templates/status.html` | carte Téléchargements avec barres de progression par catégorie |
| `web/templates/index.html` | résumé d'une ligne dans la barre latérale (« Téléchargements : 3/7 terminés ») |
| `tests/test_smoke.sh` | assertion JSON sur `/api/downloads` |
| `docs/API.md` | documenter le point d'accès |

## Ordre de mise en œuvre

1. **`DOWNLOAD_CATEGORIES` dans `web/constants.py`** — reprendre les catégories et budgets déjà
   listés dans `print_budget()` de `download_all.sh` et les noms de `run_category` (ils DOIVENT
   correspondre aux chaînes écrites dans `.download_progress`) : `kiwix`, `videos`, `books`,
   `maps`, `kolibri`, `gaps`, `mental_health`. Chaque entrée :
   `{"id": "kiwix", "name": "Wikipédia et ZIM", "budget_gb": 190, "dir": "zim"}`
   (budgets tirés de `print_budget` ; `dir` est le sous-dossier de stockage dont l'interface
   affiche la taille, correspondant aux clés de `_compute_content_stats`).

2. **`_compute_download_status()` dans `web/server.py`** :
   - Lire `STORAGE_PATH / ".download_progress"` → ensemble des identifiants terminés.
     Fichier absent = ensemble vide (installation neuve), PAS une erreur.
   - Réutiliser `get_content_stats()` (déjà en cache 60 s) pour les tailles par dossier — ne
     **pas** lancer `du` ni un nouveau parcours.
   - Une catégorie est `"complete"` si son identifiant est dans l'ensemble de progression ;
     `"in_progress"` si elle n'est pas terminée ET que son dossier a grossi :
     comparer `stats[dir]["size_gb"] > 0` ; sinon `"pending"`.
   - Dernière activité : fichier le plus récent de `STORAGE_PATH / ".logs"` selon sa date de
     modification ; lire ses **500 derniers octets** (`f.seek(max(0, size-500))`), prendre la
     dernière ligne non vide, retirer les codes ANSI avec
     `re.sub(r"\x1b\[[0-9;]*m", "", line)`.
   - Renvoyer `{"categories": [...], "active_log": {"file": name, "line": ...} | None}`.
   - Envelopper dans un `_TTLCache(15.0)` au niveau du module (la classe existe déjà).

3. **Route** : `@app.route("/api/downloads")` renvoyant
   `jsonify(_downloads_cache.get(_compute_download_status))`.

4. **`status.html`** : nouvelle carte entre la jauge de budget et la grille à deux colonnes.
   Pour chaque catégorie : nom, pastille d'état (`badge-green` terminé / `badge-yellow` en
   cours / `badge-red` en attente — classes présentes dans base.html), fine barre de
   progression `width: {{ (size/budget*100)|round }}%` (plafonnée à 100 avec le motif `|min`
   utilisé par la jauge de budget vers la ligne 83). Sous la liste, la ligne du journal actif
   en police `--mono`, et les commandes exactes pour lancer/reprendre :
   `bash download/download_all.sh` / `... --resume`. Étendre le `refreshStatus()` existant de
   cette page pour qu'il interroge aussi `/api/downloads` et mette à jour les pastilles via des
   attributs `data-dl-cat` (même motif sur place que pour les pastilles de services).

5. **Barre latérale d'`index.html`** : dans la carte Stockage, ajouter une ligne :
   `Téléchargements : <span id="dlSummary">…</span>` remplie par un `fetch('/api/downloads')`
   au chargement → `"{complete}/{total} catégories terminées"`.

## Cas limites qu'un modèle moins attentif manquerait

- **Couplage des identifiants de catégorie** : les identifiants de `DOWNLOAD_CATEGORIES`
  doivent être égaux au premier argument de chaque appel `run_category` dans
  `download_all.sh` — c'est la chaîne littérale écrite dans `.download_progress`. Ajouter un
  commentaire dans LES DEUX fichiers qui renvoie à l'autre ; une divergence affiche
  « en attente » à perpétuité sans le dire.
- **Codes d'échappement ANSI** dans les lignes de journal (les scripts colorent leur sortie) —
  à retirer côté serveur, sinon l'interface affiche du charabia `\x1b[0;34m`.
- **Lecture de la fin du journal** : les journaux peuvent faire des centaines de Mo (yt-dlp).
  Ne jamais faire `read()` sur tout le fichier ; se positionner à la fin moins 500 octets est
  obligatoire.
- **L'échappement automatique de Flask protège la ligne de journal** dans le modèle — mais le
  sondage JS doit l'afficher avec `textContent`, jamais `innerHTML` (les lignes de journal
  contiennent des noms de fichiers téléchargés arbitraires).
- **`size_gb > 0` comme « en cours »** se trompe pour les catégories qui partagent un dossier
  (`gaps` et `mental_health` écrivent toutes deux dans `pdfs/` et `books/`) : faire pointer
  les deux vers `dir: "pdfs"` et accepter l'approximation — l'état passe à terminé grâce au
  fichier de progression, qui fait foi. Ne pas inventer d'attribution fichier par fichier ;
  cela ne vaut pas le coût en E/S.
- **Concurrence sur la lecture de `.download_progress`** : le téléchargeur ajoute des lignes
  sous `flock` ; une dernière ligne partielle est possible en cours d'écriture. Lire avec
  `read_text().splitlines()` et ignorer toute ligne absente de l'ensemble d'identifiants
  connus.
- **Installation neuve** (pas de stockage, pas de fichier de progression, pas de dossier de
  journaux) : le point d'accès doit renvoyer du JSON valide avec toutes les catégories en
  `pending` et `active_log: null` — c'est exactement l'état de l'environnement de test de
  fumée, ce qui permet de le couvrir.

## Critères d'acceptation

1. Test de fumée : `check_json "GET /api/downloads" "/api/downloads"` passe dans
   l'environnement de test nu, et une assertion de suivi cherche `"pending"` dans la réponse
   (toutes les catégories en attente sur un stockage vide).
2. `echo kiwix >> /tmp/survive_test/.download_progress`, ne rien redémarrer, attendre 15 s
   (TTL du cache) → `/api/downloads` montre kiwix `"complete"`.
3. Écrire un faux journal :
   `mkdir -p /tmp/survive_test/.logs && printf '\x1b[0;34m[DL]\x1b[0m downloading wikipedia_en... 42%%\n' > /tmp/survive_test/.logs/kiwix.log`
   → `active_log.line` vaut `[DL] downloading wikipedia_en... 42%` (sans codes d'échappement).
4. `/status` dans un navigateur montre la carte Téléchargements avec 7 lignes et les bonnes
   pastilles ; les pastilles se mettent à jour sans rechargement quand le fichier de
   progression change.
5. pylint ≥ 9,5 ; tous les tests de fumée passent.
