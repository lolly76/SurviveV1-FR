# Guide de dépannage SurviveV1

## Emplacement des journaux

| Service | Fichier journal |
|---------|-----------------|
| Tableau de bord | `/var/log/survive_dashboard.log` |
| Kiwix | `/var/log/survive_kiwix.log` |
| Ollama | `/var/log/survive_ollama.log` |
| Cartes (Martin) | `/var/log/survive_maps.log` |
| Kolibri | `/var/log/survive_kolibri.log` |
| nginx | `/var/log/nginx/survive_access.log` |
| Erreurs de téléchargement | `/mnt/survive/.logs/failed_downloads.log` |
| Démarrage manuel | `/tmp/survive_dashboard.log` |

Suivre un journal en temps réel : `tail -f /var/log/survive_dashboard.log`

---

## Le tableau de bord ne se charge pas

**Symptôme :** le navigateur affiche « Connexion refusée » sur http://survive.local:8080

```bash
# Vérifier l'état des services
bash scripts/status.sh

# Vérifier que Flask tourne
ps aux | grep server.py

# Démarrer à la main et surveiller les erreurs
source /opt/survive/venv/bin/activate
cd web && python3 server.py

# Vérifier l'état systemd
sudo systemctl status survive-dashboard
sudo journalctl -u survive-dashboard -n 50
```

**Causes fréquentes :**
- Environnement virtuel Python non activé — l'installation s'est terminée mais le venv manque : `python3 -m venv /opt/survive/venv && pip install -r requirements.txt`
- Port 8080 déjà utilisé : `ss -tlnp | grep 8080`
- Fichier `config/.secret_key` manquant — lancez une fois `python3 web/server.py` pour le générer

---

## Wikipédia / Kiwix n'affiche aucun contenu

**Symptôme :** « Aucun résultat » ou page Kiwix vide

```bash
# Vérifier que les fichiers ZIM existent
ls /mnt/survive/zim/

# Vérifier le fichier de bibliothèque kiwix
cat /mnt/survive/.kiwix_library.xml | head -5

# Réenregistrer les fichiers ZIM
while IFS= read -r -d '' f; do
    kiwix-manage /mnt/survive/.kiwix_library.xml add "$f" 2>/dev/null
done < <(find /mnt/survive/zim -name "*.zim" -print0)

# Redémarrer kiwix
sudo systemctl restart kiwix
# ou à la main :
kiwix-serve --library /mnt/survive/.kiwix_library.xml --port 8081
```

**Causes fréquentes :**
- Fichiers ZIM pas encore téléchargés — lancez `bash download/kiwix_content.sh`
- Le XML de bibliothèque est vide ou mal formé — supprimez-le et réenregistrez
- Version de Kiwix incompatible — relancez la section kiwix de `bash setup/install.sh`

---

## L'IA ne répond pas

**Symptôme :** bandeau « Service IA arrêté », ou la discussion expire

```bash
# Vérifier qu'Ollama tourne
curl http://localhost:11434/api/tags

# Démarrer Ollama
ollama serve &

# Voir les modèles installés
ollama list

# Télécharger un modèle s'il n'y en a aucun (637 Mo — tient sur le Pi)
ollama pull tinyllama

# Consulter les journaux
sudo journalctl -u ollama -n 30
tail -f /var/log/survive_ollama.log
```

**Causes fréquentes :**
- Aucun modèle installé — lancez `bash ai/setup_ollama.sh`
- Ollama ne tourne pas — `sudo systemctl start ollama`
- Modèle trop gros pour la RAM — utilisez `tinyllama` (637 Mo) ou `phi3:mini` (2,3 Go) sur un Pi 5 de 4 Go

---

## Le disque de stockage ne se monte pas

**Symptôme :** avertissement « Stockage non monté », contenus absents

```bash
# Vérifier que le disque est visible
lsblk
fdisk -l

# Monter à la main
sudo mount /dev/sda1 /mnt/survive

# Vérifier le système de fichiers
sudo fsck /dev/sda1

# Vérifier l'entrée fstab pour le montage automatique
cat /etc/fstab | grep survive

# Ajouter l'entrée fstab (remplacez l'UUID par celui de votre disque, donné par blkid)
UUID=$(sudo blkid -s UUID -o value /dev/sda1)
echo "UUID=$UUID  /mnt/survive  ext4  defaults,noatime  0  2" | sudo tee -a /etc/fstab

# Tester fstab
sudo mount -a
```

---

## Plus d'espace disque

