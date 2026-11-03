# PLAN-ai-streaming : diffuser les réponses de l'IA jeton par jeton

**Rang : n° 3.**

## Objectif

`/api/ai/chat` appelle Ollama avec `"stream": False` et met toute la réponse en mémoire
tampon. Sur le processeur du Pi 5 (1 à 3 jetons/s pour gemma4:12b), une réponse détaillée
prend plusieurs minutes — mais `TIMEOUT_AI_CHAT` coupe la requête à 60 s : les utilisateurs du
meilleur modèle reçoivent donc une erreur au lieu d'une réponse, et même les modèles rapides
paraissent figés pendant plus de 20 secondes.

Après ce changement, le point d'accès diffuse des morceaux NDJSON au fur et à mesure
qu'Ollama les produit ; le navigateur affiche les jetons en direct. Première sortie visible en
~2 s quelle que soit la taille du modèle ; plus de troncature des longues réponses.

**Note de dépendance :** à appliquer après PLAN-ai-rag (les deux modifient `ai_chat()`) ; la
récupération RAG se fait une seule fois, avant le début du flux, et les `sources` sont envoyées
comme **première** ligne NDJSON.

## Fichiers exacts à modifier

| Fichier | Changement |
|---------|------------|
| `web/server.py` | réécrire `ai_chat()` comme une réponse en flux par générateur |
| `web/templates/ai.html` | consommer le flux avec `fetch` + `ReadableStream` |
| `config/nginx.conf` | désactiver la mise en tampon du proxy pour `/api/ai/chat` |
| `systemd/survive-dashboard.service` + `scripts/generate_services.sh` | ajouter `--threads 4` à gunicorn |
| `config/survive.conf` | mise à jour du commentaire : TIMEOUT_AI_CHAT devient un délai d'inactivité |
| `tests/test_smoke.sh` | test du contrat de flux |
| `docs/API.md` | documenter le protocole NDJSON |

## Ordre de mise en œuvre

1. **Serveur** — dans `ai_chat()`, mettre `"stream": True` dans la charge utile d'Ollama.
   Remplacer la lecture unique par un générateur :
   ```python
   def generate(upstream):
       yield json.dumps({"sources": sources}) + "\n"
       try:
           for raw_line in upstream:
               chunk = json.loads(raw_line)
               piece = chunk.get("message", {}).get("content", "")
               if piece:
                   yield json.dumps({"delta": piece}) + "\n"
               if chunk.get("done"):
                   yield json.dumps({"done": True, "model": model}) + "\n"
                   return
       except (OSError, json.JSONDecodeError):
           yield json.dumps({"error": "flux interrompu"}) + "\n"
       finally:
           upstream.close()
   ```
   Ouvrir la requête amont avec `urllib.request.urlopen(req, timeout=TIMEOUT_AI_CHAT)` — en
   flux, `timeout` s'applique à **chaque lecture de socket** (délai d'inactivité), pas à la
   durée totale. Renvoyer `Response(stream_with_context(generate(upstream)),
   mimetype="application/x-ndjson", headers={"X-Accel-Buffering": "no"})`.
   Importer `Response, stream_with_context` depuis flask.
   Les erreurs détectées AVANT le premier `yield` (Ollama a refusé, modèle invalide) doivent
   toujours renvoyer un `jsonify(...), 4xx/502` simple — même contrat qu'aujourd'hui.

2. **Client** (`sendMessage()` dans `ai.html`) : remplacer `res.json()` par :
   ```js
   const reader = res.body.getReader();
   const decoder = new TextDecoder();
   let buf = '', aiDiv = null, text = '';
   for (;;) {
     const {value, done} = await reader.read();
     if (done) break;
     buf += decoder.decode(value, {stream: true});
     let nl;
     while ((nl = buf.indexOf('\n')) >= 0) {
       const line = buf.slice(0, nl); buf = buf.slice(nl + 1);
       if (!line.trim()) continue;
       const msg = JSON.parse(line);
       if (msg.delta) {
         if (!aiDiv) { removeTyping(); aiDiv = addMessage('ai', ''); }
         text += msg.delta;
         aiDiv.querySelector('.message-bubble').textContent = text;
         scrollToBottom();
       }
       if (msg.sources) pendingSources = msg.sources;
       if (msg.error) { removeTyping(); addMessage('ai', 'Erreur : ' + msg.error); }
       if (msg.done && pendingSources?.length) renderSources(aiDiv, pendingSources);
     }
   }
   ```
   Conserver le câblage de l'AbortController — `reader.read()` rejette avec `AbortError` à
   l'annulation, ce que le catch existant gère. Supprimer entièrement le minuteur
   d'avertissement de 55 s (le flux le rend obsolète). Traiter d'abord les réponses d'erreur
   hors flux : si `res.headers.get('content-type')?.includes('application/json')`, se replier
   sur l'ancien chemin `res.json()`.

