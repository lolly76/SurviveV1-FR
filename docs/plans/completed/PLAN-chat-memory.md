# PLAN-chat-memory : conversations à plusieurs tours avec historique persistant

**Rang : n° 2.**

## Objectif

Chaque message du chat est une requête neuve, à un seul tour : le client n'envoie que le
message courant, donc des questions de suivi comme « et pour un enfant ? » ou « détaille
l'étape 2 » reçoivent des réponses sans aucun contexte. Un rechargement de la page efface
aussi la conversation visible.

Après ce changement : le client envoie l'historique récent avec chaque requête, le serveur le
valide et l'injecte dans l'appel à Ollama, et la conversation survit aux rechargements grâce
à localStorage. C'est la différence entre une boîte de questions-réponses et un assistant.

## Fichiers exacts à modifier

| Fichier | Changement |
|---------|------------|
| `web/server.py` | valider + injecter `history` dans `ai_chat()` |
| `web/templates/ai.html` | tenir/envoyer/conserver l'historique ; le restaurer au chargement |
| `tests/test_smoke.sh` | tests de rejet d'historiques mal formés |
| `docs/API.md` | documenter le champ `history` |

## Ordre de mise en œuvre

1. **Serveur — accepter `history`** dans `ai_chat()` après la vérification du modèle :
   ```python
   history = data.get("history", [])
   if not isinstance(history, list):
       return jsonify({"error": "l'historique doit être une liste"}), 400
   clean_history = []
   for turn in history[-8:]:                      # plafonner le nombre de tours
       if not isinstance(turn, dict):
           return jsonify({"error": "entrée d'historique invalide"}), 400
       role = turn.get("role")
       content = turn.get("content")
       if role not in ("user", "assistant") or not isinstance(content, str):
           return jsonify({"error": "entrée d'historique invalide"}), 400
       clean_history.append({"role": role, "content": content[:2000]})
   # Budget total de caractères pour que historique + RAG tiennent dans num_ctx 4096 (~16k car.) :
   total = 0
   budgeted = []
   for turn in reversed(clean_history):           # garder les tours les plus récents
       total += len(turn["content"])
       if total > 3000:
           break
       budgeted.append(turn)
   clean_history = list(reversed(budgeted))
   ```
   Construire les messages ainsi : `[system] + clean_history + [message utilisateur courant]`.
   **La recherche n'utilise QUE le message courant** — ne pas concaténer l'historique dans la
   requête Kiwix (cela dégrade la précision de la recherche, et c'est l'erreur qu'un modèle
   moins attentif commettra).

2. **Client — suivre l'historique** dans `ai.html` :
   - `let chatHistory = [];` au niveau du module (tableau de `{role, content}`).
   - Dans `sendMessage()` : inclure `history: chatHistory` dans le corps du POST (avant
     d'ajouter le message courant).
   - À la fin réussie (la ligne `done`) : ajouter `{role:'user', content: msg}` et
     `{role:'assistant', content: text}`, puis `saveHistory()`.
   - `saveHistory()` / `loadHistory()` : clé localStorage `survive_chat_v1`, valeur
     `JSON.stringify(chatHistory.slice(-20))`. Envelopper l'accès à `localStorage` dans un
     try/catch (le mode de navigation privée lève une exception).
   - Au chargement de la page : `loadHistory()` ; s'il n'est pas vide, réafficher chaque tour
     avec `addMessage()` existant (sans la bulle d'accueil dans ce cas), et afficher une petite
     note « conversation précédente restaurée — Effacer pour repartir de zéro ».
   - `clearChat()` : aussi `chatHistory = []` et supprimer la clé localStorage.

3. **Ne PAS stocker les sources dans l'historique** — `addMessage` les affiche séparément ;
   le contenu de l'historique côté assistant est uniquement le texte de la réponse (les
   sources gonfleraient le budget de contexte et troubleraient le modèle).

4. **Les tours en erreur ne font pas partie de l'historique** : n'ajouter à `chatHistory`
   qu'après un `done` propre ; les échanges interrompus ou en erreur laissent l'historique
   intact (l'utilisateur reposera la même question).

## Cas limites qu'un modèle moins attentif manquerait

- **Ne jamais se fier aux rôles du client** : sans la liste blanche
  `role in ("user","assistant")`, une requête forgée injecte `{"role":"system", ...}` et
  écrase le prompt système de survie. C'est la ligne critique pour la sécurité.
- **Calcul du budget** : 8 tours × 2000 caractères = 16k caractères ≈ tout `num_ctx` — d'où
  le second budget total de 3000 caractères. Les extraits RAG (~5-7k caractères) + l'historique
  (3k) + la question (4k au plus) tiennent encore dans ~16k. Si PLAN-pdf-text-search est aussi
  livré, ces budgets en tiennent déjà compte.
- **`MAX_CONTENT_LENGTH` vaut 64 Ko** (configuration de l'application) : 8 tours de 2000
  caractères ≈ 16 Ko de JSON — cela passe, aucun changement de configuration. Ne pas relever
  la limite.
- **Couper les plus anciens, garder les plus récents** : le va-et-vient inverser/ajouter/
  inverser conserve les tours les plus récents. Couper naïvement `[:3000 caractères]` depuis
  le début garde le contexte le plus ANCIEN — subtil et faux.
- **localStorage dans des contextes de type `file://` ou privés lève une exception** — chaque
  accès exige un try/catch, sinon toute la page du chat plante sur certains navigateurs.
- **Le chemin de restauration doit afficher avec `textContent`** (c'est le cas, via
  `addMessage`) — l'historique restauré peut être manipulé par un attaquant via localStorage,
  mêmes règles XSS que pour les messages en direct.
- **`history` est facultatif** : un `history` absent ou vide doit se comporter exactement comme
  aujourd'hui (tous les tests de fumée existants doivent passer sans changement).

## Critères d'acceptation

1. Tests de fumée (tous dans l'environnement sans Ollama, ne vérifiant que la validation) :
   - POST `{"message":"hi","history":"bad"}` → HTTP 400.
   - POST `{"message":"hi","history":[{"role":"system","content":"x"}]}` → 400.
   - POST `{"message":"hi","history":[]}` → 502 (Ollama arrêté — contrat inchangé ; prouve
     qu'un historique vide est accepté).
2. Avec un Ollama simulé : envoyer le message A, puis le message B avec l'historique — le
   simulateur enregistre le corps de la requête ; vérifier qu'il contient d'abord le prompt
   système, puis la paire utilisateur/assistant de A, puis B.
3. Playwright : envoyer un message (services simulés), recharger la page, l'échange précédent
   est toujours affiché ; cliquer sur Effacer, recharger, seule la bulle d'accueil apparaît.
4. pylint ≥ 9,5 ; tous les tests de fumée préexistants toujours au vert.
