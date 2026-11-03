# Installation du Hailo AI Hat sur Raspberry Pi 5

Le Hailo-8L AI Hat apporte jusqu'à **13 TOPS** d'accélération pour les réseaux
de neurones de vision.

> **Important — le Hailo-8L n'accélère PAS les LLM.** Le 8L est un
> accélérateur de *vision* (détection d'objets, segmentation, pose). Il ne sait
> pas exécuter les noyaux de transformeurs décodeurs dont Ollama a besoin :
> `ollama run …` sur SurviveV1 s'exécute donc **à 100 % sur le processeur du
> Pi**, que le 8L soit installé ou non. Seul le **Hailo-10H** de l'AI HAT+ 2
> (40 TOPS, 8 Go de RAM embarquée) peut accélérer des LLM, via les paquets
> `hailo-gen-ai` (installation : `sudo bash scripts/setup_hailo10.sh`).
>
> Avec un 8L, gardez-le pour la caméra et la vision ; pour l'assistant IA,
> choisissez des modèles plus petits (`llama3.2:1b`, `gemma4:e2b`).

---

## Installation matérielle

1. Éteignez complètement le Raspberry Pi 5
2. Fixez l'AI Hat sur le connecteur M.2 HAT+ du Pi 5
3. Serrez-le avec les entretoises fournies
4. La puce Hailo apparaît comme un périphérique PCIe au démarrage

---

## Vérifier le matériel

```bash
# Vérifier le périphérique PCIe
lspci | grep -i hailo
# Attendu : Hailo Technologies Ltd. Hailo-8L AI Processor

# Vérifier le nœud de périphérique
ls /dev/hailo*
# Attendu : /dev/hailo0
```

---

## Installation logicielle

```bash
# Installer le pilote et l'environnement d'exécution Hailo
sudo bash setup/install_ai_hat.sh

# Hailo-10H uniquement (pilote et paquets différents de ceux du 8L) :
sudo bash scripts/setup_hailo10.sh
```

---

## Ce que le Hailo apporte (et n'apporte pas)

| Usage | Processeur seul | Avec Hailo-8L |
|-------|-----------------|---------------|
| Classification d'images | lent | très rapide (vision) |
| Détection d'objets | lent | très rapide (vision) |
| Génération de texte (LLM, Ollama) | processeur | **identique : processeur** |

Les anciens chiffres de gain sur la génération de texte ne s'appliquent pas :
avec un 8L, le LLM tourne sur le processeur.

---

## Modèles compatibles

Les modèles de vision compilés pour l'architecture Hailo se trouvent ici :

- https://github.com/hailo-ai/hailo_model_zoo
- https://github.com/hailo-ai/hailo-rpi5-examples

Pour les LLM, Ollama reste sur le processeur, même avec un Hailo-10H ; le
déport sur NPU passe par les paquets `hailo-gen-ai` de Hailo.

---

## Fonctionner sans AI Hat

Sans AI Hat, tout fonctionne sur le processeur :
- `llama3.2:1b` : réponses rapides, qualité plus limitée
- `gemma4:e2b` : ~8-12 jetons/s sur Pi 5, le modèle `survive` par défaut
- Largement utilisable pour des questions de survie

Dans la configuration : `SKIP_AI_HAT="true"`

---

## Dépannage

**AI Hat non détecté :**
```bash
# Vérifier que le PCIe est activé
grep -i pcie /boot/firmware/config.txt
# Doit contenir : dtparam=pciex1_gen=3

# Activer le PCIe s'il manque :
echo "dtparam=pciex1_gen=3" | sudo tee -a /boot/firmware/config.txt
sudo reboot
```

Message « Hailo devices not found » alors que la puce est visible avec
`lspci` : le mauvais pilote est installé (`hailo-all` pour le 8L,
`hailo-h10-all` pour le 10H). Relancez le script d'installation adapté.

**Vérifier que le Hailo répond :**
```bash
hailortcli fw-control identify
# Doit afficher les informations du périphérique
```
