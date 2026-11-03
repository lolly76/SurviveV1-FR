# PLAN-ai-rag : ancrer l'assistant IA dans la base de connaissances locale (RAG)

**Rang : n° 1 — à faire en premier.**

## Objectif

`/api/ai/chat` (web) et `ai/query.sh` (ligne de commande) envoient pour l'instant la question
de l'utilisateur directement à Ollama. Le modèle répond avec ses seuls 1,5 à 8 Go de poids,
alors que ~800 Go de contenus de survie soigneusement choisis restent inutilisés sur le même
disque. Le README et la page `/ai` *affirment* tous deux que l'IA « cherche dans vos
contenus » — ce plan rend cette affirmation vraie.

Après ce changement : avant d'appeler Ollama, le serveur interroge la recherche plein texte de
Kiwix avec la question de l'utilisateur, extrait les meilleurs extraits d'articles, les injecte
dans le prompt comme contexte, et renvoie la réponse **accompagnée d'une liste `sources`** que
l'interface affiche sous forme de liens cliquables vers Kiwix.

Effet de levier : cela transforme la fonction la plus faible (un chat générique avec un petit
modèle) en fonction phare (un assistant qui cite « Où il n'y a pas de médecin » au lieu
d'inventer des posologies). Aucune nouvelle dépendance, aucun nouveau service.

## Fichiers exacts à modifier

| Fichier | Changement |
|---------|------------|
| `web/server.py` | ajouter `_kiwix_search()`, `_fetch_article_text()`, `_build_rag_prompt()` ; modifier `ai_chat()` |
| `web/templates/ai.html` | afficher `data.sources` sous chaque message de l'IA |
| `ai/query.sh` | même récupération via `curl` + assistant `python3` avant l'appel à Ollama |
| `tests/test_smoke.sh` | nouvelles assertions (voir les critères d'acceptation) |
| `CLAUDE.md` | documenter le flux RAG dans la section du serveur web |
| `docs/API.md` | documenter le nouveau champ `sources` dans la réponse du chat |

## Ordre de mise en œuvre

1. **`_kiwix_search(query, limit=3)` dans `web/server.py`** (à placer près des autres
   fonctions utilitaires, après `check_all_services`). Kiwix-serve expose du XML OpenSearch :
   `GET http://localhost:{PORT_KIWIX}/search?pattern=<urlencoded>&pageLength=<limit>&format=xml`
   Analyser avec `xml.etree.ElementTree` (bibliothèque standard). Chaque `<item>` contient
   `<title>`, `<link>` (URL relative de l'article) et `<description>` (extrait). Renvoyer
   `[{"title", "url", "snippet"}]`. Envelopper tout le corps dans
   `try/except (OSError, ET.ParseError): return []`. Utiliser `urllib.parse.quote()` sur le
   motif. Délai maximal : réutiliser `TIMEOUT_OLLAMA_LIST` (2 s) — la récupération ne doit
   jamais consommer le budget du chat.

2. **`_fetch_article_text(url, max_chars=2000)`** : GET
   `http://localhost:{PORT_KIWIX}{url}` (délai de 2 s), décoder, retirer les balises avec
   `re.sub(r"<script.*?</script>|<style.*?</style>", "", html, flags=re.S)` puis
   `re.sub(r"<[^>]+>", " ", ...)` puis réduire les espaces. Renvoyer les `max_chars` premiers
   caractères. En cas d'exception, renvoyer plutôt l'extrait de la recherche (passé en
   argument de repli).

3. **`_build_rag_prompt(message, articles)`** : renvoie le prompt système. Si `articles` est
   vide, renvoyer le prompt système actuel PLUS une phrase : « Aucun article de référence n'a
   été trouvé pour cette question ; dis-le si tu n'es pas sûr. » Sinon, ajouter :
   ```
   Extraits de référence de la bibliothèque hors ligne :
   [1] <titre> : <texte>
   [2] ...
   Appuie-toi sur ces extraits lorsque c'est pertinent et indique les
   numéros des sources utilisées.
   ```

4. **Modifier `ai_chat()`** : après validation de `message`, appeler
   `articles = _kiwix_search(message)` ; récupérer le texte de chaque article ; construire le
   prompt système avec `_build_rag_prompt`. Ajouter à la réponse JSON :
   `"sources": [{"title": a["title"], "url": f"http://{request.host.split(':')[0]}:{PORT_KIWIX}{a['url']}"} for a in articles]`.

5. **`ai.html`** : dans le chemin de succès de `sendMessage()`, après
   `addMessage('ai', data.response)`, si `data.sources?.length`, ajouter une petite `<div>` à
   la dernière bulle avec des liens (créer les éléments avec `textContent` pour les titres —
   jamais innerHTML — et `href` pris dans `data.sources[i].url`, `target="_blank"`).

6. **`ai/query.sh`** : avant l'appel à Ollama, ajouter une fonction `get_context()` :
   `curl -sf --max-time 3 "http://localhost:8081/search?pattern=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1]))" "$QUERY")&pageLength=3&format=xml"`
   passé dans un petit extrait `python3 -c` qui convertit le XML en texte. Placer le résultat
   en tête du prompt. Si curl échoue (Kiwix arrêté), continuer exactement comme aujourd'hui.

7. Mettre à jour `tests/test_smoke.sh`, `CLAUDE.md`, `docs/API.md`.

## Cas limites qu'un modèle moins attentif manquerait

- **Dépassement de la fenêtre de contexte** : le modèle `survive` tourne avec `num_ctx 4096`
  (~16 000 caractères). Plafond : 3 articles × 2 000 caractères + prompt système + question
  ≈ 7 500 caractères — sans danger. Ne PAS augmenter le nombre d'articles ni `max_chars` sans
  augmenter `num_ctx` dans `ai/Modelfile.survival` (ce qui coûte de la RAM sur les Pi de 4 Go).
- **Kiwix renvoie des pages d'erreur HTML avec un code HTTP 200** pour certains motifs mal
  formés — protéger l'analyse XML, ne pas se fier au code d'état.
- **`format=xml` exige kiwix-tools ≥ 3.x** (apt de Bookworm fournit 3.3+ ; l'installateur
  l'utilise). Si l'analyse XML échoue, dégrader en chat sans contexte — jamais de 500.
- **La configuration gunicorn à deux processus** : la récupération ajoute jusqu'à ~8 s dans le
  pire cas (1 recherche + 3 lectures d'articles à 2 s chacune) avant l'appel à Ollama.
  Récupérer les 3 articles avec le modèle `ThreadPoolExecutor` existant (max_workers=3) pour
  que le pire cas soit ~4 s au total, et non 8.
- **Limitation de débit** : `/api/ai/chat` reste à 5/min ; les appels de récupération sont
  internes au serveur et NON limités — ne pas les faire passer par Flask.
- **Injection dans le motif de recherche** : le message est une saisie utilisateur placée dans
  une URL — `urllib.parse.quote()` est obligatoire ; ne pas l'insérer brut dans une f-string.
- **Bibliothèque ZIM vide** (installation neuve, rien de téléchargé) : `/search` renvoie un
  résultat vide valide ; `_kiwix_search` doit renvoyer `[]`, et la phrase de repli du prompt
  garde le modèle honnête.
- **Ne pas** mettre en cache les résultats de récupération dans les caches TTL — chaque
  question est différente ; un cache renverrait un mauvais contexte.

## Critères d'acceptation

1. `bash tests/test_smoke.sh` — toutes les assertions existantes passent toujours, plus :
   - POST `/api/ai/chat` avec un JSON valide alors que Kiwix est **arrêté** renvoie toujours
     502 (Ollama arrêté dans l'environnement de test) — c'est-à-dire qu'un échec de
     récupération ne change pas le contrat d'erreur.
2. Avec Kiwix en marche et un ZIM chargé,
   `curl -s -X POST localhost:8080/api/ai/chat -H 'Content-Type: application/json' -d '{"message":"comment traiter une brûlure"}' | python3 -m json.tool`
   renvoie un tableau `sources` d'au moins 1 entrée dont l'`url` commence par `http://` et
   contient `:8081`.
3. `pylint web/server.py --disable=C0114,C0115,C0116,R0903,R0913,R0914 --fail-under=7.0` reste ≥ 9,5.
4. Dans le navigateur, une réponse de l'IA affiche une ligne « Sources » avec des liens
   cliquables qui ouvrent des articles Kiwix.
5. `bash ai/query.sh "comment purifier de l'eau"` affiche une réponse ; avec kiwix-serve
   arrêté, il affiche encore une réponse (pas de plantage).
