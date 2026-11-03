# PLAN-wifi-hotspot : le Pi comme point d'accès Wi-Fi autonome (mode réseau électrique coupé)

**Rang : n° 3.**

## Objectif

Tout le produit suppose un réseau local qui fonctionne — mais dans le scénario réel de coupure
du réseau pour lequel il est conçu, il n'y a pas de box. Aujourd'hui, si le courant (et donc le
Wi-Fi de la maison) est coupé, la base de 800 Go n'est accessible qu'avec un écran HDMI et un
clavier branchés sur le Pi.

Après ce changement : `sudo bash scripts/hotspot.sh enable` transforme le Pi en son propre
point d'accès Wi-Fi (SSID `SurviveV1`), les téléphones/ordinateurs s'y connectent directement,
et le tableau de bord est joignable à une URL stable, imprimable. `disable` revient au Wi-Fi
client normal. L'assistant d'installation le propose comme étape facultative, et la zone de
bandeau de stockage du tableau de bord indique comment joindre l'appareil en mode point
d'accès.

## Fichiers exacts à modifier

| Fichier | Changement |
|---------|------------|
| `scripts/hotspot.sh` | NOUVEAU — enable/disable/status via NetworkManager |
| `install/wizard.sh` | étape facultative « point d'accès hors réseau » après la région des cartes |
| `config/survive.conf` | valeurs par défaut `SURVIVE_HOTSPOT_SSID` / `SURVIVE_HOTSPOT_PASS` |
| `docs/TROUBLESHOOTING.md` | section point d'accès (récupération, IP, remarques sur la bande) |
| `README.md` | un paragraphe + l'URL 10.42.0.1 dans le tableau d'accès |

## Ordre de mise en œuvre

