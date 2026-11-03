# PLAN-system-monitor : température CPU, bridage et RAM sur le tableau de bord

**Rang : n° 4.**

## Objectif

L'inférence LLM sur processeur sature les quatre cœurs du Pi 5 pendant plusieurs minutes ;
un Pi mal refroidi ou sous-alimenté subit alors un **bridage thermique ou une chute de
tension**, que l'utilisateur vit comme « l'IA est devenue lente / le Pi a redémarré » sans
cause visible. Le tableau de bord affiche le disque et les services, mais rien sur la
machine elle-même.

Après ce changement : `/api/system` indique la température du CPU, l'état de bridage (y
compris les bits persistants « a été bridé depuis le démarrage »), la charge moyenne,
l'utilisation de la RAM et du swap, et la durée de fonctionnement. La page État reçoit une
carte « Santé du système », et un bandeau rouge apparaît quand le Pi est actuellement bridé
ou en sous-tension — les deux situations qui ruinent silencieusement l'expérience de l'IA.

## Fichiers exacts à modifier

| Fichier | Changement |
|---------|------------|
| `web/server.py` | `_compute_system_health()` + route `/api/system` (cache TTL 5 s) |
| `web/templates/status.html` | Carte Santé du système + inclusion dans le sondage toutes les 15 s |
| `web/templates/base.html` | petit bandeau d'alerte en cas de bridage (la page État l'injecte ; laisser base intact si c'est plus simple — voir étape 4) |
| `tests/test_smoke.sh` | assertion JSON sur `/api/system` |
| `docs/API.md` | documentation du point d'accès |

## Ordre de mise en œuvre

1. **`_compute_system_health()` dans server.py** — bibliothèque standard seulement, chaque
   source protégée individuellement pour que les environnements non-Pi/CI renvoient des
   zéros, jamais d'erreurs :
   - **Température** : lire `/sys/class/thermal/thermal_zone0/temp`
     (millidegrés → `round(int(v)/1000, 1)`). Ce chemin existe sur le Pi et la plupart des
     VM Linux ; en cas d'échec, valeur par défaut `0.0`. Ne PAS appeler `vcgencmd` pour la
     température — la lecture sysfs est gratuite et sans permission.
   - **Bridage** : `subprocess.run(["vcgencmd", "get_throttled"], ...)`, analyser
     `throttled=0x50005`. Signification des bits (micrologiciel Raspberry Pi) :
     bit 0 sous-tension MAINTENANT, bit 1 fréquence plafonnée MAINTENANT, bit 2 bridé
     MAINTENANT, bit 3 limite thermique souple MAINTENANT ; bits 16–19 = mêmes conditions
     depuis le démarrage. Renvoyer `{"undervoltage": bool, "throttled": bool, "capped": bool,
     "occurred_since_boot": bool, "raw": "0x..."}`. Si vcgencmd est absent (CI, non-Pi) →
     tout à False, raw None. Délai maximal : 2 s.
   - **Mémoire** : analyser `/proc/meminfo` — MemTotal, MemAvailable, SwapTotal, SwapFree →
     pourcentages utilisés. C'est MemAvailable (et non MemFree) qui compte.
   - **Charge** : triplet `os.getloadavg()` + `os.cpu_count()`.
   - **Durée de fonctionnement** : premier flottant de `/proc/uptime`, affiché en
     jours/heures.
2. **Route** : `_system_cache = _TTLCache(5.0)` ;
   `@app.route("/api/system")` → `jsonify(_system_cache.get(_compute_system_health))`.
3. **Carte de la page État** : quatre tuiles (Temp. °C, Charge / cœurs, RAM %, Swap %) + une
   ligne de bridage. Règles de couleur : temp ≥ 80 rouge (la limite souple du Pi 5 est 85),
   ≥ 70 orange ; RAM ≥ 90 % rouge. Si `occurred_since_boot` mais pas actuellement : note
   orange « un bridage s'est produit plus tôt — vérifiez le refroidissement/l'alimentation ».
4. **Bandeau d'alerte** : l'afficher dans status.html seulement (ne pas toucher base.html —
   un bandeau global exigerait les données sur chaque route, et ce point d'accès doit rester
   hors du chemin critique de chaque chargement de page). Le sondage de 15 s le met à jour.
5. **Sondage** : ajouter `/api/system` au `Promise.all` existant de `refreshStatus()` dans
   status.html et mettre à jour les tuiles via des attributs `data-sys-*` avec `textContent`.

## Cas limites qu'un modèle moins attentif manquerait

- **`vcgencmd` exige le groupe `video`** dans certaines configurations ; avec User=pi sous
  systemd, cela fonctionne, mais dans un shell sans sudo il peut échouer avec un message de
  permission **sur la sortie standard avec un code de retour 0** — traiter une sortie
  inanalysable comme un binaire absent (tout à False), sans se fier au seul code de retour.
- **La valeur de bridage est en hexadécimal avec le préfixe `throttled=`** — analyser avec
  `int(value.split("=")[1], 16)` ; un modèle moins attentif cherche un décimal par regex et
  affiche n'importe quoi.
- **Bits persistants ou actuels** : ne rapporter que le bit 2 fait manquer le signal le plus
  utile — « il a été bridé pendant l'exécution du modèle cette nuit » (bit 18) est
  exactement ce que doit voir un utilisateur qui cherche pourquoi l'IA est lente.
- **MemAvailable ou MemFree** : MemFree est toujours proche de zéro sous Linux (cache de
  pages) ; l'utiliser affiche un faux manque de mémoire permanent.
- **`os.getloadavg()` lève OSError dans certains conteneurs** — le protéger comme les lectures
  de fichiers (défaut `(0.0, 0.0, 0.0)`).
- **TTL du cache de 5 s, pas 60** : la température bouge vite pendant l'inférence et le coût
  de sysfs/vcgencmd est infime ; mais sans cache, le sondage de 15 s × N onglets empile les
  appels de sous-processus.
- **L'environnement du test de fumée n'a aucune des interfaces du Pi** — le test
  d'acceptation vérifie que le point d'accès renvoie du JSON valide avec les bonnes CLÉS, pas
  les valeurs.

## Critères d'acceptation

1. Test de fumée : `check_json "GET /api/system" "/api/system"` passe, et un grep vérifie que
   le corps contient `"temperature_c"`, `"load"`, `"memory"`, `"throttle"`.
2. Sur CI/non-Pi : le point d'accès renvoie 200 avec des zéros/False — aucun 500, rien dans le
   journal d'erreurs.
3. Sur un vrai Pi (manuel) : la tuile affiche une température plausible (30–70 °C au repos) ;
   `stress-ng --cpu 4` pendant 2 min fait monter la température affichée au sondage suivant ;
   une alimentation limite (ou un `vcgencmd get_throttled` montrant des bits persistants)
   fait apparaître la note orange « s'est produit plus tôt ».
4. Les tuiles de la page État se mettent à jour sur place toutes les 15 s (voir la température
   changer sans rechargement).
5. pylint ≥ 9,5 ; tous les tests de fumée au vert.
