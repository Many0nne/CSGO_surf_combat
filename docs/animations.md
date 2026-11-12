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

**Aucune clé n'est posée sans vidéo de référence.** « Pas de vidéo de cette arme » n'est pas une exception : on prend
l'arme de la même famille dans `references/` (index plus bas), une vidéo d'un autre jeu ou d'un film pour le geste, ou
dix secondes filmées au téléphone par l'utilisateur (caméra fixe, un stylo ou l'objet réel à la main). Une planche
dessinée par Claude est une supposition, pas une référence : le Ka-Bar v3 (2026-11-11) a été fait « d'une planche
validée, sans vidéo », avec le couteau CT de CS:GO disponible dans la même famille : balayage qui reste dans la moitié
droite de l'écran au lieu de traverser le cadre bras tendu, lame vue par la tranche, estoc latéral. Sans référence,
Claude interpole des poses : il n'a aucun modèle de l'anticipation, du profil de vitesse, de la profondeur ni des
sorties de cadre. Et une vidéo à juger se présente toujours avec sa vitesse (×1 puis ×0,25, comme `side_by_side.py`) :
un ralenti seul fait prendre un armé de 0,25 s pour un armé d'une seconde.

**Le seul livrable à valider est une vidéo côte à côte** référence / rendu aux mêmes instants (`side_by_side.py`). Un
rendu seul n'est jamais présenté. Quand un choix reste subjectif (vitesse, amplitude, hauteur), Claude produit deux ou
trois variantes qui ne diffèrent que sur ce paramètre, dans la même vidéo, et l'utilisateur choisit par lettre : il n'a
pas à décrire ce qu'il veut, seulement à reconnaître ce qui est juste.

## Le processus

| Étape | Ce que fait l'utilisateur | Ce que fait Claude | Ce qui est validé |
|---|---|---|---|
| 1. Référence | Fournit une vidéo et ses repères temporels | Extrait des images numérotées, reformule ce qu'il comprend | L'intention |
| 2. Poses | Corrige par numéro (« D8 : lame plus à droite ») | Rend les poses dans Studio à côté de la référence | Trajectoire, cadrage |
| 3. Mouvement | Corrige par numéro d'image | Fournit la vidéo côte à côte (×1 et ×0,25) | Fluidité, rythme |
| 4. En jeu | Valide le résultat final | Publie, met à jour le viewmodel, vérifie | Ressenti, son |

Rien n'est publié avant la validation de l'étape 3.

## Grammaire des gestes de couteau (mesurée sur CS:GO)

Relevée image par image (30 i/s) sur le couteau CT par défaut de `references/anim/csgo-couteaux-toutes-animations.mp4`
(étiquette « DEFAULT CT KNIFE » de 387,0 à 402,9 s ; avant 387,0 s c'est le **Butterfly**, sur lequel une première version de
ce tableau avait été relevée par erreur). Positions en fraction du cadre 16:9 (0,0 = haut gauche), longueurs en hauteurs
d'écran, temps depuis le début du geste, profondeur estimée par la largeur du gant (rapport au repos). Ces nombres sont les
cibles par défaut d'un geste de couteau, original ou non ; `dump_frames.py` les contrôle (voir « Contrôler le résultat »).
Une arme d'une autre famille se mesure de la même façon avant d'écrire sa première clé. Les trajectoires complètes sont
dans `assets/kabar_viewmodel/build_viewmodel.py` (`*_ROWS`).