**Symptôme :** les téléchargements échouent, les services ne démarrent pas, erreurs de disque plein

```bash
# Voir l'utilisation globale
df -h /mnt/survive

# Repérer les plus gros dossiers
du -sh /mnt/survive/* | sort -rh | head -20

# Nettoyer les fichiers temporaires de téléchargements incomplets
find /mnt/survive -name "*.aria2" -delete
find /mnt/survive -name "*.part" -delete

# Supprimer les fragments vidéo échoués ou incomplets
find /mnt/survive/videos -name "*.ytdl" -delete
```

---

## Les vidéos ne se lisent pas dans Jellyfin

**Symptôme :** Jellyfin affiche les fichiers mais ne les lit pas

```bash
# Vérifier l'état de Jellyfin
sudo systemctl status jellyfin

# Vérifier que le dossier vidéo est visible
ls /mnt/survive/videos/

# Relancer l'analyse de la médiathèque dans l'interface web de Jellyfin :
# Tableau de bord → Médiathèques → [votre médiathèque] → Analyser toutes les médiathèques
# (Dashboard → Libraries → Scan All Libraries si l'interface est en anglais)

# Chercher des erreurs de transcodage matériel
sudo journalctl -u jellyfin -n 50 | grep -i "error\|transcode"
```

---

## Les cartes ne se chargent pas

**Symptôme :** le serveur de tuiles renvoie une erreur 404 ou des tuiles vides

```bash
# Vérifier la configuration de Martin
cat /mnt/survive/maps/martin_config.yaml

# Vérifier que les fichiers .mbtiles existent
ls /mnt/survive/maps/mbtiles/

# Régénérer la configuration
bash download/maps.sh --region votre-region

# Démarrer Martin à la main
martin --config /mnt/survive/maps/martin_config.yaml --listen-addresses 0.0.0.0:3000

# Consulter les journaux
tail -f /var/log/survive_maps.log
```

---

## Les services démarrent lentement après le boot

**Symptôme :** le tableau de bord se charge, mais les services restent « ARRÊTÉ » pendant les 2 à 3 premières minutes

C'est normal : Kolibri (Khan Academy) met jusqu'à 2 minutes à s'initialiser. Kiwix et Ollama mettent 30 à 60 secondes.

```bash
# Voir l'ordre de démarrage systemd
systemctl list-dependencies survive-dashboard.service

# Voir les temps de démarrage
systemd-analyze blame | head -20
```

---

## Le réseau / mDNS (survive.local) ne se résout pas

**Symptôme :** `http://survive.local` ne fonctionne pas depuis les autres appareils

```bash
# Vérifier qu'avahi tourne
sudo systemctl status avahi-daemon

# Redémarrer avahi
sudo systemctl restart avahi-daemon

# Tester la résolution mDNS
avahi-resolve -n survive.local

# Alternative : utiliser directement l'adresse IP
hostname -I  # affiche l'IP du Pi
# Puis utiliser http://192.168.x.x:8080
```

---

## Échecs de téléchargement — relancer les téléchargements échoués

Après une session de téléchargement, consultez le journal des échecs :

```bash
cat /mnt/survive/.logs/failed_downloads.log
```

Les URL en échec sont consignées avec l'horodatage. Pour relancer un contenu précis :

```bash
# Relancer une catégorie précise
bash download/books_pdfs.sh --storage /mnt/survive

# Tout relancer (les fichiers déjà téléchargés sont ignorés)
bash download/download_all.sh --resume
```

---

## Réinstaller / repartir de zéro

```bash
# Arrêter tous les services
bash scripts/stop_services.sh

# Relancer l'installateur (sans risque)
sudo bash setup/install.sh

# Régénérer les fichiers de service systemd avec votre chemin de stockage
sudo bash scripts/generate_services.sh

# Vérifier la configuration
cat config/survive.conf
```

---

## Mode point d'accès (Wi-Fi hors réseau)

`sudo bash scripts/hotspot.sh enable` fait diffuser par le Pi son propre réseau Wi-Fi (réglages dans `survive.conf` : `SURVIVE_HOTSPOT_SSID` / `_PASS`). Le tableau de bord est alors à **http://10.42.0.1:8080** (le mode partagé de NetworkManager donne toujours l'adresse 10.42.0.1 au Pi) — `survive.local` fonctionne aussi sur le sous-réseau du point d'accès, via mDNS.

