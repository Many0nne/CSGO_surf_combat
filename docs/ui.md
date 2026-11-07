# Direction artistique de l'interface

Référence pour refaire les écrans restants (réapparition, fin de round) dans la direction du menu, déjà appliquée à l'accueil, Infos, Réglages, Feedback et au HUD de partie (vitesse, barre d'armes, timer, classement).

## La direction : « Ligne de mire »

**Principe : l'interface est faite de la matière du jeu.** Le déclic est venu d'un exemple de jeu de samouraï, dont la roue
d'armes est faite d'encre, de sang et de vrais sabres. Ici, la matière est le canyon de rampes, l'AWP et le tir.

Ce que l'utilisateur a validé dans le menu principal :

- une vraie scène 3D dans le moteur, avec les assets du jeu, plutôt que des formes dessinées ;
- on choisit en tirant : le curseur est un hitmarker, l'arme le suit, le tir a le vrai son et la vraie animation, l'impact reste ;
- la vitesse passe par le mouvement réel (surfeurs et traînées), pas par des effets graphiques posés sur une image ;
- un titrage en images usées : lettres penchées arrachées par le vent, éclats, impacts de balles.

Palette du menu : ciel bleu nuit, soleil blanc chaud, lignes ambrées, rampes brun chaud, silhouettes noires, texte os
(`243, 233, 220`), rouge d'impact (`C.HitRed`) pour ce qui est visé ou touché.

