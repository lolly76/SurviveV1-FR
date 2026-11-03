# Tester SurviveV1 sur une VM — liste de contrôle

Objectif : valider en une soirée l'installation, le tableau de bord et les modules matériels,
**sans** télécharger les 800 Go. Compter 45 à 90 minutes.

## 1. Préparer la VM

| Élément | Valeur conseillée |
|---------|-------------------|
| Système | **Debian 12 ou 13, 64 bits** (installation « standard » + serveur SSH) |
| Processeur | 2 cœurs ou plus. Activer le passage des instructions du processeur hôte (« host passthrough ») pour que l'IA détecte AVX2 |
| RAM | 4 Go minimum (8 Go pour tester l'IA) |
| Disque | 40 Go minimum pour le profil `test` ; 100 Go ou plus pour tester `leger` |
| Réseau | Pont (bridge) si vous voulez joindre le tableau de bord depuis votre téléphone |
| Utilisateur | un compte normal avec `sudo` (pas besoin d'un utilisateur `pi`) |

Ne partez pas de Tails ni d'Ubuntu : seule Debian est prise en charge.

## 2. Installer

```bash
sudo apt-get update && sudo apt-get install -y git curl
curl -fsSL https://raw.githubusercontent.com/lolly76/SurviveV1-FR/main/install/bootstrap.sh | bash
```

Dans l'assistant :

1. **Stockage** → `2` (dossier sur le disque du système), garder `/srv/survive`, confirmer.
2. **Profil** → `4` (**test**, ~6 Go).
3. Nom d'hôte au choix ; cartes → `8` (« Ne pas installer les cartes ») ; point d'accès Wi-Fi : répondre `non`.
4. Mot de passe administrateur : en définir un (utile pour tester les boutons d'administration).

L'installation prend 15 à 40 minutes selon la connexion.

## 3. Télécharger le contenu de test

```bash
cd ~/SurviveV1
bash download/download_all.sh        # profil test : ~6 Go
```

## 4. Vérification automatique

```bash
bash scripts/vm_check.sh
```

Chaque ligne est `PASS`, `WARN` ou `FAIL`. Attendu sur une VM :

- **PASS** : stockage, `survive-dashboard`, `kiwix`, toutes les pages du tableau de bord.
- **WARN acceptables** : `kolibri`, `calibre-web`, `jellyfin`, `martin-tiles`, `ollama` « installé mais inactif » ou « non installé » (profil test = peu ou pas de contenu correspondant) ; `ufw` si lancé sans `sudo`.
- **Tout `FAIL` est à me remonter**, avec la sortie de `journalctl -u <service> -n 30`.

Pour voir la détection matérielle seule : `bash scripts/detect_hardware.sh --table`.

## 5. Contrôles à faire à la main

Depuis votre téléphone ou votre PC (adresse affichée en fin de `vm_check.sh`) :

- [ ] `http://<ip>:8080` : le tableau de bord s'ouvre, tout est en français.
- [ ] Page **État** : mémoire, disque, services ; aucune erreur rouge inattendue.
- [ ] Page **Médicaments** : rechercher « paracétamol » ; une fiche s'affiche avec sa composition.
- [ ] **Recherche** : taper un mot ; la page répond sans erreur (peu de résultats : contenu minimal).
- [ ] **Notes** : créer une note, la retrouver, la supprimer (suppression = administrateur).
- [ ] **Fichiers partagés** : déposer un petit fichier et le retrouver.
- [ ] **Applications** : le dépôt d'applications liste Kiwix, VLC, F-Droid.
- [ ] Page **IA** : si la machine a AVX2 et ≥ 4 Go, la page propose le chat ; sinon un bandeau explique pourquoi l'IA est désactivée (les deux cas sont corrects).
- [ ] `http://<ip>:8081` : Kiwix répond (bibliothèque quasi vide avec ce profil).
- [ ] **Redémarrer la VM** (`sudo reboot`) puis recontrôler `bash scripts/vm_check.sh` : les services reviennent seuls.
- [ ] Juste après le redémarrage (moins d'une minute), ouvrir la page **État** : plus d'erreur 500 (bug corrigé aujourd'hui).

## 6. Pour aller plus loin (facultatif)

| Test | Commande |
|------|----------|
| Profil léger (~60 Go) | `bash scripts/apply_profile.sh leger && bash download/download_all.sh` |
| IA locale | `bash ai/setup_ollama.sh setup` (refuse proprement sans AVX2) |
| IA déportée | `SURVIVE_OLLAMA_HOST="http://<autre-machine>:11434"` dans `config/survive.conf`, puis `sudo bash scripts/generate_services.sh` |
| Forcer/désactiver un module | `SURVIVE_MODULE_AI=off` (ou `on`) dans `config/survive.conf`, puis relancer `detect_hardware.sh --table` |
| Capot de portable | `SURVIVE_MODULE_LID=on` puis `sudo bash scripts/laptop_setup.sh on off` |

## 7. Ce que la VM ne peut pas valider

Point d'accès Wi-Fi (pas de carte Wi-Fi), AI Hat Hailo, courant USB du Pi 5, batterie.
Ces modules s'affichent `off` avec leur raison : c'est le comportement attendu.

## 8. Remonter un problème

Copiez-moi : la sortie de `bash scripts/vm_check.sh`, celle de `bash scripts/detect_hardware.sh --table`,
et pour tout service en échec `sudo journalctl -u <service> -n 40 --no-pager`.
Le journal d'installation est dans `/var/log/survive_install.log`.
