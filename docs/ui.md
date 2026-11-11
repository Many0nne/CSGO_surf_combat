# Direction artistique de l'interface

Référence pour tout nouvel écran. La direction est appliquée à tous les écrans existants : accueil, Infos, Réglages, Feedback,
HUD de partie (vitesse, barre d'armes, timer, classement), réapparition et fin de round (#117).

## La direction : « Ligne de mire »

**Principe : l'interface est faite de la matière du jeu.** Le déclic est venu d'un exemple de jeu de samouraï, dont la roue
d'armes est faite d'encre, de sang et de vrais sabres. Ici, la matière est le canyon de rampes, l'AWP et le tir.

Ce que l'utilisateur a validé dans le menu principal :

- une vraie scène 3D dans le moteur, avec les assets du jeu, plutôt que des formes dessinées ;
- on choisit à la souris système ; seule l'arme de la vitrine se tire : à son survol le curseur devient un hitmarker, l'AWP le suit, le tir a le vrai son et la vraie animation (#130 : les impacts sur les boutons et le hitmarker partout ont été retirés, jugés peu lisibles) ;
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

- `src/client/ui/MainMenu.luau` : accueil de la salle des miroirs (titre, onglets, fiche d'arme, sélecteur), tir sur l'arme de la
  vitrine au clic (accueil seulement). Les onglets sont dans leur propre `ScreenGui` (`MenuTabs`, DisplayOrder 4), au-dessus des écrans
  secondaires. Sous les onglets, un message ponctuel (`MainMenu.showNotice`, 5 s, rouge d'impact à ombre) explique un
  retour au menu imprévu, par exemple une apparition impossible (#219) ; rendu provisoire, pas encore validé.
- `src/client/ui/MenuPage.luau` : gabarit des écrans secondaires, sans panneau : bloc centré sur le voile du classement,
  actions côte à côte en bas au centre (`MenuPage.ExitY`). Choix de l'utilisateur en #117, après un premier passage en
  colonne sur un dégradé à gauche jugé peu changé. Infos et Réglages partagent la même disposition (catégories à gauche
  avec barre ambrée sur l'active, contenu à droite, bloc de 780 px). Le titre en texte (Oswald à ombre, en
  haut au centre) n'est montré qu'en partie (menu en partie et ses Réglages) : au menu, l'onglet actif sert de titre. En
  partie, il se pose sous le timer du round (`TITLE_Y` 92 px, #220), resté visible au-dessus du voile. `page.choice` : choix en texte, os atténué au repos, os vif une fois choisi (`setSelected`, aussi pour
  l'action principale comme ENVOYER ou RETOUR), rouge d'impact au survol.
- Réglages (`SettingsMenu.luau`, disposition C des schémas de #117, préférée aux sous-onglets en haut et à la liste
  unique qui défile) : catégories à gauche (barre ambrée sur l'active), lignes de 54 px à droite (nom, contrôle,
  valeur os à ombre, filet). Contrôles : curseur (trace continue, poignée en pastille os, rouge au survol ; une barre segmentée ferait perdre
  la précision de la sensibilité) et choix fermé « ‹ VALEUR › ». RÉTABLIR remet la catégorie affichée à ses valeurs par
  défaut. Ajouter un réglage : une ligne dans `buildCategories` (avec son champ dans `PlayerSettings` pour qu'il soit
  conservé) ; une catégorie sans réglage n'est pas créée.
  TOUCHES (#100) : chaque ligne nomme l'action et la valeur donne le geste (choix de l'utilisateur : « Arme suivante :
  MOLETTE BAS », pas « Molette vers le haut : PRÉCÉDENTE »). « Arme suivante » (MOLETTE BAS par défaut) et « Arme
  précédente » (MOLETTE HAUT) portent le même réglage et se suivent ; AUCUNE coupe la molette. Puis une ligne par arme du
  StarterPack (« Arme 1 · AWP », 7 au plus, pas de défilement). On clique sur la touche, elle affiche « APPUIE… », la
  touche suivante est prise ; Échap ou un clic ailleurs annule. Une touche d'un autre emplacement est échangée ; une
  touche du jeu (déplacement, R, F, P, F3/F4…) ou hors liste (Espace, Maj, Tab…) est refusée par un message en rouge
  d'impact sur la ligne. Seules les lettres, les chiffres du haut et les touches F sont proposées : libellés courts dans
  la barre d'armes. RÉTABLIR remet molette et touches ensemble.
- Menu en partie (`InGameMenu.luau`, #157) : la touche `PlayerSettings.MENU_KEY` (P, seule constante de cette touche :
  réservée pour la barre d'armes, rappelée dans Infos) ouvre en partie un écran `MenuPage` titré « MENU » : colonne
  centrée de choix en texte (taille 40) REPRENDRE (os vif), RÉGLAGES, puis MENU PRINCIPAL écarté ; libellé ambré en bas
  « LA PARTIE CONTINUE · P POUR REPRENDRE ». RÉGLAGES remplace l'accueil par l'écran Réglages (présentation `modal`,
  même écran que celui du menu principal, sans copie) dont RETOUR revient à l'accueil du menu. P referme tout, Échap
  aussi (Roblox ouvre son menu par-dessus ; `GuiService.MenuOpened` ferme tout). Le jeu n'est pas en pause (FFA) : le
  menu est une surcouche, sur un voile noir à part (`InGameMenuBackdrop`, DisplayOrder 2, actif : il retient les clics
  pour qu'ils ne partent pas en tirs) qui reste posé quand les Réglages remplacent l'accueil. Tant qu'il est ouvert :
  souris libre (retenue même si `FPSCamera` la verrouille à une réapparition, la valeur voulue par le jeu est rendue à
  la fermeture), touches de jeu coupées (`InputModule.setSuspended`), barre d'armes inactive, crosshair et affichage
  des touches masqués. Disponible vivant ou mort (`InGameMenuRules.available` : `IN_ROUND`, `DEAD`), fermé
  ailleurs ; au menu principal, P ouvre ou ferme ses Réglages. Vues et routage de la touche : `InGameMenuRules`
  (testées). MENU PRINCIPAL : arme rangée, remote `LeaveRound` (le serveur retire le joueur du round, cf.
  `docs/architecture.md`), puis état `MENU` sans attendre la réponse.
- `src/client/ui/MenuShot.luau` : choix en texte à ombre décalée (`textChoice`, l'ombre s'estompe avec le choix
  désactivé) ; un clic déclenche l'action, sans tir (JOUER : explosion de la vitrine, puis action après `PLAY_DELAY`).
- `src/client/ui/MenuCursor.luau` : souris système, hitmarker au survol de l'arme (`MenuScene.isAimingWeapon`, accueil seulement).
- `src/client/systems/game/MenuScene.luau` : salle des miroirs, éclairage temporaire, visée, tir sur les éclats de l'arme (un clic à côté ne tire pas),
  explosion sur JOUER.
- `src/client/systems/game/MenuSceneRules.luau` : règles pures testées (`tests/specs/MenuSceneRules.spec.luau`).
- `src/client/ui/Transition.luau` : volets blancs, enchaînés à l'explosion de la vitrine.
- `UIKit.shadowedText` : texte os doublé d'une ombre noire décalée, commun au HUD et au menu.
- `src/client/ui/Speedometer.luau` : compteur de vitesse, piste « Titrage » : gros chiffres os penchés (-6°) avec ombre noire décalée, nom du palier, bande ambrée en biais crantée aux seuils, tout passe au rouge d'impact au dernier palier (`HUDRules.speedTier`, `speedFill`). En bas à gauche, sur un fond sombre sans bord : image de dégradé de coin (`tools/ui/make_corner_scrim.py`, `assets/ui/hud/`) teintée par `ImageColor3`.
- `src/client/ui/WeaponBar.luau` : barre d'armes en bas à droite, en miroir du compteur ; remplace le Backpack Roblox
  (`CoreGuiType.Backpack` désactivé dans `init.client.luau`). Par arme : silhouette plate tirée des MeshParts de son viewmodel
  (bras exclus) dans un `ViewportFrame` blanc teinté par `ImageColor3`, nom et touche. L'arme en main est en os, avec son
  numéro et un trait en rouge d'impact, les autres sont grisées ; toute la barre (fond compris) disparaît 2,5 s après le dernier changement d'arme
  (`HUDRules.WEAPON_BAR_FADE_DELAY`). Emplacements dans l'ordre alphabétique, comme le helper `DebugPlaytest`.
  Équipement : touches des emplacements (1 à 9 par défaut) et molette (vers le haut = arme précédente par défaut),
  réglables dans Réglages > TOUCHES (#100) ; toucher d'un emplacement, L1/R1 à la manette (fixes). La barre ignore
  touches et molette pendant que le menu en partie est ouvert (`InGameMenu.isOpen`, Réglages compris).
- `src/client/ui/AmmoCounter.luau` (#158) : « chargeur / réserve » en bas à droite, à gauche de la barre d'armes (chiffre du
  chargeur os à ombre, réserve atténuée, libellé ambré « MUNITIONS », chargeur vide en rouge d'impact). Lit
  `WeaponSystem.getAmmo` à chaque Heartbeat (met à jour les textes seulement si les valeurs changent), masqué sans
  chargeur (couteau) et hors partie (`HUDRules.gameHudVisible`, via `GameStateController.applyGameHud`). Contrairement à
  la barre d'armes, il ne s'estompe pas.
- `src/client/ui/Crosshair.luau` (#195) : réglage « Visée simplifiée » (Réglages > GRAPHISMES, `PlayerSettings.simpleAim`, coupé par
  défaut). Quatre traits fins os (`ARM_LENGTH` 9 px, `ARM_THICKNESS` 2, `CENTER_GAP` 5) sans point central, doublés d'un contour
  noir de `OUTLINE` 1 px (`OUTLINE_TRANSPARENCY` 0,1) : sur fond blanc seul le contour se lit, sur sol ou mur sombre le trait os.
  Taille fixe en pixels, pas de `scaledRoot`. `ScreenGui` en `ScreenInsets.None` pour tomber sur le centre exact de la caméra,
  comme la lunette. Affichage = `HUDRules.crosshairVisible` appliquée à `HUDState` (voir « État du HUD ») : réglage actif, HUD de
  jeu visible (donc ni menu, ni mort, ni résultat), lunette absente et menu en partie fermé.
  Toutes les armes, couteau compris. Piste rejetée : point rouge central (criard, hors de la matière du HUD).
  Branches tracées par `Reticle.drawArms` (#222), comme le réticule de la lunette (`ScopeOverlay`) : quatre branches à
  `gap` px du centre, longueur en px ou en part du parent, contour dessous plus épais de `outline.width` px par côté,
  bouts fermés (`caps`, crosshair) ou ouverts (lunette), estompe `fade` en option (lunette). Un nouveau réticule passe par là.
- `src/client/ui/KeyDisplay.luau` (#197) : réglage « Affichage des touches » (Réglages > GRAPHISMES, `PlayerSettings.keyDisplay`,
  trois valeurs `off` (défaut) / `simple` / `full`, validées par `sanitize`). Grille façon clavier en bas au centre (`BOTTOM_MARGIN`
  40 px, `scaledRoot`, entre le compteur de vitesse à gauche et la barre d'armes à droite) : touches de `KEY_SIZE` 40 px, `KEY_GAP` 4.
  **DA (#229, choix de l'utilisateur) : keycaps en relief comme un vrai clavier** (référence : photo d'un clavier blanc à
  touches roses, vu de face et un peu au-dessus), dans les couleurs du HUD. Chaque touche (`buildKey`) : ombre portée noire
  décalée de 3 px, rebord plus sombre visible sur les côtés (`CAP_SIDE` 4 px) et sous le dessus (face avant, `CAP_FRONT` 9 px),
  dessus bombé (dégradé `UIGradient` vertical multiplié à la couleur, pas de `CanvasGroup`), coins arrondis. Couleurs : touches
  os à libellé sombre (`CAP_KEY`), « modificateurs » Espace, Ctrl, Maj, M1, M2 en ambre (`CAP_MOD`, à la place du rose de la
  référence) ; enfoncée, la touche descend de `CAP_PRESS` 5 px (le haut descend, le bas reste posé, la face avant raccourcit) et
  passe au rouge d'impact à libellé os (`CAP_DOWN`). Placement mesuré en jeu (fenêtre 1291x607) : plus de 100 px d'écart avec le
  compteur et les munitions ; en 16:9, 12 px de marge côté munitions avec le mode `full` ; en 4:3, le bloc `full` chevauche les
  munitions (déjà le cas de l'ancienne grille).
  Pistes rejetées (#229, captures en jeu) : grille de cases plates (fond `C.Scrim` translucide, case os pleine une fois enfoncée,
  rendu d'origine de #197, « overlay de stream ») ; lettres os à ombre sans cases avec trait rouge sous la touche enfoncée
  (« titrage », comme le timer) ; trait de bande sous chaque touche rempli d'ambre (« jauge », comme le compteur) ; directions en
  branches de crosshair (« réticule ») ; l'utilisateur voulait garder la grille du clavier, avec de la profondeur. Palettes de
  keycaps écartées : touches sombres à libellé os (relief invisible sur fond sombre) et deux tons sombre / os (plus proche de la
  référence, recommandée mais non retenue).
  `simple` : Z/Q/S/D et Espace en barre large dessous (pas d'accroupi) ; `full` : en plus, dans un bloc séparé
  à droite (M1, M2 / recharge, inspection / CTRL accroupi, MAJ marche lente), pas les armes. La liste, la grille et la visibilité sont
  dans `HUDRules.keyDisplayEntries` / `keyDisplayVisible` (testées). Libellés : `LocalSettings.keyText` (disposition du clavier, AZERTY
  = Z Q S D), libellés fixes pour Espace, Ctrl, Maj et la souris. L'état vient de `UserInputService:IsKeyDown` /
  `IsMouseButtonPressed` à chaque Heartbeat (repeint seulement au changement). Les liaisons sont fixes et n'ont qu'une source (#224) :
  `src/shared/KeyBindings.luau` (action → noms d'`Enum.KeyCode`, `MOUSE` pour M1/M2 ; M2 lu par `WeaponSystem`, M1 reste
  `Tool.Activated`, fixé par Roblox ; tables gelées), lue par `InputModule` (`KEY_MAP`), par
  `HUDRules.keyDisplayEntries` (la grille `KEY_DISPLAY_LAYOUT` ne garde que la place et le libellé fixe de chaque action) et par
  les touches réservées de `PlayerSettings`. Une nouvelle action : sa liaison dans `KeyBindings`, sa case dans la grille.
  Les cases suivent les touches physiques, pas l'action disponible : F et M2 s'allument aussi avec une arme sans inspection
  ni lunette ; clavier ignoré pendant la saisie de texte (`GetFocusedTextBox`), pas de suivi du `gameProcessed` (piste non retenue,
  elle demandait un état par touche au lieu d'un sondage).
  Affichage (`HUDRules.keyDisplayVisible` appliquée à `HUDState`) : mode actif, HUD de jeu visible, menu en partie fermé ; la
  lunette ne le masque pas (les touches restent utiles).
  Vérifié en Studio avec `user_keyboard_input` (`keyDown` W/D/S/Espace/Ctrl/R passent en partie et allument les cases) ; le clic de
  souris M1/M2 n'a pas été simulé. Coordonnées de clic des onglets du menu : y négatif (`AbsolutePosition` du bouton).
- `src/client/ui/RoundHUD.luau` : timer et rang en haut au centre (chiffres os droits avec ombre, libellés ambrés, fondu
  sombre en deux moitiés de coin, timer en rouge d'impact sous 30 s) ; classement sous Tab : pas de panneau, voile sombre
  central qui s'efface vers les côtés, titre « CLASSEMENT » sur un filet ambre, colonnes K / M / K/M, ligne du joueur
  sur une bande rouge d'impact **droite** (penchée, elle se lisait mal en face des colonnes).
  Menu en partie ouvert (#220, choix de l'utilisateur : la partie continue derrière) : le timer et son fondu (calque
  `TimerLayer`) passent dans un `ScreenGui` à part (`RoundTimerOverMenu`, DisplayOrder 4, au-dessus du voile 2 et de la
  page 3), selon `HUDRules.roundTimerOverMenu` ; le titre « MENU » / « RÉGLAGES » descend dessous. Menu fermé, le calque
  revient dans `RoundHUD` en ZIndex 0, sous les voiles du classement et du résultat comme avant.
  Réapparition : la scène reste visible, désaturée (`ColorCorrectionEffect`), sans voile plein ; en bas au centre, sur
  deux moitiés de fondu de coin, « ÉLIMINÉ » en rouge d'impact (le joueur a été touché), compte à rebours en gros
  chiffres os à ombre, libellé ambré « RÉAPPARITION ». Au-dessus du compte à rebours (#102) : « ÉLIMINÉ PAR », nom du
  tueur en os, arme et « TÊTE » en ambre ; sans tueur, « ÉLIMINÉ » puis « CHUTE ». La caméra reste au lieu de la mort
  et pivote vers le tueur, marqué d'un losange et de « NOM · distance » en rouge d'impact (`DeathCamera`).
- `src/client/ui/KillFeed.luau` (#102) : en haut à droite, sans fond, une ligne par mort (tueur et victime en os, arme
  en ambre plus petite), 4 lignes, 5 s chacune ; les lignes du joueur sont sur une bande rouge d'impact droite qui
  s'efface vers la gauche, comme sa ligne au classement. Affiché vivant ou mort (`HUDRules.killFeedVisible`), pas au
  menu ni au résultat.
  Fin de round : voile central du classement, « ROUND TERMINÉ » ambré, nom du vainqueur en os géant, filet ambre,
  « REMPORTE LE ROUND » ; le rouge d'impact n'apparaît que si le joueur gagne (bande derrière son nom).
- `UIKit.cornerScrim` : fond de coin du HUD (`assets/ui/hud/scrim_coin.png`) dans les quatre orientations, par rotation.
  Seul le compteur de vitesse est penché (`UITheme.Layout.HudLean`, -6°) : l'utilisateur a préféré le timer, la barre
  d'armes et le classement droits.
- Titrage en images usées (police Anton, `tools/ui/make_menu_type.py`) : abandonné en #117 au profit du texte Oswald à
  ombre partout ; script et images supprimés (dans l'historique git avant #117).

Pour une image d'interface (fond de coin…) : la publier, puis récupérer l'id de l'image :

```bash
bash tools/publish_asset.sh <image>.png Decal "SurfFFA_<nom>"
```

Puis, en playtest, contexte `Server` (`execute_luau`), lire l'id de l'image à mettre dans le code :

```lua
local model = game:GetService("InsertService"):LoadAsset(<id du Decal>)
return model:FindFirstChildWhichIsA("Decal", true).Texture
```

## Règles des écrans secondaires

- Rien ne se tire (#130) : souris système, un clic agit tout de suite. Un curseur de réglage se place d'un clic, puis se glisse.
- Réglages en partie (menu en partie, touche P) : même écran sur un voile sombre.
- Piste rejetée (#130) : un impact de balle laissé sur chaque élément cliqué, et le hitmarker comme curseur partout. Peu beau et peu lisible.

## Pièges connus

- **HUD de jeu visible seulement en partie (#105) :** un `ScreenGui` créé avec `ResetOnSpawn = false` reste affiché après la fin du
  round. Source unique : `HUDRules.gameHudVisible(état)`, appliquée par `applyGameHud` dans
  `GameStateController` (compteur de vitesse, barre d'armes, lunette). `RoundHUD` (appelé par `setState`) se masque déjà seul.
  Piège : `endRound()` détruit le personnage côté serveur sans que `CharacterRemoving` se déclenche (`Player.Character` reste
  référencé) : un élément qui ne suit que la vie du personnage reste affiché au menu (cas de `WeaponBar`). Tout nouvel élément du HUD de jeu doit brancher sur cette règle, pas sur un état à lui.
  `Speedometer.init()` tourne au premier spawn, après le premier `setVisible` : le module mémorise donc la visibilité.

- **État du HUD (#223) :** `src/client/ui/HUDState.luau` tient l'état client (posé par `applyGameHud`, d'où « HUD de jeu » et
  « mort »), le menu en partie ouvert (`InGameMenu`, Réglages compris) et la lunette affichée (`ScopeOverlay.setVisible`). Les
  éléments qui dépendent de plus que l'état client s'y abonnent (`HUDState.onChanged`, nouvel et ancien instantanés) et
  appliquent leur règle de `HUDRules`, testée avec un instantané (`crosshairVisible`, `keyDisplayVisible`, `roundTimerOverMenu`).
  Une nouvelle condition de masquage : un champ et son setter dans `HUDState`, puis la règle des éléments concernés ; pas de
  setter `setMenuOpen` / `setScoped` recopié dans chaque élément (supprimés de `Crosshair` et `KeyDisplay`). Compteur de
  vitesse, barre d'armes, munitions et kill feed ne dépendent que de l'état client et restent poussés par `applyGameHud`.

- **Libellé d'une touche (#100) :** `Enum.KeyCode` désigne la position sur un clavier QWERTY. Sur un clavier AZERTY,
  `KeyCode.Q` est la touche imprimée « A » : afficher `UserInputService:GetStringForKeyCode` (`LocalSettings.keyText`),
  sauf pour les chiffres du haut, qui donneraient « & » ou « é ».
- **Piloter le vrai jeu au MCP (#195) :** un `require` dans `execute_luau` (Client) charge une copie des modules : `requestPlay`,
  `LocalSettings.update` ou `getState` n'agissent pas sur le jeu qui tourne. Lire les `ScreenGui` de `PlayerGui` (leur `Enabled`
  est réel) et passer par l'interface (`user_mouse_input` en coordonnées d'écran, soit 0,8 fois celles de `screen_capture`) ou
  par `DebugPlaytest` pour lancer la partie. Les chemins `instance_path` avec accents (« RÉGLAGES ») ne se résolvent pas, et un
  nom en double (onglet et cadre « GRAPHISMES ») est ambigu : cliquer aux coordonnées. En partie, ni les touches P et 1 ni le
  clic droit (lunette) ne passent par le MCP, mais `keyDown` / `keyUp` de W, A, S, D, Espace, Ctrl, R sont lus par
  `UserInputService:IsKeyDown` (#197) ; les onglets du menu se cliquent à l'`AbsolutePosition` du bouton, y négatif compris
  (`moveTo`, attendre, puis `mouseButtonClick`) ; équiper côté serveur (`Humanoid:EquipTool`). Les bots tuent le joueur en boucle :
  `workspace:SetAttribute("DebugBots", 0)` avant de tester.
- **Touche P au MCP (#157) :** `user_keyboard_input` ne fait pas passer P en partie (comme en #195). Pour ouvrir le menu
  en partie dans un playtest, attribut de debug Studio `DebugInGameMenu` sur le joueur (contexte `Server` ou `Client`) :
  `true` ouvre (en partie seulement), `false` ferme (`InGameMenu`, inactif hors Studio). Les choix se cliquent ensuite à
  l'`AbsolutePosition` des boutons.
- **Choix inertes en partie (#157) :** JOUER pose le verrou `MenuShot` (`locks`) qui bloque tous les choix en texte ;
  il n'était levé qu'au retour au menu (`MainMenu.show`), si bien que les choix des Réglages en partie ne répondaient
  pas. `MainMenu.hide` le lève désormais. Tout nouvel écran de partie fait de `MenuShot.textChoice` en dépend.
- **Écran Réglages piloté au MCP :** `user_mouse_input` prend ici les coordonnées de l'`AbsolutePosition` des boutons
  (`ScreenGui` en `IgnoreGuiInset`), et un refus de touche (affiché 1,5 s) se lit avec un relevé branché avant l'appui :
  deux appels MCP successifs prennent plus de temps que ça.
- **Id d'un Decal publié :** il ne s'affiche pas dans une `ImageLabel` (console : `Asset type does not match requested type`).
  Il faut l'id de l'image contenue dans le Decal (voir ci-dessus).
- **Distance d'affichage :** Roblox la réduit selon la charge, et le décor lointain disparaît d'un coup avec la map chargée.
  Le canyon est donc au tiers de sa taille apparente (1 000 studs de long). Un test sans la map ne le montre pas.
- **Éclairage :** `MenuScene` remplace celui de `Lighting` et le rétablit à sa sortie. Un tween encore actif écrase les valeurs
  rétablies : l'annuler d'abord (`burstTweens`), car le joueur peut apparaître avant la fin de l'explosion.
- **Curseur :** `MenuCursor` réimpose `MouseIconEnabled` à chaque image (faux sur l'arme, vrai ailleurs), car les autres écrans le changent en s'ouvrant ou se fermant.
- **`AbsolutePosition` avec `IgnoreGuiInset` :** elle exclut la barre du haut, contrairement à `GetMouseLocation`. Préférer
  `MouseEnter`, `MouseLeave` et `Activated` à un test de zone maison.
- **Fondu dans deux directions** (fond qui s'efface vers le haut et vers la droite) : impossible avec des `UIGradient`.
  Un `UIGradient` sur un `CanvasGroup` est ignoré ; un seul gradient en biais laisse une arête ; des calques très transparents
  empilés font des bandes visibles. Utiliser une image de dégradé blanche teintée par `ImageColor3` (voir `make_corner_scrim.py`).
- **Retourner une image :** un `ImageRectSize` négatif ne retourne pas l'image dans une `ImageLabel`. Tourner l'image
  (`UIKit.cornerScrim` : 90°, 180° ou -90° selon le coin, taille permutée pour les quarts de tour).
- **Tools des armes :** ils sont presque vides (l'arme visible vient du viewmodel). Pour dessiner une arme hors du jeu
  (icône, silhouette), cloner les MeshParts enfants directs de `ReplicatedStorage/ViewModels/<Nom>`, sans les bras.
- **`CanvasGroup` interdit (#155) :** Roblox le rend dans une texture dont la résolution baisse avec la qualité graphique
  (et la mémoire) : texte flou, illisible au minimum. Sa `GroupTransparency` est aussi ignorée dans ce rendu simple : le
  groupe reste affiché. Les écrans (classement, réapparition, résultat, Infos, Réglages, fiche d'arme) sont des `Frame` ;
  `UIKit.reveal` / `UIKit.fadeIn` animent la transparence de chaque enfant (fond, texte, image, `UIStroke`) à partir des
  valeurs relevées au lancement. Un élément ajouté pendant le fondu n'est pas animé. Vérifier toute nouvelle interface à
  la qualité graphique minimale et maximale.
- **Polices :** aucune annonce officielle d'import de police trouvée (novembre 2026). Tout le texte est en polices
  Roblox (Oswald pour les titres et libellés, Titillium pour le texte courant).
- **Bras du viewmodel :** ils forment vite une grosse masse noire quand la souris est dans un coin. Limiter le pivot
  (`MenuSceneRules.aimAngles`) et garder le soleil dégagé.

## Prototyper dans le moteur

Pour vérifier la faisabilité d'une idée, pas pour chercher une composition (voir « Méthode » plus haut). Sans toucher aux fichiers ni à la place : pendant un playtest, `execute_luau` en contexte `Client` peut construire une scène
et une UI entières, et `screen_capture` montre le résultat avec l'UI. Tout disparaît à l'arrêt du playtest. Le code ainsi
lancé ne partage pas ses modules avec le jeu (un `require` donne une autre instance). En mode Edit, `screen_capture` rend
un viewport tout blanc quand la fenêtre Studio est réduite ou en arrière-plan : la mettre au premier plan. Seul Claude ne peut pas connecter le
plugin Rojo : l'utilisateur doit le faire pour tester un worktree.

Juger la lisibilité d'un élément du HUD (#229) : en contexte `Client`, poser une `Part` ancrée sans collision à 3 studs devant
la caméra, recalée à chaque `RenderStepped`, en `Neon` couleur sable (105, 100, 92) pour un fond clair proche des rampes,
en `SmoothPlastic` presque noir pour un fond sombre ; masquer côté client le mannequin `DebugDummy`. Un mur plus proche que 3
studs passe devant : s'en éloigner au clavier (`user_keyboard_input`). On ne peut pas téléporter le joueur depuis le MCP :
le mouvement est simulé côté client (`MovementController`) et réécrit la position de la racine à chaque tick, que le
changement vienne du serveur ou du client. Pour allumer des touches sans bouger, appuyer sur deux directions opposées.

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
- **Dans Roblox** (`MenuScene.luau`, étape 3) : les jeux d'éclats texturés sont dans `assets/rbx/Menu/` (mappé sur
  `ReplicatedStorage.MenuMirrors`), construits dans Studio par `tools/menu/studio_build.luau` puis exportés
  (`receive.luau Menu`) ; fils, retards et teintes viennent de `MenuMirrorsData.luau`, généré par
  `tools/menu/make_luau.py`. Après une nouvelle découpe : `--export` des deux armes, publication, mise à jour de
  `published.json`, `make_luau.py`, construction et export dans Studio.
- La salle est fermée (plafond, murs hors champ) : sans cela le ciel et le soleil de la map entrent. Lumières réglées
  contre `reconstituee.jpg` : douche 6 (portée 40), rasante 8 (portée 34, angle 90), appoint 1,5, ambiance (44, 47, 58),
  `EnvironmentDiffuseScale` 0,3. Plus sombre, le mur du fond disparaît.
- Précharger les textures des armes (`ContentProvider:PreloadAsync` sur leurs `SurfaceAppearance`) : Roblox ne
  télécharge une texture qu'une fois la pièce visible, et une arme jamais montrée apparaissait en éclats blancs opaques
  pendant sa première vague.
- Coût mesuré dans Studio (playtest, MCP actif, donc bruité) : environ 6,7 ms par image pour toute la scène, dont
  1,8 ms pour les éclats ; fils, lumières et bloom moins de 0,4 ms chacun.
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

**Interface et tir** (étape 4) :
- Décisions de l'utilisateur : ARMES est l'accueil (la vitrine) ; JOUER, plus grand et souligné de rouge d'impact, est
  l'appel à l'action ; les onglets restent affichés sur Infos, Réglages et Feedback, qui s'ouvrent dessous ; seule l'arme
  se tire, sans trou dessiné (#130 : plus de tir ni d'impact sur les boutons) ; JOUER fait exploser la vitrine.
- Fiche d'arme : DÉGÂTS et CADENCE (RPM) rapportés à la meilleure arme de la vitrine, PRÉCISION lue dans
  `WeaponConfig.Accuracy` (valeur d'affichage, la dispersion n'est pas simulée), catégorie dans `WeaponConfig.Category`
  en capitales (`string.upper` ne passe pas « é » en « É »). Barre pleine : dernier segment en rouge d'impact.
- Tir : rayon depuis le curseur sur les éclats de l'arme montrée (les éclats vides du fond ne déclenchent pas le tir mais pivotent avec), parmi les jeux d'éclats visibles (`CanQuery` activé sur eux seuls). L'éclat touché et ses
  voisins (2,6 studs) reçoivent un élan autour de leur fil, dans un ressort amorti (`MenuSceneRules.springStep`) : deux
  tirs rapprochés se cumulent sans saut ; pointe vers 110°, retour au repos en 3,5 s.
- Explosion : chaque éclat quitte son fil (Beam coupé) avec une vitesse vers la caméra, vers l'extérieur et vers le haut,
  sous gravité, en tournoyant ; surexposition jusqu'au blanc, puis les volets (`PLAY_DELAY` 1 s). `showAtRest` remet tout
  sur les fils au retour au menu.
- Coût mesuré dans Studio (overlay F3, 1291x647, MCP actif) : boucle `menu 3D` 0,25 ms par image au repos, 0,32 ms
  pendant une série de tirs (pointe 0,64 ms), 0,40 ms pendant l'explosion (pointe 0,83 ms) ; curseur 0,02 ms ; 159 draw
  calls, CPU rendu 6 à 7 ms, GPU 8 à 10 ms.
- Vérifier au MCP : `user_mouse_input` prend des coordonnées d'écran, pas celles de `screen_capture` (0,8 fois celles de
  la capture sur ce poste) ; préférer `instance_path` pour viser un bouton. La capture arrive plusieurs centaines de ms
  après l'action : un mouvement bref (pivot, explosion) se mesure par script (échantillonnage des CFrame dans une boucle
  lancée avant le clic), pas sur une capture.

## Reste à faire

- Piste écartée pour l'instant sur le compteur : chiffres en images usées comme le titrage, et inclinaison qui augmente avec la vitesse.
- Tester le menu au tactile et à la manette : c'est prévu dans le code (flèches ‹ ›), jamais essayé.
- Première vague d'une arme jamais montrée : ses éclats passent encore en blanc opaque le temps du chargement, malgré
  `PreloadAsync` (constaté en Studio sur le M9).
