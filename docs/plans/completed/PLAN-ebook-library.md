# PLAN-ebook-library : faire fonctionner réellement le service E-Books de bout en bout

**Rang : n° 4.**

## Objectif

Calibre-Web (`cps`) est installé, a une unité systemd, un port (8083), un bloc nginx, des
liens partout dans le tableau de bord — et **ne peut pas fonctionner tel que configuré**, car
`cps` exige une *bibliothèque Calibre* (un `metadata.db` créé par les outils de Calibre), alors
que notre configuration fait pointer `CALIBRE_DBPATH` vers un simple dossier d'EPUB en vrac
(`/mnt/survive/books`). Un utilisateur qui clique aujourd'hui sur « E-Books » obtient l'erreur
de l'assistant de configuration de Calibre-Web, pas ses livres. Cela a été trouvé en suivant le
flux de données — le service *démarre*, donc `make status` est au vert, ce qui explique
justement pourquoi personne ne l'avait remarqué.

Après ce changement : un nouveau `scripts/build_ebook_library.sh` crée une vraie bibliothèque
Calibre à partir de tous les EPUB sous `books/`, le service pointe dessus, le téléchargeur la
tient à jour, et les identifiants de première connexion sont documentés.

## Fichiers exacts à modifier

| Fichier | Changement |
|---------|------------|
| `scripts/build_ebook_library.sh` | NOUVEAU — créer/rafraîchir la bibliothèque Calibre |
| `setup/install.sh` | installer `calibre` via apt (fournit `calibredb`) ; appeler le script de construction |
| `systemd/calibre-web.service` | `CALIBRE_DBPATH=/mnt/survive/books/calibre-library` |
| `scripts/start_services.sh` | même chemin dans le cas `calibre)` ; ne pas démarrer s'il n'y a pas de `metadata.db` (avertir avec la commande de correction) |
| `download/books_pdfs.sh` | appeler le script de construction à la fin (mode ajout seul) |
| `docs/TROUBLESHOOTING.md` | section de première connexion et identifiants d'administration par défaut |
| `tests/test_smoke.sh` | sans objet (nécessite calibre) — voir les critères d'acceptation pour une vérification autonome |

## Ordre de mise en œuvre

1. **`scripts/build_ebook_library.sh`** (suivre le style de la maison : `set -euo pipefail`,
   charger `survive.conf`, fonctions de couleur) :
   ```
   LIBRARY="$STORAGE_PATH/books/calibre-library"
   ```
   - Si `calibredb` est absent : erreur avec l'indication `sudo apt-get install -y calibre`,
     sortie 1.
   - Si `$LIBRARY/metadata.db` est absent : `mkdir -p "$LIBRARY"` puis initialisation —
     `calibredb --with-library="$LIBRARY" list >/dev/null 2>&1 || true` ne crée PAS de
     bibliothèque ; la méthode fiable consiste à ajouter un premier livre avec
     `calibredb add --with-library="$LIBRARY" <fichier>`, ce qui la crée automatiquement.
     Donc : initialiser implicitement par l'ajout en masse ci-dessous.
   - Ajout en masse, dédoublonné :
     `find "$STORAGE_PATH/books" -path "$LIBRARY" -prune -o -type f \( -iname '*.epub' -o -iname '*.mobi' -o -iname '*.azw3' \) -print0 | xargs -0 -r calibredb add --with-library="$LIBRARY" --automerge=ignore --`
     (`--automerge=ignore` ignore les livres déjà dans la bibliothèque → idempotent, on peut
     relancer sans risque après chaque téléchargement.)
   - Afficher le total final : `calibredb --with-library="$LIBRARY" list | wc -l`.
