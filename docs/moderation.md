# Modération du chat

Chat texte du jeu (#541) : moteur `TextChatService`, interface du jeu, journal des messages et commandes admin.
L'anti-triche (remotes, `CheatLog`) est dans `docs/anticheat.md`.

## Ce que fait Roblox, ce que fait le jeu

`TextChatService` reste le moteur. Il fait déjà, et le jeu ne le recode pas :

- le filtrage du texte (par destinataire, selon son âge et sa politique de compte) ;
- les restrictions de compte (chat désactivé par les parents, âge) ;
- le signalement (Report Abuse joint le chat) et la sourdine d'un joueur depuis le menu Roblox.

Le jeu ajoute :

| Quoi | Où |
|---|---|
| Interface (fil en bas à gauche, Entrée pour écrire), fenêtre et barre natives masquées | `src/client/ui/ChatFeed.luau` (rendu : `docs/ui.md` « Chat ») |
| Débit et longueur maximale, sourdine du serveur, `/mute`, `/unmute`, `/kick`, journal | `src/server/ChatService.luau` |
| Règles pures : nettoyage, longueur, débit, fondu, commandes, joueur visé, droits | `src/shared/ChatRules.luau` (`tests/specs/ChatRules.spec.luau`) |
| Lots du journal : mise en forme, découpe en messages Discord | `src/server/ChatLogRules.luau` (`tests/specs/ChatLogRules.spec.luau`) |

Décisions de l'utilisateur (18/11/2026) : souris toujours verrouillée pendant la saisie en partie, journal du texte
filtré seulement, PC seulement (pas de bouton mobile ni de manette), pas de messages du jeu (kills, arrivées) dans le fil.

## Limites côté serveur

Contrôlées dans le `ShouldDeliverCallback` de chaque canal (`ChatService.decide`) :

- **Longueur :** `ChatRules.MAX_LENGTH` caractères (120). Le champ de saisie coupe déjà au-delà.
- **Débit :** seau à jetons par joueur, `ChatRules.RATE` message regagné par seconde, `ChatRules.BURST` (4) d'affilée.
  Le client applique la même règle avant d'envoyer (retour « Trop de messages » dans le fil, texte gardé) ; le serveur
  tolère un message de plus (`SERVER_BURST`) pour la gigue réseau.
- **Sourdine du serveur** (`/mute`) : message refusé.

Un message refusé n'est pas journalisé. Piège : Roblox montre toujours son message à l'auteur, même refusé par le
callback ; un joueur muet ou qui spamme voit donc ses messages, les autres non.

Le callback est appelé **une fois par destinataire** (auteur compris) : la décision est prise au premier appel et gardée
par `MessageId` (`DECISION_TTL`), le message accepté est journalisé une seule fois.

## Journal

- Chaque message délivré : UserId, nom d'utilisateur, texte, heure (UTC) ; le JobId part dans le pied de l'envoi. Les
  commandes `/mute`, `/unmute`, `/kick` aussi (admin, joueur visé, motif filtré).
- Envoi par lots toutes les `ChatLogRules.FLUSH_INTERVAL` s (15), un embed par envoi (description bornée à
  `MAX_DESCRIPTION`), pause de 2 s entre deux envois d'un même passage ; dernier envoi à l'arrêt du serveur
  (`BindToClose`). Au plus `MAX_PENDING` entrées en attente ; au-delà (webhook en panne), les plus anciennes sont
  abandonnées et leur nombre est signalé dans l'envoi suivant.
- **Webhook :** `StringValue` nommé `ChatLogWebhookUrl` dans `ServerScriptService` de la place publiée, posé à la main,
  jamais versionné (comme `FeedbackWebhookUrl` et `CheatLogWebhookUrl`, `Webhook.luau`). HTTP doit être activé dans les
  réglages du jeu. Sans URL : rien n'est filtré ni envoyé, pas d'erreur. Dans Studio sans URL, chaque lot s'écrit dans
  la sortie (`[ChatLog]`) pour vérifier.
- **Texte filtré, jamais brut.** Piège : dans `ShouldDeliverCallback`, `message.Text` est le texte **brut** (le
  filtrage par destinataire vient après ; constaté par plusieurs développeurs, la doc de `TextChatMessage.Text` dit le
  contraire). Le serveur filtre donc lui-même le texte accepté avec `TextService:FilterStringAsync` puis
  `GetNonChatStringForBroadcastAsync` (version la plus stricte, celle qu'on peut montrer à tous) avant de le journaliser.
  Le texte brut ne quitte jamais la mémoire du serveur. Filtrage en échec : `[texte non filtré : filtrage indisponible]`.
  Les cas graves passent par le signalement Roblox, qui voit le texte brut.

## Commandes admin

Réservées au rôle `Admin` de `Roles` (propriétaire du jeu et liste d'UserId). Des `TextChatCommand` (`CSGOMute`,
`CSGOUnmute`, `CSGOKick`, dossier `TextChatService.CSGOCommands`) créées par le serveur : une commande n'est jamais
diffusée comme message, quel que soit l'auteur. Un non-admin qui en tape une n'obtient rien.

- `/mute <joueur>` : ses messages ne sont plus délivrés, pour le serveur en cours (reconnexion comprise sur ce serveur).
- `/unmute <joueur>` : lève la sourdine.
- `/kick <joueur> [motif]` : expulse le joueur ; le motif est filtré (version pour tous) avant d'être montré au joueur
  expulsé et journalisé. Message d'expulsion dans la langue de son compte.
- Joueur visé (`ChatRules.findTarget`, casse ignorée) : nom d'utilisateur ou nom affiché exact, sinon début de nom ;
  dans les deux cas un seul joueur doit correspondre. Piège : un nom affiché peut copier le nom d'utilisateur d'un
  autre joueur (« bob » d'un troll contre le compte « Bob ») ; c'est alors ambigu, et `@nom` vise le nom d'utilisateur
  exact, seul. Absent ou ambigu : retour à l'admin, rien n'est appliqué.
- Un admin (propriétaire, autre admin, soi-même) n'est jamais visé : retour « commande refusée ».
- Retour à l'admin dans son fil (remote `ChatNotice`, gabarits `ChatRules.Notice` traduits chez lui).
- Pas de bannissement (`Players:BanAsync`) : hors périmètre de #541.

Les commandes Roblox par défaut (`/whisper`, `/team`, `/mute` natif, `/help`, `/emote`…) sont coupées :
`TextChatService.CreateDefaultCommands = false` dans `default.project.json`, et `ChatService` désactive en plus toute
`TextChatCommand` nommée `RBX…`. Notre fil n'a pas d'interface pour leurs canaux ni leurs messages système, et `/mute`
natif prendrait notre alias.

**Studio :** les joueurs d'un serveur local n'ont pas le compte du propriétaire. Attribut de debug posé côté serveur
(contexte `Server` du MCP) : `game.Players.Player1:SetAttribute("DebugChatAdmin", true)` donne les commandes à ce
joueur, dans Studio seulement (`ChatRules.canModerate`).

## Vérifier

- Tests : `lune run tests/run.luau` (`ChatRules`, `ChatLogRules`, `InputModule`).
- En jeu (Studio, onglet Test, « Clients and Servers », 2 joueurs) : Entrée, message, Entrée sur un client, le message
  arrive chez les deux ; `DebugChatAdmin` sur Player1, `/mute Player2` puis message de Player2 : rien chez Player1, et
  une ligne `[ChatLog]` dans la sortie du serveur au lot suivant (15 s) ; 6 messages d'affilée : retour « Trop de
  messages ».
