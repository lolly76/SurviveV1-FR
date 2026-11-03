# SurviveV1-FR — Base de connaissances de survie hors ligne

> Fork francophone de [schwadb/SurviveV1](https://github.com/schwadb/SurviveV1). Le code d'origine est de son auteur ; ce fork traduit l'interface, la documentation et l'assistant IA en français.

Une base de connaissances autohébergée, pensée « hors ligne d'abord », pour les scénarios de survie en cas d'effondrement ou de coupure du réseau électrique. Elle tourne sur un **Raspberry Pi 5 avec AI Hat**, s'utilise avec un écran portable et une batterie externe, et peut contenir jusqu'à **800 Go** de connaissances de survie sélectionnées.

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

> **Avancement de la francisation des sources.** Fait : interface du tableau de bord, scripts d'installation, de démarrage et de téléchargement (messages en français), ZIM Kiwix, cartes, Kolibri, vidéos, livres/PDF, premiers secours psychologiques (OMS et Croix-Rouge), référence des médicaments (BDPM), documentation (`docs/`, page `index.html`, skill `install-pi`). Les contenus « experts » (médecine avancée, obstétrique, dentaire, assainissement, élevage, semences, forge, apiculture, sécurité…) n'ont pas d'équivalent français vérifié : ils sont conservés en anglais dans un **pack « English »** identifié (`CONTENT_GAPS_EN`, activé par défaut) ; vos documents français s'ajoutent via `config/gaps_extra.list`. Référence des médicaments : désormais basée sur la BDPM française (`CONTENT_DRUG_NOTICES="N"` pour ne garder que les fichiers de base ; `SURVIVE_DRUGS_NOTICE_MAX` limite la récupération des notices à chaque passage). L'**assistant IA** est aussi francisé (prompt système du modèle `survive`, scripts `ai/` et Hailo, `docs/ai_hat_setup.md`). `docs/gaps_analysis.md` est traduit. Les plans de conception `docs/plans/` sont également traduits. Vérifié en ligne le 3 novembre 2026 : fichiers et formats BDPM, pages de notices (redirection vers la fiche « extrait »), lien de la fiche officielle, URL Geofabrik, noms et tailles des ZIM Kiwix français, existence de la chaîne Kolibri. Quelques ressources n'existent qu'en anglais (Stack Exchange pratiques, collections « zimgit », Appropedia, Energypedia, manuels militaires américains et PDF techniques, chaînes YouTube anglophones, PDF et vidéos de santé mentale) : elles sont proposées en option, désactivées par défaut (`CONTENT_STACKEXCHANGE_EN`, `CONTENT_EXPANSION_EN`, `CONTENT_PDFS_EN`, `CONTENT_VIDEOS_EN`, `CONTENT_MENTAL_EN` dans `config/survive.conf`).

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

- **Matériel :** Raspberry Pi 5 (4 Go de RAM ou plus recommandés), AI Hat (Hailo-8L)
- **Stockage :** SSD USB 3.0 ou NVMe (256 Go minimum, 800 Go recommandés)
- **Alimentation :** Batterie externe (20 000 mAh ou plus) ou solaire + batterie
- **Système :** Raspberry Pi OS (64 bits, Bookworm)
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

## Licence

Les contenus sont soumis aux licences propres à chaque source (Creative Commons, domaine public, etc.). Voir `docs/licenses.md`.

Le dépôt d'origine ne fournit pas de fichier de licence pour son code : avant de redistribuer ce fork, vérifiez les conditions auprès de son auteur.