2. **`setup/install.sh`** : ajouter `calibre` à la liste des paquets apt (PAS `calibre-bin`,
   qui n'a pas `calibredb` dans certaines versions). Il pèse ~400 Mo avec ses dépendances sur
   aarch64 — le conditionner au motif d'indicateurs de contenu existant : n'installer que si
   `CONTENT_GUTENBERG` ou un indicateur de livres vaut `Y`. Après l'installation, lancer
   `bash scripts/build_ebook_library.sh || true` (les livres ne sont peut-être pas encore
   téléchargés — le script doit avertir puis sortir avec le code 0 quand il ne trouve aucun
   fichier de livre ; utiliser `-r` avec xargs pour qu'un find vide soit sans effet).
3. **`systemd/calibre-web.service`** : remplacer
   `Environment="CALIBRE_DBPATH=/mnt/survive/books"` par `.../books/calibre-library`.
   Remarque : `CALIBRE_DBPATH` indique à cps où se trouve la base de *l'application* ; le
   chemin de la *bibliothèque* se choisit dans l'interface web au premier lancement — pour le
   définir sans interaction, on passerait un défaut à la base de réglages de l'application :
   l'approche fiable la plus simple est de documenter le premier lancement : se connecter
   (`admin` / `admin123`), définir le chemin de la bibliothèque sur
   `/mnt/survive/books/calibre-library`. Mettre cela dans TROUBLESHOOTING.md ET l'afficher dans
   le message de succès de `build_ebook_library.sh`.
4. **`scripts/start_services.sh`**, cas `calibre)` : faire pointer `CALIBRE_DBPATH` vers le
   nouveau chemin ; avant de démarrer, tester
   `[[ -f "$STORAGE_PATH/books/calibre-library/metadata.db" ]]`, sinon
   `warn "Bibliothèque de livres non construite — lancez : bash scripts/build_ebook_library.sh"`
   et démarrer cps quand même (l'assistant vaut mieux que rien).
5. **`download/books_pdfs.sh`** : ajouter à la fin du programme principal :
   `command -v calibredb >/dev/null && bash "$REPO_DIR/scripts/build_ebook_library.sh" || true`.

## Cas limites qu'un modèle moins attentif manquerait

- **`find ... -prune`** : sans élaguer `$LIBRARY` lui-même, chaque relance rajoute les copies
  converties de la bibliothèque — croissance infinie. La clause `-path "$LIBRARY" -prune -o`
  est porteuse.
- **`--automerge=ignore`** est ce qui rend les relances idempotentes. Le comportement par
  défaut crée des enregistrements en double à chaque synchronisation.
- **`xargs -r`** : zéro EPUB (installation neuve) doit être sans effet, pas une erreur
  d'utilisation de `calibredb add` qui fait échouer `set -e`.
- **Noms de fichiers avec espaces ou guillemets** : `-print0 | xargs -0` est obligatoire ; les
  contenus téléchargés incluent des titres comme `Root Cellaring (Natural Storage).epub`.
- **calibredb ne peut pas tourner pendant que calibre-web garde la bibliothèque ouverte** — le
  script de construction doit faire `systemctl stop calibre-web 2>/dev/null || true` avant
  l'ajout en masse et le redémarrer ensuite, sinon les ajouts échouent avec une erreur de
  verrou de base de données uniquement sur les systèmes où le service tourne (marche en
  développement, casse en production).
- **Disque** : la bibliothèque duplique chaque livre ajouté dans sa propre arborescence.
  18 Go de livres → 36 Go au total. Le mentionner dans la sortie du script ;
  `calibredb add --add-duplicates=false` ne dédoublonne PAS le contenu — la bonne paire
  d'options est `--automerge=ignore`.
- **User=pi dans l'unité** — le dossier de la bibliothèque doit appartenir à `pi`
  (`chown -R pi:pi "$LIBRARY"` à la fin du script lorsqu'il tourne en root), sinon cps obtient
  des erreurs sqlite en lecture seule.
- **Les PDF restent dehors** : Calibre gère mal les PDF avec la RAM d'un Pi ; le tableau de
  bord sert déjà les PDF nativement via `/serve/`. N'indexer que epub/mobi/azw3.

## Critères d'acceptation

1. Sur un Pi (ou toute machine Debian avec `calibre` installé) :
   `SURVIVE_STORAGE_PATH=/tmp/cal_test bash scripts/build_ebook_library.sh`
   avec 3 EPUB d'exemple sous `/tmp/cal_test/books/` crée
   `/tmp/cal_test/books/calibre-library/metadata.db` et affiche « 3 ».
2. Relancer la même commande affiche encore « 3 » (idempotent, sans doublons).
3. L'exécution sans aucun EPUB se termine avec le code 0 et un avertissement, pas une erreur.
4. `systemctl start calibre-web` puis `curl -sf localhost:8083 | grep -qi calibre` réussit.
5. Dans un navigateur : se connecter sur `:8083`, voir les 3 livres avec leurs couvertures,
   en ouvrir un dans le lecteur intégré, lire au-delà de la page 1.
6. Après la fin de `bash download/books_pdfs.sh`, les EPUB nouvellement téléchargés
   apparaissent dans Calibre-Web sans manipulation manuelle.
7. shellcheck (réglages de la CI) passe sur tous les scripts modifiés.
