# API du tableau de bord SurviveV1

URL de base : `http://survive.local:8080`

Tous les points d'accès renvoient du JSON sauf mention contraire. Aucune authentification n'est requise (réseau local uniquement), sauf les actions réservées à l'administrateur.

---

## GET /api/status

État global : utilisation du stockage, services en marche, inventaire des contenus.

```bash
curl http://localhost:8080/api/status
```

**Réponse :**
```json
{
  "storage": {
    "total_gb": 931.5,
    "used_gb": 423.1,
    "free_gb": 508.4,
    "percent": 45.4
  },
  "services": {
    "kiwix":   { "running": true,  "port": 8081 },
    "kolibri": { "running": true,  "port": 8082 },
    "calibre": { "running": false, "port": 8083 },
    "jellyfin":{ "running": true,  "port": 8096 },
    "maps":    { "running": true,  "port": 3000  },
    "ai":      { "running": true,  "port": 11434 }
  },
  "content": {
    "zim":    { "count": 12, "size_gb": 182.4, "exists": true },
    "videos": { "count": 2341, "size_gb": 148.2, "exists": true },
    "books":  { "count": 890, "size_gb": 18.4, "exists": true },
    "pdfs":   { "count": 234, "size_gb": 4.1, "exists": true },
    "maps":   { "count": 3, "size_gb": 72.1, "exists": true }
  },
  "timestamp": "2025-04-01T14:32:01.123456"
}
```

---

## GET /api/recent

Les 20 fichiers de contenu modifiés le plus récemment.

```bash
curl http://localhost:8080/api/recent
```

**Réponse :**
```json
[
  {
    "name": "wikipedia_fr_all_maxi_2026-05.zim",
    "path": "zim/wikipedia/wikipedia_fr_all_maxi_2026-05.zim",
    "size_mb": 53248.0,
    "modified": "2026-05-28T09:12:44"
  }
]
```

---

## POST /api/ai/chat

Envoie un message à l'assistant IA Ollama local. La question est d'abord cherchée en plein texte dans la
bibliothèque Kiwix locale ; les meilleurs extraits d'articles sont injectés dans le prompt système du modèle
(génération augmentée par la recherche) et renvoyés dans la liste `sources`. La réponse est **diffusée au fil
de l'eau** en JSON délimité par des sauts de ligne (`Content-Type: application/x-ndjson`).

```bash
curl -N -X POST http://localhost:8080/api/ai/chat \
  -H "Content-Type: application/json" \
  -d '{"message": "Comment purifier de l'\''eau ?", "model": "survive"}'
```

**Corps de la requête :**
| Champ | Type | Requis | Description |
|-------|------|--------|-------------|
| `message` | chaîne | oui | Question de l'utilisateur (tronquée à 4096 caractères) |
| `model` | chaîne | non | Nom du modèle Ollama (par défaut : `survive`) |
| `history` | tableau | non | Tours précédents `[{"role": "user"\|"assistant", "content": "..."}]` pour le contexte multi-tours. Seuls les rôles `user`/`assistant` sont acceptés (sinon 400) ; le serveur garde au plus les 8 derniers tours / ~3000 caractères. |

**Réponse (succès) — un objet JSON par ligne, dans l'ordre :**
```
{"sources": [{"title": "Purification de l'eau", "url": "http://survive.local:8081/viewer#..."}]}
{"delta": "Pour purifier "}
{"delta": "l'eau, faites-la bouillir..."}
{"done": true, "model": "survive"}
```
- `sources` est toujours la première ligne (tableau vide si rien ne correspond).
- Les lignes `delta` portent le texte produit au fur et à mesure ; concaténez-les pour obtenir la réponse.
- Une panne en cours de flux est signalée par une ligne `{"error": "..."}`.