| Geste | Mesures sur la référence |
|---|---|
| Repos (395,5 s) | Garde (0,665 ; 0,775), pointe (0,46 ; 0,605) : lame **de face**, 0,40 de long, à ≈ 65° de la verticale (25° au-dessus de l'horizontale). Gant droit centré vers (0,74 ; 0,85), manche coupée par le bord bas. Poing gauche visible vers (0,41 ; 0,83), avant-bras vers le coin bas gauche. |
| Taille 1 (Shoot, 397,30 s), 1,1 s | **Aucune anticipation** : à la première image la main saute au centre-bas (0,60 ; 0,68), lame dressée vers l'avant (0,15 de long, gant 1,6 fois plus petit qu'au repos : bras tendu, loin). Balayage vers la gauche, (0,34 ; 0,83) puis (0,18 ; 0,94), **sortie en bas à gauche à 0,17 s**. Hors cadre 0,5 s. Retour en bas au centre, lame horizontale vers la gauche, qui se relève jusqu'au repos à 1,1 s. |
| Taille 2 (Shoot2, 398,50 s), 0,87 s | Revers : la main saute à gauche du centre (0,50 ; 0,68), gant 1,3 fois plus petit, puis balaie vers la droite (0,81 ; 0,78) et **sort en bas à droite à 0,17 s**. Hors cadre 0,4 s, retour par le bas à droite. La lame garde à peu près l'orientation du repos. |
| Estoc (Stab, 399,63 s), 1,07 s | En une image la main monte au centre (0,50 ; 0,58), loin (gant 1,5 fois plus petit), couteau **retourné** : pommeau à gauche, lame vers la droite, puis pointe en haut à droite. Armé tenu 0,25 s en dérivant vers (0,30 ; 0,64). **Frappe en une image** : la main plonge en (0,25 ; 0,93), plus proche, lame dressée, et sort en bas à gauche. Hors cadre 0,3 s, retour par le bas au centre, repos à 1,07 s. |
| Equip (387,07 s), ≈ 0,8 s | La vidéo coupe le début. Première image : main près du repos, lame vers le bas à gauche. Elle se relève au poignet (horizontale à 0,07 s, au-dessus de la tenue à 0,1 s), **dépasse la tenue** (lame à 40° au-dessus de l'horizontale) jusqu'à 0,35 s, puis s'y couche vers 0,75 s. La main gauche entre par le bas à 0,07 s. |
| Inspect (388,40 s), 5,6 s | Montée 0,4 s en passant brièvement par la tranche. Couteau vertical **face à la caméra** (garde (0,70 ; 0,59), pointe (0,70 ; 0,30)), tenu 1,6 s en montant lentement. Roulis de 0,3 s vers l'autre face en basculant à gauche (≈ 23° depuis la verticale), tenu 1,2 s. Retour de face en 0,3 s **par le même chemin** (le poignet revient : le tranchant passe vers le joueur à l'aller comme au retour), tenu 1,4 s. Petit coup de poignet et descente au repos en 0,3 s. **Jamais de pause sur la tranche.** |

Ce que ces mesures ont en commun, et qui vaut pour tout geste d'arme blanche :

