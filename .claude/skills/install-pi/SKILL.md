---
name: install-pi
description: Installation guidée complète de SurviveV1-FR sur un Raspberry Pi 5 — système, installation en une commande, assistant, téléchargement des contenus, vérification et dépannage. À utiliser quand l'utilisateur demande comment installer, déployer ou réinstaller SurviveV1 sur un Raspberry Pi, ou réclame des instructions d'installation.
---

# Guide d'installation de SurviveV1-FR sur Raspberry Pi

Accompagnez l'utilisateur dans l'installation de bout en bout, en français. Adaptez-vous à son avancement :
si le système est déjà flashé ou le dépôt déjà cloné, passez à l'étape suivante. Demandez où il en est
si ce n'est pas évident.

## Phase 0 — Matériel

Vérifiez que l'utilisateur dispose de :

- **Raspberry Pi 5** (4 Go suffisent ; 8 Go confortable ; 16 Go ouvre le plus gros modèle d'IA)
- **SSD USB 3.0 ou NVMe** — 256 Go minimum, 800 Go et plus recommandés (contient tous les contenus)
- **Carte microSD** (32 Go ou plus) pour le système
- Facultatif : AI Hat Hailo-8L (accélère la vision uniquement — le LLM tourne sur le processeur dans tous les cas)
- Internet pendant l'installation seulement ; ensuite le système fonctionne à 100 % hors ligne

La RAM détermine le niveau de modèle d'IA choisi automatiquement :

| RAM | Modèle | Vitesse |
|-----|--------|---------|
| < 6 Go | gemma4:e2b | la plus rapide |
| ≥ 6 Go | gemma4:e4b | équilibré |
| ≥ 14 Go | gemma4:12b | meilleure qualité, ~1–3 tok/s |

## Phase 1 — Flasher le système

1. Télécharger Raspberry Pi Imager : https://www.raspberrypi.com/software
2. Choisir **Raspberry Pi OS (64 bits), Bookworm**. Le 64 bits est OBLIGATOIRE (aarch64) —
   le script d'amorçage refuse les systèmes 32 bits.
3. Dans les réglages d'Imager : définir nom d'utilisateur, Wi-Fi, pays Wi-Fi (France) et activer SSH pour une installation sans écran.
4. Flasher, insérer la carte SD, brancher le SSD sur un **port USB 3.0 bleu**, allumer.

## Phase 2 — Installation en une commande

Vérifiez sur quelle branche se trouve le code (`git branch -a`) avant de donner la commande.
Le script d'amorçage utilise `main` par défaut ; si le code est sur une autre branche, utilisez la forme
avec `SURVIVE_BRANCH`.

Depuis `main` :

```bash
curl -fsSL https://raw.githubusercontent.com/lolly76/SurviveV1-FR/main/install/bootstrap.sh | bash
```

Depuis une branche (remplacez par le vrai nom) :

```bash
curl -fsSL https://raw.githubusercontent.com/lolly76/SurviveV1-FR/<BRANCHE>/install/bootstrap.sh | SURVIVE_BRANCH=<BRANCHE> bash
```

Variables d'environnement : `SURVIVE_REPO` (URL d'un autre fork), `SURVIVE_DIR` (dossier de clonage,
`~/SurviveV1` par défaut).

Le script vérifie aarch64 + Bookworm + Internet, installe git si besoin, clone le dépôt, puis lance
l'assistant interactif avec sudo.

## Phase 3 — L'assistant (quoi dire à chaque question)

1. **Bienvenue** — affiche la RAM détectée et le niveau de modèle d'IA qui sera installé.
2. **Stockage** — liste les disques USB (carte SD et périphériques loop masqués pour qu'on ne puisse pas choisir le disque
   de démarrage). Le formatage est DESTRUCTIF et doublement protégé : une question o/n, puis il faut taper
   littéralement `formater`. Le disque est monté sur `/mnt/survive` et ajouté à /etc/fstab par UUID.
   - Si le disque contient déjà un système de fichiers à conserver, le choisir SANS le formater — l'assistant détecte les montages existants.
3. **Nom d'hôte** — `survive` par défaut → tableau de bord sur `http://survive.local`.
4. **Région des cartes** — **France** par défaut (~5 Go) ; choisir une autre région ou `world` (~70 Go) seulement si nécessaire.
5. **Récapitulatif** — relire et confirmer ; l'installation des logiciels dure 15 à 30 min.
6. **Téléchargement du modèle d'IA** — conseillé (~8 Go pour gemma4:12b sur un Pi 16 Go). Les réponses de l'assistant sont en français.

## Phase 4 — Téléchargement des contenus (séparé, long)

