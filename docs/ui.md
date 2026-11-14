# Direction artistique de l'interface

Référence pour tout nouvel écran. La direction est appliquée à tous les écrans existants : accueil, Infos, Réglages, Feedback,
HUD de partie (vitesse, barre d'armes, timer, classement), réapparition et fin de round (#117).

## La direction : « Ligne de mire »

**Principe : l'interface est faite de la matière du jeu.** Le déclic est venu d'un exemple de jeu de samouraï, dont la roue
d'armes est faite d'encre, de sang et de vrais sabres. Ici, la matière est le canyon de rampes, l'AWP et le tir.

Ce que l'utilisateur a validé dans le menu principal :

- une vraie scène 3D dans le moteur, avec les assets du jeu, plutôt que des formes dessinées ;
- on choisit à la souris système ; rien ne se tire au menu (#130 : impacts sur les boutons et hitmarker partout retirés, jugés peu lisibles ; #253 : plus d'arme à tirer à l'accueil) ;
- la vitesse passe par le mouvement réel (surfeurs et traînées), pas par des effets graphiques posés sur une image ;
- un titrage en images usées : lettres penchées arrachées par le vent, éclats, impacts de balles.

Palette du menu : ciel bleu nuit, soleil blanc chaud, lignes ambrées, rampes brun chaud, silhouettes noires, texte os
(`243, 233, 220`), rouge d'impact (`C.HitRed`) pour ce qui est visé ou touché.

Le canyon au couchant est abandonné (il collait à l'ancienne map), puis la salle des miroirs (#112, rejetée en #253) :
l'accueil montre le **personnage du jeu en pose sur la map** (section « Menu : accueil sur la map » plus bas), avec
la palette du HUD.

## Règles communes à tous les écrans (#308)

Harmonisation faite en #308, à partir de l'écran d'équipement (disposition validée par l'utilisateur) : les autres écrans
avaient chacun leur écriture du même état. Un nouvel écran suit ces règles ; s'en écarter se décide avec l'utilisateur.

- **Deux cadres, selon le rôle du personnage.** L'écran d'équipement tient à gauche, le personnage net à droite : il
  tient l'arme qu'on choisit. Les écrans secondaires (Réglages, Infos, Feedback, menu en partie, `MenuPage`) sont un
  bloc centré de 780 px sur un voile, sans panneau : titre, onglets en boîte, contenu, actions en bas au centre. Hors
  de l'onglet ARMES, la caméra de l'accueil se recentre (`MenuScene.setCentered`) et le personnage repasse derrière le
  bloc. **Piste rejetée (#308) : le cadre de l'équipement appliqué à tous les écrans.** Essayé dans le moteur, refusé
  par l'utilisateur : « comme il n'y a rien à droite c'est trop bizarre, dans tous les jeux ces éléments sont
  centrés » ; l'équipement est l'exception, pas la règle.
- **Ambre = « là où je suis »**. Sous-onglets (catégories des Réglages et d'Infos, emplacements de l'équipement) : boîte
  ambrée pleine à texte sombre (`MenuShot.boxChoice`), une seule à la fois. Barre du menu : texte os vif souligné
  d'ambre. **Piste rejetée (#308) : les onglets du menu en boîtes** (onglet ouvert en boîte ambrée, JOUER en boîte
  os) : deux boîtes pleines côte à côte, de tailles et de couleurs différentes, l'utilisateur n'a pas aimé le rendu.
  JOUER reste en gros texte, sans soulignement (le soulignement veut dire « page ouverte »).
- **Rouge d'impact = « à moi » ou survolé** : arme équipée, ligne du joueur au classement et au kill feed, survol d'un
  choix. Jamais pour dire quelle page est ouverte.
- **Touche nommée dans un menu = boîte os à texte sombre** (`UIKit.tag`, `UIKit.keyHint` : aide de l'équipement,
  Infos > COMMANDES, menu en partie). Dans le HUD, les touches restent des keycaps en relief (`KeyDisplay`, #229).
- **Action principale d'un écran** (RETOUR, ENVOYER, REPRENDRE) : texte os vif, les autres en os atténué (`page.action`,
  `page.choice`), l'action principale en dernier (à droite).
- **Aucun texte sous 16 px** (`UITheme.TextSize.Min`), libellés ambrés compris (`UIKit.accentLabel`) : à 12 ou 14 px ils
  étaient illisibles une fois l'écran réduit (« COMBAT DE SURF », « FREE FOR ALL », « RANG », « MUNITIONS »,
  « RÉAPPARITION », étiquettes et aide de l'équipement).
- **Une seule famille de police, Oswald** : gras pour les titres et les chiffres, medium pour les libellés, regular
  (`Fonts.DisplayText`) pour le texte courant (Infos, champ du Feedback, noms du classement). Titillium n'est plus
  utilisé par les écrans.
- **Filets** : os à 0,88 de transparence, partout (lignes des Réglages et des commandes).
- **Ombre décalée** : 3 px au plus sous 50 px de texte ; à 5 px, « CLASSEMENT » se lisait en double.
- **Mêmes mots pour les mêmes chiffres** : KILLS, MORTS, K/M au classement comme sur la fiche de statistiques.
- **Rien de penché dans le HUD** : le compteur de vitesse est droit depuis #308 (il répondait au titrage penché de
  l'accueil, disparu en #117).

Piste écartée (#308) : le rapport « Industrial Competitive 2.0 » (PDF joint à l'issue, écrit sans accès au jeu) proposait
des panneaux graphite partout, le jaune pour la sélection, Barlow Condensed et Inter. L'utilisateur a gardé la palette
(os, ambre, rouge d'impact), Oswald et l'absence de panneau, et n'a repris que l'idée d'unifier les états. Les lots
fonctionnels du rapport (HUD, aides de touches, responsive) ont leurs propres issues.

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
- Pour une scène inventée : composer d'abord une image (plans, échelle, silhouette) dans une planche de rendus Blender, la
  faire choisir, puis seulement la construire dans Roblox. Pour une scène prise dans la map : chercher le cadrage
  directement dans Studio (`screen_capture` avec position et visée), le personnage posé à la main.

## Comment c'est construit

- `src/client/ui/MainMenu.luau` : accueil (titre, onglets, fiche de statistiques, écran d'équipement ; rien ne se
  tire). **Écran d'équipement (#280, disposition de #308, `src/client/ui/EquipmentScreen.luau`)** : l'onglet ARMES le
  porte. **Disposition validée par l'utilisateur en #308**, d'après une capture d'un écran de choix d'arme d'un autre
  FPS, prise pour sa disposition et non pour son style (palette et police inchangées). Tout tient à gauche, le personnage est au tiers droit (`MenuScene`, section « Menu : accueil sur la map »).
  De haut en bas : « ÉQUIPEMENT » puis l'emplacement actif en Oswald gras 52 px à ombre, suivi de l'étiquette ambrée
  « EMPLACEMENT n » ; à droite du titre, rendu texturé de l'arme montrée (`UIKit.weaponSilhouette` avec `textured`, un
  `ViewportFrame` par viewmodel, gardé) ; nom « AWP / D'ORIGINE » avec l'étiquette « ÉQUIPÉ » pleine en rouge d'impact,
  ou « CLIC POUR ÉQUIPER » en contour quand l'arme survolée ne l'est pas, catégorie de l'arme dessous ; onglets
  « 1 · SNIPER » et « 2 · COUTEAU » (`MenuShot.boxChoice` : actif en boîte ambrée à texte sombre, survol en rouge
  d'impact) ; grille de
  cartes sur quatre colonnes : une rangée d'armes possédées, puis « SKINS · ARME » et une rangée de skins (silhouette,
  nom, coche et trait rouge d'impact sur l'équipé, contour rouge au survol). Les cases restantes d'une rangée sont
  vides et barrées d'une croix : elles tiennent la grille tant qu'il y a une ou deux armes. Aide en bas à gauche,
  touches en boîte (« MOLETTE » emplacement, « CLIC » équiper, « ENREGISTRÉ AUSSITÔT »). **Plus de stats d'arme**
  (barres dégâts, cadence, précision retirées en #308 : inutiles tant qu'aucune autre arme n'est prévue).
  Un clic sur un onglet, sa touche (réglée dans TOUCHES, 1 et 2 par défaut) ou la molette (sens réglé, coupée sur
  AUCUNE) changent d'emplacement actif (SNIPER à l'arrivée et au retour sur l'accueil). Le personnage tient l'arme de
  la carte survolée, sinon celle de l'emplacement actif ; le nom et le rendu suivent. Un clic équipe : remote
  `EquipItem`, l'écran ne change qu'à la réponse du serveur (attribut `EquippedItems`, les deux attributs posés
  ensemble ne déclenchent qu'une mise à jour, `LocalInventory.onChanged` différé), pas d'affichage optimiste. **Seuls
  les items possédés apparaissent**, jamais grisés ni verrouillés. Piège : le fond de coin (`cornerScrim`
  « BottomLeft ») est créé après la colonne de gauche ; à ZIndex égal il passait devant et voilait la grille, il est
  donc en ZIndex 0. Non traité : en 4:3, la grille passe sur le personnage.
  Pistes rejetées : liste en texte seul qui s'ouvre au clic sur un emplacement (premier rendu de #280, refusé :
  « quand il faut deviner quelque chose en UX c'est une mauvaise chose ») ; armes puis skins en deux temps avec retour
  « ‹ ARMES » ; emplacements à gauche et liste à droite du personnage (#280, remplacé en #308). **Libellés ambrés :
  16 px gras à ombre** (`UIKit.accentLabel`) ; à 13 px avec contour noir, l'utilisateur les trouvait illisibles (la
  taille plus que la couleur). Les onglets sont dans leur propre `ScreenGui` (`MenuTabs`, DisplayOrder 4), au-dessus des écrans
  secondaires, avec le titre du jeu (« SURF FFA », « COMBAT DE SURF »), affiché sur toutes les pages (#308). **Onglet
  ouvert en os vif souligné d'ambre** (#308) : avant, JOUER était le seul onglet marqué (plus gros, souligné de
  rouge) et l'onglet ouvert à peine plus clair, on ne savait pas sur quelle page on était. JOUER reste plus gros,
  sans soulignement. Sous les onglets, un message ponctuel (`MainMenu.showNotice`, 5 s, rouge d'impact à ombre) explique un
  retour au menu imprévu, par exemple une apparition impossible (#219) ; rendu provisoire, pas encore validé.
- **Fiche de statistiques (#301, `src/client/ui/StatsCard.luau`)** : sur l'accueil (pas d'onglet en plus, choix de
  l'utilisateur), en bas à droite sous les pieds du personnage (#308 : la grille d'équipement occupe la gauche, la
  fiche prend la place des stats d'arme de la référence), sur un fond de coin (`cornerScrim` « BottomRight »). Cinq
  colonnes séparées par des filets comme les onglets : chiffre os à ombre (Oswald 28 px), libellé ambré dessous (KILLS,
  MORTS, K/M, ROUNDS, VICTOIRES). Lue dans l'attribut informatif `PlayerStats` du Player (`StatsRules.ATTRIBUTE`, posé
  par `StatsStore` une fois le stocké lu puis à chaque kill, mort et fin de manche ; jamais relu par le serveur, pas de
  remote). Attribut absent (chargement en cours, ou en échec : Studio sans accès aux API) : « — » partout
  (`HUDRules.STATS_UNKNOWN`), jamais des zéros présentés comme vrais. Mise en forme dans `HUDRules.statsView` (testée,
  client : le module partagé `StatsRules` ne garde que l'attribut) : ratio du classement (`formatKD`, sans mort il vaut
  les kills, sans décimale à partir de 100), compteurs en chiffres complets sous 10 000 (espace des milliers dès 1 000)
  puis abrégés et tronqués (« 12.3k », « 1.2M »). Les kills et morts face aux bots ne comptent pas
  (`ParticipantRules.killCountsInStats`) : la fiche ne suit donc pas le classement d'une manche jouée contre des bots.
- `src/client/ui/MenuPage.luau` : gabarit des écrans secondaires (Réglages, Infos, Feedback, menu en partie), sans
  panneau : bloc centré de 780 px (`page.block`, cotes exportées : `BlockWidth`, `PageTitleY`, `TabsY`, `ContentTop`,
  `ContentBottom`) sur le voile du classement. Choix de l'utilisateur en #117, confirmé en #308. Titre centré (Oswald
  gras 40 px à ombre), toujours affiché : au menu sous les onglets, en partie sous le timer du round, resté visible
  au-dessus du voile (#220). `page.tabs(titres, onSelect)` : onglets en boîte centrés sous le titre, renvoie de quoi
  marquer l'actif ; `page.action(texte, action)` : actions en bas au centre, dans l'ordre des appels ; `page.choice` :
  choix en texte, os atténué au repos, os vif une fois choisi (`setSelected`), rouge d'impact au survol.
  `MenuPage.followTopbar` et les cotes `Edge`, `TitleY`, `TitleSize` servent à la colonne de gauche de l'accueil.
- Réglages (`SettingsMenu.luau`) : catégories en onglets en boîte sous le titre (#308 ; avant, colonne à gauche avec
  barre ambrée sur l'active, disposition C de #117), lignes de 46 px sur toute la largeur du bloc (nom, contrôle,
  valeur os à ombre, filet). Place : 9 lignes au plus par catégorie avant les actions (`MenuPage.ContentBottom`), pas de
  défilement ; une section qui ne tient pas devient une catégorie (VISEUR, #251). Un curseur sans décimale donne des
  entiers (px du viseur) ; les autres gardent leur précision (ne pas arrondir : les sensibilités déjà sauvegardées
  changeraient au chargement). Contrôles : curseur (trace continue, poignée en pastille os, rouge au survol ; une barre segmentée ferait perdre
  la précision de la sensibilité) et choix fermé « ‹ VALEUR › ». RÉTABLIR remet la catégorie affichée à ses valeurs par
  défaut. Ajouter un réglage : une ligne dans `buildCategories` (avec son champ dans `PlayerSettings` pour qu'il soit
  conservé) ; une catégorie sans réglage n'est pas créée.
  TOUCHES (#100) : chaque ligne nomme l'action et la valeur donne le geste (choix de l'utilisateur : « Arme suivante :
  MOLETTE BAS », pas « Molette vers le haut : PRÉCÉDENTE »). « Arme suivante » (MOLETTE BAS par défaut) et « Arme
  précédente » (MOLETTE HAUT) portent le même réglage et se suivent ; AUCUNE coupe la molette. Les gestes de molette
  s'affichent en icônes (#254, `UIKit.mouseIcon`, option `icon` de `addPicker`) : souris dessinée en Frames (contour,
  molette pleine), chevron au-dessus (vers le haut) ou en dessous (vers le bas), en os à ombre de 1 px (à 2 ou 3 px le
  chevron se lit en double ; corps de 14x20 px : plus large, la souris passait pour un œuf) ; AUCUNE reste en texte. L'icône
  « clic molette » (`wheelClick`, sans chevron) existe mais ne sert pas : le clic molette n'est pas une touche proposée.
  L'aide de l'équipement et Infos > COMMANDES gardent « MOLETTE » en boîte. Puis une ligne par emplacement
  (#280 : « Arme 1 · AWP », « Arme 2 · KA BAR », nommées d'après l'arme équipée, renommées quand l'équipement arrive ou
  change). On clique sur la touche, elle affiche « APPUIE… », la
  touche suivante est prise ; Échap ou un clic ailleurs annule. Une touche d'un autre emplacement est échangée ; une
  touche du jeu (déplacement, R, F, P, F3/F4…) ou hors liste (Espace, Maj, Tab…) est refusée par un message en rouge
  d'impact sur la ligne. Seules les lettres, les chiffres du haut et les touches F sont proposées : libellés courts dans
  la barre d'armes. RÉTABLIR remet molette et touches ensemble.
- Menu en partie (`InGameMenu.luau`, #157) : la touche `PlayerSettings.MENU_KEY` (P, seule constante de cette touche :
  réservée pour la barre d'armes, rappelée dans Infos) ouvre en partie un écran `MenuPage` titré « MENU » : colonne
  centrée de choix en texte (taille 40) REPRENDRE (os vif), RÉGLAGES, puis MENU PRINCIPAL écarté ; aide en bas au
  centre, touche en boîte : « P REPRENDRE », puis « LA PARTIE CONTINUE ». RÉGLAGES remplace l'accueil par l'écran Réglages (présentation `modal`,
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
  désactivé) ; un clic déclenche l'action, sans tir. JOUER (`locks`) bloque ensuite tous les choix jusqu'à `MenuShot.reset`.
- `src/client/ui/MenuCursor.luau` : souris système réimposée à chaque image tant que le menu est ouvert.
- `src/client/systems/game/MenuScene.luau` : accueil sur la map (#253, section dédiée plus bas).
- `src/client/systems/game/MenuSceneRules.luau` : règles pures testées (`tests/specs/MenuSceneRules.spec.luau`).
- `src/client/ui/Transition.luau` : volets blancs ; JOUER les ferme aussitôt (#253 : plus d'explosion avant).
- `UIKit.shadowedText` : texte os doublé d'une ombre noire décalée, commun au HUD et au menu. `UIKit.accentLabel` : libellé
  ambré du menu (16 px gras, même ombre, sans contour, #280).
- CoreGui Roblox désactivés dans `init.client.luau` : `PlayerList`, `Backpack`, `Health` (#307 : la barre de vie native
  apparaissait au premier dégât, au-dessus du kill feed, et restait jusqu'au menu). Pas d'affichage de la vie dans le HUD
  pour l'instant (choix de l'utilisateur) ; s'il en faut un, le brancher sur `HUDRules.gameHudVisible`.
- `src/client/ui/Speedometer.luau` : compteur de vitesse, en bas à gauche, en miroir du compteur de munitions : chiffres os droits de 72 px avec ombre noire décalée, alignés à droite d'une case fixe (le palier et l'unité ne bougent pas), nom du palier et « U/S » ambrés à droite, bande ambrée horizontale crantée aux seuils, tout passe au rouge d'impact au dernier palier (`HUDRules.speedTier`, `speedFill`). Sur un fond sombre sans bord : image de dégradé de coin (`tools/ui/make_corner_scrim.py`, `assets/ui/hud/`) teintée par `ImageColor3`. Jusqu'à #308 : piste « Titrage », chiffres de 92 px penchés de -6° et bande en biais (`UITheme.Layout.HudLean`, retiré).
- `src/client/ui/WeaponBar.luau` : barre d'armes en bas à droite, en miroir du compteur ; remplace le Backpack Roblox
  (`CoreGuiType.Backpack` désactivé dans `init.client.luau`). Par arme : silhouette plate tirée des MeshParts de son viewmodel
  (bras exclus) dans un `ViewportFrame` blanc teinté par `ImageColor3`, nom et touche. L'arme en main est en os, avec son
  numéro et un trait en rouge d'impact, les autres sont grisées ; toute la barre (fond compris) disparaît 2,5 s après le dernier changement d'arme
  (`HUDRules.WEAPON_BAR_FADE_DELAY`). Deux emplacements depuis #280 (le sac ne contient que l'arme équipée de chacun),
  dans l'ordre `InventoryRules.SLOTS` : 1 · SNIPER, 2 · COUTEAU (`HUDRules.slotOrder`).
  Équipement : touches des emplacements (1 et 2 par défaut) et molette (vers le haut = arme précédente par défaut),
  réglables dans Réglages > TOUCHES (#100) ; toucher d'un emplacement, L1/R1 à la manette (fixes). La barre ignore
  touches et molette pendant que le menu en partie est ouvert (`InGameMenu.isOpen`, Réglages compris).
- `src/client/ui/AmmoCounter.luau` (#158) : « chargeur / réserve » en bas à droite, à gauche de la barre d'armes (chiffre du
  chargeur os à ombre, réserve atténuée, libellé ambré « MUNITIONS » à contour noir (`TextStroke`, transparence 0,35 ; #247 :
  sans contour, illisible sur rampe claire), chargeur vide en rouge d'impact). Son emprise (`HUDRules.AMMO_BOX`) sert aussi à placer l'affichage des touches. Lit
  `WeaponSystem.getAmmo` à chaque Heartbeat (met à jour les textes seulement si les valeurs changent), masqué sans
  chargeur (couteau) et hors partie (`HUDRules.gameHudVisible`, via `GameStateController.applyGameHud`). Contrairement à
  la barre d'armes, il ne s'estompe pas.
- Réglage « Auto-bhop » (#255) : catégorie MOUVEMENT de `SettingsMenu` (une seule ligne, ACTIVÉ par défaut), `PlayerSettings.autoBhop`, lu à chaque tick par `MovementController` et passé à `BhopSystem` : sans respawn.
- Réglage « Conseils » (#291) : catégorie GRAPHISMES de `SettingsMenu`, juste sous « Affichage des touches » (les deux
  aides affichées à l'écran côte à côte), ACTIVÉS par défaut, suivi par RÉTABLIR ; `PlayerSettings.deathTips` (absent d'un
  réglage sauvegardé = activés). Coupé, l'écran de mort d'un débutant n'affiche plus de conseil ; sans effet pour les autres.
- `src/client/ui/Crosshair.luau` (#195) : réglage « Visée simplifiée » (Réglages > VISEUR depuis #251, `PlayerSettings.simpleAim`, coupé par
  défaut). Par défaut, quatre traits fins os (longueur 9 px, épaisseur 2, écart 5) sans point central, doublés d'un contour
  noir de `OUTLINE` 1 px (`OUTLINE_TRANSPARENCY` 0,1) : sur fond blanc seul le contour se lit, sur sol ou mur sombre le trait os.
  **Viseur personnalisé (#251)** : catégorie VISEUR des Réglages, « Visée simplifiée » en tête (l'interrupteur), puis couleur
  (palette fermée `UITheme.CrosshairPalette` : os, blanc, ambre, rouge d'impact, vert, cyan ; libellé du choix dans sa
  couleur), longueur 2 à 20 px, épaisseur 1 à 6, écart central 0 à 15, point central, contour, opacité 0,20 à 1 (pas
  d'invisible). Bornes et défauts : `PlayerSettings.CROSSHAIR` (défauts = rendu d'origine), validés par `sanitize` (px
  entiers, couleur hors palette refusée). L'opacité vaut pour le trait et le contour. RÉTABLIR remet le style d'origine
  sans couper la visée simplifiée. Aperçu à droite des lignes de la catégorie, plus étroites que celles des autres catégories (#308 ; avant, sous la
  colonne des catégories, d'où #305), dans son conteneur : deux cases l'une sous l'autre (sable clair, sombre) où `Crosshair.draw`
  trace le viseur à sa taille réelle en px (le `UIScale` de l'écran est compensé par un `UIScale` inverse lu dans
  l'attribut `Scale` de `UIKit.scaledRoot`). En jeu, le crosshair se redessine dès que son style change (clé
  `Crosshair.styleKey`), sans respawn.
  Taille fixe en pixels, pas de `scaledRoot`. `ScreenGui` en `ScreenInsets.None` pour tomber sur le centre exact de la caméra,
  comme la lunette. Affichage = `HUDRules.crosshairVisible` appliquée à `HUDState` (voir « État du HUD ») : réglage actif, HUD de
  jeu visible (donc ni menu, ni mort, ni résultat), lunette absente et menu en partie fermé.
  Toutes les armes, couteau compris. Piste rejetée : point rouge central (criard, hors de la matière du HUD).
  Branches tracées par `Reticle.drawArms` (#222), comme le réticule de la lunette (`ScopeOverlay`) : quatre branches à
  `gap` px du centre, longueur en px ou en part du parent, contour de `outline.width` px par côté ; bouts ouverts
  (lunette) : couche plus large posée dessous, sur laquelle joue l'estompe `fade` ; crosshair (`pixelAligned`) : traits
  sur des px entiers (épaisseur impaire : un px de plus en bas ou à droite de l'axe, branches droite et basse décalées
  d'un px pour garder l'écart symétrique ; des demi-px seraient arrondis frame par frame et décolleraient le contour ;
  le `Root` du crosshair reste centré en part de l'écran : un `ScreenGui` désactivé garde une `AbsoluteSize` périmée,
  800x600, un centre calculé en px tombait hors du centre ; avec la mise à l'échelle d'affichage de Windows, un px
  d'interface n'est de toute façon pas un px physique), contour en cadre qui ferme les bouts, rien dessous (#251 : avec un contour dessous,
  baisser l'opacité assombrissait le trait au lieu de le rendre translucide). Point central `dot` en option. Limite connue : à opacité réduite et écart central
  inférieur à environ épaisseur / 2 + 2 px, branches, point et contours se superposent au centre et y paraissent plus
  opaques. Un nouveau réticule passe par là.
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
  compteur et les munitions ; en 16:9, 12 px de marge côté munitions avec le mode `full`.
  **Écran étroit (#247, choix de l'utilisateur) :** la grille garde sa taille et remonte au-dessus du compteur de munitions
  quand elle l'atteindrait (`HUDRules.keyDisplayBottom` : bord droit de la grille + `KEY_DISPLAY_CLEARANCE` 12 px au-delà du
  bord gauche de `AMMO_BOX`, en px du repère `scaledRoot`). Seuil en largeur de ce repère : 1 252 px en `full`, 1 120 px en
  `simple`. Soit, pour une fenêtre de 540 à 1 152 px de haut (échelle de `scaledRoot` non bornée par 0,75 et 1,6), un ratio de 1,74 en `full` (16:9 inchangé,
  16:10 et 4:3 remontent) et 1,56 en `simple` (16:10 reste, 4:3 remonte) ; hors de ces hauteurs, le seuil suit la largeur. Replacée au redimensionnement (`AbsoluteSize` du `ScreenGui`, lu après la mise à jour de `scaledRoot`).
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
  les touches réservées de `PlayerSettings`. Une nouvelle action : sa liaison dans `KeyBindings`, sa case dans la grille (et dans `CAP_MODIFIERS` de `KeyDisplay` si sa touche est ambrée).
  Les cases suivent les touches physiques, pas l'action disponible : F et M2 s'enfoncent aussi avec une arme sans inspection
  ni lunette ; clavier ignoré pendant la saisie de texte (`GetFocusedTextBox`), pas de suivi du `gameProcessed` (piste non retenue,
  elle demandait un état par touche au lieu d'un sondage).
  Affichage (`HUDRules.keyDisplayVisible` appliquée à `HUDState`) : mode actif, HUD de jeu visible, menu en partie fermé ; la
  lunette ne le masque pas (les touches restent utiles). Mode actif : le réglage, ou `full` pour un débutant (#291,
  `HUDRules.keyDisplayMode`), le réglage sauvegardé restant intact.
  Vérifié en Studio avec `user_keyboard_input` (`keyDown` W/D/S/Espace/Ctrl/R passent en partie et enfoncent les touches) ; le clic de
  souris M1/M2 n'a pas été simulé. Coordonnées de clic des onglets du menu : y négatif (`AbsolutePosition` du bouton).
- `src/client/ui/RoundHUD.luau` : timer et rang en haut au centre (chiffres os droits avec ombre, libellés ambrés, fondu
  sombre de bord (`cornerScrim` « Top »), timer en rouge d'impact sous 30 s) ; classement sous Tab : pas de panneau, voile sombre
  central qui s'efface vers les côtés, titre « CLASSEMENT » sur un filet ambre, colonnes KILLS / MORTS / K/M (les mots de la fiche de statistiques,
  #308), ligne du joueur
  sur une bande rouge d'impact **droite** (penchée, elle se lisait mal en face des colonnes).
  Menu en partie ouvert (#220, choix de l'utilisateur : la partie continue derrière) : le timer et son fondu (calque
  `TimerLayer`) passent dans un `ScreenGui` à part (`RoundTimerOverMenu`, DisplayOrder 4, au-dessus du voile 2 et de la
  page 3), selon `HUDRules.roundTimerOverMenu` ; le titre « MENU » / « RÉGLAGES » est dessous. Menu fermé, le calque
  revient dans `RoundHUD` en ZIndex 0, sous les voiles du classement et du résultat comme avant.
  Réapparition : la scène reste visible, désaturée (`ColorCorrectionEffect`), sans voile plein ; en bas au centre, sur
  un fondu de bord (`cornerScrim` « Bottom »), « ÉLIMINÉ » en rouge d'impact (le joueur a été touché), compte à rebours en gros
  chiffres os à ombre, libellé ambré « RÉAPPARITION ». Au-dessus du compte à rebours (#102) : « ÉLIMINÉ PAR », nom du
  tueur en os, arme et « TÊTE » en ambre ; sans tueur, « ÉLIMINÉ » puis « CHUTE ». La caméra reste au lieu de la mort
  et pivote vers le tueur, marqué d'un losange et de « NOM · distance » en rouge d'impact (`DeathCamera`).
  Débutant (#291, conseils non coupés) : sous « RÉAPPARITION », une ligne de conseil en texte courant (Oswald regular,
  18 px, os), son thème en ambre (« SURF : », « BHOP : », « AIR STRAFE : »), plus large que le bloc (680 px) ; le
  bloc remonte d'autant et le fondu de bord s'agrandit (780x270 au lieu de 520x230). Rien de plus pour les autres.
- `src/client/ui/KillFeed.luau` (#102) : en haut à droite, sans fond, une ligne par mort (tueur et victime en os, arme
  en ambre plus petite), 4 lignes, 5 s chacune ; les lignes du joueur sont sur une bande rouge d'impact droite qui
  s'efface vers la gauche, comme sa ligne au classement. Affiché vivant ou mort (`HUDRules.killFeedVisible`), pas au
  menu ni au résultat.
  Fin de round : voile central du classement, « ROUND TERMINÉ » ambré, nom du vainqueur en os géant, filet ambre,
  « REMPORTE LE ROUND » ; le rouge d'impact n'apparaît que si le joueur gagne (bande derrière son nom). Sans vainqueur
  (#295) : « AUCUN VAINQUEUR » (aucun kill) ou « ÉGALITÉ » (mêmes kills et mêmes morts en tête) à la place du nom, sans
  sous-titre. Dessous, le podium (3 premiers) puis, après un écart, la ligne du joueur s'il n'y est pas : ce sont les
  lignes du classement de Tab (`scoreRow`, en-têtes `columnHeaders`, tri `HUDRules.sortScores`), pas un second dessin.
  Pas de classement complet à la fin : Tab maintenu remplace l'écran de fin par le classement, rendu au relâchement
  (jamais l'un sur l'autre). Contenu composé par `HUDRules.readRoundResult` (nom du vainqueur résolu par son id dans les
  scores de `RoundResult`) ; ordre et issue de la manche dans `src/shared/ScoreRules.luau`, communs au serveur.
- `UIKit.cornerScrim` : fond de coin du HUD (`assets/ui/hud/scrim_coin.png`) dans les quatre orientations, par rotation ;
  `Top` / `Bottom` : fond centré sur un bord (`scrim_bord.png`, `make_corner_scrim.py --edge`), `size` = largeur totale.
  Rien n'est penché dans le HUD depuis #308 (le compteur de vitesse l'était, de -6°).
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

## Démos rejouées (écran Apprendre, #285)

**Où :** écran Apprendre (`LearnScreen`), onglet APPRENDRE du menu principal, juste avant JOUER (on apprend le geste,
puis on joue ; JOUER n'est plus pile au centre avec six onglets). Rien au premier lancement. Le lecteur 640x360 (16:9)
seul, sa légende en une ligne dessus ; pas de texte dessous : l'ancien texte de SURFER (`surfLines`) expliquait le surf,
pas le bhop montré, il a été retiré (2026-11-14). Pas d'onglets : le contenu commence à leur hauteur. Page du menu comme Feedback, pas un état de jeu comme Infos ; le lecteur est libéré à RETOUR, à un autre onglet
et au départ en partie (`SPAWNING`, `IN_ROUND`).
- Déplacé d'Infos (onglet SURFER retiré, Infos s'ouvre sur COMMANDES) : Infos sert de référence, pas de tuto.
- L'écran de mort renvoie à la démo : les conseils BHOP et AIR STRAFE finissent par « Démo : APPRENDRE. »
  (`InfosRules.DEMO_POINTER`), en texte (souris verrouillée pendant la mort ; une mini-démo sur l'écran de mort coûterait
  la copie de la map à chaque mort). Mode entraînement (rejouer soi-même le geste) : #345.

**Une seule démo : BHOP** (le geste montre aussi l'air strafe). Prise jouée par l'utilisateur avec l'auto-bhop (Espace tenu), Q/D en tournant la
souris du même côté, vitesse de 25 à 126 en 15 s. Surf et enchaînement abandonnés le 2026-11-14 : Dizzy n'a pas de
rampe assez longue pour une démo lisible (une rampe se traverse en 2 s environ). Ils pourront revenir avec une autre map :
le code reste générique (`InfosRules.demoClips` renvoie une liste ; à partir de deux démos, un sélecteur en choix de
texte apparaît, la démo choisie en os vif soulignée d'ambre, gardée d'une ouverture à l'autre : les onglets d'Infos sont
déjà en boîte ambrée juste au-dessus, deux boîtes pleines empilées disaient deux fois « là où je suis »). Piste écartée :
un bhop joué par entrées simulées (MCP) ; la prise humaine était déjà propre (98 % des virages dans le sens de la touche).

**Pas de vidéo :** un clip est une trajectoire enregistrée dans Studio puis rejouée dans le moteur.
- Données : `src/client/ui/DemoClips/<Nom>.luau` (aujourd'hui `Bhop`), un module qui renvoie le texte du
  clip. Format `DemoClipRules` : en-tête `CLIP 1 <hz> <map>`, puis une ligne d'entiers par échantillon (30 Hz) : écarts
  avec l'échantillon précédent de x, y, z de la racine, hauteur des yeux, lacet et tangage de la caméra (centièmes de
  stud ou de degré, écarts pris entre valeurs arrondies : pas de dérive), masque des touches (avant, gauche, arrière,
  droite, saut, accroupi), vitesse horizontale x 10. Environ 25 octets par échantillon, 9 Ko pour 12 s. Un module absent
  ou illisible affiche « CLIP À ENREGISTRER ».
- Souris : lue dans la rotation du lacet (degrés par seconde, lissée sur ± 2 échantillons), pas dans le delta brut de
  la souris : l'indicateur ne dépend pas de la sensibilité de celui qui a enregistré. Plein à 400°/s
  (`DemoClipRules.TURN_FULL`), rouge d'impact au-delà de 75 %.
- Lecteur (`DemoPlayer.luau`) : `ViewportFrame` contenant une copie des pièces visibles de la map (`Workspace.Maps.<map
  du clip>`) à moins de 450 studs des trajectoires de tous les clips, copiée sur plusieurs images à la première lecture
  (Dizzy : 16 365 pièces en 0,43 s dans Studio, quasiment toute la map), gardée tant que l'onglet est ouvert. Caméra du
  viewport au FOV du jeu (`CameraConfig.DEFAULT_FOV`), même composition lacet puis tangage que `FPSCamera`. Position et
  angles interpolés par Catmull-Rom entre échantillons (pas de saccade à 60 i/s), touches sans interpolation. Boucle avec
  fondu au noir de 0,35 s de part et d'autre du raccord, trait d'avancement ambré au bas du cadre. Le personnage, la
  caméra et la map du joueur ne sont pas touchés.
- Par-dessus : légende (nom du geste en ambre, geste en une ligne, `InfosRules.demoClips`, touches selon le clavier du
  joueur), vitesse au style du compteur (`HUDRules.speedTier` / `speedFill`), touches en keycaps du HUD
  (`KeyDisplay.buildKeycap`, mode simple : directions et saut, à 80 %), souris (icône et demi-barre du côté où elle tourne).
- Libération : `InfosScreen` détruit le lecteur (cadre, copie de la map, boucle de rendu) dès qu'on change d'onglet ou
  qu'on quitte l'écran. Vérifié : 0 `ViewportFrame` et 16 476 Instances de moins après RETOUR.
- Éclairage du viewport (pas d'ombres portées ni de ciel dans un `ViewportFrame`) : `Ambient` (190, 178, 190),
  `LightColor` (255, 214, 170), `LightDirection` opposée au soleil de `Lighting`, ciel en dégradé sous le viewport. Avec
  l'éclairage par défaut (150, 146, 140), la scène était presque noire.
- Coût mesuré (Studio, qualité auto 1/10, menu principal, overlay F3, bilans de 10 s, repère `démo infos`) : lecteur
  ouvert CPU 3,9 à 4,6 ms, GPU 7,2 à 8,6 ms, boucle du lecteur 0,04 à 0,05 ms par image ; fermé CPU 3,7 ms, GPU 3,1 ms.
  Soit environ 4 à 5 ms de GPU tant que la démo est affichée, rien après. Copie du décor : 17 443 pièces en 0,30 s.
  Image la plus longue : 51 ms à l'ouverture, 131 ms dans la période de la fermeture (un seul relevé, cause non isolée).

**Refaire un clip :**
1. Studio réservé, playtest lancé, partie lancée (`DebugPlaytest`), bots retirés (`workspace:SetAttribute("DebugBots", 0)`).
2. Armer l'enregistreur (contexte `Server` ou `Client`) : `game.Players:GetPlayers()[1]:SetAttribute("DebugClipRecorder",
   "surf")` (`surf`, `bhop`, `strafe` ou `chain`). Un bandeau « CLIP surf PRÊT · F7 ENREGISTRER · F6 CLIP SUIVANT »
   s'affiche en haut, et dessous la liste des clips déjà pris (« PRIS : surf 14 s · bhop — … »). **F6** passe au clip
   suivant (surf, bhop, strafe, chain) : pas besoin de la barre de commande pour changer de clip.
3. Se placer, appuyer sur **F7**, jouer le geste (10 à 20 s ; arrêt d'office à 30 s), **F7** pour arrêter. La console
   écrit `[ClipRecorder] STOP surf : … s, … échantillons`. Recommencer autant que voulu : la dernière prise remplace la
   précédente. L'enregistreur ne fait que lire (racine, caméra, `KeyBindings`, `MovementController.getVelocity`).
4. Extraire (contexte `Client`, sans écrire de `Source`) : `return game.Players.LocalPlayer.DebugClips.surf.Value`, et
   enregistrer le texte rendu tel quel dans un fichier hors du dépôt (ex. `%TEMP%\surf.txt`). À la main : barre de
   commande de Studio en contexte client, `print(...)`, puis copier la sortie.
   **Piège (#285) :** `Player.DebugClips` disparaît à l'arrêt du playtest (6 prises perdues ainsi). Chaque prise est donc
   aussi recopiée dans la sortie de Studio, qui survit à l'arrêt : lignes `[ClipData <clip> <prise> <i>/<n>] …` (morceaux
   de 2 000 caractères, sans blanc). Si le playtest est arrêté, copier la sortie (ou `get_console_output`, qui rogne le
   début d'une longue sortie : extraire au plus tôt) dans un fichier : `write_clip` reconnaît ces lignes et recolle la
   dernière prise complète du clip demandé.
5. `lune run tools/clips/write_clip.luau %TEMP%\bhop.txt Bhop [début_s] [fin_s]` : valide le clip, garde au besoin la
   partie entre début et fin, et réécrit `src/client/ui/DemoClips/Bhop.luau` (CRLF, comme StyLua).
6. Arrêter le playtest (Rojo ne synchronise qu'en mode Edit), relancer, ouvrir APPRENDRE et vérifier la démo.

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

- **Échelle du HUD (#250) :** réglage « Échelle du HUD » (Réglages > GRAPHISMES, `PlayerSettings.hudScale`, 50 à 100 %, défaut 100 %,
  pas d'agrandissement, validé par `sanitize`, facteur par `PlayerSettings.hudScaleFactor`). Une seule échelle pour les éléments de
  bord : compteur de vitesse, barre d'armes, munitions, affichage des touches, kill feed, timer et rang. Réticule, hitmarker,
  classement, réapparition et menus restent inchangés. Point d'application commun : `UIKit.scaledRoot(gui, true)` (racine « de bord » :
  `UIScale` = échelle de l'écran x échelle du HUD, `Size` = 1 / total, donc cadre toujours plein écran et éléments ancrés à leur
  bord ; l'attribut `Scale` vaut l'échelle totale, `KeyDisplay` replace sa grille dessus) et `UIKit.setHudScale` / `onHudScale`,
  alimentés par `init.client`. Un nouvel élément de bord du HUD passe par `scaledRoot(gui, true)`. Piège : le timer vit dans un
  calque plein écran partagé avec le classement et qui change de `ScreenGui` (menu en partie) ; il porte donc son propre `UIScale`
  sur une ancre sans taille au milieu du bord haut (`TimerAnchor`), un `UIScale` sur le calque ferait dériver le timer.
  `KeyDisplay` et `AmmoCounter` s'échelonnent ensemble : le calcul d'#247 (`keyDisplayBottom`) reste en px du repère commun.

- **Libellé d'une touche (#100) :** `Enum.KeyCode` désigne la position sur un clavier QWERTY. Sur un clavier AZERTY,
  `KeyCode.Q` est la touche imprimée « A » : afficher `UserInputService:GetStringForKeyCode` (`LocalSettings.keyText`),
  sauf pour les chiffres du haut, qui donneraient « & » ou « é ».
- **Piloter le vrai jeu au MCP (#195) :** un `require` dans `execute_luau` (Client) charge une copie des modules : `requestPlay`,
  `LocalSettings.update` ou `getState` n'agissent pas sur le jeu qui tourne. Lire les `ScreenGui` de `PlayerGui` (leur `Enabled`
  est réel) et passer par l'interface (`user_mouse_input` en coordonnées d'écran, soit 0,8 fois celles de `screen_capture`) ou
  par `DebugPlaytest` pour lancer la partie. Les chemins `instance_path` avec accents (« RÉGLAGES ») ne se résolvent pas, et un
  nom en double (onglet et cadre « GRAPHISMES ») est ambigu : cliquer aux coordonnées. En partie, les touches P et 1 ne
  passent pas par le MCP, mais `keyDown` / `keyUp` de W, A, S, D, Espace, Ctrl, R sont lus par
  `UserInputService:IsKeyDown` (#197) ; passent aussi (constaté le 2026-11-12) : Tab maintenu (`keyDown`, classement),
  F3 (`keyPress`, overlay de performance) et le clic droit de la lunette (`mouseButtonDown` puis `mouseButtonUp` à
  150 ms, un clic par niveau de zoom) ; les onglets du menu se cliquent à l'`AbsolutePosition` du bouton, y négatif compris
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
  Un décor de menu construit loin de la map se juge donc map chargée.
- **Curseur :** `MenuCursor` réimpose `MouseIconEnabled` à chaque image, car les autres écrans le changent en s'ouvrant ou se fermant.
- **Barre de Roblox et `scaledRoot` (#306) :** la barre du haut (logo, menu, chat, micro, `GuiService.TopbarInset`,
  environ 58 px) garde sa taille en px réels, alors que `scaledRoot` réduit l'interface jusqu'à 0,75. Un élément posé
  « juste sous la barre » en px de maquette passe donc dessous dans une petite fenêtre. Dans les coins du haut, calculer
  la position avec `TopbarInset` et l'attribut `Scale` de la racine (`MenuSceneRules.topbarShift`, colonne de gauche de
  l'accueil). Ne pas mettre `ScreenInsets.TopbarSafeInsets` sur tout le `ScreenGui` : les onglets centrés et la scène
  descendraient aussi.
- **`AbsolutePosition` avec `IgnoreGuiInset` :** elle exclut la barre du haut, contrairement à `GetMouseLocation`. Préférer
  `MouseEnter`, `MouseLeave` et `Activated` à un test de zone maison.
- **Fondu dans deux directions** (fond qui s'efface vers le haut et vers la droite) : impossible avec des `UIGradient`.
  Un `UIGradient` sur un `CanvasGroup` est ignoré ; un seul gradient en biais laisse une arête ; des calques très transparents
  empilés font des bandes visibles. Utiliser une image de dégradé blanche teintée par `ImageColor3` (voir `make_corner_scrim.py`).
- **Fond centré : une seule image (#247).** Deux `cornerScrim` collés en miroir (bord à bord, ou 1 px de recouvrement)
  laissent un filet clair à leur jonction : l'arête de chaque image est lissée (sous-pixel, `UIScale` non entier), et deux
  arêtes à moitié couvertes ne refont pas un fond plein. Un recouvrement plus large assombrit la jonction à la place. Pour un
  fond au milieu d'un bord, une seule image symétrique (`cornerScrim` « Top » / « Bottom »).
- **Libellé posé sur la scène :** un texte ambré ou atténué sans fond se perd sur une rampe claire (`AmmoCounter`, #247).
  Tout texte du HUD hors d'un `cornerScrim` prend l'ombre noire décalée (`UIKit.shadowedText`) ; sous ~16 px, l'ombre
  double les lettres (essai à 1 et 2 px, captures #247) : contour noir `TextStroke` à la place, comme le crosshair.
- **Retourner une image :** un `ImageRectSize` négatif ne retourne pas l'image dans une `ImageLabel`. Tourner l'image
  (`UIKit.cornerScrim` : 90°, 180° ou -90° selon le coin, taille permutée pour les quarts de tour).
- **Tools des armes :** ils sont presque vides (l'arme visible vient du viewmodel). Pour dessiner une arme hors du jeu
  (icône, silhouette), cloner les MeshParts enfants directs de `ReplicatedStorage/ViewModels/<Nom>`, sans les bras :
  c'est ce que fait `UIKit.weaponSilhouette` (barre d'armes, écran d'équipement), à réutiliser.
- **`CanvasGroup` interdit (#155) :** Roblox le rend dans une texture dont la résolution baisse avec la qualité graphique
  (et la mémoire) : texte flou, illisible au minimum. Sa `GroupTransparency` est aussi ignorée dans ce rendu simple : le
  groupe reste affiché. Les écrans (classement, réapparition, résultat, Infos, Réglages) sont des `Frame` ;
  `UIKit.reveal` / `UIKit.fadeIn` animent la transparence de chaque enfant (fond, texte, image, `UIStroke`) à partir des
  valeurs relevées au lancement. Un élément ajouté pendant le fondu n'est pas animé. Vérifier toute nouvelle interface à
  la qualité graphique minimale et maximale.
- **Polices :** aucune annonce officielle d'import de police trouvée (novembre 2026). Tout le texte est en polices
  Roblox (Oswald pour les titres et libellés, Titillium pour le texte courant).

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

## Captures de référence

`docs/ui/captures/` : une image par écran (menu, HUD, lunette, classement, réapparition, fin de round, menu en partie),
avec un index (`README.md` : écran, code, comment y arriver, ce qui manque). À citer dans une demande de modification,
et à refaire quand un écran change.

`screen_capture` du MCP ne rend l'image que dans la conversation (un JPG dans le dossier de résultats de l'outil, pas
dans le dépôt) : les PNG viennent de la capture de fenêtre de `tools/anim/capture_server.py`, recadrée par
`tools/ui/capture.py`. Studio réservé, playtest lancé, depuis le worktree (PowerShell) :

```powershell
$env:CAP_DIR = "$env:TEMP\csgo-ui-captures"; New-Item -ItemType Directory -Force "$env:CAP_DIR\raw"; Set-Content "$env:CAP_DIR\frames.json" '{}'
uv run tools/anim/capture_server.py "$env:CAP_DIR\raw" "$env:CAP_DIR\frames.json"   # en arrière-plan, port 34991
uv run tools/ui/capture.py place save; uv run tools/ui/capture.py place set 0 0 1655 1080   # viewport 16:9
curl.exe -s "http://127.0.0.1:34991/shot?name=_voile"; uv run tools/ui/capture.py rect _voile   # voile magenta posé, voir ci-dessous
curl.exe -s "http://127.0.0.1:34991/shot?name=menu-accueil"                           # une capture brute par écran
uv run tools/ui/capture.py crop docs/ui/captures menu-accueil                         # recadrage sur le viewport
uv run tools/ui/capture.py place restore; curl.exe -s "http://127.0.0.1:34991/quit"   # à la fin
```

- **Viewport en 16:9 :** il dépend de la disposition de Studio. Sur ce poste (1920x1080, échelle 125 %), une fenêtre
  de 1655x1080 donne 1349x759 px ; ailleurs, ajuster la largeur jusqu'à un ratio de 1,778 (affiché par `rect`).
- **Repérer le viewport :** en contexte `Client`, poser un `ScreenGui` plein écran (`IgnoreGuiInset`, `ScreenInsets.None`,
  `DisplayOrder` 10000) avec un `Frame` magenta (255, 0, 255), capturer, lancer `rect`, puis le détruire.
- **Curseur :** le curseur simulé par `user_mouse_input` (une main jaune) apparaît dans l'image. Au menu, le garer en
  bas de l'écran (`moveTo` 540, 547) avant de capturer ; en partie, écarter les images où il traîne.
- **Éléments brefs** (barre d'armes 2,5 s, réapparition 2,5 s, fin de round 6 s, volets) : un appel MCP prend 5 à 10 s,
  trop pour viser une image. Lancer d'abord une rafale en arrière-plan (boucle de `/shot` toutes les 0,3 à 1 s), puis
  déclencher l'action, et choisir sur une planche (`capture.py sheet`). Une manche dure 5 min : le timer court pendant
  qu'on réfléchit.
- **Studio en arrière-plan tourne à ~15 i/s** (mesuré : 15,5 i/s, bots figés ou non ; `capture.py focus` dit qui a le
  focus). À cette cadence le viewmodel quitte l'écran dès que la caméra tourne, et n'y revient qu'au rééquipement
  (modèle retrouvé à un million de studs ; cause probable : le ressort du balancement de `ViewmodelSystem`, instable
  sous ~22 i/s, non vérifié par un test dédié). Pour un HUD avec l'arme : lancer la partie par le bouton JOUER et
  équiper côté serveur (`Humanoid:EquipTool`), caméra immobile. `DebugPlaytest` tourne la caméra (étape AIM) : l'arme
  disparaît juste après son run.
- **Écrans à déclencheur :** classement = `keyDown` Tab, capturer, `keyUp` ; lunette = clic droit ; menu en partie =
  attribut `DebugInGameMenu` (le remettre à `false` avant de le reposer à `true`) ; message d'apparition impossible =
  `workspace:SetAttribute("DebugSpawnFail", true)` (contexte `Server`) puis JOUER, il n'arrive qu'après 30 s
  (`SpawnRequestRules.GIVE_UP_AFTER`) ; réapparition = retirer `DebugBotsPassive` et attendre un bot.
- Les captures montrent les réglages enregistrés du compte qui joue : le préciser dans l'index.

## Menu : accueil sur la map (#253)

**Choix de l'utilisateur** (référence : l'accueil de CS2, un personnage en pied dans une rue de la map) : le personnage
du jeu, de face et en grand au centre, tient l'arme choisie dans le menu, sur une copie de la map ; caméra à hauteur
d'homme. Copie figée et isolée plutôt que la vraie map en direct (pas d'affichage de la partie en cours) ; JOUER ferme
les volets tout de suite.

**Construction** (`MenuScene.luau`, tout local au client, construit à la première ouverture puis gardé hors du
workspace pendant la partie) :
- Plan par map dans `SHOTS` : pieds du personnage, son regard, distance et hauteurs de la caméra, décalage latéral.
  Dizzy : couloir du toit haut entre le grillage et le mur à bande bleue (au-dessus de la rampe ouest), regard vers le
  couchant, le couloir fuit derrière lui. Map sans plan : devant le premier point d'apparition au sol.
- Copie : pièces visibles de la map jouée dans le cône de la caméra (`MenuSceneRules.inView`) ou toutes proches,
  clonées sans physique ni requête (`CanQuery` coupé) et décalées de `OFFSET` (5 000 studs en Z). Sur Dizzy : 14 300
  pièces sur 17 500 visibles, car les murs cachent la map mais ne la retirent pas du cône. Copier toute la map visible
  coûte environ 0,2 s de clonage et 0,1 s d'ajout au workspace (mesuré en Studio) : on n'a pas filtré davantage.
- Personnage : `StarterCharacter` cloné, skin commun (`CharacterAppearance.apply`), sans script, racine ancrée. Arme :
  modèle 3P du jeu (`WeaponThirdPerson.attach`), sorti du rendu des armes 3P (tag retiré) pour garder la tenue du menu.
  Tenues (`MenuPoses.luau`, générées par `tools/anim/poses3p/export_pose.js`, tenues M1 et M2 de `poses.js`) : AWP en
  travers du torse, canon vers le haut à gauche du personnage, avec sa propre prise ; couteau le long du corps, lame
  vers le bas, avec la prise du jeu (même inclinaison que la garde C1). Articulations posées par `C0` (aucune piste ne
  tourne sur ce personnage), respiration de la taille (`breathAngle`).
- Armes : Tools possédés (#267, `LocalInventory`) de `ReplicatedStorage.Tools` (attribut `WeaponName`). L'écran
  d'équipement (#280, `MainMenu`) choisit l'arme tenue (`MenuScene.holdTool`) : survolée, sinon équipée de l'emplacement
  choisi ; la fiche suit. Les skins ne sont pas encore rendus sur le modèle (#268).
- Caméra : fixe, FOV vertical 40° en 16:9 (ouvert sur un écran plus étroit, `fitFov`), léger suivi du curseur
  (`aimAngles`). Depuis #308 elle est tournée de 20° vers la gauche (`CHARACTER_YAW`) : le personnage passe au tiers
  droit de l'image et laisse la gauche à l'écran d'équipement. Un lacet plutôt qu'un décalage (`shift`) : la caméra
  ne bouge pas, elle ne risque pas d'entrer dans un mur du couloir. Hors de l'onglet ARMES, le lacet revient à 0 en
  douceur (`MenuScene.setCentered`, appelé par `MainMenu.setPage`) : le personnage repasse au centre, derrière le bloc
  de l'écran ouvert. Flou du fond : `DepthOfFieldEffect` posé sous la caméra le temps du menu.
- Éclairage : celui du jeu, plus une **lumière de portrait** (SpotLight chaud devant le personnage, du côté du soleil).
  Avec un soleil à 1,4° au-dessus de l'horizon, les bords du toit ombrent tout le couloir : sans elle le personnage
  est sombre. Piège : juste après le lancement, les ombres ne sont pas encore calculées et le personnage paraît au
  soleil ; juger l'éclairage après quelques secondes, ou tester l'ombre par rayons vers `Lighting:GetSunDirection()`
  (en ignorant les pièces invisibles, murs d'air compris).
- Sur la place partagée, `ReplicatedStorage.MenuMirrors` reste après le merge : Rojo ne supprime pas une instance qu'il
  ne gère plus. La supprimer à la main dans Studio une fois #253 mergée.

**Pistes écartées pour l'accueil :**

| Piste | Pourquoi |
|---|---|
| Salle des miroirs (#106, #112) : éclats pendus à des fils qui reconstituent l'image de l'arme, tir sur les éclats, explosion sur JOUER | Ne collait pas à la direction artistique (#253). Code, assets (`assets/rbx/Menu`), outils Blender (`tools/menu/`) et rendus (`docs/ui/menu-miroirs/`) retirés, dans l'historique git avant #253 |
| Silhouette en contre-jour sur le parapet, personnage surfant sur la rampe, contre-plongée depuis le vide | Captures proposées en #253 ; l'utilisateur voulait un personnage de face, en grand, à hauteur d'homme |
| Tenue fusil du jeu (épaulé) vue de face | Le canon pointe vers la caméra et la crosse cache le buste |
| Garde du couteau du jeu vue de face | Avant-bras levé vers la caméra : on croit qu'il salue |

## Reste à faire

- Piste écartée pour l'instant sur le compteur : chiffres en images usées comme le titrage, et inclinaison qui augmente avec la vitesse.
- Tester le menu au tactile et à la manette : jamais essayé. Depuis #280, plus de flèches ‹ › : l'écran d'équipement se
  pilote au clic (le toucher devrait suivre `Activated`) ; rien à la manette (#276).