- **La frappe tient en 1 à 3 images.** Toute la durée du geste est dans une anticipation courte (aucune pour les tailles
  du CT, un armé tenu 0,25 s pour l'estoc) et dans le retour (≥ 60 % du geste). Un armé d'une seconde est une pose, pas un coup.
- **La main sort du cadre** au moins une fois par coup, par un coin bas, et revient par le bas (au centre pour la taille 1
  et l'estoc, par le même coin pour la taille 2).
- **La profondeur travaille** : le couteau au bout du bras tendu paraît 1,5 à 2 fois plus petit que proche de la caméra.
  Une rotation sur place, à profondeur fixe, ne ressemble à aucun coup de la référence.
- **Le bras tendu se voit en entier**, en diagonale à travers le cadre, pendant la frappe et la poussée.
- **Retour au repos en moins d'une seconde** après le pic de vitesse.
- **Rien ne s'arrête au milieu d'un geste** (pas de clé `io` entre le départ et le pic : vitesse nulle = geste cassé).
- **Un roulis va et revient.** Montrer l'autre face puis revenir, c'est tourner le poignet puis le ramener : le tranchant
  passe deux fois du même côté (vers le joueur sur le CT). Enchaîner 0 → 180 → 360 fait faire un tour complet au couteau
  dans la main, ce qu'aucun avant-bras ne permet (pronation et supination font ≈ 180° à elles deux).
- **Au repos et aux pauses, la lame est de face.** La tranche et le dos ne sont jamais des poses tenues.

## Un geste original

L'originalité porte sur l'arme, la trajectoire et le rythme, pas sur la méthode : un geste inédit se décompose en
archétypes qui, eux, ont tous une référence ou une physique.

1. **Décomposer.** Une faux qui arrive de loin en tournant sur elle-même et se plante dans la main, c'est : une approche
   (objet lancé qui revient), une réception (un Equip : impact, recul, tassement) et un repos. Chaque morceau se traite
   séparément et se raccorde par `settle`.
2. **La physique d'abord.** Un objet en vol suit un arc balistique, tourne à vitesse constante et ne ralentit que dans la
   main. Vitesse angulaire, hauteur de l'arc, durée d'approche sont des nombres qu'on calcule ou qu'on simule dans
   Blender, pas qu'on devine image par image.
3. **La référence est celle du geste, pas de l'arme.** Le rappel de la hache dans God of War (2018), le marteau qui
   revient dans les films Thor, sont des références recevables pour « un objet qui revient en tournant ». Les ranger
   dans `references/` sous le nom du geste, pas de l'arme. L'utilisateur fournit un lien ou un extrait ; Claude peut en
   proposer un à confirmer.
4. **Ce qui reste subjectif se tranche par variantes**, un paramètre à la fois (vitesse de rotation, hauteur de l'arc,
   durée du tassement), dans une seule vidéo côte à côte. L'utilisateur choisit par lettre.
5. **Le fragment reproductible se filme.** La réception, le geste du poignet, un moulinet : dix secondes au téléphone
   valent mieux que dix allers-retours.
6. **La grammaire s'applique quand même** : frappe courte, sortie de cadre, profondeur, retour rapide, lame de face aux
   pauses. `dump_frames.py` le vérifie sur n'importe quel geste.

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

Pour le rendu : `VIEWMODEL = "AWP"` et `RECENTER_HANDLE = false` dans `studio_render.luau`. `dump_frames.py` sert aux couteaux (scripts `build_viewmodel.py`), pas à l'AWP.

Le `.blend` garde les anciennes actions : `run_build.py` les régénère à chaque lancement et ne sauvegarde pas le fichier.

**Marqueurs de `Shoot` :** `Shoot Sound` (0 s), `Bolt Sound` (culasse levée moins 0,07 s) et `Eject` (culasse en
arrière, `bt["back"]`, 0,817 s : la douille sort, #237, `docs/assets.md`). Un marqueur se rattache à la keyframe la plus
proche (`make_rbxm.luau`). **Ajouter un marqueur sans toucher au mouvement :** reconstruire la piste, puis comparer ses
poses à celles de la piste publiée (téléchargée par `asset-delivery-api`) avant de publier : pour #237, 1 144 poses
identiques, seul `Eject` en plus.

## Vidéos de référence

Les vidéos sont rangées dans `references/` à la racine du checkout principal (dossier ignoré par git, à recopier sur un
nouveau poste : ce ne sont pas des fichiers du projet). Avant toute animation, prendre ici la vidéo de l'arme, ou à défaut
de l'arme de la même famille, et relever ses repères temporels avec `tools/anim/grid.py`. Les repères ci-dessous ont été
lus à 2 images par seconde : les affiner avant de mesurer. Les noms de couteaux marqués « ? » restent à confirmer.

### `references/anim/csgo-couteaux-toutes-animations.mp4` (CS:GO, 8 min 12 s, 640x360 à 30 i/s, sha256 `345133499115d2e1…`)

Un couteau par segment, toujours dans le même ordre : Equip, coups de taille, estoc, Inspect (parfois une variante « rare
animation »), puis le couteau suivant. Caméra fixe, ciel dégagé derrière l'arme : `track_blade.py` s'y prête.

| Début | Couteau | Repères utiles |
|---|---|---|
| 0:00 | couteau 1 (?) | |
| 0:16 | couteau 2, manche rouge (?) | |
| 0:32 | couteau 3 (?) | |
| 0:50 | couteau 4 (?) | |
| 1:12 | Karambit | prise inversée, rotation autour du doigt 1:16-1:20 |
| 1:38 | couteau 6 (?) | |
| 1:56 | couteau 7 (?) | |
| 2:24 | couteau 8 (?) | |
| 2:48 | couteau 9 (?) | |
| 3:10 | couteau 10 (?) | |
| 3:36 | couteau 11 (?) | |
| 3:58 | couteau 12 (?) | |
| 4:20 | couteau 13 (?) | |
| 4:46 | couteau 14, lame courbe (?) | |
| 5:10 | couteau 15 (?) | |
| 5:36 | couteau 16 (?) | |
| 6:00 | Butterfly (étiquette lue de 6:16 à 6:27) | ses coups (6:23,9 à 6:27) ne sont pas ceux du CT |
| 6:27 | **couteau CT par défaut** (référence du Ka-Bar) | étiquette « DEFAULT CT KNIFE » de 6:27,0 à 6:42,9 (avant : Butterfly). Equip 6:27,07 (début coupé) ; Inspect 6:28,4-6:34,0 ; repos 6:34-6:37,3 ; taille 1 6:37,30 ; taille 2 6:38,50 ; estoc 6:39,63 ; repos jusqu'à 6:42,9. Mesures détaillées : « Grammaire des gestes de couteau » |
| 6:43 | **couteau T par défaut** | Equip 6:44 ; Inspect 6:45-6:50 ; tailles 6:50-6:55 ; estoc vers 6:52,5-6:53,5 |
| 6:58 | Ghost Knife (Danger Zone) | |
| 7:14 | hache, 7:26 marteau, 7:32 clé à molette (Danger Zone) | outils de mêlée, hors couteaux |

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
blender -b --factory-startup --python tools/anim/dump_frames.py -- <dossier_build_viewmodel> <Nom> <frames.json> [taille|estoc|equip|inspect]

# Rendu dans Studio : lancer le serveur, puis coller tools/anim/studio_render.luau dans execute_luau (Edit, VIEWMODEL à
# régler). Si Studio répond « not in the Assistant HTTP allowlist », prendre le port 34990 (déjà autorisé pour localhost) :
CAPTURE_PORT=34990 uv run tools/anim/capture_server.py <dossier_captures> <frames.json>   # et BASE = "http://localhost:34990"

# Vidéo à faire valider. Viewport en pixels, à relever sur une capture : il dépend de la disposition de Studio.
# i/s = cadence des captures (30 pour une référence à 30 i/s rendue image pour image), titre = piste et variante.
uv run tools/anim/side_by_side.py <reference.mp4> <debut_video> <ralenti> <dossier_captures> <Nom> <x0,y0,x1,y1> <sortie.mp4> [i/s] [titre]
# Plusieurs pistes et variantes bout à bout (une seule vidéo à valider) : ffmpeg -f concat -safe 0 -i liste.txt -c copy <sortie.mp4>

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
  parasite. `knife_from_roll` utilise un roulis : 0 = de plat, 90 = dos vers la caméra. Le sens du roulis se lit dans les
  lignes mesurées : un retour de face s'écrit en revenant à la valeur de départ (180 → 0), pas en continuant (180 → 360).
- **Laisser la profondeur suivre la longueur de la lame à l'écran.** Avec une profondeur fixe, la lame peut paraître trop
  courte ou tourner hors de son axe.

## Contrôler le résultat

- **Lire d'abord le tableau de `dump_frames.py`.** Une rotation propre monte puis redescend, sans creux ni pic isolé, et
  la main reste à 0 tant que le couteau tourne dedans. C'est le contrôle le moins cher : il ne coûte aucun rendu.
- **Lire ensuite son bilan de grammaire.** `dump_frames.py` mesure le profil du geste (départ, pic de vitesse, durée de
  la frappe, temps hors cadre, retour au repos, écart de profondeur) et le compare aux cibles de la grammaire selon
  l'archétype (déduit du nom de l'animation, ou donné en quatrième argument : `taille`, `estoc`, `equip`, `inspect`).
  Chaque ligne `GRAMMAIRE` est un écart à corriger avant tout rendu, ou à justifier dans la PR. Pour tous les archétypes,
  il mesure aussi la **torsion de l'avant-bras** (rotation de la main autour de son axe, cumulée image par image) et
  signale plus de 200° : c'est le tour du couteau dans la main. Tailles et estoc doivent sortir du cadre **par le bas**
  (le CT sort toujours par un coin bas ou le centre bas, et revient au centre ou par le même coin). La montée et la
  descente de l'Inspect s'arrêtent à la première tenue (0,15 s sous 1 stud/s), pas à l'arrêt complet : le CT monte encore
  lentement pendant qu'il tient le couteau.
- **Regarder des images consécutives**, jamais des images espacées : 8 images réparties sur 1 s ne révèlent pas un saut.
- **Vérifier que l'arme reste visible** : les bras R15 sont massifs (1,2 stud) et cachent ce qui passe derrière eux.
- **En jeu, comparer des nombres** : figer la piste (`AdjustSpeed(0)`, `TimePosition`) et comparer les CFrames au JSON
  (écart attendu : moins de 0,01 stud). Le client ne peut pas envoyer de requêtes HTTP, et une capture minutée se décale.
- Ces mesures prouvent que le rig joue bien ce qui est prévu, **pas que le mouvement est beau**. Seule la vidéo côte à
  côte répond à cette question.

## Ka-Bar : refait sur le couteau CT

Refonte du 2026-11-11, à partir du couteau CT par défaut (`build_viewmodel.py`, lignes `*_ROWS`).

- **Le bon segment :** « DEFAULT CT KNIFE » de 387,0 à 402,9 s. Avant 387,0 s c'est le Butterfly, sur lequel une première
  version de la grammaire avait été relevée. Lire l'étiquette du couteau sur la vidéo avant de mesurer.
- **Sens du tranchant pendant l'Inspect :** le premier rendu continuait le roulis de 180 à 360° au retour de face, ce qui
  faisait passer le tranchant à l'opposé du joueur et tourner le couteau d'un tour dans la main. Sur le CT, le poignet
  revient par le même chemin et le tranchant passe vers le joueur aux deux bascules. Contrôle sans rendu : signe de
  `tranchant · vers la caméra` au milieu de chaque bascule (positif = vers le joueur), et torsion de l'avant-bras dans
  le bilan `GRAMMAIRE` (226° avant correction, 120° après).
- **Profondeur de repos 2,6** (`REST_DEPTH`) : à 2,8 la lame de repos atteint sa longueur réelle à l'écran et son
  inclinaison saute.
- **Port de capture 34990** : le MCP Studio n'autorise que `localhost:34990` (`CAPTURE_PORT=34990`,
  `BASE = "http://localhost:34990"`).
- **Variantes rejetées :** repos décalé en bas à droite (B) et bascule de l'Inspect à 32° (B). L'utilisateur était
  indifférent : les valeurs mesurées sur le CT (A) sont gardées. `KABAR_REST_SHIFT` et `KABAR_INSPECT_TILT` restent
  pour rendre des variantes.
- **Rig de repos changé = `KaBar.rbxm` à mettre à jour**, sinon les pistes (calculées avec les nouveaux C1) jouent faux.
  Dans Studio, appliquer `export/kabar_rig.json` au viewmodel : C1 des Motor6D (Handle : `Q⁻¹ · C1`, voir
  `docs/assets.md`), CFrames de repos depuis la `HumanoidRootPart` (Handle : `repos · Q`, `Blade` et `Fittings` gardent
  leur décalage), ids des animations. Contrôle : `Part1 = Part0 · C0 · C1⁻¹` à 0 près. Puis, sans jamais réécrire le
  fichier synchronisé pendant la connexion : export vers `assets/rbx/KaBar_pending.rbxm` (racine de `assets/rbx/` non
  synchronisée par Rojo), `-ReleaseStudio`, renommer en `assets/rbx/ViewModels/KaBar.rbxm`, `-AcquireStudio` (le plugin
  reconnecte et accepte le patch).
- **Contrôle numérique en jeu :** `Animator:StepAnimations` en mode Edit laisse les Transform à l'identité (l'asset
  publié n'est pas encore chargé), et une boucle lancée par `task.spawn` côté client meurt avec le joueur (les bots
  tuent pendant la mesure : poser un `ForceField`). Ce qui marche : figer la piste dans un appel MCP (`AdjustSpeed(0)`,
  `TimePosition`), lire la pose dans l'appel suivant. Écart mesuré : 0,001 stud sur la main droite.

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

