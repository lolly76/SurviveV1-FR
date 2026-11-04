# SurviveV1-FR — Base de connaissances de survie hors ligne

> Fork francophone de [schwadb/SurviveV1](https://github.com/schwadb/SurviveV1). Le code d'origine est de son auteur ; ce fork traduit l'interface, la documentation et l'assistant IA en français.

Une base de connaissances autohébergée, pensée « hors ligne d'abord », pour les scénarios de survie en cas d'effondrement ou de coupure du réseau électrique. Elle tourne sur un **Raspberry Pi 5 (avec ou sans AI Hat)**, sur une VM ou sur un vieux portable Debian 64 bits, s'utilise avec un écran portable et une batterie externe, et peut contenir jusqu'à **800 Go** de connaissances de survie sélectionnées.

---

## Contenu

| Catégorie | Sources |
|-----------|---------|
| **Référence** | Wikipédia FR complète, Wikilivres, Wikivoyage, Wikisource et Wiktionnaire en français, Vikidia, Wikiversité FR |
| **Médical** | Sous-ensemble « Médecine » de Wikipédia FR, *Là où il n'y a pas de docteur* (Hesperian, chapitres en français), vidéos de formation aux premiers secours de la Croix-Rouge française |
| **Référence des médicaments** | Base de données publique des médicaments (ANSM, HAS, UNCAM, licence ouverte) : noms, substances, conditions de prescription, plus indications / posologie / contre-indications / mises en garde / interactions tirées des RCP officiels (récupération lente et reprenable) ; page `/drugs` avec date de mise à jour et source affichées |
| **Savoir-faire** | Guides de réparation iFixit (FR), Ekopédia, Cuisine Libre, French Language Stack Exchange ; pack « English » : médecine avancée, obstétrique, dentaire, élevage, semences, forge, etc. |
| **Éducation** | Khan Academy en français (Kolibri et ZIM Kiwix), Projet Gutenberg (livres en français), simulations PhET FR |
| **Vidéos de survie** | Chaînes YouTube francophones (bushcraft, potager, permaculture, énergie, bricolage, radio) téléchargées avec yt-dlp ; liste extensible dans `config/videos_extra.list` |
| **Cartes** | Tuiles OpenStreetMap hors ligne, **France métropolitaine par défaut** (région au choix), mémo pour récupérer les cartes IGN |
| **Livres / PDF** | Guide gouvernemental « Tous responsables » (SGDSN), chapitres Hesperian en français, séchage solaire (GRET) ; liste extensible dans `config/pdfs_extra.list` |
| **Assistant IA** | LLM local (Ollama) avec recherche dans la bibliothèque hors ligne (CPU ; le Hailo-8L n'accélère pas les LLM) |
| **Cartes et repères** | Cartes routières dans le navigateur (sans serveur de tuiles), repères enregistrés avec notes, import/export GPX/GeoJSON, calque satellite |
| **Gestionnaire de bibliothèque** | Parcourir le catalogue Kiwix (français par défaut), télécharger des ZIM depuis le tableau de bord, enregistrer des fichiers copiés à la main |
| **Notes et fichiers partagés** | Carnet Markdown partagé et dépôt pour vos propres documents, tous deux stockés sur le disque |
| **Transmissions** | Encodeur/décodeur Morse, clients web Meshtastic et MeshCore, listes de relais importées et consultables, référence des fréquences d'urgence en France |

### Phase 2 (option) : la base anglaise d'origine

Le projet SurviveV1 d'origine est entièrement en anglais. Si vous voulez aussi cette base (voyage hors de France, croisement des sources, lecture en anglais), activez la **phase 2** dans `config/survive.conf` : elle **s'ajoute** au contenu français, rien n'est remplacé.

```bash
CONTENT_BASE_EN="Y"               # active la phase 2 (désactivée par défaut)
CONTENT_BASE_EN_WIKIPEDIA="nopic" # nopic (≈ 25 Go au total) | maxi (≈ 130 Go) | N
CONTENT_BASE_EN_KHAN="N"          # Y pour ajouter Khan Academy EN (≈ 90 Go de plus)
```

Elle télécharge : Wikipédia EN, Wikibooks, Wikivoyage, Wikisource et Wiktionary EN, iFixit EN, Projet Gutenberg EN, MedlinePlus, WikiMed, Wikiversity EN et PhET EN (liste exacte dans « Sources utilisées »). Les tailles sont des ordres de grandeur ; le script vérifie l'espace libre avant chaque ZIM. Lancer ensuite `bash download/kiwix_content.sh` (ou `bash download/kiwix_content.sh --only base_en` pour la phase 2 seule). Les packs anglais déjà existants (`CONTENT_STACKEXCHANGE_EN`, `CONTENT_EXPANSION_EN`, `CONTENT_PDFS_EN`, `CONTENT_VIDEOS_EN`, `CONTENT_MENTAL_EN`) restent indépendants.

> **Avancement de la francisation des sources.** Fait : interface du tableau de bord, scripts d'installation, de démarrage et de téléchargement (messages en français), ZIM Kiwix, cartes, Kolibri, vidéos, livres/PDF, premiers secours psychologiques (OMS et Croix-Rouge), référence des médicaments (BDPM), documentation (`docs/`, page `index.html`, skill `install-pi`). Les contenus « experts » (médecine avancée, obstétrique, dentaire, assainissement, élevage, semences, forge, apiculture, sécurité…) n'ont pas d'équivalent français vérifié : ils sont conservés en anglais dans un **pack « English »** identifié (`CONTENT_GAPS_EN`, activé par défaut) ; vos documents français s'ajoutent via `config/gaps_extra.list`. Référence des médicaments : désormais basée sur la BDPM française (`CONTENT_DRUG_NOTICES="N"` pour ne garder que les fichiers de base ; `SURVIVE_DRUGS_NOTICE_MAX` limite la récupération des notices à chaque passage). L'**assistant IA** est aussi francisé (prompt système du modèle `survive`, scripts `ai/` et Hailo, `docs/ai_hat_setup.md`). `docs/gaps_analysis.md` est traduit. Les plans de conception `docs/plans/` sont également traduits. Vérifié en ligne le 3 novembre 2026 : fichiers et formats BDPM, pages de notices (redirection vers la fiche « extrait »), lien de la fiche officielle, URL Geofabrik, noms et tailles des ZIM Kiwix français, existence de la chaîne Kolibri. Quelques ressources n'existent qu'en anglais (Stack Exchange pratiques, collections « zimgit », Appropedia, Energypedia, manuels militaires américains et PDF techniques, chaînes YouTube anglophones, PDF et vidéos de santé mentale) : elles sont proposées en option, désactivées par défaut (`CONTENT_STACKEXCHANGE_EN`, `CONTENT_EXPANSION_EN`, `CONTENT_PDFS_EN`, `CONTENT_VIDEOS_EN`, `CONTENT_MENTAL_EN` dans `config/survive.conf`).
>
> **Avancement du 3 novembre 2026 — consolidation avant test.** Vérification des URL de téléchargement (rapport automatique `url-health` sur 250 URL) et corrections : installation de Martin (tuiles de cartes) choisie selon l'architecture, dépôt Hailo inexistant remplacé par `hailo-all`, raccourci Kolibri mort retiré, encodage réel des fichiers BDPM (cp1252), tailles et dates des ZIM mises à jour. **Matériel agnostique :** détection (`scripts/detect_hardware.sh`) et modules activables (IA, Hailo, USB du Pi, point d'accès Wi-Fi, capot, batterie) ; l'IA se désactive proprement sans AVX2. **Stockage :** disque dédié ou dossier système, profils `test` / `léger` / `moyen` / `complet`. **Qualité :** CI GitHub sur Debian 12 et 13, 130 tests, correction d'un bug de cache qui provoquait des erreurs 500 juste après un démarrage. **À valider :** installation réelle sur VM (`docs/VM_TEST.md`, `scripts/vm_check.sh`), puis sur Raspberry Pi. **Limites connues :** une vingtaine de liens PDF américains et ~18 chaînes YouTube des packs anglophones optionnels sont morts (packs désactivés par défaut) ; plusieurs sites officiels (CDC, FEMA, Peace Corps…) répondent 403 aux robots, leur téléchargement réel reste à confirmer ; le code d'origine n'a pas de licence explicite.
>
> **Avancement du 4 novembre 2026.** Phase 2 optionnelle (`CONTENT_BASE_EN`) : télécharge la base anglaise d'origine en plus du français. Section [« Sources utilisées »](#sources-utilisées) ajoutée : liste exhaustive des ressources téléchargeables, **générée** depuis les scripts (`python3 scripts/gen_sources.py --write`) et vérifiée par un test.

---

## Démarrage rapide

### Installation en une commande (recommandée)

Collez cette commande dans le terminal de votre Raspberry Pi :

```bash
curl -fsSL https://raw.githubusercontent.com/lolly76/SurviveV1-FR/main/install/bootstrap.sh | bash
```

Cette commande :
1. Vérifie votre système (architecture, OS, accès Internet)
2. Clone le dépôt
3. Lance un assistant interactif qui vous guide pour le stockage, le nom d'hôte et le modèle d'IA
4. Installe tous les services et les démarre automatiquement

### Installation manuelle

```bash
# 1. Cloner le dépôt sur votre Raspberry Pi
git clone https://github.com/lolly76/SurviveV1-FR.git ~/SurviveV1
cd ~/SurviveV1

# 2. Lancer l'assistant interactif (recommandé)
sudo bash install/wizard.sh

# — ou lancer directement l'installateur (non interactif) —
sudo bash setup/install.sh

# 3. Télécharger le contenu (tourne en arrière-plan, peut durer des jours)
bash download/download_all.sh --storage /mnt/survive

# 4. Démarrer tous les services
bash scripts/start_services.sh

# 5. Ouvrir le navigateur
http://localhost:8080
```

---

## Configuration requise

- **Matériel :** Raspberry Pi 5 (4 Go de RAM ou plus recommandés ; AI Hat Hailo facultatif) **ou** PC / portable reconditionné / VM 64 bits (aarch64 ou x86_64, 4 Go de RAM minimum). Voir « Matériel : Raspberry Pi, VM ou vieux portable » ci-dessous.
- **Stockage :** disque dédié (SSD USB 3.0 ou NVMe) ou dossier sur le disque du système ; de 60 Go (profil `léger`) à 800 Go (profil `complet`)
- **Alimentation :** Batterie externe (20 000 mAh ou plus) ou solaire + batterie ; sur un portable, la batterie interne sert d'onduleur de secours
- **Système :** **Debian 12 ou 13, 64 bits** (Raspberry Pi OS inclus). Ubuntu et Tails ne sont pas pris en charge
- **Facultatif :** Clé Wi-Fi pour le partage sur le réseau local

---

### Matériel : Raspberry Pi, VM ou vieux portable

SurviveV1 fonctionne sur Debian 12/13 **64 bits** (aarch64 ou x86_64) : Raspberry Pi 5, VM de test ou
portable reconditionné. Les fonctions dépendant du matériel sont des **modules** que l'installateur
active seulement si la machine le permet. Pour voir le résultat sur votre machine :

```bash
bash scripts/detect_hardware.sh --table
```

| Module | Actif automatiquement si… | Réglage |
|--------|---------------------------|---------|
| `AI` (Ollama local) | AVX2 présent (x86) et ≥ 4 Go de RAM | `SURVIVE_MODULE_AI` |
| `HAILO` (AI Hat) | Raspberry Pi avec Hailo détecté | `SURVIVE_MODULE_HAILO` |
| `PI_USB` (courant USB, TRIM) | Raspberry Pi | `SURVIVE_MODULE_PI_USB` |
| `HOTSPOT` (point d'accès Wi-Fi) | carte Wi-Fi gérant le mode AP | `SURVIVE_MODULE_HOTSPOT` |
| `LID` (capot fermé sans veille) | portable | `SURVIVE_MODULE_LID` |
| `BATTERY` (batterie = onduleur) | batterie détectée, affichée sur la page État | `SURVIVE_MODULE_BATTERY` |

Chaque réglage vaut `auto` (défaut), `on` (forcé) ou `off` dans `config/survive.conf`. Sans AVX2 ou
avec trop peu de RAM, l'assistant IA est désactivé proprement (message explicatif, le reste du
système fonctionne) ; `SURVIVE_OLLAMA_HOST` permet d'utiliser l'IA d'une autre machine. Les binaires
(Kiwix, Martin, pmtiles, Jellyfin) sont choisis selon l'architecture, et les services tournent sous
l'utilisateur `sudo`. `SURVIVE_PLATFORM=pi|generic` force la détection Pi/PC.
`bash download/download_all.sh --dry-run` simule les téléchargements. Tails n'est pas pris en charge
(système amnésique dont le pare-feu bloque les connexions entrantes).

### Stockage et profils de contenu

L'assistant propose deux modes de stockage :

1. **Disque dédié** (recommandé) : SSD USB ou second disque interne, monté sur `/mnt/survive`, formatage
   proposé avec double confirmation. Le disque qui porte Debian n'est **jamais** listé.
2. **Dossier sur le disque du système** (ex. `/srv/survive`) : aucun formatage, pour un portable à disque
   unique. Refusé sous 80 Go libres, et le profil conseillé garde une marge de 20 Go ou 15 %.

Le **profil de contenu** se choisit selon l'espace (valeurs approximatives) :

| Profil | Taille | Contenu |
|--------|--------|---------|
| `leger` | ~60 Go | Wikipédia sans images, Wikilivres & co, cartes, PDF de survie, médicaments |
| `moyen` | ~250 Go | + Wikipédia complète, livres, iFixit, Khan Academy (ZIM), sans vidéos ni Kolibri |
| `complet` | ~800 Go | tout, y compris vidéos de survie et Kolibri |
| `test` | ~6 Go | validation d'une installation sur VM (voir `docs/VM_TEST.md`) |

Changer de profil plus tard : `bash scripts/apply_profile.sh leger` puis
`bash download/download_all.sh`. Les profils sont des fichiers lisibles dans `config/profiles/`.

## Arborescence

```
SurviveV1/
├── setup/          # Scripts d'installation de toutes les dépendances
├── download/       # Récupération des contenus (Kiwix, yt-dlp, wget)
├── web/            # Tableau de bord Flask servi sur :8080
├── ai/             # Ollama + LLM local (inférence CPU)
├── sync/           # Synchronisation cloud avec rclone (Google Drive, Dropbox, S3)
├── scripts/        # Utilitaires démarrage/arrêt/état/mise à jour
├── systemd/        # Unités de service systemd
├── config/         # Configuration nginx, kiwix, application
├── docs/           # Documentation détaillée
└── data/           # Lien symbolique → votre point de montage de stockage
```

---

## Services

| Service | Port | Description |
|---------|------|-------------|
| Tableau de bord | 8080 | Interface web principale |
| Kiwix | 8081 | Wikipédia, livres, Stack Exchange |
| Kolibri | 8082 | Contenus éducatifs Khan Academy, CK-12 |
| Jellyfin | 8096 | Lecteur des vidéos téléchargées |
| Calibre-Web | 8083 | Lecteur de livres numériques (PDF, EPUB) |
| Ollama AI | 11434 | API du LLM local |
| Meshtastic Web | 8084 | Client radio maillée LoRa (après `download/comms.sh`) |
| MeshCore Web | 8085 | Client maillé LoRa MeshCore (après `download/comms.sh`) ; ses applications Android/Windows vont dans le dépôt d'applications |
| Nginx | 80 | Proxy inverse (facultatif) |

### Pages du tableau de bord

| Page | Fonction |
|------|----------|
| `/maps` | Carte routière hors ligne avec repères enregistrés (icône, couleur, notes, masquage), recherche, import/export GPX/GeoJSON, localisation GPS en HTTPS, calque satellite |
| `/content` | Gestionnaire de bibliothèque : catalogue Kiwix par langue et catégorie, téléchargement de ZIM en un clic (admin), liste des téléchargements, « Réanalyser la bibliothèque » pour les fichiers copiés à la main |
| `/notes` | Notes Markdown partagées (tout le monde peut écrire, l'admin supprime) ; consultables depuis la recherche principale |
| `/shared` | Dépôt et téléchargement de fichiers personnels (2 Go par envoi, 10 Go toujours laissés libres) |
| `/comms` | Outil Morse, lien vers le client web Meshtastic, annuaire de relais à partir de vos exports CSV, fréquences d'appel et d'urgence |
| `/status` | Services, téléchargements, mise à jour en un clic et interrupteur de la mise à jour automatique nocturne |

### Mise à jour automatique nocturne

Définissez `SURVIVE_AUTO_UPDATE="true"` (l'heure et la limite de débit se trouvent à côté) dans `config/survive.conf`, puis relancez `sudo bash scripts/generate_services.sh`, ou actionnez l'interrupteur sur la page État. Le minuteur lance la mise à jour des contenus manquants à basse priorité et ne fait rien lorsque le Pi est hors ligne.

### Accès sans réseau (sans routeur)

```bash
sudo bash scripts/hotspot.sh enable
```

Le Pi diffuse son propre réseau Wi-Fi (SSID par défaut : `SurviveV1`) ; connectez un téléphone ou un ordinateur portable et ouvrez **http://10.42.0.1:8080**. Désactivez-le avec `... disable` ; un redémarrage remet aussi le Pi sur le Wi-Fi normal.

---

## Synchronisation cloud

```bash
# Configuration initiale de rclone
bash sync/setup_rclone.sh

# Synchroniser vers Google Drive
bash sync/sync_to_cloud.sh gdrive

# Synchroniser vers Dropbox
bash sync/sync_to_cloud.sh dropbox

# Programmer une synchronisation nocturne (quand Internet est disponible)
bash sync/schedule_sync.sh
```

---

## Mise à jour des contenus

```bash
# Mettre à jour une catégorie précise
bash download/kiwix_content.sh --update wikipedia

# Tout mettre à jour (télécharge les nouvelles versions)
bash scripts/update_content.sh

# Voir ce qui est installé et ce qui est disponible
bash scripts/status.sh
```

---

## Assistant IA

L'assistant (modèle `survive`, prompt système en français) tourne en local avec Ollama, sur le processeur : le Hailo-8L n'accélère pas les LLM (voir `docs/ai_hat_setup.md`). Il s'appuie sur les articles de votre bibliothèque hors ligne et cite ses sources :

```bash
# Discuter avec l'IA locale (elle cherche dans vos contenus)
bash ai/query.sh "Comment purifier de l'eau sans produits chimiques ?"

# Ou via l'interface web : http://localhost:8080/ai
```

---

## Budget de stockage (~800 Go)

Estimations pour les sources françaises (les ZIM Kiwix datés sont remplacés par leur dernière version publiée).

| Contenu | Taille |
|---------|--------|
| Wikipédia FR (avec images) | ~52 Go (12 Go sans images) |
| Wikilivres, Wikivoyage, Wikisource, Wiktionnaire FR | ~17 Go |
| iFixit FR | ~3,5 Go |
| Projet Gutenberg FR | ~10,5 Go |
| Khan Academy FR (ZIM Kiwix) | ~101 Go |
| Khan Academy FR (Kolibri) | ~200 Go |
| Conférences TED (sous-titres FR) | ~39 Go |
| Vidéos de survie | ~150 Go |
| OpenStreetMap France | ~5 Go (monde : ~70 Go) |
| PDF + manuels, pack d'extension FR | ~25 Go |
| Référence des médicaments (BDPM + notices) | ~1 Go |
| Modèles LLM (IA) | ~50 Go |
| Réserve | variable |

---

<!-- SOURCES:BEGIN (généré par scripts/gen_sources.py — ne pas modifier à la main) -->

## Sources utilisées

Liste générée depuis les scripts de téléchargement : chaque ligne est une ressource que SurviveV1-FR peut récupérer. Rien n'est stocké dans ce dépôt ; les contenus gardent leur licence d'origine (voir [`docs/licenses.md`](docs/licenses.md)). Les noms de fichiers Kiwix perdent leur date : c'est toujours la dernière version publiée qui est téléchargée. **Pack English** = ressource sans équivalent français vérifié, conservée en anglais. **Phase 2** = la base anglaise d'origine du projet SurviveV1, en option (voir « Phase 2 » dans la section Contenu).

### Bibliothèques Kiwix (ZIM) — [download.kiwix.org](https://download.kiwix.org/zim/)

| Ressource | Fichier ZIM | Activation |
|---|---|---|
| Wikipédia FR | `wikipedia_fr_all_maxi` | `CONTENT_WIKIPEDIA` / `CONTENT_WIKIPEDIA_NOPIC` |
| Wikipédia FR (sans images) | `wikipedia_fr_all_nopic` | `CONTENT_WIKIPEDIA` / `CONTENT_WIKIPEDIA_NOPIC` |
| Wikilivres FR | `wikibooks_fr_all_maxi` | `CONTENT_WIKIBOOKS` |
| Wikivoyage FR | `wikivoyage_fr_all_maxi` | `CONTENT_WIKIBOOKS` |
| Wikisource FR | `wikisource_fr_all_nopic` | `CONTENT_WIKIBOOKS` |
| Wiktionnaire FR | `wiktionary_fr_all_nopic` | `CONTENT_WIKIBOOKS` |
| iFixit FR | `ifixit_fr_all` | `CONTENT_IFIX` |
| French Language Stack Exchange | `french.stackexchange.com_mul_all` | `CONTENT_STACKEXCHANGE` |
| Stack Exchange — DIY | `diy.stackexchange.com_en_all` | `CONTENT_STACKEXCHANGE_EN` (pack English, désactivé par défaut) |
| Stack Exchange — Cooking | `cooking.stackexchange.com_en_all` | `CONTENT_STACKEXCHANGE_EN` (pack English, désactivé par défaut) |
| Stack Exchange — Ham Radio | `ham.stackexchange.com_en_all` | `CONTENT_STACKEXCHANGE_EN` (pack English, désactivé par défaut) |
| Stack Exchange — Outdoors | `outdoors.stackexchange.com_en_all` | `CONTENT_STACKEXCHANGE_EN` (pack English, désactivé par défaut) |
| Stack Exchange — Gardening | `gardening.stackexchange.com_en_all` | `CONTENT_STACKEXCHANGE_EN` (pack English, désactivé par défaut) |
| Stack Exchange — Medical Sciences | `medicalsciences.stackexchange.com_en_all` | `CONTENT_STACKEXCHANGE_EN` (pack English, désactivé par défaut) |
| Stack Exchange — Sustainability | `sustainability.stackexchange.com_en_all` | `CONTENT_STACKEXCHANGE_EN` (pack English, désactivé par défaut) |
| Stack Exchange — Electronics | `electronics.stackexchange.com_en_all` | `CONTENT_STACKEXCHANGE_EN` (pack English, désactivé par défaut) |
| Stack Exchange — Unix/Linux | `unix.stackexchange.com_en_all` | `CONTENT_STACKEXCHANGE_EN` (pack English, désactivé par défaut) |
| Gutenberg FR | `gutenberg_fr_all` | `CONTENT_GUTENBERG` |
| Khan Academy FR | `khanacademy_fr_all` | `CONTENT_KHAN_ZIM` |
| Wikipédia FR — Médecine | `wikipedia_fr_medicine_maxi` | toujours |
| TED Technology | `ted_mul_technology` | toujours |
| TED Health Care | `ted_mul_health-care` | toujours |
| TED Public Health | `ted_mul_public-health` | toujours |
| TED Mental Health | `ted_mul_mental-health` | toujours |
| TED Science | `ted_mul_science` | toujours |
| Ekopédia (écologie pratique, autonomie) | `ekopedia_fr_all_maxi` | `CONTENT_EXPANSION` |
| Cuisine Libre (recettes) | `cuisinelibre.org_fr_all` | `CONTENT_EXPANSION` |
| PhET — simulations scientifiques FR | `phet_fr_all` | `CONTENT_EXPANSION` |
| Wikiversité FR | `wikiversity_fr_all_maxi` | `CONTENT_EXPANSION` |
| Vikidia FR (encyclopédie simplifiée) | `vikidia_fr_all_maxi` | `CONTENT_EXPANSION` |
| Post-disaster Library (EN) | `zimgit-post-disaster_en` | `CONTENT_EXPANSION_EN` (pack English, désactivé par défaut) |
| Emergency Medicine Collection (EN) | `zimgit-medicine_en` | `CONTENT_EXPANSION_EN` (pack English, désactivé par défaut) |
| Water Purification Collection (EN) | `zimgit-water_en` | `CONTENT_EXPANSION_EN` (pack English, désactivé par défaut) |
| Food Preparation Collection (EN) | `zimgit-food-preparation_en` | `CONTENT_EXPANSION_EN` (pack English, désactivé par défaut) |
| Knots Guide (EN) | `zimgit-knots_en` | `CONTENT_EXPANSION_EN` (pack English, désactivé par défaut) |
| Appropedia (EN) | `appropedia_en_all_maxi` | `CONTENT_EXPANSION_EN` (pack English, désactivé par défaut) |
| Energypedia (EN) | `energypedia_en_all_maxi` | `CONTENT_EXPANSION_EN` (pack English, désactivé par défaut) |
| Wikipedia EN | `wikipedia_en_all_maxi` | `CONTENT_BASE_EN` + `CONTENT_BASE_EN_WIKIPEDIA=nopic\|maxi` (phase 2) |
| Wikipedia EN (no-pic) | `wikipedia_en_all_nopic` | `CONTENT_BASE_EN` + `CONTENT_BASE_EN_WIKIPEDIA=nopic\|maxi` (phase 2) |
| Wikibooks EN | `wikibooks_en_all_maxi` | `CONTENT_BASE_EN` (phase 2, base anglaise, désactivée par défaut) |
| Wikivoyage EN | `wikivoyage_en_all_maxi` | `CONTENT_BASE_EN` (phase 2, base anglaise, désactivée par défaut) |
| Wikisource EN | `wikisource_en_all_maxi` | `CONTENT_BASE_EN` (phase 2, base anglaise, désactivée par défaut) |
| Wiktionary EN | `wiktionary_en_all_nopic` | `CONTENT_BASE_EN` (phase 2, base anglaise, désactivée par défaut) |
| iFixit EN | `ifixit_en_all` | `CONTENT_BASE_EN` (phase 2, base anglaise, désactivée par défaut) |
| Gutenberg EN | `gutenberg_en_all` | `CONTENT_BASE_EN` (phase 2, base anglaise, désactivée par défaut) |
| Medline Plus (EN) | `medlineplus.gov_en_all` | `CONTENT_BASE_EN` (phase 2, base anglaise, désactivée par défaut) |
| WikiMed (EN) | `mdwiki_en_all_maxi` | `CONTENT_BASE_EN` (phase 2, base anglaise, désactivée par défaut) |
| PhET Science Simulations (EN) | `phet_en_all` | `CONTENT_BASE_EN` (phase 2, base anglaise, désactivée par défaut) |
| Wikiversity EN | `wikiversity_en_all_maxi` | `CONTENT_BASE_EN` (phase 2, base anglaise, désactivée par défaut) |
| Khan Academy EN | `khanacademy_en_all` | `CONTENT_BASE_EN` + `CONTENT_BASE_EN_KHAN=Y` (phase 2) |

### Livres et PDF (`download/books_pdfs.sh`)

**En français**

- [Guide « Tous responsables » (SGDSN)](https://www.ecologie.gouv.fr/sites/default/files/documents/SGDSN_Guide_Tous%20responsables.pdf)
- [Là où il n'y a pas de docteur — sommaire](https://www.hesperian.org/wp-content/uploads/pdf/fr_nwtnd_2014/fr_nwtnd_2014_fm.pdf)
- [Là où il n'y a pas de docteur — ch. 15 Douleurs au ventre, diarrhées, vers](https://www.hesperian.org/wp-content/uploads/pdf/fr_nwtnd_2014/fr_nwtnd_2014_15.pdf)
- [Là où il n'y a pas de docteur — ch. 26 Grossesse et accouchement](https://www.hesperian.org/wp-content/uploads/pdf/fr_nwtnd_2014/fr_nwtnd_2014_26.pdf)
- [Là où il n'y a pas de docteur — ch. 27 Nouveau-nés et allaitement](https://www.hesperian.org/wp-content/uploads/pdf/fr_nwtnd_2014/fr_nwtnd_2014_27.pdf)
- [Là où il n'y a pas de docteur — ch. 28 Prendre soin des enfants](https://www.hesperian.org/wp-content/uploads/pdf/fr_nwtnd_2014/fr_nwtnd_2014_28.pdf)
- [Là où il n'y a pas de docteur — ch. 31 Bien s'alimenter](https://www.hesperian.org/wp-content/uploads/pdf/fr_nwtnd_2014/fr_nwtnd_2014_31.pdf)
- [Là où il n'y a pas de docteur — ch. 32 Eau et assainissement](https://www.hesperian.org/wp-content/uploads/pdf/fr_nwtnd_2014/fr_nwtnd_2014_32.pdf)
- [Manuel de santé des femmes handicapées — Grossesse](https://hesperian.org/wp-content/uploads/pdf/fr_wwd_2024/fr_wwd_2024_10.pdf)
- [Manuel de santé des femmes handicapées — Travail et accouchement](https://hesperian.org/wp-content/uploads/pdf/fr_wwd_2024/fr_wwd_2024_11.pdf)
- [Manuel de santé des femmes handicapées — Prendre soin de votre bébé](https://hesperian.org/wp-content/uploads/pdf/fr_wwd_2024/fr_wwd_2024_12.pdf)
- [Séchage solaire des fruits et légumes (GRET)](https://gret.org/wp-content/uploads/2021/11/GP-08_Sechage-solaire-des-fruits-et-legumes.pdf)
- [jules verne — l ile mysterieuse](https://www.gutenberg.org/ebooks/14287.epub3.images)

**Pack English** (`CONTENT_PDFS_EN`, désactivé par défaut)

- *Manuels militaires américains* : [FM 21-76 US Army Survival Manual](https://archive.org/download/milmanual-mcrp-3-02f-fm-21-76-survival/mcrp_3-02f_fm_21-76_survival.pdf) · [ATP 3-50.21 Survival](https://armypubs.army.mil/epubs/DR_pubs/DR_a/ARN32107-ATP_3-50.21-000-WEB-1.pdf) · [FM 4-25.11 First Aid](https://archive.org/download/fm-4-25.11-first-aid/FM%204-25.11%20First%20Aid.pdf) · [TC 3-97.61 Military Mountaineering](https://armypubs.army.mil/epubs/DR_pubs/DR_a/pdf/web/tc3_97x61.pdf) · [FM 3-05.70 Special Forces Survival](https://archive.org/download/fm-3-05.70-survival-2002/FM%203-05.70%20Survival%20%202002.pdf) · [FM 3-05.213 Special Forces Use of Pack Animals](https://armypubs.army.mil/epubs/DR_pubs/DR_a/pdf/web/fm3_05x213.pdf) · [FM 21-10 Field Sanitation](https://archive.org/download/milmanual-fm-21-10-mcrp-4-11.1d-field-hygiene-and-sanitation/fm_21-10_mcrp_4-11.1d_field_hygiene_and_sanitation.pdf) · [FM 90-5 Jungle Operations](https://archive.org/download/milmanual-fm-90-5-jungle-operations/fm_90-5_jungle_operations.pdf) · [SAS Survival Handbook (excerpt)](https://www.ibiblio.org/hyperwar/ATO/USAAF/SurvivalManual.pdf)
- *Références médicales* : [Where There Is No Doctor (Hesperian)](https://archive.org/download/where-there-is-no-doctor/Where%20There%20Is%20No%20Doctor.pdf) · [Where There Is No Dentist](https://archive.org/download/Where_There_is_no_Dentist/Where_There_is_no_Dentist.pdf) · [A Book for Midwives](https://archive.org/download/ABookForMidwives/26.SusanKlien-ABookForMidwives.pdf) · [Helping Children Who Are Blind](https://store.hesperian.org/prod/pdf/A250E.pdf) · [Merck Veterinary Manual (online guide)](https://www.msdvetmanual.com/Content/Whitepaper/MVM_Whitepaper.pdf) · [Emergency Preparedness and Response (CDC)](https://www.cdc.gov/niosh/docs/2004-101/pdfs/2004-101.pdf) · [Combat Casualty Care Manual](https://www.usso.med.navy.mil/sites/usso/files/2018-12/tccc-guidelines.pdf)
- *Agriculture et alimentation* : [USDA Home Canning Guide](https://nchfp.uga.edu/publications/publications_usda.html) · [Square Foot Gardening Manual](https://extension.sdstate.edu/sites/default/files/2020-06/P-00003.pdf) · [Organic Farming Guide (ATTRA)](https://attra.ncat.org/product/beginning-farmer.pdf) · [Permaculture Design Manual (excerpt)](https://holmgren.com.au/downloads/Essence_of_Pc_EN.pdf) · [Small-Scale Chicken Keeping](https://extension.psu.edu/programs/betterkidcare/news/2018/small-scale-chicken-keeping) · [Wild Edible Plants Guide (USDA)](https://www.fs.usda.gov/Internet/FSE_DOCUMENTS/stelprdb5444952.pdf) · [Food Preservation Methods](https://nchfp.uga.edu/how/store/uga_freeze_dry.pdf)
- *Ingénierie et construction* : [Tiny House Building Guide](https://www.huduser.gov/portal/publications/pdf/HousingFirst_TinyHomes.pdf) · [Earthship Construction Manual](https://www.earthship.com/earthship-construction.pdf) · [Solar Power System Design Guide](https://www.nrel.gov/docs/fy03osti/31146.pdf) · [Wind Energy Basics](https://www.nrel.gov/docs/fy01osti/29492.pdf) · [Water System Design Guide](https://www.nrcs.usda.gov/sites/default/files/2022-10/NEH_210-600.pdf) · [Composting Guide (EPA)](https://www.epa.gov/sites/default/files/2016-01/documents/master_composter_manual.pdf)
- *Radioamateur et communications* : [ARRL Handbook excerpt (legal free chapters)](http://www.arrl.org/files/file/Technology/tis/info/pdf/0111qex017.pdf) · [Amateur Radio Emergency Communications](https://www.arrl.org/files/file/ARESHandbook2015.pdf) · [FCC Technician License Study Guide](https://ncvec.org/downloads/2022-2026%20Tech%20Pool%20w%20Errata.pdf)
- *Vie autonome et bricolage* : [The Encyclopedia of Country Living (excerpt)](https://www.nps.gov/articles/000/upload/Basic-Wilderness-Skills.pdf) · [Foxfire Series excerpts (public domain)](https://docslib.org/doc/12279028/the-foxfire-book.pdf) · [Herbal Medicine Guide (PubMed)](https://www.ncbi.nlm.nih.gov/books/NBK92766/pdf/Bookshelf_NBK92766.pdf)
- *Livres du domaine public (anglais)* : [charles darwin — on the origin of species](https://www.gutenberg.org/ebooks/2009.epub3.images) · [henry david thoreau — walden](https://www.gutenberg.org/ebooks/205.epub3.images) · [jules verne — the mysterious island](https://www.gutenberg.org/ebooks/1268.epub3.images) · [jack london — the call of the wild](https://www.gutenberg.org/ebooks/215.epub3.images) · [mark twain — adventures of huckleberry finn](https://www.gutenberg.org/ebooks/76.epub3.images) · [daniel defoe — robinson crusoe](https://www.gutenberg.org/ebooks/521.epub3.images)

### Contenus experts — pack English (`download/gaps_content.sh`, `CONTENT_GAPS_EN`)

- *Médecine avancée et en milieu isolé* : [Emergency War Surgery 5th Ed](https://archive.org/download/ews5man-mil/ews5man.pdf) · [SOF Medical Handbook](https://archive.org/download/SOFMH2001/SOFMH2001.pdf) · [NOLS Wilderness Medicine Guide](https://www.nols.edu/media/filer_public/wilderness_medicine/wilderness-medicine-field-guide.pdf) · [Combat Medic Field Reference](https://archive.org/download/FM_8_10_1_T_M_C_T_T_P_1994/FM%208-10-1%20The%20Medical%20Company.%20Tactics%2C%20Techniques%20and%20Procedures-1994.pdf) · [Survival and Austere Medicine 3rd Ed (free)](https://griddownmed.blog/wp-content/uploads/2018/11/austmed.pdf) · [ACEP Austere Medicine Book List](https://www.acep.org/siteassets/uploads/uploaded-files/acep/membership/sections-of-membership/disaster/austere-medicine-books.pdf) — vidéos : [Doom and Bloom (Dr. Bones & Nurse Amy)](https://www.youtube.com/@DoomAndBloom/videos) · [The Patriot Nurse](https://www.youtube.com/@ThePatriotNurse/videos) · [Skinny Medic (TCCC)](https://www.youtube.com/@SkinnyMedic/videos)
- *Obstétrique* : [A Book for Midwives (Hesperian)](https://archive.org/download/ABookForMidwives/26.SusanKlien-ABookForMidwives.pdf) · [WHO Safe Motherhood Practical Guide](https://iris.who.int/handle/10665/43972) · [Peace Corps Maternal Child Health Guide](https://files.peacecorps.gov/multimedia/pdf/library/M0063.pdf)
- *Soins dentaires* : [Where There Is No Dentist (Hesperian)](https://archive.org/download/Where_There_is_no_Dentist/Where_There_is_no_Dentist.pdf) · [WHO Oral Health Primary Care](https://iris.who.int/handle/10665/42654)
- *Santé mentale* : [Where There Is No Psychiatrist (Hesperian)](https://store.hesperian.org/prod/pdf/A490E.pdf) · [WHO Psychological First Aid Guide](https://iris.who.int/handle/10665/44615) · [NCTSN Psychological First Aid Field Operations Guide](https://www.nctsn.org/sites/default/files/resources/pfa_field_operations_guide.pdf) · [The Sphere Handbook (Mental Health chapter)](https://sphere-standards-media.s3.eu-central-1.amazonaws.com/app/uploads/2026/07/02150526/Sphere-Handbook-2018-EN.pdf) · [CDC NIOSH Disaster Survival Psychology (Everly)](https://www.cdc.gov/niosh/docket/archive/pdfs/NIOSH-154/0154-010108-everly.pdf)
- *Assainissement* : [The Humanure Handbook (Jenkins)](https://humanurehandbook.com/downloads/H2.pdf) · [WHO Sanitation and Health Guide](https://iris.who.int/handle/10665/337673) · [Peace Corps Latrine Construction](https://files.peacecorps.gov/multimedia/pdf/library/M0055_latrineconst.pdf) · [Greywater Oasis Design Guide (excerpt)](https://oasisdesign.net/greywater/laundrytolandscape/intro.pdf)
- *Élevage* : [FAO Small-Scale Poultry Production](https://www.fao.org/3/y5114e/y5114e.pdf) · [FAO Better Farming Series - Small Animals](https://www.fao.org/3/T0690E/T0690E.pdf) · [FAO Goat Production Guide](https://www.fao.org/3/t0750e/t0750e.pdf) · [FAO Pig Production Guide](https://www.fao.org/3/t0690e/t0690e.pdf) · [USDA Rabbit Production](https://www.ams.usda.gov/sites/default/files/media/Rabbit%20Handbook.pdf) · [Merck Veterinary Manual (online reference note)](https://www.msdvetmanual.com/Content/Whitepaper/MVM_Whitepaper.pdf) — vidéos : [Weed em and Reap](https://www.youtube.com/@weedemnreap/videos) · [Jill Winger Prairie Homestead](https://www.youtube.com/@JillWinger/videos)
- *Semences* : [NRCS Seed Saving Basics](https://www.nrcs.usda.gov/Internet/FSE_DOCUMENTS/nrcs144p2_016285.pdf) · [Peace Corps Seed Production and Improvement](https://files.peacecorps.gov/multimedia/pdf/library/M0046_seedproduction.pdf) · [Southern Exposure Seed Saving Guide](https://www.southernexposure.com/growing-guides/saving-seeds-home-use.pdf) · [OSU Extension Seed Saving Guide](https://extension.oregonstate.edu/sites/default/files/documents/ec871.pdf) — vidéos : [MIGardener (seed saving)](https://www.youtube.com/@MIGardener/videos) · [Hoss Tools (seed saving)](https://www.youtube.com/@HossTools/videos)
- *Apiculture* : [USDA Beekeeping for Beginners](https://www.ams.usda.gov/sites/default/files/media/Beekeeping%20for%20Beginners.pdf) · [Penn State Beekeeping Guide](https://extension.psu.edu/bees/pdf/pennsylvania-beekeeping-guide.pdf) · [FAO Beekeeping in Africa (general principles)](https://www.fao.org/3/T0104E/T0104E.pdf)
- *Forge* : [Practical Blacksmithing, vol. 1 à 4 (Richardson)](https://archive.org/details/practicalblacksmithing01rich) — vidéos : [Blackbear Forge](https://www.youtube.com/@BlackbearForge/videos) · [Alec Steele Blacksmithing](https://www.youtube.com/@AlecSteele/videos)
- *Savoir-faire traditionnels* : vidéos : [Townsends (18th century skills)](https://www.youtube.com/@Townsends/videos) · [Primitive Technology](https://www.youtube.com/@primitivetechnology9550/videos) · [Far North Bushcraft and Survival](https://www.youtube.com/@FarNorthBushcraft/videos)
- *Fermentation et brassage* : [FAO Fermented Fruits and Vegetables](https://www.fao.org/3/x0560e/x0560e.pdf) · [FAO Traditional Food Plants (includes fermentation)](https://www.fao.org/3/x0453e/x0453e.pdf) — vidéos : [Homesteady (fermentation)](https://www.youtube.com/@Homesteady/videos) · [City Steading Brews (mead/wine)](https://www.youtube.com/@CitySteadingBrews/videos) · [Townsends Brewing/Fermentation](https://www.youtube.com/playlist?list=PLQfT5iqzeqneoJ_RVB3CDvzORSDkKOaDs)
- *Permaculture et agroforesterie* : [USDA Agroforestry Overview](https://www.fs.usda.gov/nac/assets/documents/agroforestry/brochures/agroforestryoverview.pdf) · [FAO Agroforestry Systems](https://www.fao.org/3/a-i6383e.pdf) — vidéos : [Geoff Lawton Permaculture](https://www.youtube.com/@GeoffLawtonOnline/videos) · [Andrew Millison Permaculture](https://www.youtube.com/@andrewmillison/videos)
- *Eau* : [Peace Corps Manual Well Drilling](https://files.peacecorps.gov/multimedia/pdf/library/M0017_manual_well_drilling.pdf) · [Peace Corps Water Supply](https://files.peacecorps.gov/multimedia/pdf/library/M0017_water_supply.pdf) · [WHO Guidelines for Drinking Water Quality](https://iris.who.int/handle/10665/352532) · [USAID Water Sanitation and Hygiene](https://pdf.usaid.gov/pdf_docs/PNADW118.pdf)
- *Sécurité* : [FM 7-8 Infantry Rifle Platoon and Squad](https://archive.org/download/milmanual-fm-7-8-infantry-rifle-platoon-and-squad/fm_7-8_infantry_rifle_platoon_and_squad.pdf) · [FM 21-60 Visual Signals (Hand Signals)](https://archive.org/download/milmanual-fm-21-60-visual-signals/fm_21-60_visual_signals.pdf) · [Ranger Handbook SH 21-76](https://archive.org/download/sh-21-76-ranger-handbook-2006/SH%2021-76%20Ranger%20Handbook%20%202006.pdf) · [MCWP 3-11.2 Marine Rifle Squad](https://archive.org/download/milmanual-mcwp-3-11.2-marine-rifle-squad/mcwp_3-11.2_marine_rifle_squad.pdf)
- *Résilience communautaire* : [FEMA Community Resilience Planning Guide](https://www.fema.gov/sites/default/files/2020-06/fema_community-resilience-planning-guide.pdf) · [WHO Community Health Worker Guidelines](https://iris.who.int/handle/10665/275765) · [Sphere Handbook 2018 (Humanitarian Standards)](https://sphere-standards-media.s3.eu-central-1.amazonaws.com/app/uploads/2026/07/02150526/Sphere-Handbook-2018-EN.pdf)
- *Morse et radio* : [Art and Skill of Radio Telegraphy (N0HFF)](https://www.qsl.net/n9bor/n0hff.pdf) · [Emergency Communication Reference Frequencies](https://www.arrl.org/files/file/Public%20Service/Emergency%20Communication/EC-001.pdf) — vidéos : [K0PIR Ham Radio Crash Course](https://www.youtube.com/@K0PIR/videos) · [David Casler KE0OG Ham Radio](https://www.youtube.com/@DavidCasler/videos)
- *Hesperian (lot)* : [Where There Is No Psychiatrist (Patel)](https://www.rcpsych.ac.uk/docs/default-source/members/faculties/international/where-there-is-no-psychiatrist.pdf)
- *Bibliothèque technique du Peace Corps* : [PC_Agroforestry.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0006_agroforestry.pdf) · [PC_Small_Farm_Grain_Storage.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0035_smallfarmgrain.pdf) · [PC_Soil_and_Water_Conservation.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0036_soilconservation.pdf) · [PC_Fishpond_Construction.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0008_fishpond.pdf) · [PC_Forestry.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0026_forestry.pdf) · [PC_Solar_Drying.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0038_solardrying.pdf) · [PC_Windmill_Construction.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0030_windmill.pdf) · [PC_Biogas.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0011_biogas.pdf) · [PC_Appropriate_Technology.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0036_apptechnology.pdf) · [PC_Water_Purification.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0012_waterpurification.pdf) · [PC_Vegetable_Production.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0029_vegproduction.pdf) · [PC_Food_Preservation.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0010_foodpreservation.pdf) · [PC_Beekeeping.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0007_beekeeping.pdf) · [PC_Small_Animal_Husbandry.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0013_smallanimal.pdf) · [PC_Grain_Legumes.pdf](https://files.peacecorps.gov/multimedia/pdf/library/M0023_grainlegumes.pdf)

### Santé mentale (`download/mental_health.sh`)

- *Premiers secours psychologiques (français)* : [OMS — Les premiers secours psychologiques : guide pour les acteurs de terrain](https://terrorvictimresponse.ca/wp-content/uploads/9789242548204_fre.pdf) · [PSP — module 2](https://mhpsshub.org/wp-content/uploads/2020/11/12007_psc_pfa_modul2_T2_fr_FR_high-res.pdf) · [PSP — module 3](https://mhpsshub.org/wp-content/uploads/2020/11/12007_psc_pfa_modul3_T2_fr_FR_high-res.pdf) · [PSP — module 4 : soutien en groupes](https://mhpsshub.org/wp-content/uploads/2020/02/Premiers-Secour-Psychologique-Soutien-en-groupes-Module-4-1.pdf)
- *Premiers secours psychologiques (anglais)* *(pack English, `CONTENT_MENTAL_EN`)* : [WHO Psychological First Aid Field Guide](https://iris.who.int/handle/10665/44615) · [WHO PFA Facilitator Manual](https://iris.who.int/handle/10665/44427) · [UNHCR Community Mental Health Guide](https://www.unhcr.org/media/community-mental-health-guide-humanitarian-settings) · [IASC Guidelines on Mental Health in Emergencies](https://interagencystandingcommittee.org/system/files/2020-11/IASC%20Guidelines%20on%20Mental%20Health%20and%20Psychosocial%20Support%20in%20Emergency%20Settings.pdf)
- *Psychologie des catastrophes (anglais)* *(pack English, `CONTENT_MENTAL_EN`)* : [CDC NIOSH Trauma and Recovery](https://www.cdc.gov/niosh/docs/2004-101/pdfs/2004-101.pdf) · [SAMHSA Disaster Behavioral Health Guide](https://store.samhsa.gov/sites/default/files/pep21-01-01-001.pdf) · [FEMA Crisis Counseling Guide](https://www.fema.gov/sites/default/files/2020-07/fema_ccp_guidance-manual.pdf)
- *Résilience (anglais)* *(pack English, `CONTENT_MENTAL_EN`)* : [Sphere Standards — Protection & MHPSS](https://sphere-standards-media.s3.eu-central-1.amazonaws.com/app/uploads/2026/07/02150526/Sphere-Handbook-2018-EN.pdf) · [Building Community Resilience Toolkit (CDC)](https://www.cdc.gov/cpr/resiliencetoolkit/pdf/Community_Resilience_Toolkit.pdf) · [Where There Is No Psychiatrist (Patel)](https://www.rcpsych.ac.uk/docs/default-source/members/faculties/international/where-there-is-no-psychiatrist.pdf)
- *Deuil (anglais)* *(pack English, `CONTENT_MENTAL_EN`)* : [Red Cross Grief Support Guide](https://www.redcross.org/content/dam/redcross/atg/PDF_s/Preparedness___Disaster_Recovery/Disaster_Preparedness/Coping_with_Grief_and_Loss.pdf)

### Vidéos (`download/videos.sh`, téléchargées avec yt-dlp)

**En français**

- *Survie et bushcraft* : [Invictus France — Bushcraft & Survie](https://www.youtube.com/channel/UCKPcuCK3FyZvIDS0gB842Yg/videos) · [Alban Cambe — Bushcraft & navigation naturelle](https://www.youtube.com/channel/UCu0B8D0Xa8NWSMidJGS_wMw/videos) · [Sankhoï — Survie Bushcraft](https://www.youtube.com/channel/UCphU_Qd6MzWFGQ-arUPm6Wg/videos) · [Skol Louarn — Bushcraft, survie, rando](https://www.youtube.com/channel/UCHFG1iDURjUcA6ViSdsILiQ/videos)
- *Médical et premiers secours* : [Croix-Rouge française — Formations premiers secours](https://www.youtube.com/playlist?list=PL9tJFzSvOEC1Si34LO1PsMMdxemHeP42A)
- *Alimentation et potager* : [Popote et Potager](https://www.youtube.com/channel/UCiusFKWbx0TV8t9WM1GLizA/videos)
- *Culture et permaculture* : [École de permaculture du Bec Hellouin](https://www.youtube.com/channel/UCzgsQwiy6sKt6Ne9aDXGc5Q/videos)
- *Habitat* : [Maison-Construction.com](https://www.youtube.com/@maison-construction/videos)
- *Énergie* : [L'énergie partout](https://www.youtube.com/channel/UCKTJiNMMxk2W0CpOxPLoUkQ/videos)
- *Outils et bricolage* : [Le Coin des Bricoleurs](https://www.youtube.com/@LECOINDESBRICOLEURS/videos) · [Fix Ta Maison](https://www.youtube.com/@fixtamaison/videos) · [Robert Longechal](https://www.youtube.com/user/robertlongechal/videos)
- *Savoir-faire* : [Low-tech Lab](https://www.youtube.com/channel/UCu6mFdACj_quODcUujiT62Q/videos)
- *Radio et préparation* : [Radioamateur par F4HTZ](https://www.youtube.com/@radio.f4htz/videos) · [Cours de préparation à la licence radioamateur (F4KLH)](https://www.youtube.com/playlist?list=PLjg_1YSBWRdtxJ1YgU-0--RgE0Q0hTWRy)

**Pack English** (`CONTENT_VIDEOS_EN`, désactivé par défaut)

- *Survie et bushcraft* : [Canadian Prepper](https://www.youtube.com/@CanadianPrepper/videos) · [SensiblePrepper](https://www.youtube.com/@SensiblePrepper/videos) · [City Prepping](https://www.youtube.com/@cityprepping/videos) · [Survival Lilly](https://www.youtube.com/@SurvivalLilly/videos) · [Corporals Corner](https://www.youtube.com/@CorporalsCorner/videos) · [Primitive Technology](https://www.youtube.com/@primitivetechnology9550/videos)
- *Médical et premiers secours* : [Medcram Medical](https://www.youtube.com/@MedCram/videos) · [Wilderness Medical Associates](https://www.youtube.com/@WildernessMA/videos) · [Rethink Survival Medical](https://www.youtube.com/@RethinkSurvival/videos) · [Doom and Bloom Survival Medicine](https://www.youtube.com/@DoomandBloom/videos) · [The Patriot Nurse](https://www.youtube.com/@ThePatriotNurse/videos) · [Skinny Medic TCCC](https://www.youtube.com/@SkinnyMedic/videos) · [Lone Star Medics](https://www.youtube.com/@LoneStarMedics/videos) · [Stop the Bleed Official](https://www.youtube.com/playlist?list=PLUHBLmZ-rPXKlFmS7gZO77Lft5WT8DXH4) · [FEMA First Aid](https://www.youtube.com/playlist?list=PL56C96E2FBDB2CCEA)
- *Élevage* : [Weed em and Reap (chickens/goats)](https://www.youtube.com/@WeedEmandReap/videos) · [Prairie Homestead (goats/cattle)](https://www.youtube.com/@theprairiehomestead/videos) · [Jill Winger Old Fashioned On Purpose](https://www.youtube.com/@jillwinger/videos) · [Becky's Homestead (rabbits/chickens)](https://www.youtube.com/@BeckysHomestead/videos) · [Homestead Corner (goats)](https://www.youtube.com/@HomesteadCorner/videos) · [Kathy Voth Small-Scale Grazing](https://www.youtube.com/@KathyVoth/videos)
- *Alimentation et potager* : [The Elliott Homestead](https://www.youtube.com/@TheElliottHomestead/videos) · [Justin Rhodes Homesteading](https://www.youtube.com/@JustinRhodes/videos) · [Homesteading Family](https://www.youtube.com/@HomesteadingFamily/videos) · [Townsends Historical Cooking](https://www.youtube.com/@Townsends/videos)
- *Culture et permaculture* : [Charles Dowding No-Dig](https://www.youtube.com/@CharlesDowding1/videos) · [Back to Reality (permaculture)](https://www.youtube.com/@BacktoReality/videos) · [OSU Extension](https://www.youtube.com/@OSUExtension/videos)
- *Eau* : [The Prepared](https://www.youtube.com/@ThePrepared/videos) · [Water Purification Methods](https://www.youtube.com/playlist?list=PLK2c-rTCIuqJAXKNNGOJr8xShz5HgONzj)
- *Habitat* : [Essential Craftsman](https://www.youtube.com/@EssentialCraftsman/videos) · [Matt Risinger Build](https://www.youtube.com/@MattRisinger/videos) · [Log Cabin Builders](https://www.youtube.com/@LogCabinBuilders/videos) · [Stoney Ridge Farmer](https://www.youtube.com/@stoneyridgefarmer/videos)
- *Énergie* : [LDSPrepper Solar](https://www.youtube.com/@LDSPrepper/videos) · [Will Prowse Solar](https://www.youtube.com/@WillProwse/videos) · [Off Grid with Doug & Stacy](https://www.youtube.com/@OffGridwithDougStacy/videos) · [BPS Solar](https://www.youtube.com/@BPSsolar/videos)
- *Outils et bricolage* : [This Old House](https://www.youtube.com/@thisoldhouse/videos) · [Paul Sellers Woodworking](https://www.youtube.com/@PaulSellersWoodworking/videos) · [AvE Engineering](https://www.youtube.com/@avoandace/videos) · [Clickspring Metalwork](https://www.youtube.com/@clickspring/videos)
- *Radio et préparation* : [Ham Radio Crash Course](https://www.youtube.com/@HamRadioCrashCourse/videos) · [Survival Dispatch](https://www.youtube.com/@SurvivalDispatch/videos) · [ITS Tactical](https://www.youtube.com/@ITSTactical/videos) · [FEMA Ready](https://www.youtube.com/@FEMAReady/videos)

### Cartes (`download/maps.sh`)

- [OpenStreetMap — extraits Geofabrik](https://download.geofabrik.de/) : France (par défaut), Europe, Amérique du Nord, Amérique du Sud, Afrique, Asie, Australie-Océanie, États-Unis et Nouvelle-Angleterre ; [planète entière](https://planet.openstreetmap.org/) en option (`MAP_REGION`).
- [Protomaps — builds de tuiles vectorielles](https://maps.protomaps.com/builds/) (`build.protomaps.com`), extraites avec la commande `pmtiles` ([protomaps/go-pmtiles](https://github.com/protomaps/go-pmtiles)).
- [Protomaps — polices et sprites des cartes](https://protomaps.github.io/basemaps-assets) (`maps/fonts`, `maps/sprites`).
- [Tuiles satellite basse résolution (IIAB)](https://download.iiab.io/content/OSM/vector-tiles/) — surcouche satellite z0–z6.
- [USGS — The National Map](https://apps.nationalmap.gov/downloader/) (API `tnmaccess.nationalmap.gov`, index `prd-tnm.s3.amazonaws.com`) — cartes topographiques américaines, `CONTENT_NPS_MAPS`.
- [npmaps.com](https://npmaps.com/) — cartes PDF des parcs nationaux américains (`CONTENT_NPS_MAPS`, désactivé par défaut).
- [IGN — Géoservices](https://geoservices.ign.fr/telechargement) : non téléchargé automatiquement, mémo de téléchargement manuel.

### Cours et éducation

- [Kolibri — chaîne « Khan Academy (Français) »](https://studio.learningequality.org/) (identifiant `878ec2e6f88c5c268b1be6f202833cd4`), importée depuis Learning Equality (`download/kolibri_content.sh`).
- Kiwix : Khan Academy FR, TED, PhET, Wikiversité, Vikidia (voir « Bibliothèques Kiwix »).

### Médicaments

- [Base de données publique des médicaments (BDPM)](https://base-donnees-publique.medicaments.gouv.fr/) — ministère de la Santé / ANSM : fichiers de base (`download/file/…`) et notices officielles (RCP) récupérées une à une (`download/drug_reference.sh`, `scripts/build_drug_index.py`, `scripts/fetch_drug_notices.py`).

### Transmissions radio (`download/comms.sh`)

- [Meshtastic Web](https://github.com/meshtastic/web) — client web (`releases/latest/download/build.tar`), servi sur le port 8084.
- [MeshCore](https://files.liamcottle.net/MeshCore) — client web et applications Android / Windows (fichiers de Liam Cottle), port 8085.
- Relais radioamateurs : **non inclus** ; vous importez vos propres exports CSV (par exemple RepeaterBook) dans `comms/repeaters/`.

### Dépôt d'applications hors ligne (`download/app_depot.sh`)

- [Kiwix Android](https://download.kiwix.org/release/kiwix-android/) et [Kiwix Desktop](https://download.kiwix.org/release/kiwix-desktop/) (dernières versions du miroir).
- [F-Droid](https://f-droid.org/) (`F-Droid.apk`).
- [VLC pour Windows](https://get.videolan.org/vlc/last/win64/).
- MeshCore Android / Windows (voir « Transmissions radio »).

### Logiciels installés (`setup/`, `ai/`, `requirements.txt`)

- **Système :** paquets Debian / Raspberry Pi OS (git, curl, wget, aria2, rsync, python3, ffmpeg, vlc, nginx, sqlite3, zstd, p7zip, poppler-utils, ufw, jq, avahi, samba, ntfs-3g, exfatprogs, rclone, chrony, fuse3, calibre) ; paquet `hailo-all` du dépôt Raspberry Pi OS pour l'AI Hat.
- **Kiwix :** [kiwix-tools](https://download.kiwix.org/release/kiwix-tools/) (paquet Debian, sinon binaire du projet Kiwix).
- **Intelligence artificielle :** [Ollama](https://ollama.com/) (script d'installation officiel `ollama.ai/install.sh`) et modèles de sa bibliothèque : `gemma4:e2b`, `gemma4:e4b`, `gemma4:12b`, `gemma3:4b`, `gemma3:12b-it-q4_K_M` selon la RAM.
- **Apprentissage :** [Kolibri](https://learningequality.org/kolibri/) (PyPI).
- **Livres :** [Calibre](https://calibre-ebook.com/) (`download.calibre-ebook.com`) et [Calibre-Web](https://github.com/janeczku/calibre-web) (PyPI `calibreweb`).
- **Vidéos :** [Jellyfin](https://jellyfin.org/) (dépôt `repo.jellyfin.org`) et [yt-dlp](https://github.com/yt-dlp/yt-dlp) (GitHub).
- **Cartes :** serveur de tuiles [Martin](https://github.com/maplibre/martin) (versions GitHub `maplibre/martin`) ; bibliothèques intégrées à `web/static/vendor/` : MapLibre GL JS, PMTiles, `@protomaps/basemaps` (licences dans le même dossier).
- **Tableau de bord :** Flask, Flask-WTF, Flask-Limiter, gunicorn, requests, tqdm, PyYAML (voir `requirements.txt`).

### Listes personnelles (aucune source par défaut)

- `config/gaps_extra.list`, `config/pdfs_extra.list`, `config/mental_health_extra.list`, `config/videos_extra.list` : vos propres documents et chaînes, déclarés ligne par ligne.

<!-- SOURCES:END -->

---

## Licence

Les contenus sont soumis aux licences propres à chaque source (Creative Commons, domaine public, etc.). Voir `docs/licenses.md`.

Le dépôt d'origine ne fournit pas de fichier de licence pour son code : avant de redistribuer ce fork, vérifiez les conditions auprès de son auteur.
