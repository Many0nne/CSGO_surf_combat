# Direction artistique de l'interface

Référence pour refaire les autres écrans (Infos, Réglages, Feedback, HUD, fin de round) dans la direction du menu principal.

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

## Comment c'est construit

- `src/client/ui/MainMenu.luau` : titre et choix (`ImageButton`), hitmarker-curseur, impacts, tir au clic.
- `src/client/systems/game/MenuScene.luau` : scène 3D, éclairage temporaire, visée, tir, surfeurs, plongée sur JOUER.
- `src/client/systems/game/MenuSceneRules.luau` : règles pures testées (`tests/specs/MenuSceneRules.spec.luau`).
- `src/client/ui/Transition.luau` : volets couleur du soleil, enchaînés à la plongée vers le soleil.
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

## Pièges connus

- **Id d'un Decal publié :** il ne s'affiche pas dans une `ImageLabel` (console : `Asset type does not match requested type`).
  Il faut l'id de l'image contenue dans le Decal (voir ci-dessus).
- **Distance d'affichage :** Roblox la réduit selon la charge, et le décor lointain disparaît d'un coup avec la map chargée.
  Le canyon est donc au tiers de sa taille apparente (1 000 studs de long). Un test sans la map ne le montre pas.
- **Éclairage :** `MenuScene` remplace celui de `Lighting` et le rétablit à sa sortie. Un tween encore actif écrase les valeurs
  rétablies : l'annuler d'abord (`diveTweens`), car le joueur peut apparaître avant la fin de la plongée.
- **Curseur :** `MainMenu` remet `MouseIconEnabled = false` à chaque image, car les autres écrans le réactivent en se fermant.
- **`AbsolutePosition` avec `IgnoreGuiInset` :** elle exclut la barre du haut, contrairement à `GetMouseLocation`. Préférer
  `MouseEnter`, `MouseLeave` et `Activated` à un test de zone maison.
- **Polices :** aucune annonce officielle d'import de police trouvée (novembre 2026). Les titres passent par des images ;
  le texte courant reste en police Roblox.
- **Bras du viewmodel :** ils forment vite une grosse masse noire quand la souris est dans un coin. Limiter le pivot
  (`MenuSceneRules.aimAngles`) et garder le soleil dégagé.

## Prototyper dans le moteur

Sans toucher aux fichiers ni à la place : pendant un playtest, `execute_luau` en contexte `Client` peut construire une scène
et une UI entières, et `screen_capture` montre le résultat avec l'UI. Tout disparaît à l'arrêt du playtest. Le code ainsi
lancé ne partage pas ses modules avec le jeu (un `require` donne une autre instance). Seul Claude ne peut pas connecter le
plugin Rojo : l'utilisateur doit le faire pour tester un worktree.

## Reste à faire

- Passer Infos, Réglages, Feedback, le HUD et la fin de round du style « Tactical » ambre à cette direction (`UITheme.luau`).
- Traduire le panneau Infos, encore en anglais alors que le menu est en français.
- Afficher les munitions dans le HUD (`WeaponSystem` les gère, rien ne les montre) et réduire le compteur de vitesse.
- Tester le menu au tactile et à la manette : c'est prévu dans le code, jamais essayé.
- Ajouter un modèle de personnage dédié si l'on veut un sniper visible en 3e personne dans le menu.
- Trouver la source de l'erreur console `rbxassetid://203785492`, antérieure à ce menu.