- **Fondu des pistes d'action (#42) :** `ViewmodelSystem.playAnimation(name, markerOverrides, fadeTime)` passe `fadeTime` à
  `track:Play()` et à l'arrêt des pistes précédentes. Sans valeur, Roblox applique son fondu par défaut de 0,1 s, qui
  absorbe l'armé d'un coup court (celui des slashs de la M9 dure 0,09 à 0,1 s) et rend le coup mou. Le réglage est **par
  arme**, via `AttackFadeTime` dans `WeaponConfig` (lu par `startMeleeAttack`) : la M9 est à `0` (la piste démarre sur la
  pose de repos, donc rien à fondre). Les autres armes n'ont pas le champ et gardent le défaut de 0,1 s : l'AWP (Shoot,
  Reload, Inspect) est inchangée. Si un coup à 0 paraît saccadé, monter `AttackFadeTime` à 0,03-0,05 s plutôt que
  d'avancer le défaut global.
- **Verrou de tir et cadence (#221) :** `ShootAnimTime` (état `FIRING` de `WeaponSystem`, qui refuse tout clic) ne
  dépasse jamais `FireDelay`, seule cadence connue du serveur : sinon le client tire moins vite que la cadence de l'arme.
  Une piste de tir plus longue que la cadence (AWP : Shoot dure 1,63 s, cadence 60/41 = 1,46 s) est coupée par le tir
  suivant, comme les slashs de la M9 : `playAnimation` arrête la piste en cours et relance Shoot avec le fondu par défaut
  (0,1 s). Les 0,17 s coupées sont la fin du réarmement, proche de la pose de repos : rendu de la coupure à juger à
  l'œil en jeu (non vérifié par capture, #221). Le son `Bolt` de la piste part avant la coupure (`DebugPlaytest` AWP :
  `Bolt Sound` atteint). Vérifié en Studio : 4 clics à ~1,5 s, 4 touches serveur, aucun clic ignoré. Invariant testé
  par `tests/specs/WeaponConfig.spec.luau`.