1. **`scripts/hotspot.sh`** (style de la maison : `set -euo pipefail`, en-tête de chargement de
   la configuration AVEC le motif de capture des surcharges d'environnement de
   `scripts/build_ebook_library.sh` — copier ce bloc exact) :
   - Sous-commandes : `enable`, `disable`, `status` (par défaut `status`).
   - Conditions préalables à `enable` :
     - `command -v nmcli` — s'il est absent, s'arrêter avec : « NetworkManager est requis
       (par défaut sur Raspberry Pi OS Bookworm). Les anciens systèmes dhcpcd ne sont pas
       pris en charge. »
     - `[[ $EUID -eq 0 ]]` — s'arrêter avec « lancez avec sudo ».
     - `nmcli radio wifi` ne doit pas valoir `disabled` → `nmcli radio wifi on`.
     - Domaine réglementaire : si `iw reg get 2>/dev/null | grep -q "country 00"`, avertir
       que le pays du Wi-Fi n'est pas défini (`sudo raspi-config nonint do_wifi_country FR`)
       — le choix du canal en mode point d'accès peut échouer sans lui.
   - `enable` :
     ```bash
     SSID="${SURVIVE_HOTSPOT_SSID:-SurviveV1}"
     PASS="${SURVIVE_HOTSPOT_PASS:-survive2026}"
     nmcli connection delete survive-hotspot 2>/dev/null || true
     nmcli connection add type wifi ifname wlan0 con-name survive-hotspot \
         autoconnect no ssid "$SSID" \
         802-11-wireless.mode ap 802-11-wireless.band bg \
         ipv4.method shared ipv6.method disabled \
         wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$PASS"
     nmcli connection up survive-hotspot
     ```
     `ipv4.method shared` fait lancer à NetworkManager son propre DHCP+NAT sur 10.42.0.0/24 —
     le Pi est toujours **10.42.0.1**. Afficher un récapitulatif encadré : SSID, mot de passe,
     et `http://10.42.0.1:8080` (+ le nom survive.local, qui fonctionne aussi via mDNS sur le
     sous-réseau du point d'accès).
   - `disable` : `nmcli connection down survive-hotspot` puis
     `nmcli connection delete survive-hotspot` ; afficher « reconnexion aux réseaux Wi-Fi
     connus (s'il y en a) ».
   - `status` : `nmcli -t -f NAME,DEVICE,STATE connection show --active | grep
     survive-hotspot` → afficher point d'accès actif + nombre de clients via
     `iw dev wlan0 station dump | grep -c ^Station` (|| echo 0).
   - Validation du mot de passe : WPA-PSK exige 8 à 63 caractères — vérifier et s'arrêter tôt
     avec un message clair, car l'erreur de nmcli est cryptique.

2. **`install/wizard.sh`** : après l'étape de région des cartes, ajouter un `choose_hotspot()`
   facultatif — question o/N (« Activer maintenant le mode point d'accès Wi-Fi hors réseau ? »),
   en expliquant que l'activer **déconnecte le Pi du Wi-Fi de la maison** (ils ne coexistent
   qu'avec Ethernet pour l'accès à Internet). Si oui, demander SSID/mot de passe (valeurs par
   défaut ci-dessus), écrire les deux dans le `survive.conf` généré, et le noter dans l'écran de
   récapitulatif. NE PAS activer automatiquement pendant l'installation — les téléchargements
   ont besoin d'Internet ; afficher plutôt la commande d'activation dans l'écran final de
   réussite.

3. **`config/survive.conf`** : ajouter les deux valeurs par défaut en commentaire.

4. **Documentation** : TROUBLESHOOTING gagne « Mode point d'accès » couvrant : comment
   récupérer la main si l'on a activé le point d'accès via SSH-par-Wi-Fi et que l'on s'est
   enfermé dehors (brancher Ethernet, ou la connexion est en `autoconnect no` donc un
   **redémarrage** rétablit le Wi-Fi normal — c'est un dispositif d'homme mort voulu),
   pourquoi la bande `bg` (le 2,4 GHz porte plus loin et tous les téléphones le gèrent), et
   l'adresse 10.42.0.1.

## Cas limites qu'un modèle moins attentif manquerait

- **Activer le point d'accès coupe votre session SSH si vous êtes connecté en Wi-Fi** — wlan0
  ne peut pas être à la fois client et point d'accès. Le script doit détecter
  `who am i`/`SSH_CONNECTION` + une connexion cliente wlan0 active et exiger un indicateur
  `--force` (ou un « yes » saisi) avec un avertissement, exactement comme la protection de
  formatage de l'assistant. Le SSH par Ethernet n'est pas concerné.
- **`autoconnect no` est le dispositif d'homme mort** : si un utilisateur active le point
  d'accès et s'en va, un cycle d'alimentation rétablit le Wi-Fi normal. `autoconnect yes`
  condamnerait les boîtiers sans écran au mode point d'accès seul. Si l'utilisateur veut un
  mode point d'accès permanent, documenter `nmcli connection modify survive-hotspot
  connection.autoconnect yes` — une étape explicite et éclairée.
- **Bande `bg`, pas `a`** : les canaux 5 GHz en point d'accès dépendent de la région et
  échouent silencieusement avec `country 00` ; le 2,4 GHz marche partout et traverse les murs
  — en cas de catastrophe, c'est le bon compromis.
- **`ipv6.method disabled`** évite les bizarreries des annonces RA IPv6 du mode partagé de NM
  sur Bookworm (faux `activation failed` avec certains noyaux).
- **ufw** : `setup/install.sh` ouvre 8080/80, etc. — ces règles sont indépendantes de
  l'interface, donc les clients du point d'accès passent ; ne PAS ajouter de règles limitées à
  une interface.
- **rfkill** : les Pi neufs sans pays Wi-Fi défini sont bloqués logiciellement
  (`rfkill list wifi`) — `nmcli radio wifi on` lève le blocage de NM mais pas celui de rfkill ;
  ajouter `rfkill unblock wifi || true` avant d'activer.
- **L'environnement de test de fumée/CI n'a pas NetworkManager** — chaque appel nmcli se place
  derrière la garde `command -v nmcli` ; shellcheck doit passer, et `status` sur une machine
  sans NM affiche « NetworkManager indisponible » et sort avec le code 0 (il sera utilisé plus
  tard par `scripts/status.sh` ; un code non nul casserait les appelants sous `set -e`).

## Critères d'acceptation

1. `bash -n scripts/hotspot.sh` et shellcheck (options de la CI) passent.
2. Sur une machine sans NetworkManager : `bash scripts/hotspot.sh status` sort avec le code 0
   et le message « indisponible » ; `enable` sort avec un code non nul et le message Bookworm.
3. Sur un vrai Pi 5 (à la main) : `sudo bash scripts/hotspot.sh enable` → un téléphone voit le
   SSID `SurviveV1`, s'y connecte avec le mot de passe, charge `http://10.42.0.1:8080` ET
   `http://survive.local:8080` ; `status` montre 1 client ; `disable` rétablit le Wi-Fi de la
   maison en ~15 s ; après `enable` + redémarrage, le Pi est de retour sur le Wi-Fi de la maison
   (dispositif d'homme mort vérifié).
4. Un passage dans l'assistant montre la nouvelle étape, écrit les deux clés de configuration,
   et l'écran de réussite affiche la commande d'activation.
5. Le mot de passe `short` est rejeté avec le message des 8 caractères avant tout appel nmcli.