Logiciels et contenus sont séparés. Les contenus peuvent atteindre ~800 Go et prendre des jours.

```bash
cd ~/SurviveV1
# Facultatif d'abord : éditer config/survive.conf — options CONTENT_*, VIDEO_QUALITY,
# SURVIVE_BANDWIDTH_LIMIT (octets/s), MAP_REGION.

bash download/download_all.sh --dry-run          # aperçu du budget de taille
tmux new -s download                             # survit aux déconnexions SSH
bash download/download_all.sh --storage /mnt/survive
# Détacher : Ctrl+B puis D. Rattacher : tmux attach -t download
```

Interrompu ? `--resume` saute les catégories déjà terminées dans `/mnt/survive/.download_progress`.
Une seule catégorie : `--only kiwix`, `--only videos`, `--only books`, `--only maps`, `--only kolibri`.

Contenus en anglais : le pack « English » des contenus experts (`CONTENT_GAPS_EN`) est activé par défaut ;
les extras anglais (`CONTENT_STACKEXCHANGE_EN`, `CONTENT_EXPANSION_EN`) sont désactivés. Les notices de médicaments
(BDPM) se récupèrent lentement et peuvent être reprises à tout moment (`bash download/drug_reference.sh`).

Conseillez l'Ethernet filaire et un lancement de nuit.

## Phase 5 — Vérifier l'installation

```bash
cd ~/SurviveV1
make status                          # tous les services au vert ?
curl -sf http://localhost:8080/health          # {"status":"ok"}
curl -sf http://localhost:8080/api/status | python3 -m json.tool
curl -sf http://localhost:8080/api/connectivity  # {"online": true/false}
```

Puis le **test hors ligne** — tout l'intérêt du système. Débranchez l'Ethernet / coupez le Wi-Fi et vérifiez :

1. Le tableau de bord se charge toujours sur `http://survive.local:8080`
2. Le bandeau de la page d'accueil passe à « Mode hors ligne : ACTIF »
3. Wikipédia (:8081) sert toujours les articles
4. Le chat IA répond encore (lentement — inférence sur CPU)

## Phase 6 — Adresses d'accès

| Service | Adresse |
|---------|---------|
| Tableau de bord | http://survive.local:8080 |
| Assistant IA | http://survive.local:8080/ai |
| Wikipédia (Kiwix) | http://survive.local:8081 |
| Khan Academy (Kolibri) | http://survive.local:8082 |
| Livres numériques (Calibre-Web) | http://survive.local:8083 |
| Vidéos (Jellyfin) | http://survive.local:8096 |
| Cartes | http://survive.local:8080/maps |
| Médicaments | http://survive.local:8080/drugs |

Si `survive.local` ne se résout pas (courant sur Android) : utilisez l'IP du Pi —
`hostname -I` sur le Pi, ou l'encadré affiché par `make start`.

## Gestion courante

```bash
make start / make stop / make status   # contrôle des services
make test                              # lint + tests de fumée
bash scripts/update_content.sh         # actualiser les contenus quand on est en ligne
bash sync/setup_rclone.sh              # sauvegarde cloud facultative
git -C ~/SurviveV1 pull && make start  # mettre à jour le logiciel
```

## Dépannage rapide

| Symptôme | Solution |
|----------|----------|
| Échec de la vérification préalable | lancer seul `bash setup/pre_flight_check.sh` pour voir quel test |
| Bandeau « Disque de stockage non monté » | `lsblk`, puis `sudo mount /mnt/survive` ; vérifier l'entrée /etc/fstab |
| Service arrêté | journaux dans `/tmp/*.log` ou `journalctl -u survive-dashboard` |
| survive.local injoignable | utiliser l'IP ; le mDNS demande Avahi (installé par défaut sur Pi OS) |
| IA lente | normal — inférence CPU ; choisir gemma4:e4b ou e2b dans la liste |
| Erreurs de l'IA | `curl localhost:11434/api/tags` — Ollama tourne ? `ollama list` — modèle présent ? |
| Téléchargement bloqué | Ctrl+C puis relancer avec `--resume` ; régler SURVIVE_BANDWIDTH_LIMIT |
| Disque plein en cours de route | désactiver des catégories dans survive.conf, supprimer les fichiers partiels, `--resume` |

## Désinstaller / repartir de zéro

```bash
bash scripts/stop_services.sh
sudo systemctl disable --now survive-dashboard kiwix ollama kolibri calibre-web martin-tiles 2>/dev/null
rm -rf ~/SurviveV1            # code
# Le contenu de /mnt/survive n'est pas touché — reformatez via l'assistant pour l'effacer.
```