- **Viewmodel dans Studio :** vérifier `PrimaryPart` avant un playtest. Il a disparu de l'instance Studio de l'AWP pendant la
  refonte, Rojo connecté à un autre worktree, alors que le `.rbxm` exporté l'avait encore (cause non établie). Le viewmodel
  retombe alors sur `HumanoidRootPart` et se décale de (-0,19 ; 0 ; 0,14) par rapport au rendu. Réparation : `CLAUDE.md`.

## Tenue 3P du personnage (#107)

Ce que voient les autres joueurs : le haut du corps tient l'arme dans tous les états, les jambes suivent les pistes de
déplacement R15. Méthode retenue faute de vidéo de référence : une planche de poses clés numérotées, validée avant le code.

- **Outils :** `tools/anim/poses3p/poses.js` est la source unique (rig aux cotes du StarterCharacter, tenues, états).
  `planche.html` l'affiche (ouvrir dans un navigateur), `node tools/anim/poses3p/export_pose.js` produit les données Luau
  de `WeaponThirdPerson.POSES` et les grips de `WeaponConfig`. Modifier une tenue = modifier `poses.js`, régénérer, coller.
- **Pas d'asset publié :** les tenues sont figées, donc posées par code. Chaque client impose le `Transform` des Motor6D
  tenus en `RunService.PreSimulation`, qui suit la mise à jour des animations : la valeur posée remplace celle de
  l'Animator pour la frame. Les pistes de déplacement restent seules sur les jambes.
