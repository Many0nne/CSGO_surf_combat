# Page du jeu : miniatures et promo

Référence pour les images et vidéos de la page Roblox du jeu (miniatures #524, vidéo #525). La direction artistique
reste celle de `docs/ui.md` (« Ligne de mire ») : ciel bleu nuit, soleil blanc chaud, ambre, rampes brun chaud,
silhouettes noires, rouge d'impact.

## Règles de Roblox (vérifiées le 17/11/2026)

Source principale : [Thumbnails](https://create.roblox.com/docs/production/publishing/thumbnails) (documentation
officielle) ; annonces du DevForum citées au fil du texte.

- **Format :** 16:9, idéalement **1920×1080**. Formats acceptés : PNG, JPG, GIF, TGA, BMP. Une image d'un autre ratio est
  **étirée**, pas recadrée. Les miniatures de l'onglet « Home Page » doivent faire **moins de 3 Mo** (PNG trop lourd :
  exporter en JPG de qualité 90 à 95).
- **Nombre :** jusqu'à 10 images ou vidéos sur la page du jeu ; **2 à 5 miniatures actives** pour la personnalisation de
  l'accueil (voir plus bas). Vidéos : 3 envois par mois, refus compris ; pas affichées sur Xbox, PlayStation ni VR.
- **Vidéo :** gratuite, placée **en premier** sur la page du jeu une fois acceptée, et peut aussi apparaître sur l'accueil.
  **30 s au plus** (ancienne page d'aide et [fil du DevForum de 2024](https://devforum.roblox.com/t/what-is-the-maximum-length-for-video-thumbnails/3073873) ;
  la documentation actuelle ne donne ni durée, ni format, ni poids : à confirmer dans la fenêtre d'envoi). Elle doit
  montrer du **vrai gameplay** : angles de caméra variés, retouche légère (luminosité, contraste) et logo permis ;
  interface du jeu permise ; texte ajouté « avec parcimonie, pour décrire le gameplay ». **Son :** ni voix off, ni
  chat vocal, ni musique à paroles ; seule la musique du catalogue audio de Roblox est autorisée.
- **Obligatoire depuis le 19/10/2026 :** un jeu sans miniature personnalisée n'est plus recommandé sur l'accueil
  ([annonce](https://devforum.roblox.com/t/homepage-recommendation-eligibility-now-requires-a-custom-thumbnail/4945086)).
- **La 1re miniature est la plus vue :** depuis le 16/03/2026, la recherche affiche la **première miniature 16:9** de la
  galerie au lieu de l'icône carrée ([annonce](https://devforum.roblox.com/t/search-results-will-now-show-169-thumbnails/4525356)).
  L'icône reste dans les classements et « Continuer ». Mettre la plus forte en premier.
- **Bas de l'image :** Roblox y superpose des informations (nombre de joueurs, note) : rien d'important dans le
  cinquième inférieur (marge estimée, pas de chiffre officiel).
- **Modération (règles des contenus trompeurs) :** tout ce qui est montré existe en jeu : armes, skins, map,
  personnage, effets, interface. Pas de mécanique, d'interface ou de graphisme inventés, pas d'image réelle, pas de
  promesse commerciale (« -50 % », « UGC gratuit »). Le logo du jeu est permis. Pas de QR code (avertissement de compte
  rapporté sur le DevForum).
- **Armes réalistes :** un utilisateur du DevForum rapporte une modération pour une arme moderne réaliste montrée hors
  usage en jeu ([fil](https://devforum.roblox.com/t/auto-generated-image-thumbnails-for-packages-can-lead-to-moderation-action/1974283)) :
  montrer l'AWP en situation de jeu (tenue, visée, tir), pas comme un produit isolé sur fond neutre. Non confirmé par
  une règle officielle.

## Références de l'utilisateur (17/11/2026)

Miniatures jugées réussies par l'utilisateur, relevées par l'API publique de Roblox (non versionnées : images d'autres
jeux). Pour les relire : `https://apis.roblox.com/universes/v1/places/<placeId>/universe` donne l'`universeId`, puis
`https://thumbnails.roblox.com/v1/games/multiget/thumbnails?universeIds=<id>&countPerUniverse=10&size=768x432&format=Png`.

| Jeu | Place | Miniatures | Ce qu'elles font |
|---|---|---|---|
| Revolver Arena | 108419873026523 | 9 | Revolvers à skin seuls ou tenus, vue subjective face à des adversaires en silhouettes rouges, lignes de vitesse |
| Hypershot | 17516596118 | 4 | Arme à skin tenue en contre-plongée, ciel bleu et tours ; adversaire en l'air, balles en traînées rouges |
| Sniper Arena | 122446657157717 | 5 | Sniper à skin tenu, contre-plongée vers le ciel ; une vue à travers la lunette sur un adversaire en rouge |
| Scoped FPS | 93466613073564 | 4 | Sniper tenu en vue subjective, contre-jour du soleil, reflets |
| Knife Arena | 135757618941587 | 9 | Un couteau par image, tenu, lame vers le ciel bleu, éclat de soleil sur la pointe |

Ce qui revient :

- **Vue subjective** : les bras du joueur tiennent l'arme, qui remplit 60 à 100 % de l'image, coupée par les bords,
  en diagonale. Presque aucun personnage en pied ; quand il y en a un, c'est l'adversaire.
- **Le skin est le sujet** : un skin par image, couleurs saturées, rendu brillant (3D retravaillée), éclat de soleil.
- **Contre-plongée vers le ciel** : fond simple et clair, l'arme s'y détache.
- **L'action** quand il y en a une : adversaire visé (lunette, silhouette), tir en cours.
- À ne pas reprendre ici : les silhouettes rouges (pas de surbrillance des ennemis en jeu), les lignes de vitesse
  dessinées (effet posé sur l'image, écarté par la DA, `docs/ui.md`), les logos (choix : aucun texte).

## Ce qui fait cliquer (règles retenues pour ce jeu)

Roblox ne publie pas d'étude sur les miniatures des shooters ; les règles ci-dessous combinent sa documentation
(images nettes, uniques, pertinentes, ton donné par la couleur, rien d'ambigu) et les conseils courants des créateurs.

1. **Vendre la vitesse et l'air, pas le surf** (retour de l'utilisateur, 17/11/2026) : « impossible de comprendre avec
   une miniature ce qu'est le surf ». Une rampe vue de près ressemble à un mur ou à une chute, même dans un décor
   construit exprès. Montrer le bunny hop, le saut, le tir en plein vol, les armes et leurs skins rares.
2. **Une idée, un sujet, une action en cours.** Un joueur qui fait quelque chose (saute, tire, frappe), pas un
   personnage qui pose. Un personnage seul ou un gros plan d'adversaire à la lunette n'apporte rien (rejetés).
3. **Comme les jeux de référence** : vue subjective, arme à skin en gros plan en diagonale, contre-plongée vers le ciel,
   éclat de soleil ; adversaire touché en plein saut.
4. **Lisible en petit :** juger chaque image à **320×180** (tuile de recherche ou d'accueil sur ordinateur) et
   **160×90** (téléphone, quatre jeux par ligne).
5. **Lumière du jeu :** ciel de crépuscule bleu nuit, soleil bas, mer de nuages ; plu à l'utilisateur (garder). Pas
   de néon, pas de lueur inventée.
6. **Aucun texte** (choix de l'utilisateur, #524) : l'image doit se comprendre seule.
7. **Fidèle au jeu :** le personnage est celui du jeu (`StarterCharacter`, tous les joueurs ont le même), avec ses
   proportions en blocs ; armes et skins à l'identique. Effets permis car présents en jeu : flamme de bouche, rayon de
   la balle (ruban jaune pâle `TRACER_RGB`), lunette. **Pas d'éclats d'impact ni de surbrillance des ennemis** : ils
   n'existent pas en jeu. Un décor inventé est accepté par l'utilisateur s'il ressemble à Dizzy.
8. **Les cinq se distinguent :** idées différentes, pour que la personnalisation de Roblox puisse trouver la meilleure
   par public.

## Fabrication

**Retenu (17/11/2026, choix de l'utilisateur) : ChatGPT fait les miniatures en entier** à partir d'un kit de références
et d'un brief ; Claude fournit le kit, contrôle la fidélité et exporte. Deux essais de mise en scène dans Studio
retravaillés par ChatGPT ont été rejetés (voir « Pistes écartées »).

1. **Kit de références** (`assets/promo/kit/`, régénérable par `tools/promo/stage.luau`) : personnage du jeu sous
   plusieurs angles avec chaque tenue d'arme (`01-*`), armes et skins de profil (`02-*`), bras du joueur et arme en vue
   subjective (`03-*`), map et ciel (`04-*`), brief `BRIEF-CHATGPT.md`. ChatGPT prend une dizaine d'images par
   message : envoyer des planches (une par famille du kit, une par jeu de référence) et les skins légendaires en grand.
   Les captures d'écran de partie avec interface sont à éviter (interface à exclure, et celles de `docs/ui/captures`
   peuvent dater : AWP d'origine en bois au 12/11, olive au 17/11).
2. **Contrôle** : comparer chaque image au kit, lister les écarts (forme de l'arme, motif du skin, visage et tenue du
   personnage, décor, effets inventés), les faire corriger, puis export 1920×1080 dans `assets/promo/thumbnails/`
   (`tools/promo/finish.py export` ; PNG suivi par Git LFS, JPG < 3 Mo pour l'envoi si le PNG dépasse), et planche de
   lisibilité (`finish.py small`).

### Outil de mise en scène (`tools/promo/stage.luau`)

Construit en **mode Edit**, sans playtest (rien ne tourne du jeu, la caméra reste où on la pose), avec les vrais
assets : personnage du jeu en l'air (piste de chute figée, tenue de l'arme de `WeaponThirdPerson`), viewmodels habillés
(`WeaponSkins`, pose Idle), rayon de la balle et flamme (`ShotEffectRules`), lumière du jeu. Scènes dans un décor à part
(deux rampes au-dessus des nappes de nuages de Dizzy, axe vers le soleil). Rien n'est enregistré : dossier
`Workspace.__PromoStage` non archivable, retiré par `_G.Promo.clear()`. Procédure, Studio réservé, depuis le worktree :

```powershell
$env:CAP_DIR = "$env:TEMP\csgo-promo"; $env:CAPTURE_PORT = "34990"   # 34991 refusé par l'allowlist HTTP du MCP
uv run tools/anim/capture_server.py "$env:CAP_DIR\raw" tools/promo/stage.luau   # en arrière-plan : /frames sert le script
uv run tools/ui/capture.py place save; uv run tools/ui/capture.py place set 0 0 1655 1080   # viewport 16:9
```

Puis dans `execute_luau` (contexte Edit) :
`loadstring(game:GetService("HttpService"):GetAsync("http://localhost:34990/frames"))()` charge le script (à refaire
après chaque modification), `_G.Promo.shot("tir")` pose une scène (`surf`, `tir`, `lame`, `ciselure`, `cordoue` ;
réglages remplaçables : `_G.Promo.shot("tir", { fov = 70 })` ; décor : `_G.Promo.SPACE`), `screen_capture` pour juger,
puis `curl.exe "http://localhost:34990/shot?name=<nom>"` et `uv run tools/ui/capture.py crop <dossier> <nom>` (repérer
d'abord le viewport avec un voile magenta dans `CoreGui`, voir `docs/ui.md` « Captures de référence »). Pour une série
de captures sans attendre dans l'appel MCP : `task.spawn` qui pose chaque vue, `task.wait(1)`, puis
`HttpService:GetAsync(".../shot?name=...")`. À la fin : `_G.Promo.clear()`, `capture.py place restore`, `/quit`,
libérer Studio.

- **Piège : en mode Edit, un `Motor6D.Transform` posé par script n'est pas rendu** (les bras restaient dans la pose de
  la piste de chute alors que `Transform` valait la tenue). Le script fige les poses dans les `C0` (le rig n'a aucune
  rotation dans ses `C0`, donc `C0 * Transform` donne la pose du jeu).
- Le cube de vue de Studio apparaît dans les captures (coin haut droit) : `uv run tools/promo/finish.py clean`.
- La lunette (interface) n'existe pas en mode Edit : `finish.py scope` la dessine comme `ScopeOverlay`.
- Fiches de référence : personnage face au soleil plus une `PointLight` près de la caméra (sinon contre-jour noir) ;
  arme seule = viewmodel bras cachés (`hide`), tourné de profil (AWP : lacet -90° ; couteaux : tangage -60°, roulis
  -90°), pointe à droite comme partout dans le jeu.

### Pistes écartées

| Essai | Retour de l'utilisateur |
|---|---|
| Mises en scène sur les rampes de Dizzy (surf en vue subjective, lunette à FOV 10, inspection des deux skins, surfeur de dos), retravaillées par ChatGPT | « Pas très proche des miniatures de référence » ; zoom sur l'ennemi et plan avec l'adversaire seul inutiles ; la rampe gêne sur les inspections ; sa tôle est laide et on croit que le joueur tombe ou vole. Gardés : mer de nuages et soleil, inspections des armes |
| Décor dédié : deux rampes isolées au-dessus des nuages, vers le soleil (vue d'ensemble, tir en vol, couteau, inspections sans rampe) | « Trop focus sur le surf » : on ne comprend pas le surf sur une miniature. Passage au kit et à ChatGPT en entier |

## Vidéo de la page (#525)

Objectif : qu'un joueur qui ne connaît pas le surf comprenne le jeu avant de cliquer. La vidéo passe avant les
miniatures sur la page du jeu, et la plupart des gens la voient sans le son.

**Décisions de l'utilisateur (17/11/2026) :** vrai gameplay monté, pas d'animation (c'est aussi ce qu'exige la
modération) ; **16:9 seulement** (le vertical reste aux vidéos TikTok) ; **aucun texte ajouté** ; **musique du
catalogue Roblox** sous les sons du jeu. **Pas d'OBS (même jour) :** filmer en jouant fait saccader le jeu sur le poste de
l'utilisateur et lui fait rater ses mouvements. Il joue donc sans rien filmer, un enregistreur léger note ses meilleures
actions dans les journaux de Roblox, et Claude les rejoue dans Studio pour les filmer (voir « Tournage par rejeu »).
Claude monte, l'utilisateur publie.

**Expliquer sans texte :** c'est l'interface du jeu qui parle (elle est autorisée). Le compteur de vitesse change de
palier (`RUN`, `FAST`, `SURF`, `MACH`, `HUDRules.SPEED_TIERS`) et l'affichage des touches montre A et D enfoncées
pendant le surf et l'air strafe. Les deux doivent donc rester visibles dans les plans de mouvement.

### Découpage (30 s)

Le meilleur moment ouvre la vidéo ; chaque plan dure 2 à 5 s, coupé sur l'action (un saut, un tir).

| Temps | Plan | Ce qu'on doit comprendre |
|---|---|---|
| 0–3 s | P01 tir en vol | Accroche : on tue en plein saut, au sniper, au-dessus du vide |
| 3–8 s | P02 surf | On glisse sur une rampe et on prend de la vitesse (le compteur passe à `SURF`) |
| 8–11 s | P03 surfeur vu de loin | Ce qu'est le surf vu de l'extérieur (une prise de surf rejouée vue de côté) |
| 11–15 s | P04 bhop | Les sauts enchaînés font gagner de la vitesse (le compteur monte) |
| 15–18 s | P05 air strafe | On tourne en l'air sans perdre de vitesse |
| 18–21 s | P06 duel à la lunette | Combat : visée, tir, l'adversaire tombe (fil des éliminations) |
| 21–23 s | P07 couteau | Le couteau au corps à corps |
| 23–27 s | P08 + P09 inspections | Les skins : AWP CISELURE, puis M9 CUIR DE CORDOUE |
| 27–30 s | P10 sortie | Grand saut vers le soleil couchant au-dessus de la mer de nuages |

### Tournage par rejeu (pas d'OBS)

Le jeu sait déjà rejouer à partir de données : parcours de mesure (`PerfRecorder`/`PerfReplay`, entrées de chaque tick,
même trajectoire au rejeu, cf. `docs/performance.md` « Parcours rejoué »), démos de l'écran Apprendre (`DemoClipRules`,
caméra, touches, vitesse) et clip de fin de partie (#499 : pistes de tous les personnages, tirs, armes, ragdolls,
`HighlightPlayer`). La vidéo réunit ces briques :

1. **L'utilisateur joue**, client publié, sans rien filmer. Un enregistreur léger (`VideoRecorder`, mêmes droits que
   l'overlay F3 : créateur du jeu) garde en mémoire les 20 dernières secondes, sans rien envoyer ni écrire. Après une
   belle action, une touche (**F8**, libre) écrit ce tampon dans la sortie (lignes `[VideoTake …]`, copiées dans le
   journal de Roblox), avec un numéro de prise annoncé à l'écran. Contenu par tick : entrées du joueur (format des
   parcours : touches, angles, tirs, arme, points de contrôle) ; à 30 Hz : position et cap des autres personnages
   (joueurs et bots), arme en main ; événements : tirs (direction), touches, éliminations (tueur, arme, tête, victime),
   inspections.
2. **Transfert :** l'utilisateur dépose `%LOCALAPPDATA%\Roblox\logs\*_Player_*_last.log` dans `worktrees/.rushes/525/`,
   avec une ligne par prise retenue (numéro et plan visé, ex. `12 = P01`).
3. **Extraction :** un outil (`tools/promo/write_take.luau`, sur le modèle de `tools/perf/write_route.luau`) sort chaque
   prise du journal dans un fichier de données (non versionné, `worktrees/.rushes/525/takes/`).
4. **Rejeu dans Studio** (`VideoReplay`, Studio uniquement) : le joueur rejoue ses entrées par la vraie physique et la
   vraie caméra (`MovementController.setTickHook`, `InputModule.setVirtual`, `FPSCamera.setScripted`, recalage aux
   points de contrôle comme `PerfReplay`), donc viewmodel, skin, compteur de vitesse, affichage des touches et sons sont
   ceux du jeu. Les autres personnages sont des figurants qui suivent leur piste (mécanisme de `HighlightPlayer`), tirs
   en 3D, ragdolls à leur mort ; le fil des éliminations et les marqueurs de touche sont rejoués depuis les événements
   (le serveur de Studio ne connaît pas ces kills ; même besoin que #534 pour le clip).
5. **Angles de caméra :** la prise se rejoue en vue du joueur (cas par défaut) ou depuis une caméra posée
   (`tools/promo/stage.luau` sait déjà poser une caméra) : le plan P03 « surfeur vu de loin » ne demande plus de caméra
   libre ni de 2e compte.
6. **Capture :** l'image vient de Studio sur le poste de Claude, sans personne aux commandes. À mesurer au premier
   essai : capture en temps réel de la fenêtre (`ffmpeg -f gdigrab`), puis, si elle saccade, rendu image par image
   (horloge du rejeu avancée de 1/60 s, une capture par image, assemblage `ffmpeg`). Le son du jeu s'enregistre à
   part, en temps réel (sortie audio du poste, `ffmpeg -f dshow` ou WASAPI), puis se cale sur l'image au montage.

**Limites connues :** le rendu de Studio diffère du client publié (qualité graphique à régler au maximum, fenêtre de
rendu à caler sur 1920×1080) : comparer à une capture d'écran du client publié avant de monter. Un contact avec un
figurant ne pousse pas le joueur comme le vrai personnage ; le recalage aux points de contrôle corrige l'écart.

### Moments à jouer

**Réglages :** affichage des touches en « simple », champ de vision et viseur par défaut. AWP **CISELURE** et M9
**CUIR DE CORDOUE** équipés. Compte propriétaire du jeu (admin d'office, `Roles`, possède tout le catalogue). Partie
normale sur Dizzy, contre des bots ou d'autres joueurs. Graphismes et plein écran sans importance : l'image est refaite
dans Studio.

Jouer normalement et appuyer sur **F8** juste après chaque moment réussi (le tampon couvre les 20 s précédentes) ; noter
le numéro de prise affiché et le plan visé. Plusieurs prises par plan, le tri se fait au montage.

| Plan | À jouer | Ce qui doit se passer | Prises |
|---|---|---|---|
| P01 tir en vol | Sauter d'une rampe ou d'un toit au-dessus du vide, ouvrir la lunette et tuer un adversaire en l'air ou sur une rampe | Élimination en plein saut, soleil ou ciel dans le champ | 5+ si possible |
| P02 surf | Arriver sur une rampe, la descendre jusqu'au bout et décoller, idéalement face au soleil | Compteur de vitesse qui passe à `SURF` ou `MACH`, A ou D tenue | 3 |
| P03 surfeur vu de loin | Rien de plus à jouer : une prise de surf (P02) est rejouée vue de côté | — | — |
| P04 bhop | Sur un sol plat et dégagé, enchaîner 8 à 10 sauts sans s'arrêter en faisant de l'air strafe | Compteur qui monte de `RUN` à `FAST` ou au-delà, A et D en alternance | 3 |
| P05 air strafe | Saut long (sortie de rampe ou d'un toit à l'autre) avec un virage net en l'air | Virage en l'air, vitesse conservée | 3 |
| P06 duel à la lunette | Visée à la lunette d'un adversaire qui bouge, tir, élimination | Lunette, tir, élimination | 3 |
| P07 couteau | Rattraper un adversaire et l'éliminer au M9 CUIR DE CORDOUE | Le coup de lame qui tue | 2 |
| P08 inspection AWP | Au calme, face au soleil, touche F avec l'AWP CISELURE | Inspection complète | 2 |
| P09 inspection M9 | Idem avec la M9 CUIR DE CORDOUE | Idem | 2 |
| P10 sortie | Du point le plus haut de la map, grand saut vers le soleil couchant, regard vers la mer de nuages | Ciel, soleil, nuages ; personne d'autre | 2 |

### Montage et export

- Musique : un titre instrumental du catalogue audio de Roblox (Creator Store > Audio > Music), 2 ou 3 candidats proposés
  au moment du montage. Sons du jeu gardés par-dessus (tirs, sauts).
- Coupes sur l'action, pas de transition, pas d'effet ajouté. Recadrage léger permis (≤ 5 %) pour sortir les boutons de
  Roblox des bords ; luminosité et contraste seulement.
- Export : MP4 H.264, 1920×1080, 60 i/s, AAC, **30 s au plus**. Fichier final versionné : `assets/promo/video/`
  (MP4 suivi par Git LFS).
- Envoi : Creator Hub > le jeu > Configure > Places > la place de départ > **Videos** (menu de gauche). Une vidéo
  refusée consomme un des 3 envois du mois.

## Mise en ligne et personnalisation (test A/B)

Roblox ne fait pas d'A/B fixe mais une **personnalisation des miniatures** (bandit manchot) : chaque miniature active
est d'abord montrée au hasard, puis la plus performante pour chaque groupe d'utilisateurs reçoit le gros du trafic, les
autres en gardent une petite part ([annonce](https://devforum.roblox.com/t/live-now-personalize-your-thumbnails-to-attract-more-users/3257233)).
Elle ne concerne que l'**accueil** ; la page du jeu garde l'ordre fixé à la main.

- **Condition :** au moins 2 miniatures actives (5 au plus). Pas de seuil officiel de trafic, mais sous ~1 000
  joueurs actifs par jour les résultats sont peu significatifs (annonce de lancement).
- **Mesure :** le tableau « Thumbnail Performance » donne impressions, parties qualifiées, temps de jeu moyen et
  **qPTR** (parties qualifiées / impressions), par miniature et par groupe (ex. 18+ et moins de 18 ans). Les
  statistiques arrivent après quelques heures, le trafic est réparti chaque heure ; attendre quelques jours avant de
  conclure. Ajouter une miniature ne remet plus les compteurs à zéro (juillet 2025).
- **Icône :** pas de test natif de l'icône.

### Procédure Creator Hub

Libellés d'après la documentation et les annonces citées plus haut (pas vérifiés dans l'interface, faute d'accès) :

1. Creator Hub > Creations > le jeu > **Configure > Places** > la place de départ > **Thumbnails**. Deux onglets :
   « Experience/Game Detail Page » (page du jeu) et « Home Page » (accueil, personnalisation).
2. **Page du jeu** : envoyer les miniatures de `assets/promo/thumbnails/` dans l'ordre de leur numéro (la 1re est
   aussi celle que montre la recherche), réordonner par glisser si besoin, renseigner le texte alternatif (une phrase
   qui décrit l'image). Chaque image passe en modération avant d'apparaître.
3. **Accueil** : « Edit active thumbnails », envoyer les mêmes images (moins de 3 Mo chacune : les PNG du dépôt font
   ~2 Mo), cocher **Active** sur chacune (2 à 5), **Save**, puis **Start**. Un bandeau confirme que la
   personnalisation tourne.
4. Après quelques jours : tableau « Thumbnail Performance » (impressions, parties qualifiées, **qPTR**). Ajouter une
   nouvelle miniature active ne remet pas les compteurs à zéro : les suivantes s'ajoutent au fil de l'eau. Sous ~1 000
   joueurs par jour, ne pas conclure.

### Travailler avec ChatGPT (retour de l'utilisateur, 17/11/2026)

- Après la première image d'une conversation, ChatGPT refait la même en boucle : **une conversation par miniature**.
- Chaque conversation a une limite de pièces jointes : regrouper le kit en planches (moins de 10 images), ou, piste
  proposée par l'utilisateur pour la suite, déposer le kit sur un Drive et donner le lien.

## Miniatures publiées

Faites par ChatGPT à partir du kit (`assets/promo/kit/`), exportées en 1920×1080 par `tools/promo/finish.py export`
(sources 1672×941, déjà en 16:9). Lisibles à 320×180 et 160×90 (`finish.py small`).

| Ordre | Fichier | Idée | Écarts avec le jeu, gardés |
|---|---|---|---|
| 1 | `assets/promo/thumbnails/1-tir-en-vol-awp-ciselure.png` | Vue subjective, AWP CISELURE : un adversaire touché en plein saut au-dessus des nuages, au couchant, grue de Dizzy | Étoile d'impact sur l'adversaire (pas d'effet d'impact en jeu) ; adversaire sans arme (il en tient toujours une) ; rayon du tir plus épais et doré ; nuages en volume (nappes translucides en jeu) |
| 2 | `assets/promo/thumbnails/2-m9-cuir-de-cordoue.png` | Inspection de la M9 CUIR DE CORDOUE, lame vers le soleil, toits de Dizzy et grue | Nuages en volume ; motifs de la lame redessinés (paon, fleurs, garde et manche fidèles) |

Reste à faire (#524) : trois miniatures (vitesse du bunny hop, AWP CISELURE en inspection, autre idée de ChatGPT).