**Erreurs avant le flux** : elles gardent de vrais codes HTTP avec un corps JSON (le flux n'a pas commencé) :
| Statut | Cause |
|--------|-------|
| 400 | `message` manquant |
| 415 | `Content-Type` différent de `application/json` |
| 429 | Limite de débit dépassée (5/min) |
| 502 | Ollama injoignable |

> Remarque : avec la diffusion, `SURVIVE_AI_CHAT_TIMEOUT` est un délai d'*inactivité* entre deux morceaux, et non un plafond de longueur de réponse.

---

## GET /api/downloads

Progression des téléchargements par catégorie, reconstituée à partir de `.download_progress`, de la taille des contenus et de la fin du plus récent `.logs/*.log`.

```bash
curl http://localhost:8080/api/downloads
```

**Réponse :**
```json
{
  "categories": [
    {"id": "kiwix", "name": "Wikipédia et ZIM", "budget_gb": 190,
     "size_gb": 182.4, "status": "complete"}
  ],
  "active_log": {"file": "kiwix.log", "line": "[DL] downloading wikipedia_fr... 42%"},
  "complete": 1,
  "total": 7
}
```
`status` vaut `complete` (consigné dans `.download_progress`), `in_progress` (le dossier de contenu a grossi) ou `pending`.

---

## GET /api/system

Santé de la machine (mise en cache 5 s) : température du processeur, état de bridage du firmware du Pi (courant + bits mémorisés depuis le démarrage), RAM/swap via MemAvailable, charge moyenne, durée de fonctionnement. Hors Pi, tous les champs retombent à zéro/False.

```bash
curl http://localhost:8080/api/system
```

**Réponse :**
```json
{
  "temperature_c": 52.1,
  "throttle": {"undervoltage": false, "capped": false, "throttled": false,
               "soft_temp_limit": false, "occurred_since_boot": false, "raw": "0x0"},
  "memory": {"total_mb": 16384, "available_mb": 12100, "used_percent": 26.1,
             "swap_total_mb": 512, "swap_used_percent": 0.0},
  "load": {"avg_1m": 0.42, "avg_5m": 0.31, "avg_15m": 0.25, "cores": 4},
  "uptime_days": 3.2
}
```

---

## GET /api/connectivity

Test d'accès à Internet côté serveur (la connectivité du Pi lui-même, mise en cache 30 s).

```bash
curl http://localhost:8080/api/connectivity
```

**Réponse :** `{"online": true}`

---

## POST /api/update/start

Lance en arrière-plan une « actualisation sûre » de tous les contenus locaux (`scripts/update_content.sh`) : nouvelles vidéos, livres, PDF, ZIM Kiwix nouveaux ou manquants, mises à jour des modèles d'IA. Les gros ZIM existants ne sont jamais remplacés. Exige `Content-Type: application/json` (sinon 415) ; 409 si une mise à jour est déjà en cours ; 503 si le Pi est hors ligne. Limité à 3/min.

```bash
curl -X POST http://localhost:8080/api/update/start \
  -H "Content-Type: application/json" -d '{}'
```

**Réponse :** `202 {"started": true, "pid": 12345}`

---

## GET /api/update/status

État de la mise à jour en cours ou de la dernière, reconstitué à partir des fichiers sur disque (journal + fichier pid), donc conservé après un redémarrage du tableau de bord.

```bash
curl http://localhost:8080/api/update/status
```

**Réponse :**

```json
{
  "running": false,
  "started": "2026-08-17T10:00:00",
  "exit_code": 0,
  "log_tail": ["[UPDATE] Mise à jour des contenus terminée"]
}
```

`exit_code` vaut `null` pendant l'exécution ou avant tout passage ; le journal se trouve dans `$STORAGE/.logs/update_content.log`.

---

## GET /search

Recherche de fichiers par nom (index SQLite FTS5), plus des sections pour les articles Kiwix, les documents et les notes. Renvoie une page HTML. Limité à 30/min.

```
GET /search?q=purification+eau
```

| Paramètre | Description |
|-----------|-------------|
| `q` | Requête de recherche (2 à 200 caractères) |

---

## GET /serve/&lt;chemin&gt;

Sert directement un fichier du stockage.

```bash
curl http://localhost:8080/serve/pdfs/medical/Hesperian_LOIPD_15_ventre_diarrhees.pdf -o chapitre15.pdf
```

- Le chemin est relatif à `SURVIVE_STORAGE_PATH`
- La traversée de répertoires est bloquée (403 si le chemin sort de la racine du stockage)
- 404 si le fichier est introuvable

---

## GET /category/&lt;id&gt;

Page HTML listant les fichiers d'une catégorie de contenu.

Identifiants disponibles : `medical`, `food`, `shelter`, `energy`, `skills`, `communication`, `security`, `maps`, `reference`, `videos`, etc. — voir la liste `CATEGORIES` de `web/constants.py`.

---

## GET /files

Parcours interactif du système de fichiers.

```
GET /files?path=pdfs/medical
```

| Paramètre | Description |
|-----------|-------------|
| `path` | Chemin relatif dans le stockage (facultatif, racine par défaut) |

Renvoie un listing HTML du dossier.

---

## Référence des médicaments

Données issues de la Base de données publique des médicaments (BDPM). L'accès exige d'avoir accepté l'avertissement (session) ; sinon la page d'avertissement s'affiche et l'API renvoie 403.

| Endpoint | Méthode | Notes |
|----------|---------|-------|
| `/drugs?q=&mode=drug\|symptom` | GET | Recherche par nom/substance (`drug`) ou par symptôme/indication (`symptom`). La source et la date de mise à jour des données sont affichées. |
| `/drugs/<id>` | GET | Fiche : forme, voie, titulaire, conditions de prescription, indications, posologie, contre-indications, mises en garde, interactions, lien vers la fiche officielle. |
| `/drugs/disclaimer` | POST | Formulaire CSRF : accepte l'avertissement pour la session. |
| `/api/drugs/interactions?a=<id>&b=<nom>` | GET | Recherche **textuelle** (insensible aux accents) du nom de `b` dans les interactions, mises en garde et contre-indications de `a`, et inversement. Ce n'est pas un vérificateur clinique d'interactions. |

---

## GET /api/update/schedule

État du minuteur de mise à jour nocturne. `available` vaut false tant que `generate_services.sh` n'a pas installé le minuteur. `next_run` / `last_run` sont les horodatages lisibles de systemd.

```json
{"available": true, "enabled": true, "active": true, "next_run": "Sat 2026-10-11 02:30:00 CEST",
 "last_run": null, "time": "02:30", "rate_limit_kbps": 2048}
```

## POST /api/update/schedule

Administrateur seulement, corps JSON `{"enabled": true|false}`. Exécute la commande autorisée `systemctl enable|disable --now survive-content-update.timer` et renvoie la même forme que le GET. 500 avec une commande `manual` si la règle sudoers est absente.

## Cartes et repères

| Endpoint | Méthode | Notes |
|----------|---------|-------|
| `/maps` | GET | Page de la carte. Définit une CSP par route (workers `blob:`) et `Permissions-Policy: geolocation=(self)`. |
| `/api/map/assets` | GET | `{basemaps:[{name,file,url,size_mb}], overlays:[...], fonts_ok, sprites_ok, park_maps}` |
| `/api/map/pins` | GET | `{pins:[{id,name,lat,lon,icon,color,notes,hidden,created,updated}]}` |
| `/api/map/pins` | POST | Repère JSON → 201 avec la ligne enregistrée. Ouvert au réseau local ; 60/min. `icon` parmi `pin water fuel medical camp cache home food danger radio tools people`. |
| `/api/map/pins/<id>` | PUT / DELETE | Corps JSON (mise à jour partielle possible). 404 si absent. |
| `/api/map/pins/export?format=gpx\|geojson` | GET | Téléchargement de tous les repères. |
| `/api/map/pins/import` | POST | `{"text": "<gpx ou geojson>"}` (4 Mo max) → `{imported, pins}`. |

## Gestionnaire de bibliothèque

| Endpoint | Méthode | Notes |
|----------|---------|-------|
| `/content` | GET | Page. |
| `/api/content/catalog?lang=fra&q=&category=&start=0&count=50` | GET | Relaie `library.kiwix.org/catalog/v2/entries` (cache 15 min). Chaque entrée porte un `status` : `installed`, `partial`, `downloading` ou `available`. 503 hors ligne. |
| `/api/content/languages` | GET | `{languages:[{code,name,count}]}` |
| `/api/content/local` | GET | Fichiers ZIM du disque avec les indicateurs `registered` (connu de Kiwix) et `partial`, plus `free_gb`. |
| `/api/content/jobs` | GET | Téléchargements lancés depuis le tableau de bord (journaux `zimdl_*`) et tâche de réanalyse, avec `running`, `exit_code`, `progress`, `log_tail`. |
| `/api/content/download` | POST | Admin, JSON `{url, name, size}`. Uniquement `https://download.kiwix.org/...zim` (et les hôtes `lb.`/`mirror.`). 507 si le fichier plus 10 Go de marge ne tient pas ; 409 si deux téléchargements tournent déjà. Lance `scripts/download_zim.sh` en arrière-plan → 202. |
| `/api/content/rescan` | POST | Admin. Lance `scripts/rescan_library.sh` en arrière-plan → 202. |

## Notes, fichiers partagés, transmissions

Ce sont des pages HTML avec formulaires protégés par CSRF, et non des API JSON.

| Route | Méthode | Notes |
|-------|---------|-------|
| `/notes`, `/notes?q=` | GET | Liste / recherche. |
| `/notes/new`, `/notes/<slug>`, `/notes/<slug>?edit=1` | GET | Éditeur, vue rendue, éditeur. |
| `/notes/save` | POST | Formulaire `body` (+ `slug` pour mettre à jour). Une nouvelle note prend son slug du premier titre. 512 Ko max. |
| `/notes/<slug>/delete` | POST | Admin. |
| `/shared` | GET | Liste de `$STORAGE/shared`. |
| `/shared/upload` | POST | `files` multipart (plusieurs). 2 Go par requête, 10 Go toujours libres, noms de fichiers passés dans `secure_filename`. |
| `/shared/delete` | POST | Admin, formulaire `name`. |
| `/comms`, `/comms/morse`, `/comms/repeaters?q=&band=` | GET | Pages. Bandes : `6m 2m 1.25m 70cm gmrs other`. |
| `/comms/repeaters/upload`, `/comms/repeaters/delete` | POST | Admin. CSV uniquement (20 Mo). |

## Ports des services

| Service | Port | URL |
|---------|------|-----|
| Tableau de bord | 8080 | http://survive.local:8080 |
| Kiwix (Wikipédia) | 8081 | http://survive.local:8081 |
| Kolibri (Khan Academy) | 8082 | http://survive.local:8082 |
| Calibre-Web (livres numériques) | 8083 | http://survive.local:8083 |
| Jellyfin (vidéos) | 8096 | http://survive.local:8096 |
| Martin (cartes, facultatif) | 3000 | http://survive.local:3000 |
| Meshtastic Web | 8084 | http://survive.local:8084 |
| MeshCore Web | 8085 | http://survive.local:8085 |
| Ollama (IA) | 11434 | http://survive.local:11434 |

---

## Configuration

Les délais et autres comportements de l'API se règlent par variables d'environnement (ou `config/survive.conf`) :

| Variable | Défaut | Description |
|----------|--------|-------------|
| `SURVIVE_SERVICE_CHECK_TIMEOUT` | `1` | Secondes d'attente lors du test des ports de services |
| `SURVIVE_OLLAMA_LIST_TIMEOUT` | `2` | Secondes d'attente pour la liste des modèles Ollama |
| `SURVIVE_AI_CHAT_TIMEOUT` | `60` | Secondes d'attente pour la réponse du chat IA |
| `SURVIVE_STORAGE_PATH` | `/mnt/survive` | Racine du stockage des contenus |