Le canyon au couchant est abandonné (il collait à l'ancienne map) : le menu passe à la **salle des miroirs** (section
dédiée plus bas, implémentation #112), avec la palette du HUD.

## Ce qui a été rejeté, et pourquoi

Essais successifs (maquettes HTML sur la page privée « Surf FFA, direction Vitesse ») :

| Essai | Retour de l'utilisateur |
|---|---|
| Aplats outremer, jaune et rouge, grande diagonale | Trop vif, ne fait pas « vitesse », compteur de vitesse trop gros |
| Traînées et ombre sur le texte | Effet de vitesse bas de gamme, typo simpliste |
| Bandes qui s'étirent | Simple semblant de vitesse |
| Murs en perspective CSS | Ressemble à une transition PowerPoint |
| Carte de parcours | Correct, mais sans lien avec le jeu |
| Personnage 3e personne avec sniper | Écarté par Claude avant présentation : rig en blocs et arme minuscule, rendu ridicule |

**Conclusions :**

- Ne pas valider une DA sur des maquettes HTML plates : prototyper dans le moteur dès que l'idée repose sur de la 3D.
- Montrer et faire essayer plutôt que décrire : l'utilisateur n'a pas d'idée précise a priori, il réagit à ce qu'il voit.
- Pousser les idées loin, puis vérifier la lisibilité : le premier titrage était trop abîmé (« SURF » se lisait « URF »).
- Compteur de vitesse et autres éléments de HUD : discrets, ils ne doivent pas prendre une grosse partie de l'écran.
- Pour une scène : composer d'abord une image (plans, échelle, silhouette) dans une planche de rendus Blender, la faire
  choisir, puis seulement la construire dans Roblox. Voir « Menu : salle des miroirs ».

## Comment c'est construit

- `src/client/ui/MainMenu.luau` : titre et choix de l'accueil, tir dans la scène au clic.
- `src/client/ui/MenuPage.luau` : gabarit des écrans secondaires : pas de panneau, dégradé sombre à gauche, titre en image, action de sortie en bas à gauche.
- `src/client/ui/MenuShot.luau` : tir sur un élément, impact, puis action ; choix en images usées communs à tous les écrans.
- `src/client/ui/MenuCursor.luau` : hitmarker-curseur.
- `src/client/systems/game/MenuScene.luau` : scène 3D, éclairage temporaire, visée, tir, surfeurs, plongée sur JOUER.
- `src/client/systems/game/MenuSceneRules.luau` : règles pures testées (`tests/specs/MenuSceneRules.spec.luau`).
- `src/client/ui/Transition.luau` : volets couleur du soleil, enchaînés à la plongée vers le soleil.
- `src/client/ui/Speedometer.luau` : compteur de vitesse, piste « Titrage » : gros chiffres os penchés (-6°) avec ombre noire décalée, nom du palier, bande ambrée en biais crantée aux seuils, tout passe au rouge d'impact au dernier palier (`HUDRules.speedTier`, `speedFill`). En bas à gauche, sur un fond sombre sans bord : image de dégradé de coin (`tools/ui/make_corner_scrim.py`, `assets/ui/hud/`) teintée par `ImageColor3`.
- `src/client/ui/WeaponBar.luau` : barre d'armes en bas à droite, en miroir du compteur ; remplace le Backpack Roblox
  (`CoreGuiType.Backpack` désactivé dans `init.client.luau`). Par arme : silhouette plate tirée des MeshParts de son viewmodel
  (bras exclus) dans un `ViewportFrame` blanc teinté par `ImageColor3`, nom et touche. L'arme en main est en os, avec son
  numéro et un trait en rouge d'impact, les autres sont grisées ; toute la barre (fond compris) disparaît 2,5 s après le dernier changement d'arme
  (`HUDRules.WEAPON_BAR_FADE_DELAY`). Emplacements dans l'ordre alphabétique, comme le helper `DebugPlaytest`.
  Équipement : 1 à 9, molette (vers le haut = arme précédente), toucher d'un emplacement, L1/R1 à la manette.
  Touches réglables : #100.
- `src/client/ui/RoundHUD.luau` : timer et rang en haut au centre (chiffres os droits avec ombre, libellés ambrés, fondu
  sombre en deux moitiés de coin, timer en rouge d'impact sous 30 s) ; classement sous Tab : pas de panneau, voile sombre
  central qui s'efface vers les côtés, titre « CLASSEMENT » sur un filet ambre, colonnes K / M / K/M, ligne du joueur
  sur une bande rouge d'impact **droite** (penchée, elle se lisait mal en face des colonnes).
- `UIKit.cornerScrim` : fond de coin du HUD (`assets/ui/hud/scrim_coin.png`) dans les quatre orientations, par rotation.
  Seul le compteur de vitesse est penché (`UITheme.Layout.HudLean`, -6°) : l'utilisateur a préféré le timer, la barre
  d'armes et le classement droits.
- `tools/ui/make_menu_type.py` : génère le titrage dans `assets/ui/menu/` (police Anton, licence OFL).

Pour un nouveau mot : l'ajouter à la fin de `make_menu_type.py`, générer, publier, puis récupérer l'id de l'image :

```bash
uv run tools/ui/make_menu_type.py <Anton-Regular.ttf> assets/ui/menu
bash tools/publish_asset.sh assets/ui/menu/<mot>.png Decal "SurfFFA_Menu_<mot>"
```

Puis, en playtest, contexte `Server` (`execute_luau`), lire l'id de l'image à mettre dans le code :

```lua
local model = game:GetService("InsertService"):LoadAsset(<id du Decal>)
return model:FindFirstChildWhichIsA("Decal", true).Texture
```

## Règles des écrans secondaires

- Tout se tire sauf la saisie de texte. Un curseur de réglage se place d'un tir, puis se glisse sans retirer : sa poignée est un impact, sans trou ajouté à l'écran.
- Réglages en partie (touche P) : même écran sur un voile sombre, avec le curseur système et sans son de tir, pour ne pas le confondre avec un vrai tir.
- Les impacts sont propres à chaque écran et limités à 14 : le plus ancien disparaît.

## Pièges connus

- **HUD de jeu visible seulement en partie (#105) :** un `ScreenGui` créé avec `ResetOnSpawn = false` reste affiché après la fin du
  round. Source unique : `HUDRules.gameHudVisible(état)`, appliquée par `applyGameHud` dans
  `GameStateController` (compteur de vitesse, barre d'armes, lunette). `RoundHUD` (appelé par `setState`) se masque déjà seul.
  Piège : `endRound()` détruit le personnage côté serveur sans que `CharacterRemoving` se déclenche (`Player.Character` reste
  référencé) : un élément qui ne suit que la vie du personnage reste affiché au menu (cas de `WeaponBar`). Tout nouvel élément du HUD de jeu doit brancher sur cette règle, pas sur un état à lui.
  `Speedometer.init()` tourne au premier spawn, après le premier `setVisible` : le module mémorise donc la visibilité.

- **Id d'un Decal publié :** il ne s'affiche pas dans une `ImageLabel` (console : `Asset type does not match requested type`).
  Il faut l'id de l'image contenue dans le Decal (voir ci-dessus).
- **Distance d'affichage :** Roblox la réduit selon la charge, et le décor lointain disparaît d'un coup avec la map chargée.
  Le canyon est donc au tiers de sa taille apparente (1 000 studs de long). Un test sans la map ne le montre pas.
- **Éclairage :** `MenuScene` remplace celui de `Lighting` et le rétablit à sa sortie. Un tween encore actif écrase les valeurs
  rétablies : l'annuler d'abord (`diveTweens`), car le joueur peut apparaître avant la fin de la plongée.
- **Curseur :** `MenuCursor` remet `MouseIconEnabled = false` à chaque image, car les autres écrans le réactivent en se fermant.
- **`AbsolutePosition` avec `IgnoreGuiInset` :** elle exclut la barre du haut, contrairement à `GetMouseLocation`. Préférer
  `MouseEnter`, `MouseLeave` et `Activated` à un test de zone maison.
- **Fondu dans deux directions** (fond qui s'efface vers le haut et vers la droite) : impossible avec des `UIGradient`.
  Un `UIGradient` sur un `CanvasGroup` est ignoré ; un seul gradient en biais laisse une arête ; des calques très transparents
  empilés font des bandes visibles. Utiliser une image de dégradé blanche teintée par `ImageColor3` (voir `make_corner_scrim.py`).
- **Retourner une image :** un `ImageRectSize` négatif ne retourne pas l'image dans une `ImageLabel`. Tourner l'image
  (`UIKit.cornerScrim` : 90°, 180° ou -90° selon le coin, taille permutée pour les quarts de tour).
- **Tools des armes :** ils sont presque vides (l'arme visible vient du viewmodel). Pour dessiner une arme hors du jeu
  (icône, silhouette), cloner les MeshParts enfants directs de `ReplicatedStorage/ViewModels/<Nom>`, sans les bras.
- **`CanvasGroup` et fondu :** sa `GroupTransparency` est ignorée quand Roblox retombe sur le rendu simple (qualité
  graphique, mémoire) : le groupe reste affiché. Pour estomper un élément qui doit vraiment disparaître (barre d'armes),
  animer la transparence de chaque enfant.
- **Polices :** aucune annonce officielle d'import de police trouvée (novembre 2026). Les titres passent par des images ;
  le texte courant reste en police Roblox.
- **Bras du viewmodel :** ils forment vite une grosse masse noire quand la souris est dans un coin. Limiter le pivot
  (`MenuSceneRules.aimAngles`) et garder le soleil dégagé.

## Prototyper dans le moteur

Pour vérifier la faisabilité d'une idée, pas pour chercher une composition (voir « Méthode » plus haut). Sans toucher aux fichiers ni à la place : pendant un playtest, `execute_luau` en contexte `Client` peut construire une scène
et une UI entières, et `screen_capture` montre le résultat avec l'UI. Tout disparaît à l'arrêt du playtest. Le code ainsi
lancé ne partage pas ses modules avec le jeu (un `require` donne une autre instance). En mode Edit, `screen_capture` rend
un viewport tout blanc quand la fenêtre Studio est réduite ou en arrière-plan : la mettre au premier plan. Seul Claude ne peut pas connecter le
plugin Rojo : l'utilisateur doit le faire pour tester un worktree.

## Menu : salle des miroirs (#106, implémentation #112)

**Piste retenue :** des éclats de verre suspendus à des fils dans une salle de béton. Chacun porte un morceau de l'image
de l'arme. En pivotant sur leurs fils, ils la reconstituent face à la caméra. Au repos l'arme est entière ; au
changement d'arme, les éclats se dispersent puis se reposent en vague de gauche à droite ; au tir, les éclats touchés
pivotent puis se reposent. Rendus de référence : `docs/ui/menu-miroirs/` (`reconstituee.jpg`, `mi-rotation.jpg`,
`dispersee.jpg`, `reconstitution.mp4`).

Décisions de l'utilisateur :
- le centre du menu est une vitrine d'arme, sans personnage ;
- le menu ne dépend d'aucune map : plus de rampes ni de soleil couchant ;
- l'interface reprend le style du HUD (texte os à ombre décalée, libellés ambrés Oswald, rouge d'impact rare, barres
  segmentées), avec la disposition des maquettes ;
- pas d'affichage de la partie en cours.

**Pistes écartées** (`docs/ui/menu-miroirs/planche-ecartee.jpg` pour les quatre dernières) :

| Piste | Pourquoi |
|---|---|
| Travelling de canyon, rampes flottantes et surfeurs fantômes, mer de brume | Liées à l'ancienne map |
| Lobby avec personnage | Rig en blocs, ridicule |
| Studio noir, réticule géant, stand de tir de nuit | « Pas mal mais pas assez originaux » |
| Vue éclatée avec étiquettes, tir figé (balle et anneaux), vitrine pare-balles | Objets empilés, pas des compositions |
| Planche Blender : établi, macro de la bouche, machine murale, éclaté sur l'axe | Correctes, mais l'utilisateur a préféré l'idée des miroirs |

**Méthode** (après une douzaine de maquettes rejetées) :
- Ne pas traduire les mots d'un concept en pièces primitives construites à la volée dans Studio (anneau = « onde »,
  étiquette = « technique ») : cela donne des objets empilés, sans premier plan ni fond, sans rapports d'échelle.
  L'originalité vient de la forme du décor et du cadrage, pas d'effets ajoutés.
- Partir de références visuelles de l'utilisateur, puis faire une planche de 3 ou 4 rendus Blender au cadrage final
  16:9, avec l'interface posée par-dessus (`tools/menu/overlay_mockup.py`). Rendus reproductibles dans Roblox :
  matériaux PBR simples, lumières ponctuelles, pas de volumétrique.
- Une fois l'image choisie, juger le mouvement sur une courte vidéo avant toute intégration ; l'utilisateur a demandé
  une reconstitution plus lente que le premier essai (arme entière vers 5,5 s).

**Technique** (`tools/menu/mirrors.py`, Blender en arrière-plan) :
- Roblox n'a pas de vrais miroirs (`Reflectance` ne reflète que le ciel) : on rend l'arme seule depuis la caméra du
  menu, on découpe la zone de l'arme en cellules de Voronoï, puis chaque cellule est reprojetée à sa propre profondeur,
  face à la caméra, avec des UV projetés depuis la vue. Alignés, les éclats redonnent l'image exacte.
- Les éclats pivotent autour de leur fil (axe vertical), avec un léger balancement : les fils restent justes. La
  reconstitution est une oscillation amortie (`exp(-1.6 t) cos(2π·0.32 t)`), libérée en vague sur 2,6 s.
- Une découpe par arme ; échanger les jeux d'éclats pendant la dispersion, quand ils sont de profil.
- Garder les cellules d'après une grille de points (part de pixels opaques) : un test sur quelques points perd les
  pièces fines (lunette, canon).
- **Caméra définitive** (1 unité Blender = 1 stud, Roblox = `(x, z, -y)`, relative à l'origine de la scène du menu) :
  position `(0, 3.4, 17)`, visée `(0.6, 4.6, 0)`, `FieldOfView` = **35,12°** (objectif 32 mm, capteur ajusté en hauteur
  dans Blender pour un FOV vertical fixe, comme Roblox). `mirrors.py` écrit la disposition complète (caméra, salle,
  lumières, pivots des éclats) dans `layout.json`, à côté des rendus.
- **Écrans non 16:9** : la reconstitution ne dépend que de la position et de l'orientation de la caméra, pas du FOV.
  Sur un écran plus étroit que 16:9, ouvrir le FOV vertical pour garder la largeur du 16:9
  (`2·atan(tan(29,35°) / ratio)`, 45,75° en 4:3), sinon le canon sort du cadre ; sur un écran plus large, garder
  35,12°. Vérifier avec `--aspect 4:3` ou `--aspect 21:9`.
- **Export pour Roblox** (`mirrors.py --export --weapon AWP|M9`, module `shard_export.py`) : un MeshPart ne porte
  qu'une `SurfaceAppearance`, donc face, dos et tranche d'un éclat partagent une texture. Par arme : `atlas.png`
  (1024 px, morceaux d'image à pleine résolution 1080p composés sur le verre sombre, alpha 0,55 hors de l'arme ; bande
  de nuancier en haut : dos, tranche claire, dégradé irisé), `masque.png` (opacité de l'arme, pour
  `EmissiveMaskContent`), `eclats.fbx` (`Eclat_01`…, sans chanfrein, dont les faces mêleraient image et nuancier) et
  `eclats.json` (centre du MeshPart, point d'attache du fil, retard de la vague, teinte, liseré). Communs aux armes :
  `vides.fbx`, `vides.json`, `verre.png` (la bande seule ; tirage aléatoire séparé de la découpe). Le maillage est figé
  en coordonnées monde : Roblox place chaque MeshPart au centre de sa boîte, sans rotation, et on le replace d'après
  `center`.
- Contrôle : `check_export.py -- <arme>` réimporte les FBX et rend `controle.png` sans éclairage depuis la caméra du
  menu ; l'arme doit se reconstituer. Une forme qui traverse l'image dans ce contrôle vient du tri de transparence de
  Blender (toutes les origines à zéro), pas de l'export.
- `SurfaceAppearance` a bien `EmissiveMaskContent`, `EmissiveStrength` et `EmissiveTint` (Studio 0.746) : l'image peut
  rester lumineuse comme dans les rendus.
- Les assets de la Toolbox (le M9) ne s'ouvrent ni en `EditableMesh`/`EditableImage` (« no permission ») ni par
  l'asset delivery (401, scope `legacy-asset:manage` absent) : les sortir par *Export Selection* dans Studio, dans
  `.maquettes/m9/`. L'OBJ obtenu est en coordonnées monde (couteau incliné dans la pose du viewmodel) et sa texture
  réduite à 64 px : `blend_common.import_m9` le redresse sur ses axes principaux (scie en haut) et lui donne deux
  matières nettes (acier, manche) choisies face par face d'après cette texture.
- M9 dans la vitrine : agrandi à 0,85 fois la longueur de l'AWP (décision : l'arme remplit la vitrine) ; `--fill`
  pour régler.
- Ids publiés : `tools/menu/published.json`. L'import Roblox du FBX garde les positions absolues des éclats (vérifié au
  millième contre `center`) et les noms `Eclat_NN` / `Vide_NN`, sans rotation.
- Une `SurfaceAppearance` ne se modifie pas en jeu par script (seulement en Edit, par plugin) : les deux jeux d'éclats
  texturés sont construits d'avance (`.rbxm`) et échangés pendant la dispersion. Essai dans Studio : atlas net,
  `EmissiveMaskContent` + `EmissiveStrength` 1,5 font ressortir l'arme sur le verre sombre.
- Un éclat vide reflète les lumières dans le verre : la lumière d'appoint au sol est sans reflet (`specular_factor = 0`),
  sinon deux éclats sous le chargeur paraissaient gris clair. Roblox n'aura pas ce reflet.
- Commandes :
  ```bash
  blender -b --factory-startup --python tools/menu/mirrors.py -- --full --state assembled   # ou half, scattered ; --aspect 4:3
  blender -b --factory-startup --python tools/menu/mirrors.py -- --anim                     # images de la vidéo
  uv run tools/menu/overlay_mockup.py <Oswald.ttf> <rendu.png> <sortie.jpg>
  uv run tools/menu/video.py <Oswald.ttf> <dossier des images> <sortie.mp4>
  ```
  Sortie dans `.maquettes/menu-miroirs/` (non versionné, `MENU_OUT` pour la changer). Environ 2 min par image en
  1920x1080 : lancer les rendus l'un après l'autre (deux en parallèle doublent le temps de chacun).
- La source Blender de l'AWP (`assets/awp_viewmodel/AWP_Viewmodel_Anims.blend`) est en vert uni alors que l'arme du jeu
  a une crosse en bois : `blend_common.awp_materials` remet le bois.

## Reste à faire

- Passer l'écran de réapparition et la bannière de fin de round (`RoundHUD.luau`) du style « Tactical » ambre à cette direction.
- Afficher les munitions dans le HUD (`WeaponSystem` les gère, rien ne les montre), dans le même langage que le compteur de vitesse.
- Piste écartée pour l'instant sur le compteur : chiffres en images usées comme le titrage, et inclinaison qui augmente avec la vitesse.
- Tester le menu au tactile et à la manette : c'est prévu dans le code, jamais essayé.
- Construire le menu « salle des miroirs » (#112).