- **Remettre au repos en `PreAnimation` :** l'Animator ne réécrit que les articulations pilotées par une piste. Sans
  remise à zéro avant sa passe, une articulation libre (taille, cou) garderait la tenue après l'arme rangée, et le
  fondu partirait du résultat de la frame précédente. Ne pas comparer `Transform` à la dernière valeur écrite.
- **Côté client seulement :** le serveur voit les bras dans la pose des pistes. Sans effet tant que la validation des
  tirs ne contrôle que la pièce touchée, à revoir si elle contrôle un jour des positions.
- **Ne plus toucher au C0 des épaules :** l'ancienne pose (C0 tourné par le serveur) s'additionnait au `Transform` des
  pistes R15. Au saut, les bras levés de la piste partaient en arrière par-dessus la pose. C'était le bug.
- **Bras R15 courts :** 2,7 studs de portée pour 3,2 studs entre les épaules. Buste de face, la main gauche n'atteint
  pas le garde-main de l'AWP : la tenue fusil tourne la taille de 40° (`Waist`).
- **Portée réelle d'un bras :** le pivot de l'épaule est décalé de 0,79 stud de l'axe du bras. Bras tendu, la main est
  à 2,69 studs du pivot, pas à la somme des deux os (2,81). Au-delà, l'IK produit une rotation fausse sans erreur
  visible : `export_pose.js` refuse une main hors de portée ou un coude presque tendu.