3. **nginx.conf** — le bloc `location /` du tableau de bord convient aux pages avec mise en
   tampon, mais ajouter un bloc dédié AU-DESSUS :
   ```nginx
   location /api/ai/chat {
       proxy_pass         http://127.0.0.1:8080;
       proxy_set_header   Host $host;
       proxy_buffering    off;
       proxy_read_timeout 600s;
   }
   ```

4. **Fils gunicorn** — un flux occupe un processus pendant plusieurs minutes ; avec 2
   processus synchrones, deux chats simultanés figent tout le tableau de bord. Modifier
   `ExecStart` pour ajouter `--threads 4` (la classe de processus gthread est alors
   implicite) dans `systemd/survive-dashboard.service`, et reporter dans
   `scripts/generate_services.sh` et dans la commande de lancement de CLAUDE.md.

## Cas limites qu'un modèle moins attentif manquerait

- **La sémantique de `timeout` s'inverse** : avec `stream: False`, le plafond de 60 s était
  total ; en flux, il devient l'intervalle d'inactivité entre deux morceaux. C'est le
  comportement voulu — un modèle qui génère émet un morceau par seconde. Le documenter dans le
  commentaire de `survive.conf`, sinon les modèles lents « marcheront » alors que la
  documentation dit qu'ils ne le peuvent pas.
- **Erreurs après l'envoi des en-têtes** : dès que la première ligne NDJSON est émise, on ne
  peut plus changer le code HTTP — c'est pourquoi les échecs en cours de flux sont des lignes
  `{"error": ...}` et les échecs avant le flux gardent de vrais codes d'état. Le test de fumée
  doit couvrir les deux.
- **Déconnexion du client** : quand le navigateur interrompt, Flask lève `GeneratorExit` dans
  `generate()` — le `finally: upstream.close()` arrête la génération d'Ollama (Ollama annule
  à la fermeture de la connexion). Sans lui, le Pi continue de brûler du processeur pour une
  réponse que personne ne lira.
- **Flask-Limiter** compte la requête au moment du routage ; la durée du flux ne consomme pas
  de quota supplémentaire. Rien à changer — mais ne pas déplacer le décorateur du limiteur
  sous `@csrf.exempt` (l'ordre des décorateurs compte).
- **`decoder.decode(value, {stream: true})`** — sans `stream: true`, l'UTF-8 multi-octets
  (— … •) coupé entre deux morceaux produit des caractères corrompus. Les modèles moins
  attentifs l'oublient toujours.
- **Les réponses limitées en débit (429)** viennent de Flask-Limiter en JSON avant le début du
  flux — le repli selon le content-type de l'étape 2 du client les gère.
- **L'environnement de test de fumée n'a pas Ollama** — le chemin du flux ne peut pas être
  exercé de bout en bout en CI ; tester plutôt le contrat d'erreur (voir ci-dessous) et le
  chemin nominal à la main sur le Pi.

## Critères d'acceptation

1. Tests de fumée : corps vide 400, formulaire 415 et (Ollama arrêté) 502 **renvoient tous
   encore application/json avec les bons codes d'état** — le contrat d'erreur avant flux est
   inchangé. Ajouter une assertion qu'une requête valide contre un Ollama mort renvoie un JSON
   502, pas un flux 200.
2. À la main sur le Pi : poser une longue question avec `gemma4:12b` ; premier jeton visible en
   < 5 s ; la génération dépasse 60 s SANS troncature ; Annuler arrête l'usage processeur
   d'`ollama` (à vérifier avec `top`) en ~2 s.
3. `curl -N -X POST localhost:8080/api/ai/chat -H 'Content-Type: application/json' -d '{"message":"salut"}'`
   (Ollama en marche) affiche des lignes NDJSON au fil de l'eau : d'abord `{"sources":...}`,
   puis des lignes `{"delta":...}`, et enfin `{"done": true,...}`.
4. Via nginx (`http://survive.local/api/ai/chat`), les morceaux arrivent au fur et à mesure et
   non d'un seul bloc à la fin (prouve `proxy_buffering off`).
5. Deux chats simultanés + un troisième onglet qui charge `/` — le tableau de bord répond
   encore (prouve `--threads`).
6. pylint ≥ 9,5 ; shellcheck propre.
