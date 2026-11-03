# Guide de démarrage rapide SurviveV1

## Ce qu'il vous faut

- Raspberry Pi 5 (4 Go ou 8 Go de RAM)
- AI Hat (Hailo-8L, enfiché dans le connecteur M.2)
- SSD USB 3.0 ou NVMe de 512 Go à 1 To (via USB 3.1 ou adaptateur M.2)
- Écran portable (HDMI)
- Batterie externe (20 000 mAh ou plus, USB-C PD 45 W ou plus)
- Carte microSD (32 Go ou plus) avec Raspberry Pi OS 64 bits Bookworm

---

## Étape 1 : Préparer le Pi

```bash
# Flasher Raspberry Pi OS (64 bits) sur la carte SD avec Raspberry Pi Imager
# Activer SSH dans les réglages d'Imager
# Démarrer, puis se connecter au Pi en SSH ou avec clavier/écran
```

---

## Étape 2 : Cloner et installer

```bash
# Cloner le dépôt (remplacez l'URL par votre fork ou un chemin local)
git clone https://github.com/lolly76/SurviveV1-FR.git ~/SurviveV1
cd ~/SurviveV1

# Lancer l'installateur (15 à 30 minutes)
sudo bash setup/install.sh
```

L'installateur va :
- Mettre à jour le système
- Installer tous les logiciels nécessaires (Kiwix, Kolibri, Jellyfin, Calibre, Ollama, nginx)
- Configurer le partage réseau (Samba, mDNS)
- Configurer le pare-feu
- Installer les services systemd

---

## Étape 3 : Monter votre disque de stockage

```bash
# Repérer votre disque
lsblk

# Formater s'il est neuf (ATTENTION : efface toutes les données)
sudo mkfs.ext4 /dev/sda1  # remplacez sda1 par votre disque

# Monter
sudo mkdir -p /mnt/survive
sudo mount /dev/sda1 /mnt/survive

# Montage automatique au démarrage
echo "UUID=$(sudo blkid -s UUID -o value /dev/sda1)  /mnt/survive  ext4  defaults,noatime  0  2" | sudo tee -a /etc/fstab
```

---

## Étape 4 : Configurer

```bash
# Modifier la configuration
nano ~/SurviveV1/config/survive.conf

# Réglages principaux :
# SURVIVE_STORAGE_PATH="/mnt/survive"
# MAP_REGION="france"        (ou europe, world, etc.)
# CONTENT_VIDEOS="Y"          (mettre N pour ignorer)
```

---

## Étape 5 : Télécharger les contenus

```bash
# Tout télécharger (cela prendra DES JOURS — laissez tourner la nuit)
bash download/download_all.sh

# Ou télécharger certaines catégories seulement :
bash download/kiwix_content.sh          # Wikipédia FR et ZIM français (~90 Go)
bash download/videos.sh                  # Vidéos de survie (~150 Go)
bash download/books_pdfs.sh              # PDF/livres (~20 Go)
bash download/maps.sh --region france    # Cartes de France (~5 Go)
bash download/kolibri_content.sh         # Khan Academy FR (~200 Go)
```

**Durées de téléchargement (connexion à 100 Mbit/s) :**

| Contenu | Taille | Durée estimée |
|---------|--------|---------------|
| Wikipédia FR | 52 Go | ~1,5 heure |
| Vidéos | 150 Go | ~4 heures |
| Cartes (France) | 5 Go | ~10 min |
| Khan Academy | 200 Go | ~5 heures |
| PDF/livres | 20 Go | ~30 min |

---

## Étape 6 : Configurer l'IA

```bash
# Télécharger les modèles d'IA
bash ai/setup_ollama.sh

# Ou télécharger un modèle précis à la main
ollama pull phi3:mini    # 2,3 Go — recommandé pour le RPi5
ollama pull tinyllama    # 637 Mo — très rapide, qualité basique
```

---

## Étape 7 : Tout démarrer

```bash
# Première fois : générer les fichiers de service systemd pour votre chemin de stockage
sudo bash scripts/generate_services.sh

# Activer les services au démarrage
sudo systemctl enable survive-dashboard kiwix ollama martin-tiles kolibri

# Démarrer tous les services maintenant
sudo systemctl start survive-dashboard kiwix ollama martin-tiles

# Ou utiliser le script pratique (fonctionne avec ou sans systemd)
bash scripts/start_services.sh
```

**Gérer chaque service avec systemctl :**
```bash
# Voir l'état
sudo systemctl status survive-dashboard

# Redémarrer un service
sudo systemctl restart kiwix

# Suivre les journaux en direct
sudo journalctl -u ollama -f

# Arrêter tous les services SurviveV1
sudo systemctl stop survive-dashboard kiwix ollama martin-tiles kolibri
```

Ouvrir dans le navigateur :
- Depuis le Pi : `http://localhost:8080`
- Depuis un autre appareil : `http://survive.local:8080`

---

## Étape 8 : Sauvegarde dans le cloud (facultatif)

À faire tant que vous avez Internet, pour pouvoir restaurer plus tard.

```bash
# Configurer le stockage cloud
bash sync/setup_rclone.sh gdrive     # Google Drive
bash sync/setup_rclone.sh dropbox    # Dropbox

# Synchroniser vers le cloud
bash sync/sync_to_cloud.sh gdrive

# Programmer une synchronisation automatique quand Internet est disponible
sudo bash sync/schedule_sync.sh gdrive
```

---

## Accéder à votre système

### Depuis le Pi lui-même :
- Ouvrir le navigateur : `http://localhost:8080`

### Depuis d'autres appareils du même réseau :
- Navigateur : `http://survive.local:8080`
- Ou : `http://192.168.1.X:8080` (remplacez par l'IP du Pi)

### Partage de fichiers :
- Windows : `\\survive\survive`
- Mac : `smb://survive/survive`
- Linux : `smb://survive/survive`

---

## Ports des services

| Service | URL |
|---------|-----|
| Tableau de bord principal | http://survive.local:8080 |
| Wikipédia | http://survive.local:8081 |
| Khan Academy | http://survive.local:8082 |
| Livres numériques | http://survive.local:8083 |
| Vidéos | http://survive.local:8096 |
| Cartes | http://survive.local:3000 |
| Discussion avec l'IA | http://survive.local:8080/ai |

---

## Conseils d'alimentation

| Configuration | Autonomie |
|---------------|-----------|
| Pi 5 + écran | ~5 à 6 heures avec 20 000 mAh |
| Pi 5 seul (sans écran) | ~10 à 12 heures |
| Pi 5 + panneau solaire | Illimitée |

- Utilisez `sudo vcgencmd get_throttled` pour détecter les problèmes d'alimentation
- Utilisez `sudo cpufreq-set -g powersave` pour prolonger l'autonomie

---

## Dépannage

**Le tableau de bord ne se charge pas :**
```bash
bash scripts/status.sh
tail -f /tmp/survive_dashboard.log
```

**Wikipédia n'affiche aucun contenu :**
```bash
ls /mnt/survive/zim/
# Doit afficher des fichiers .zim
bash scripts/start_services.sh  # redémarrer kiwix
```

**L'IA ne répond pas :**
```bash
ollama serve &
ollama list    # vérifier que les modèles sont installés
```

**Plus d'espace disque :**
```bash
df -h /mnt/survive
du -sh /mnt/survive/*   # repérer les plus gros dossiers
```
