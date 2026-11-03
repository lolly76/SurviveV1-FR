# PLAN : parité fonctionnelle avec Project NOMAD / Prepper Disk (terminé)

Source : comparaison de Project NOMAD 1.35 (Crosstalk Solutions, oct. 2026), Prepper Disk
et Internet-in-a-Box avec SurviveV1. Six lacunes ont été retenues ; cinq ont été livrées
en entier, une sous une forme adaptée, et un point n'a pas pu être ajouté.

## Livré

| # | Fonctionnalité | Où |
|---|----------------|----|
| 1 | Page de cartes hors ligne avec repères, recherche, masquage, import/export GPX/GeoJSON, localisation GPS, calque satellite | `/maps`, `web/templates/maps.html`, `/api/map/*`, `web/static/vendor/`, `maps.sh dl_map_assets`/`dl_satellite` |
| 2 | Gestionnaire de bibliothèque : catalogue Kiwix par langue/catégorie, téléchargements depuis le tableau de bord, liste des téléchargements, réanalyse des ZIM copiés à la main | `/content`, `/api/content/*`, `scripts/download_zim.sh`, `scripts/rescan_library.sh` |
| 3 | Notes Markdown partagées (avec recherche) et dépôt de fichiers personnels | `/notes`, `/shared`, `web/textutils.render_markdown` |
| 5 | Transmissions : encodeur/décodeur/manipulateur Morse, client web Meshtastic sur :8084, annuaire de relais à partir de CSV importés, référentiel de fréquences | `/comms`, `download/comms.sh`, `systemd/survive-meshtastic.service` |
| 8 | Mise à jour nocturne automatique avec plafond de débit et interrupteur sur la page État | `systemd/survive-content-update.{service,timer}`, `update_content.sh --scheduled`, `/api/update/schedule` |
| 9 | PDF de cartes des parcs nationaux (63 parcs) et calque satellite mondial | `maps.sh dl_nps_maps`/`dl_satellite` |

## Adapté

- **Annuaire de relais.** Les conditions de l'API de RepeaterBook (mars 2026) interdisent
  l'export en masse, l'intégration hors ligne et l'usage dans une « plateforme de
  préparation », et l'accès exige désormais un jeton approuvé. Au lieu de collecter les
  données, la page Transmissions importe le CSV qu'un utilisateur exporte depuis son propre
  compte RepeaterBook ou depuis CHIRP. L'usage personnel reste dans leurs conditions.

## Non ajouté

- **WikiHow.** Le ZIM n'est plus publié par Kiwix (`zim/wikihow/` renvoie 404 et le
  catalogue n'a aucune entrée) : il n'y a donc rien de légitime à télécharger.
- **Imagerie satellite à fort zoom.** Seul le calque mondial d'Internet-in-a-Box (zoom 0–6,
  25 Mo) est librement redistribuable en masse. Les fournisseurs d'imagerie au niveau de la
  rue interdisent le téléchargement en masse.

## Notes de conception

- La page de cartes lit directement les archives PMTiles par requêtes HTTP à plage d'octets
  via `/serve/` : Martin n'est donc plus sur le chemin critique. Polices et sprites sont
  récupérés une fois par `maps.sh`.
- Chaque tâche de fond (téléchargement de ZIM, réanalyse, mise à jour nocturne) reprend la
  convention du bouton Mettre à jour : journal + pid + marqueur de fin, car les processus
  gunicorn ne partagent pas de mémoire.
- Les fonctions d'écriture suivent le modèle de l'invité anonyme : toute personne du réseau
  local peut ajouter des repères, notes et fichiers (outil partagé du foyer) ; les
  suppressions et téléchargements restent derrière la connexion administrateur.
- Des limites de corps de requête par route remplacent un relèvement général de la limite
  de 64 Ko.