**Vous vous êtes enfermé dehors ?** (vous avez activé le point d'accès depuis une session SSH en Wi-Fi et perdu la liaison) : branchez un câble Ethernet, ou **coupez simplement l'alimentation du Pi** — la connexion du point d'accès est créée avec `autoconnect no`, donc un redémarrage ramène au Wi-Fi normal. C'est voulu (un interrupteur de sécurité pour les boîtiers sans écran). Pour rendre au contraire le point d'accès persistant après redémarrage :

```bash
sudo nmcli connection modify survive-hotspot connection.autoconnect yes
```

**Pourquoi le 2,4 GHz ?** Le point d'accès utilise la bande `bg` volontairement : elle fonctionne dans tous les domaines réglementaires (les canaux 5 GHz échouent sans message quand le pays Wi-Fi n'est pas défini), tous les téléphones la gèrent, et elle traverse mieux les murs — le bon compromis en cas de catastrophe.

**Le point d'accès ne démarre pas ?** Définissez d'abord votre pays Wi-Fi : `sudo raspi-config nonint do_wifi_country FR` (ou votre code pays).

**Le téléphone affiche « Erreur de configuration IP » / « Échec de l'obtention de l'adresse IP » ?** Le téléphone s'est associé, mais le pare-feu du Pi (ufw) a rejeté sa requête DHCP. `hotspot.sh enable` ouvre désormais automatiquement DHCP, DNS et le tableau de bord sur `wlan0`, mais si vous avez activé le point d'accès avec une ancienne copie du script, ouvrez-les à la main :

```bash
sudo ufw allow in on wlan0 to any port 67 proto udp   # DHCP
sudo ufw allow in on wlan0 to any port 53             # DNS
sudo ufw allow in on wlan0 to any port 8080 proto tcp # tableau de bord
sudo ufw reload
```

Ensuite, sur le téléphone : oubliez le réseau et reconnectez-vous. Vérifiez que le serveur DHCP tourne bien avec `sudo journalctl -u NetworkManager | grep -i dhcp` — vous devez voir une ligne comme `DHCP, IP range 10.42.0.10 -- 10.42.0.254`.

---

## YouTube « Sign in to confirm you're not a bot »

Les téléchargements yt-dlp échouent avec ce message lorsque YouTube juge la requête automatisée. C'est un changement de politique de YouTube, pas un défaut des scripts de téléchargement — et il va et vient.

Solutions, de la moins coûteuse à la plus coûteuse :

```bash
# 1. Mettre à jour yt-dlp — le projet publie en permanence des correctifs contre ces blocages
sudo yt-dlp -U    # ou : sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp && sudo chmod +x /usr/local/bin/yt-dlp
```

```bash
# 2. Fournir les cookies d'une session YouTube connectée.
#    Dans le navigateur du bureau du Pi, installez une extension « Get cookies.txt »,
#    exportez-les en étant connecté à youtube.com, puis renseignez dans config/survive.conf :
SURVIVE_YTDLP_COOKIES="/home/<utilisateur>/yt_cookies.txt"
```

```bash
# 3. Ou lire les cookies directement depuis un profil de navigateur local :
SURVIVE_YTDLP_BROWSER="chromium"
```

**Le « n challenge » (formats manquants même avec les cookies) :** YouTube masque aussi les URL des flux avec du JavaScript que yt-dlp doit exécuter. Prérequis (les trois, dans le MÊME environnement) :

```bash
sudo apt install -y nodejs
sudo pip install --break-system-packages -U yt-dlp yt-dlp-ejs
```

Important : le binaire autonome de yt-dlp NE PEUT PAS charger le solveur yt-dlp-ejs — yt-dlp doit être le paquet installé par pip. Si `which yt-dlp` indique un binaire antérieur à l'installation par pip, supprimez-le pour que la copie pip prenne le relais.

Si « n challenge solving failed » persiste alors que tout ce qui précède est à jour, YouTube a une longueur d'avance sur les outils — un état connu et récurrent. Réessayez chaque mois :

```bash
sudo pip install --break-system-packages -U yt-dlp yt-dlp-ejs
```

Notez que l'utilisation d'un compte personnel pour des téléchargements en masse peut entraîner une limitation de débit de ce compte ; un compte jetable est plus prudent. Les vidéos bloquées sont ignorées au lieu d'interrompre la session : des bibliothèques vidéo partielles sont donc à prévoir.

---

## Obtenir de l'aide

- Vérifier l'état des services : `bash scripts/status.sh`
- Voir tous les journaux : `tail -f /var/log/survive_*.log`
- Tickets GitHub : https://github.com/lolly76/SurviveV1-FR/issues
