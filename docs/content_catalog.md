# SurviveV1-FR — Catalogue des contenus

Liste des contenus téléchargés par défaut dans cette version francophone, avec leur source.
Les tailles sont des estimations ; les ZIM Kiwix datés sont remplacés par leur dernière version publiée.
Les contenus sans équivalent français vérifié sont regroupés dans un **pack « English »** facultatif.

---

## ZIM Kiwix (`download/kiwix_content.sh`)

### Référence générale (français)
| Contenu | Taille | Option |
|---------|--------|--------|
| Wikipédia FR (avec images) | ~52 Go | `CONTENT_WIKIPEDIA` |
| Wikipédia FR (sans images) | ~12 Go | `CONTENT_WIKIPEDIA_NOPIC` |
| Wikipédia FR — sous-ensemble Médecine | variable | `CONTENT_WIKIPEDIA` |
| Wikilivres, Wikivoyage, Wikisource, Wiktionnaire FR | ~17 Go | `CONTENT_WIKIBOOKS` |
| iFixit FR (guides de réparation) | ~3,5 Go | `CONTENT_IFIX` |
| French Language Stack Exchange | < 1 Go | `CONTENT_STACKEXCHANGE` |
| Projet Gutenberg FR | ~15 Go (estimation) | `CONTENT_GUTENBERG` |
| Khan Academy FR (ZIM) | ~94 Go | `CONTENT_KOLIBRI` |
| Conférences TED (technologie, santé, santé publique, santé mentale, science) | ~39 Go | — |

### Extras français (`CONTENT_EXPANSION`)
Ekopédia (écologie pratique), Cuisine Libre, simulations PhET FR, Wikiversité, Vikidia.

### Extras en anglais (options, désactivées par défaut)
| Contenu | Option |
|---------|--------|
| Sites Stack Exchange pratiques (Super User, DIY, Cooking, Ham Radio, Outdoors, Gardening, Medical Sciences, Sustainability, Electronics, Unix/Linux) | `CONTENT_STACKEXCHANGE_EN` |
| Collections « zimgit » (catastrophes, secours, eau, alimentation, nœuds), Appropedia, Energypedia | `CONTENT_EXPANSION_EN` |

---

## Éducation (Kolibri)
Khan Academy en français (canal Kolibri `878ec2e6f88c5c268b1be6f202833cd4`), servi sur le port 8082.
Les chemins d'URL `/fr-fr/` et l'identifiant du canal viennent de la documentation openZIM/Kolibri et n'ont pas pu être testés sur un Kolibri réel : à vérifier au premier import.

---

## Cartes (`download/maps.sh`)
- OpenStreetMap, **France métropolitaine par défaut** (`MAP_REGION="france"`, ~5 Go), tuiles PMTiles lues directement par le navigateur.
- Autres régions : Europe, Amérique du Nord/Sud, Afrique, Asie, Océanie, États-Unis, monde (~70 Go).
- Calque satellite mondial (zoom 0-6) ; polices et sprites de la carte.
- Mémo pour récupérer les cartes IGN (téléchargement manuel, conditions propres à l'IGN).
- Cartes des parcs nationaux américains : option `CONTENT_NPS_MAPS`, désactivée (sans objet pour la France).

---

## PDF et livres (`download/books_pdfs.sh`, `config/pdfs_extra.list`)
- Guide gouvernemental « Tous responsables » (SGDSN).
- Hesperian en français : *Là où il n'y a pas de docteur* (sommaire et chapitres 15, 26, 27, 28, 31, 32), *Manuel de santé des femmes handicapées* (chapitres 10 à 12).
- Séchage solaire des fruits et légumes (GRET).
- Livres Gutenberg FR sélectionnés (EPUB).
- Vos propres documents : ajoutez des lignes `dossier|nom|url|fichier.pdf` à `config/pdfs_extra.list`.

## Santé mentale (`download/mental_health.sh`)
Premiers secours psychologiques (OMS, version française) et modules PSP (MHPSS Hub), plus les chaînes vidéo listées dans `config/mental_health_extra.list`.

---

## Référence des médicaments (`download/drug_reference.sh`)
Base de données publique des médicaments (ANSM, HAS, UNCAM) : spécialités, compositions, conditions de prescription, puis récupération lente et reprenable des RCP/notices officielles (indications, posologie, contre-indications, mises en garde, interactions). Voir la page `/drugs` du tableau de bord ; la source et la date de mise à jour y sont affichées.

---

## Vidéos de survie (`download/videos.sh`, `config/videos_extra.list`)
Chaînes et playlists YouTube francophones téléchargées avec yt-dlp :
- **Survie / bushcraft** : Invictus France, Alban Cambe, Sankhoï, Skol Louarn
- **Secourisme** : Croix-Rouge française (formations premiers secours)
- **Alimentation et potager** : Popote et Potager
- **Permaculture** : École de permaculture du Bec Hellouin
- **Habitat** : Maison-Construction.com
- **Énergie** : L'énergie partout
- **Bricolage** : Le Coin des Bricoleurs, Fix Ta Maison, Robert Longechal
- **Savoir-faire** : Low-tech Lab
- **Radio** : Radioamateur par F4HTZ, cours de préparation à la licence radioamateur (F4KLH)

Ajoutez vos sources dans `config/videos_extra.list` (format `catégorie|nom|url|nombre_max`).

---

## Pack « English » — contenus experts (`CONTENT_GAPS_EN`, activé par défaut)
Médecine avancée, obstétrique, dentaire, assainissement, élevage, semences, forge, apiculture, sécurité… : ressources sans équivalent français vérifié, conservées dans leur version anglaise et identifiées comme telles (`download/gaps_content.sh`, section « PACK English »). Mettez `CONTENT_GAPS_EN="N"` pour les ignorer ; vos documents français s'ajoutent via `config/gaps_extra.list`.

---

## Transmissions (`download/comms.sh`)
Clients web Meshtastic (:8084) et MeshCore (:8085) hébergés localement, applications MeshCore Android/Windows pour le dépôt d'applications, listes de relais importées par vos soins (`comms/repeaters/*.csv`).

## Dépôt d'applications (`download/app_depot.sh`)
Kiwix Android et Desktop, F-Droid, VLC, pour que les appareils connectés au point d'accès Wi-Fi puissent installer les lecteurs sans Internet.
