# Faire une animation de viewmodel

Méthode issue de la refonte de la M9 Bayonet (PR #46). À suivre pour toute nouvelle animation d'arme.

## La règle

**On se met d'accord sur des images et une vidéo avant de publier, jamais sur une description.** Les mots décrivent mal
un mouvement, et chaque essai en jeu coûte cher. Deux validations sont nécessaires, et la première ne remplace pas la
seconde :

1. les **poses** (images fixes) fixent la trajectoire et le cadrage ;
2. le **mouvement** (vidéo côte à côte) fixe la fluidité et le rythme.

Sur la M9, toutes les poses avaient été validées, mais la rotation de l'Equip était cassée en jeu parce que l'étape 2
avait été sautée.

## Le processus

| Étape | Ce que fait l'utilisateur | Ce que fait Claude | Ce qui est validé |
|---|---|---|---|
| 1. Référence | Fournit une vidéo et ses repères temporels | Extrait des images numérotées, reformule ce qu'il comprend | L'intention |
| 2. Poses | Corrige par numéro (« D8 : lame plus à droite ») | Rend les poses dans Studio à côté de la référence | Trajectoire, cadrage |
| 3. Mouvement | Corrige par numéro d'image | Fournit la vidéo côte à côte (×1 et ×0,25) | Fluidité, rythme |
| 4. En jeu | Valide le résultat final | Publie, met à jour le viewmodel, vérifie | Ressenti, son |

Rien n'est publié avant la validation de l'étape 3.

## L'AWP : mesurer deux points et reconstruire la pose

Méthode de la refonte de l'Equip, du Shoot et du Reload de l'AWP (référence CS2). Elle s'applique à toute arme longue.

- **Mesure :** relever à l'écran l'œilleton et le bout du canon sur des planches `grid.py` zoomées (`EQUIP_TRACK`,
  `SHOOT_TRACK` et `RELOAD_TRACK` dans `assets/awp_viewmodel/build_anims.py`), toutes les 1/30 s pendant un choc et toutes
  les 0,1 s ailleurs. `solve_gun` en déduit la pose de l'arme ; la profondeur vient du grossissement apparent, estimé à l'œil.
- **Le roulis est invisible sur ces deux points :** il se règle à l'œil (`BOLT_ROLL`, `RELOAD_ROLL`, `EQUIP_ROLL_LOW`).
- **Le suivi automatique ne suffit pas ici :** la soustraction du décor prend la flamme du tir pour le canon et perd le canon
  fin sur fond clair, et le suivi de l'œilleton dérive sous la main droite. Il a servi à repérer les instants, pas à mesurer.
- **Mesurer un écart au repos, pas une position :** seuls les écarts à `REF_IDLE` sont repris, ce qui absorbe la petite
  différence de cadrage entre CS2 et le jeu.
- **Tout passe par l'arme, jamais par `FakeCamera` :** quand le `PrimaryPart` du viewmodel est `FakeCamera`, cet os est recalé
  sur la caméra à chaque image (`PivotTo`) et son animation n'a aucun effet.
- **Durée :** le cycle de tir CS2 dure environ `FireDelay`, et le Reload colle à `ReloadTime`. Seul l'Equip est étiré
  (1,13 s de geste dans la vidéo, 1,58 s en jeu pour garder l'équilibrage).

```bash
# Construire sans toucher au Blender ouvert : écrit anim_<Nom>.json (make_rbxm) et frames_<Nom>.json (studio_render, à 60 images/s)
blender -b assets/awp_viewmodel/AWP_Viewmodel_Anims.blend --python assets/awp_viewmodel/run_build.py -- <sortie> Equip Shoot Reload
lune run assets/awp_viewmodel/make_rbxm.luau <sortie> <sortie> Equip Shoot Reload
bash tools/anim/publish.sh <sortie> AWP_ Equip Shoot Reload
```

Pour le rendu : `VIEWMODEL = "AWP"` et `RECENTER_HANDLE = false` dans `studio_render.luau`. `dump_frames.py` ne sert qu'à la M9.

Le `.blend` garde les anciennes actions : `run_build.py` les régénère à chaque lancement et ne sauvegarde pas le fichier.

## Les outils

Depuis la racine du worktree. `uv` installe tout seul les dépendances des scripts Python (Pillow, ffmpeg), rien à
installer sur le système. Les fichiers temporaires vont hors du dépôt.

```bash
# Étape 1 : planche numérotée avec grille de mesure (xmin/xmax zooment sur la zone de l'arme)
uv run tools/anim/grid.py <video> <sortie.jpg> <debut> <fin> <pas> [colonnes] [xmin] [xmax]

# Étape 1 bis : mesurer le geste image par image (caméra fixe), puis contrôler la planche produite
uv run tools/anim/track_blade.py <video> <debut> <fin> <garde_x,garde_y> <pointe_x,pointe_y> <roulis_debut> <trajectoire.json> <controle.jpg>

# Construire les animations sans toucher au Blender ouvert (la scène de la session serait effacée)
blender -b --factory-startup --python <script qui exécute build_viewmodel.py avec __name__="__main__" et ASSET_DIR>
lune run assets/m9_viewmodel/make_rbxm.luau assets/m9_viewmodel/export assets/m9_viewmodel/export <Nom>

# Étape 3 : exporter les frames et lire les vitesses de rotation, AVANT tout rendu
blender -b --factory-startup --python tools/anim/dump_frames.py -- <dossier_build_viewmodel> <Nom> <frames.json>

# Rendu dans Studio : lancer le serveur, puis coller tools/anim/studio_render.luau dans execute_luau (Edit)
uv run tools/anim/capture_server.py <dossier_captures> <frames.json>

# Vidéo à faire valider. Viewport en pixels, à relever sur une capture : il dépend de la disposition de Studio
uv run tools/anim/side_by_side.py <reference.mp4> <debut_video> <ralenti> <dossier_captures> <Nom> <x0,y0,x1,y1> <sortie.mp4>

# Étape 4 : publier (clé dans la variable d'environnement utilisateur ROBLOX_OPEN_CLOUD_KEY)
bash tools/anim/publish.sh assets/m9_viewmodel/export M9_ <Nom>
```

Après la publication : dans Studio, mettre le nouvel id sur `ViewModels.<Arme>.Animations.<Nom>`, puis coller
`tools/anim/studio_save_viewmodel.luau` (serveur de capture lancé). Il n'écrit que ce viewmodel, alors que
`tools/rbxm/studio_export.luau` réécrit toutes les armes. Enfin : `rojo build`, `tools/rbxm/verify_place.luau` et le
helper de playtest.

Si un clone reste dans `Workspace` après une erreur de rendu, supprimer `__AnimPreview` à la main.

## Décrire le mouvement

- **Reproduire une référence : mesurer toute la trajectoire.** Relever la garde et la pointe à l'écran toutes les 0,05 s
  de vidéo, puis les interpoler avec une spline (voir `EQUIP_TRACK` dans `build_viewmodel.py`). C'est ce qui a donné un
  Equip fidèle.
- **Un geste long ou rapide se mesure avec `track_blade.py`, pas à l'œil.** Le rythme vient directement de la vidéo : sur
  l'Inspect, le relevé à l'œil avait donné un seul aller-retour du poignet au lieu de trois. La trajectoire se branche
  avec `measured=` dans la spec (voir `spec_inspect`). Si un geste va trop vite pour le suivi, couper la mesure avant et
  finir par le raccord `settle`.
- **Ne pas poser une clé avec courbe au milieu d'un geste continu.** Chaque clé en `io` ramène la vitesse à zéro : la
  rotation semble interrompue. Un geste continu se décrit par une seule courbe, ou par une spline.
- **Un objet qui tourne dans la main n'a pas la même trajectoire que la main.** Faire suivre la main au couteau la fait
  basculer (54° en 1/30 s sur la M9). La main garde sa propre trajectoire, et le couteau tourne devant elle.
- **Exprimer le tranchant par rapport au regard, pas par une direction fixe** : une direction fixe impose une rotation
  parasite. `knife_from_roll` utilise un roulis : 0 = de plat, 90 = dos vers la caméra.
- **Laisser la profondeur suivre la longueur de la lame à l'écran.** Avec une profondeur fixe, la lame peut paraître trop
  courte ou tourner hors de son axe.

## Contrôler le résultat

- **Lire d'abord le tableau de `dump_frames.py`.** Une rotation propre monte puis redescend, sans creux ni pic isolé, et
  la main reste à 0 tant que le couteau tourne dedans. C'est le contrôle le moins cher : il ne coûte aucun rendu.
- **Regarder des images consécutives**, jamais des images espacées : 8 images réparties sur 1 s ne révèlent pas un saut.
- **Vérifier que l'arme reste visible** : les bras R15 sont massifs (1,2 stud) et cachent ce qui passe derrière eux.
- **En jeu, comparer des nombres** : figer la piste (`AdjustSpeed(0)`, `TimePosition`) et comparer les CFrames au JSON
  (écart attendu : moins de 0,01 stud). Le client ne peut pas envoyer de requêtes HTTP, et une capture minutée se décale.
- Ces mesures prouvent que le rig joue bien ce qui est prévu, **pas que le mouvement est beau**. Seule la vidéo côte à
  côte répond à cette question.

## Rig et code du viewmodel

Repris du retour d'expérience de la M9 (`docs/notes/retex-viewmodel-m9.md`).

- **Rig par script :** extraire de Studio les CFrames relatifs à la `HumanoidRootPart` et les C0/C1 des Motor6D (`rig.json`), puis les reconstruire dans Blender avec `C = (x, -z, y)`. L'export applique `Transform = C0⁻¹·Part0⁻¹·Part1·C1`.
- **La pose de repos du rig est la pose idle**, en recalculant `C1 = Part1⁻¹·Part0·C0` : sans animation Idle, le rig y revient à la fin de chaque piste, sans saut visible.
- **IK à deux os :** si la cible est hors de portée, c'est l'épaule qui suit la main. Sinon la main se décroche de l'avant-bras, ce qui se voit à une translation non nulle de `RightHand` dans la piste. Dans le viewmodel R15, le pivot du Motor6D d'épaule est à environ 3 studs du bras (grande translation dans C1).
- **Orientations :** ne pas deviner des angles d'Euler. Les calculer par ajustement numérique à partir de directions cibles (axe du couteau, sens du tranchant).
- **Mêlée :** le coup est déclenché par le marqueur `Stab Sound` (`WeaponSystem`).
- **Modèle 3e personne :** `WeaponThirdPerson` clone les pièces du viewmodel et a besoin d'une pièce `Handle`. Les CFrames en mode Edit des pièces de l'arme doivent donc être justes.

## Pièges connus

- **FOV :** le jeu tourne à 90° vertical (`CameraConfig.DEFAULT_FOV`) et le joueur voit du 16:9. Juger un cadrage à un
  autre FOV ne sert à rien. Le viewport de Studio est plus large : `side_by_side.py` recadre en 16:9.
- **Vidéo de référence :** elle peut être ralentie. Celle de la M9 l'est d'environ 1,25 fois, valeur estimée à partir du
  Draw. Les autres durées ne suivent pas ce facteur (l'attaque fait 1,9 s dans la vidéo et 0,7 s dans le jeu).
- **Durées CS:GO :** Valve ne les publie pas. Seul un guide tiers donne la cadence des couteaux (0,4 s et 1 s).
- **Mesh tiers :** `AssetService:CreateEditableMeshAsync` refuse les meshes qu'on ne possède pas, et il ne faut pas
  chercher à contourner ce refus. Le rendu se fait dans Studio, où le mesh s'affiche normalement.
- **Blender :** lancer en `-b --factory-startup`. `build_scene` efface tous les objets de la scène.
- **Open Cloud :** les assets doivent appartenir au créateur 434916384, sinon ils ne fonctionnent pas en jeu.
  `rbxtemp://` est refusé en playtest : il faut publier pour tester une piste.
- **Hook `git-safe` :** il bloque `git checkout --` et `git stash drop`. Exporter un seul viewmodel évite d'avoir à
  annuler le bruit d'export des autres armes.
- **Shell :** un long heredoc contenant des apostrophes peut échouer dans l'outil Bash. Écrire le script avec un fichier.
- **Studio et Rojo :** le code d'un worktree n'arrive dans Studio qu'après la connexion du plugin à son port (un clic
  de l'utilisateur, en mode Edit). Vérifier que le code attendu est bien là avant de conclure sur un test.

- **Viewmodel dans Studio :** vérifier `PrimaryPart` avant un playtest. Il a disparu de l'instance Studio de l'AWP pendant la
  refonte, Rojo connecté à un autre worktree, alors que le `.rbxm` exporté l'avait encore (cause non établie). Le viewmodel
  retombe alors sur `HumanoidRootPart` et se décale de (-0,19 ; 0 ; 0,14) par rapport au rendu. Réparation : `CLAUDE.md`.

## Limites actuelles

- Le rig n'a pas de doigts : le couteau tourne devant un poing fermé. C'est accepté pour la M9.
- `Shoot`, `Shoot2` et `Stab` utilisent encore des clés espacées. Elles n'ont pas eu de validation du mouvement et
  peuvent avoir les mêmes saccades que l'ancien Equip. À reprendre avec `track_blade.py`.
- `track_blade.py` suppose une caméra fixe et une lame sur fond dégagé. Ses seuils (texte incrusté, ciel, largeur par la
  tranche) sont réglés sur la vidéo de la M9 et sont à revoir pour une autre vidéo.
- L'Equip reste sur sa trajectoire relevée à la main (`EQUIP_TRACK`, `sample_track`).