- **Échelle de l'AWP 3P :** 0,7 (7,1 studs). À 0,5, la crosse disparaît dans l'épaule et l'arme paraît petite de loin.
  Agrandir l'arme éloigne le garde-main : rapprocher l'arme du corps (`gunRoot.g` de F1) puis régénérer.
- **Couteau :** à l'échelle 0,6, le manche disparaît dans le poing (1,59 stud) et il reste environ 1 stud de lame. La
  prise compte autant que l'échelle : lame dans l'axe de l'avant-bras, la main n'en cache que 0,24 stud.
- **Personnage distant en l'air :** un client ne connaît pas l'état de mouvement des autres. Il le déduit des pistes
  répliquées (`CharacterAnimator.isAirborneAnimationId`), ce qui sert au bras gauche du couteau, libre au sol.
- **Lire un `.rbxm` hors de Studio :** `lune` échoue sur les viewmodels (`Animation.Tags`). Passer par
  `rojo build` d'un projet qui ne contient que ce fichier, vers un `.rbxmx`, puis lire le XML.
- **Rig :** les C0/C1 des Motor6D du StarterCharacter n'ont aucune rotation. Un `Transform` exporté s'applique donc
  directement dans le repère de la pièce parente.

## Limites actuelles

- Le rig n'a pas de doigts : le couteau tourne devant un poing fermé. C'est accepté pour la M9.
- M9 : `Shoot`, `Shoot2` et `Stab` utilisent encore des clés espacées. Elles n'ont pas eu de validation du mouvement et
  peuvent avoir les mêmes saccades que l'ancien Equip. À reprendre avec `track_blade.py`. Le bilan `GRAMMAIRE` y relève
  une sortie à droite (Shoot), une torsion de 320° (Shoot2) et une profondeur ×1,25 (Stab).
- `track_blade.py` suppose une caméra fixe et une lame sur fond dégagé. Ses seuils (texte incrusté, ciel, largeur par la
  tranche) sont réglés sur la vidéo de la M9 et sont à revoir pour une autre vidéo.
- L'Equip de la M9 reste sur sa trajectoire relevée à la main (`EQUIP_TRACK`, `sample_track`). Le Ka-Bar est entièrement
  sur des lignes mesurées image par image (`*_ROWS`).
