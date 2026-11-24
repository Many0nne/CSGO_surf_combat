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
5. **Lumière :** ciel bleu de plein jour (choix de l'utilisateur, 24/11/2026, comme les jeux de référence), soleil
   **derrière la caméra** : face à elle, le skin passe en contre-jour et ne se lit plus (refusé). Pas de néon.
6. **Aucun texte** (choix de l'utilisateur, #524) : l'image doit se comprendre seule.
7. **Fidèle au jeu :** le personnage est celui du jeu (`StarterCharacter`, tous les joueurs ont le même), avec ses
   proportions en blocs ; armes et skins à l'identique. Effets permis car présents en jeu : flamme de bouche, rayon de
   la balle (ruban jaune pâle `TRACER_RGB`), lunette. **Pas d'éclats d'impact ni de surbrillance des ennemis** : ils
   n'existent pas en jeu. Un décor inventé est accepté par l'utilisateur s'il ressemble à Dizzy.
8. **Les cinq se distinguent :** idées différentes, pour que la personnalisation de Roblox puisse trouver la meilleure
   par public.

## Fabrication

**Retenu (24/11/2026) : rendu Blender (Cycles) des vrais modèles et des vrais skins.** Rien n'est redessiné : le skin
rendu est celui du jeu (les images de ChatGPT déformaient les skins, voir « Pistes écartées »). Les plans des cinq
miniatures sont versionnés dans `tools/promo/shots/` ; Blender sans interface, aucun besoin de Studio.

1. **Modèles** (dans `.promo/`, non versionné ; clé `ROBLOX_OPEN_CLOUD_KEY`) :
   ```bash
   uv run tools/preview/fetch_viewmodel.py AWP .promo/AWP.glb --arms          # viewmodel avec ses bras
   uv run tools/preview/fetch_viewmodel.py M9Bayonet .promo/M9Bayonet.glb --arms
   uv run tools/promo/fetch_character.py .promo/saut.glb tools/promo/pose-saut.json   # adversaire en plein saut
   ```
   `fetch_character.py` reconstruit le `StarterCharacter` (absent de Rojo : pièces, couleurs et articulations relevées
   dans `tools/promo/character.json`, lues dans Studio le 24/11/2026), posé articulation par articulation comme un
   Motor6D ; la tête classique et son visage sont recréés.
2. **Rendu** (~50 s par image en 1920×1080, 64 échantillons, sur ce poste sans GPU NVIDIA) :
   ```bash
   blender -b --factory-startup --python tools/promo/render_thumb.py -- tools/promo/shots/<n>.json <sortie.png> --samples 64
   ```
   Pour chercher un cadrage, `--engine workbench --res 960x540` rend en quelques secondes (lumière fausse). Options du
   plan : docstring de `render_thumb.py`.
3. **Export** : `uv run tools/promo/finish.py export <rendu> assets/promo/thumbnails/<n>.png`, puis
   `finish.py small` (planche 320×180 et 160×90).

Pièges rencontrés :

- **Contre-jour :** soleil face à la caméra = skin illisible (refusé). Azimut du soleil vers l'arrière de la caméra.
- **Métal qui reflète le ciel :** même bien éclairé, un skin métallique devient bleu et sombre sur fond de ciel. Le plan
  fait émettre au skin sa propre couleur (`skin_glow` 0,6) et coupe les ombres du soleil (`shadows: false`) : validé.
- **Ciel pâle :** `sun_disc` du ciel Nishita brûle l'éclairage (bras blancs) ; le soleil est une lampe à part, le fond
  un dégradé vu seulement par la caméra, en vue « Standard » (AgX délave le bleu).
- **Couleurs Roblox en sRGB :** les écrire en linéaire dans le glTF (`srgb_to_linear`), sinon tout est délavé.
- **Bras blancs dans le jeu :** rendus gris clair (`plain_color` 0,26), sinon brûlés au soleil.
- **Couteau vu par la tranche ou main qui flotte :** `align` pose l'arme comme l'inspection du jeu (axe long en
  diagonale, flanc vers la caméra, main ancrée à l'écran).

### Ancienne méthode : kit de références pour ChatGPT (17/11/2026, abandonnée)

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
| ChatGPT fait les miniatures en entier à partir du kit (2 images publiées, 17/11) | Skin déformé, rendu en dessous des autres jeux (24/11). Remplacé par le rendu Blender |
| Rendu Blender avec le soleil face à la caméra (halo dans le ciel) | Contre-jour : on ne voit pas bien le skin |

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

Rendues dans Blender (`tools/promo/shots/<fichier>.json`), validées par l'utilisateur le 24/11/2026. Lisibles à
320×180 et 160×90 (`finish.py small`). Les quatre skins légendaires plus un plan d'action.

| Ordre | Fichier | Idée | Écarts avec le jeu, gardés |
|---|---|---|---|
| 1 | `assets/promo/thumbnails/1-tir-en-vol-awp-ciselure.png` | Vue subjective, AWP CISELURE (caméra du viewmodel) : tir sur un adversaire armé en plein saut, contre-plongée | Ciel de jour (crépuscule en jeu) ; flamme de bouche en volume (particules en jeu) ; bras gris clair (blancs en jeu) ; tête du personnage recréée |
| 2 | `assets/promo/thumbnails/2-awp-ciselure.png` | Inspection de l'AWP CISELURE vers le ciel | Ciel de jour sans décor ; skin légèrement lumineux (`skin_glow`) |
| 3 | `assets/promo/thumbnails/3-m9-cuir-de-cordoue.png` | Inspection de la M9 CUIR DE CORDOUE, pointe vers le ciel | Idem |
| 4 | `assets/promo/thumbnails/4-awp-trempe.png` | Inspection de l'AWP TREMPE | Idem |
| 5 | `assets/promo/thumbnails/5-m9-couchant.png` | Inspection de la M9 COUCHANT | Idem |

## Enregistreur de partie (#582)

Les outils de capture (OBS) font laguer le jeu quand on joue et qu'on filme en même temps. On joue donc sans filmer
dans le jeu publié, la partie est notée en données, puis reconstruite dans Studio et filmée au ralenti.

**Ce qui est noté.** Le serveur (`src/server/MatchRecorder.luau`) relève la racine de chaque participant en vie
(joueurs et bots) à 20 Hz, la tenue portée et les actions de l'arme 3P (tir, recharge, sortie : attributs de
`WeaponThirdPerson`) ; il reçoit de `HighlightService` (observateur, même hors manche active) les tirs acceptés, les
armes sorties avec leur skin, les kills et les morts. Pour un rejeu fidèle (#586), il note aussi l'effet de tir équipé
de chaque joueur (relevé comme la tenue), les pas et atterrissages (`FootstepService`), les touches confirmées au
joueur qui enregistre (hitmarker), l'état et le timer de la manche et le classement (`RoundManager`, au début de chaque
morceau et quand ils changent). Le client qui enregistre (`src/client/debug/MatchRecorder.luau`) ajoute sa caméra à
30 Hz (position, hauteur des yeux, lacet, tangage, champ de vision, lunette), ses inspections et ses munitions.
Format et lecture : `src/shared/MatchRecordRules.luau` (testé). Taille mesurée : 65 Ko pour 36 s avec 5 participants
(~550 Ko pour 5 min) avant #586 ; 86 Ko pour 28 s avec 8 participants depuis (pas : 247 évènements, l'essentiel de la
hausse). Un enregistrement fait avant #586 se rejoue encore, sans effet de tir, pas, HUD de manche ni touches.

**Transport.** Un morceau toutes les 5 s, envoyé au client qui enregistre (remote `MatchRecord`, JSON), recopié dans la
console en lignes `[MatchRec <enregistrement> <morceau> i/n]` : il finit dans le journal Roblox du poste qui joue.
Rien n'est stocké côté Roblox (pas de DataStore) : la clé Open Cloud du dépôt n'a que les droits d'assets, et l'accès
de Studio aux API ferait écrire les playtests dans les vraies données.

**Enregistrer** (compte créateur dans le jeu publié, ou Studio) :

1. En partie, **F8** : bandeau rouge « ● REC 0:00 · F8 POUR ARRÊTER » en haut de l'écran. Jouer (20 min au plus).
2. **F8** pour arrêter : « ENREGISTREMENT <numéro> · durée · n MORCEAUX ».
3. Récupérer le journal : `%LOCALAPPDATA%\Roblox\logs\*_Player_*_last.log` sur le poste qui a joué (le plus récent),
   ou tout le dossier. Dans Studio, F8 est un raccourci de l'éditeur : attribut joueur `MatchRecord` = true / false
   (contexte Server) ; le journal est alors `*_Studio_*_last.log`.

**Extraire** : `lune run tools/matchrec/extract.luau <journal ou dossier> <Nom>` écrit `recordings/<Nom>/` (un `.txt`
par morceau, non versionné), liste les enregistrements trouvés (le plus récent par défaut, ou donner son numéro en 3e
argument), les participants, les kills et les morceaux manquants. Rojo le synchronise dans
`ServerStorage.MatchRecordings.<Nom>` (retiré au démarrage hors de Studio).

**Rejouer** (Studio, playtest lancé, joueur resté au menu : pas de manche, pas de bots ; attributs du joueur en
contexte Server) :

```lua
local p = game.Players:GetPlayers()[1]
p:SetAttribute("MatchReplayCamera", "side")   -- pov (défaut), follow, side, front, orbit, track, fixed
p:SetAttribute("MatchReplayTarget", -5)       -- id du participant suivi (défaut : le joueur qui enregistrait)
p:SetAttribute("MatchReplayFrom", 6)          -- début et fin (s depuis le début de l'enregistrement)
p:SetAttribute("MatchReplayTo", 12)
p:SetAttribute("MatchReplaySpeed", 0.25)      -- vitesse du rejeu
p:SetAttribute("MatchReplay", "Essai")        -- charge et lance ; nil arrête
p:SetAttribute("MatchReplayRun", os.clock())  -- relance avec les réglages courants
```

Réglages des plans hors POV : `MatchReplayDistance` (10), `MatchReplayHeight` (3), `MatchReplayFov` (70),
`MatchReplayCameraPosition` (Vector3, plan `track`), `MatchReplayCameraCFrame` (plan `fixed`), `MatchReplayHud` (false :
sans interface de jeu). Les ids des participants sont listés par l'extraction (bots négatifs, joueurs = UserId). La
scène 3D du menu, la musique, la souris, l'interface du jeu et celle de Roblox sont coupées pendant le rejeu, puis
rendues.

**Ce que le rejeu reproduit (#586).** Figurants habillés et armés (skin), effet de tir équipé de chaque tireur
(ÉCLAIR, PAN !, CIRCUIT…), flamme, douilles, sons des tirs et des pas, ragdolls, kill feed. En vue du joueur, le HUD
est celui de la partie, piloté par les données : viseur, hitmarker et son de touche, munitions, compteur de vitesse,
barre d'armes, timer, rang, série de kills (crâne), annonceur (« Headshot », « Double kill »…) ; rien de ce HUD pendant
la mort, comme en partie. Pas de musique (choix de l'utilisateur : elle se pose au montage). Au ralenti, effets de tir,
douilles, hitmarker et interpolations du HUD suivent le temps du rejeu (`src/client/systems/game/EffectClock.luau`,
lu par les modules d'effets à la place d'`os.clock`) : la vidéo remise à vitesse normale, chaque effet dure ce qu'il
dure en partie. Non reproduits : écran de mort (caméra vers le tueur, compte à rebours), bannière de fin de manche et
clip de la partie.

**Filmer** : deux passes du même segment (`MatchReplayFrom` / `MatchReplayTo` inchangés), l'outil lancé avant
`MatchReplayRun`, Studio au premier plan.

1. Son : `MatchReplaySpeed` = 1, `MatchReplayAudio` = true, puis `uv run tools/matchrec/capture.py <son.wav>`. L'outil
   enregistre la sortie audio du poste (boucle WASAPI, paquet `soundcard`) ; le rejeu joue un bip 0,5 s avant sa
   lecture, pendant l'écran noir, et le son est coupé à partir de là. Rien d'autre ne doit jouer sur le poste.
2. Image : `MatchReplaySpeed` = 0.25, `MatchReplayAudio` = false, puis
   `uv run tools/matchrec/capture.py <sortie.mp4> --speed 0.25 --cut-top 80 --audio <son.wav>`.

Calage mesuré sur `Test586` (segment de 1,5 à 6 s, un tir AWP ÉCLAIR à 3,82 s, soit 2,32 s dans la vidéo) : son du
tir à 2,310 s, flamme à l'image 139 (2,317 s), soit moins d'une image d'écart à 60 i/s. Pièges : la musique du menu joue
avant l'écran noir (le bip n'est cherché qu'autour de 0,5 s avant la lecture).

**Son haché (#601).** Les rushes du 20/11 avaient des claquements (« micro qui sature qu'on tapote ») : 27 trous de 20
à 40 ms dans le son du rush A. Trois causes, toutes dans la passe du son :
- `soundcard` dimensionne le tampon WASAPI sur `blocksize` : à 480 échantillons, il ne tenait que 10 ms, et le fil
  de lecture, qui partageait le GIL avec la capture d'écran, prenait du retard. Le son perdu n'était signalé que par
  un avertissement « data discontinuity », alors masqué.
- `soundcard` invente des zéros d'après l'horloge quand rien n'arrive pendant 40 ms, même si le son, simplement en
  retard, arrive ensuite (trous, son allongé).
- La boucle WASAPI ne livre rien quand rien ne joue : l'ancien outil recollait les blocs sur l'heure d'arrivée.

Depuis : enregistrement dans un processus à part, tampon de 0,5 s, silence joué sur la sortie pendant l'enregistrement
(flux continu, rien à recoller), lecture seulement quand des données attendent. L'outil affiche les discontinuités et
l'écart entre la durée enregistrée et l'horloge ; s'il en signale, refaire la passe. Banc (son pur de 6 s joué pendant
la capture d'écran, `worktrees/.briefs/son-capture/bench.py`, non versionné), 3 essais : ancienne méthode 3 à 6
discontinuités et 1 à 2 trous, nouvelle 0 et 0, écart avec l'horloge de -4 à -8 ms. Le PC doit rester libre pendant
la passe : rien d'autre ne doit jouer de son (tout ce qui sort des haut-parleurs est enregistré) et Studio doit rester
au premier plan.

**Non résolu (23/11, #601) :** le rush A refait sans aucune coupure garde, à l'oreille de l'utilisateur, le même défaut.
Ce qu'il entend vient donc d'ailleurs, cause non trouvée. Pistes : le son d'atterrissage (`FootstepRules`, joué à
chaque saut du bhop, aux instants exacts des atterrissages notés) ou le rendu du son par Studio. Sujet mis de côté :
l'utilisateur fournira des parties filmées directement.

Passe de l'image : Le rejeu s'ouvre et se ferme sur un écran noir : l'outil y trouve le cadre du viewport, le début et la
fin, place chaque capture à l'instant du rejeu qu'elle montre et écrit une vidéo à 60 i/s à vitesse normale.
Mesuré sur `Essai` (plan de côté, 6 s de rejeu au quart de la vitesse, fenêtre Studio 1920x1080, viewport
1614x758) : 19 captures par seconde réelle, soit 77 par seconde de rejeu, vidéo de 359 images à 60 i/s sans aucune image
en double tant que la scène bouge. Les boutons Roblox du coin haut gauche (logo, menu, micro) restent affichés en
playtest et aucune API ne les cache (`SetCoreGuiEnabled`, `TopbarEnabled` essayés) : `--cut-top 80` retire le haut du
viewport, et un recadrage vertical (TikTok) centré les exclut de lui-même.

**Plans retenus.** Les rushes se filment en vue du joueur (`pov`). Les plans en 3e personne (`follow`, `side`,
`front`, `orbit`) ont été jugés « plutôt mauvais » par l'utilisateur (19/11/2026, rush de côté sur un bot) : gardés
dans le code, mais ni proposés ni améliorés sans demande.

**Limites.**

- Au ralenti, positions, caméra, pistes d'animation (personnages et viewmodel), actions 3P, kill feed et chute des
  corps (gravité × vitesse², élan × vitesse) suivent le temps du rejeu. Les rayons des tirs et les sons restent en temps
  réel : rayons 4 fois plus brefs une fois la vidéo remise à vitesse normale, sons inutilisables (la capture n'a pas de
  son ; l'utilisateur pose une musique sur TikTok).
- Rayon ordinaire pour tous les tirs (comme le clip de fin de manche, #568) ; pas de HUD (vie, munitions) en vue du joueur,
  seulement le kill feed et la lunette.
- Les autres participants sont relevés à 20 Hz sur le serveur : écart d'interpolation mesuré sur `Essai` (bots en
  mouvement, relevés retirés un sur deux, donc au pas de 0,1 s) : 0,47 stud en moyenne, 1,5 au p95. Le joueur qui
  enregistre est rejoué sur sa caméra à 30 Hz. Kills et morts : instants du serveur, au millième.
- La cible `DebugDummy` du helper de playtest n'est pas un participant : absente du rejeu.
