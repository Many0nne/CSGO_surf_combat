# RETEX : viewmodel M9 Bayonet (modèle Blender + animations), 2026-10-31

> Mise à jour (issue #26) : le modèle procédural a été remplacé par le mesh du Creator Store `18775128699`, et
> `build_knife.py`, le `.blend` et le FBX ont été retirés (voir l'historique git). `build_viewmodel.py` reste la source
> des animations (Idle, Equip, Shoot, Shoot2, Inspect), avec un simple volume à la place du couteau.

Session interrompue avant validation : le modèle procédural n'était pas assez bon et le slash n'a jamais pu être
testé en jeu. Ce document liste ce qui a bloqué, ce qui a marché, et ce qu'il faut mettre en place pour aller plus vite.

État laissé : worktree `CSGO_surf_combat-m9` (branche `feat/m9-bayonet`, rien de commité) avec `assets/m9_viewmodel/`
(scripts Blender, rig, exports). Côté Studio, des modifications non sauvegardées : `ViewModels.M9Bayonet`, Tool
renommé en `M9Bayonet`, `ViewModels.Butterfly` supprimé. Ne pas sauvegarder la place tant que le code de `main`
attend `Butterfly`.

## Ce qui a coûté du temps (par ordre d'impact)

1. **Studio et le code n'étaient pas synchronisés sur le même checkout.** Le renommage `Butterfly` → `M9Bayonet` dans
   `WeaponConfig` n'existait que dans le worktree, mais Studio était connecté au `rojo serve` d'un autre dossier (port
   34872). Résultat : la M9 tournait sans config, donc sans slash, sans son et sans dégâts, et le test utilisateur
   paraissait « cassé ». Le plugin Rojo ne se connecte qu'en mode **Edit** : en Play, il renvoie
   `Http requests can only be executed by game server`.
2. **Les viewmodels, Tools et animations vivent uniquement dans la place Studio**, pas dans `src/`. Toute modification
   passe par le MCP, n'est pas versionnée, n'est pas isolée par worktree, et reste perdue tant que la place n'est pas
   sauvegardée.
3. **L'import du mesh est manuel** (Fichier → Import 3D). Ça impose un aller-retour avec l'utilisateur au milieu de la
   tâche.
4. **Il faut publier les animations avant de pouvoir les tester.** `KeyframeSequenceProvider:RegisterKeyframeSequence`
   donne un `rbxtemp://…` que le client refuse en playtest (`rbxtemp:// not allowed`), ce qui casse le chargement du
   viewmodel.
5. **La clé Open Cloud n'était stockée nulle part** : demande en cours de route, puis saisie sécurisée.
6. **La qualité du modèle est limitée par la modélisation 100 % script** (bmesh) sans référence visuelle. Les
   bibliothèques et générateurs de l'addon Blender MCP (Sketchfab, Poly Haven, Tripo, Meshy…) sont tous désactivés. Les
   bras R15 du viewmodel sont des boîtes de 1,2 stud qui cachent tout le manche.
7. **Orientations d'animation devinées en angles d'Euler** : trois itérations perdues sur le slash. Ça a été réglé en
   calculant les angles par ajustement numérique à partir de directions cibles (axe du couteau, sens du tranchant).
8. **Payload JSON collé dans `execute_luau`** (environ 12 Ko par envoi) pour créer les KeyframeSequences dans Studio :
   cher en tokens et fragile.
9. **Pipeline AWP en doublon** : `assets/awp_viewmodel/` (non commité, worktree `CSGO_surf_combat-awp-anims`)
   contenait déjà `make_rbxm.luau` et l'approche « rig.json → Blender → JSON → KeyframeSequence ». Je ne l'ai découvert
   qu'en cours de route.

## Ce qui a marché (à réutiliser)

- **Publier par Open Cloud fonctionne** : `POST https://apis.roblox.com/assets/v1/assets` en multipart, avec
  `request={"assetType":"Animation","displayName":…,"creationContext":{"creator":{"userId":"434916384"}}}` et
  `fileContent=@X.rbxm;type=model/x-rbxm`, puis interroger `GET /assets/v1/operations/{id}` jusqu'à `done`. Les
  animations ont été approuvées en quelques secondes. L'expérience appartient à l'utilisateur 434916384 : les assets
  doivent être publiés sous ce créateur pour fonctionner en live.
- **Rig de viewmodel par script** : on extrait de Studio les CFrames relatifs à la HumanoidRootPart et les C0/C1 des
  Motor6D (`rig.json`). On les reconstruit dans Blender avec `C = (x, -z, y)` (Roblox → Blender ; la base s'annule dans
  `Part0⁻¹·Part1`). L'export applique `Transform = C0⁻¹·Part0⁻¹·Part1·C1`.
- **La pose de repos du rig = la pose idle**, en recalculant les C1 avec `C1 = Part1⁻¹·Part0·C0`. Sans animation Idle,
  le rig revient à sa pose de repos à la fin de chaque piste : aucun saut visible.
- **IK à deux os maison** (épaule = haut de l'UpperArm, pôle de coude). Si la cible est hors de portée, c'est
  l'**épaule** qui suit la main ; sinon la main se décroche de l'avant-bras (détecté parce que la translation de
  `RightHand` dans la piste n'était pas nulle).
- **Prévisualiser avec la caméra du jeu** dans Blender (caméra à l'origine, FOV vertical 70°) et `look` en mode
  `frames` : boucle d'itération rapide et fiable.
- **Import FBX** : avec `apply_scale_options="FBX_SCALE_ALL"` et 1 unité Blender = 1 stud, les tailles arrivent exactes
  dans Studio. Mais avec `axis_forward="-Z", axis_up="Y", bake_space_transform=True`, la géométrie est **retournée de
  180° autour de Y** : à compenser (essayer `axis_forward="Z"`) ou corriger le CFrame après import.
- **Lancer un playtest sans passer par l'UI** : `ReplicatedStorage.RequestSpawn:FireServer()` côté client, puis
  `Humanoid:EquipTool`. Attention : hors état `IN_ROUND`, l'outil est rapidement déséquipé par le jeu.

## À mettre en place (par ordre de gain)

1. **Versionner les viewmodels et les Tools dans le repo** : exporter `ReplicatedStorage.ViewModels.*` et les Tools de
   `StarterPack` en `.rbxm` (par exemple `assets/rbx/ViewModels/AWP.rbxm`) et les mapper dans `default.project.json`.
   Chaque worktree embarque alors son état complet, Rojo synchronise tout, et il n'y a plus de modification Studio
   orpheline. C'est le changement le plus rentable.
2. **Clé Open Cloud en variable d'environnement utilisateur** `ROBLOX_OPEN_CLOUD_KEY` (scopes `asset:read` +
   `asset:write`), et l'ID créateur (434916384) dans `CLAUDE.md`.
3. **Script `tools/publish_asset.sh <fichier> <Animation|Model> <nom>`** qui uploade par Open Cloud, attend la fin de
   l'opération et affiche l'`assetId`. Les meshes FBX passent aussi : uploader en `Model`, puis
   `insert_asset(assetId)` via le MCP Studio. Ça supprime l'import manuel.
4. **Un port Rojo par worktree** (par exemple 34872 pour `main`, 34873 et plus pour les worktrees), à documenter dans
   `CLAUDE.md` avec le rappel « connexion du plugin en mode Edit uniquement ». Le mieux serait que
   `/setup-worktrees` le prenne en charge (le projet n'est pas encore équipé).
5. **Factoriser le pipeline d'animation** une fois la branche AWP mergée : `tools/anim/` avec l'extraction du rig
   (snippet Luau pour le MCP), le module commun IK/export Blender et un `make_rbxm.luau` paramétré.
6. **Helper de playtest debug** (Studio uniquement) : une commande ou un attribut qui spawn, équipe un slot et tire
   sans passer par le menu. Ça permettrait de vérifier slash, son et dégâts en autonomie.
7. **Meilleure source pour les modèles** : activer Sketchfab ou un générateur dans l'addon Blender MCP, ou fournir des
   images de référence et blueprints (silhouette, proportions) avant de modéliser. Partir d'un modèle CC0 ou généré,
   puis le retoucher, donnera un meilleur résultat que du bmesh pur.
8. **Hook stop-validate** : il redemande les tests après des modifications d'assets seulement (`assets/**/*.py`, JSON,
   Studio). On pourrait ignorer `assets/`.

## Points du projet bons à savoir

- `ViewmodelSystem` charge les pistes depuis le dossier `Animations` du viewmodel et ne joue pas d'Idle (la branche AWP
  en ajoute un).
- Le hit melee est déclenché par le marqueur `Stab Sound` de l'animation `Shoot` (`WeaponSystem`).
- Le modèle 3e personne (`WeaponThirdPerson.buildModel`) clone les pièces du viewmodel, sauf bras, caméra, sons et
  animations, et a besoin d'une pièce `Handle`. Les CFrames en mode Edit des pièces de l'arme doivent être justes.
- Dans le viewmodel R15, le pivot du Motor6D d'épaule est à environ 3 studs du bras (grande translation dans C1).
