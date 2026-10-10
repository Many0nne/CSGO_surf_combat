# Audit des animations du viewmodel FPS (issue #6)

Fichiers lus : `src/shared/WeaponConfig.luau`, `src/client/systems/weapon/ViewmodelSystem.luau`,
`src/client/systems/weapon/AnimationSoundSystem.luau`, `src/client/systems/weapon/WeaponSystem.luau`,
`src/client/systems/weapon/ScopeSystem.luau`.

## Où vivent les animations

- Les assets ne sont **pas dans `src/`** : chaque viewmodel est un `Model` dans `ReplicatedStorage.ViewModels.<ViewmodelName>`
  (place Studio), avec un dossier `Animations` (ou `AnimSaves`) d'objets `Animation` et un dossier `Sounds`.
- Le code ne connaît que des **noms** de pistes : `Equip`, `Shoot`, `Reload` (et désormais `Idle`, optionnel).
  Aucun `AnimationId` n'est écrit dans le dépôt.
- `WeaponConfig.Weapons[*].AnimationSounds[<anim>]` liste les sons ; le son `X` est joué au marqueur `"X Sound"`.
- `ShootAnimTime`, `EquipTime`, `ReloadTime` (WeaponConfig) pilotent la machine d'état de `WeaponSystem`, pas l'animation.

Les ids réels sont à relever dans Studio (lecture seule, barre de commande) :

```lua
for _, vm in game.ReplicatedStorage.ViewModels:GetChildren() do
	local f = vm:FindFirstChild("Animations") or vm:FindFirstChild("AnimSaves")
	for _, a in f and f:GetChildren() or {} do
		if a:IsA("Animation") then print(vm.Name, a.Name, a.AnimationId) end
	end
end
```

## Tableau arme × animation

| Arme | Anim | Référencée par | Sons (marqueurs) | État | Problèmes probables (avant cette PR) | Priorité refonte |
|---|---|---|---|---|---|---|
| AWP | Shoot | `WeaponSystem.onToolActivated` → `playAnimation("Shoot")` | Shoot, Bolt | suspect | fondu par défaut 0,1 s, priorité de l'asset non forcée, retour brusque à la pose du rig en fin de piste (pas d'idle) ; `ShootAnimTime` 1,63 s > `FireDelay` 1,46 s | 1 |
| AWP | Reload | `WeaponSystem.reloadTool` → `playReload` | Bolt, ClipIn, ClipOut, ClipHit | suspect | durée de l'asset non calée sur `ReloadTime` (3,7 s) : munitions rendues avant/après la fin visuelle ; marqueurs Equip/Shoot pas déconnectés avant la recharge | 2 |
| AWP | Equip | `ViewmodelSystem.equipTool` | Bolt, Draw | suspect | durée lue par `WeaponSystem` via `getPreloadedTrackLength("Equip")` : course entre les deux handlers `Equipped` (peut renvoyer 0 → fallback `EquipTime` 1,58 s, ou la longueur de l'arme précédente) | 4 |
| AWP | Inspect | — | — | manquant | aucune piste ni input d'inspect | 3 |
| AWP | Idle | — (pris en charge par cette PR si présent) | — | manquant / à vérifier | sans idle, chaque fin d'action retombe sur la pose statique du rig | 3 |
| AWP | Zoom | `ScopeSystem.toggle` (sons joués directement, pas de piste) | ZoomIn, ZoomOut | ok | `AnimationSounds.Zoom` n'est pas une piste : liste purement documentaire | — |
| Butterfly | Shoot (stab) | `WeaponSystem.onToolActivated` → `playAnimation("Shoot", { ["Stab Sound"] = resolveHit })` | Stab (dynamique) | suspect | les overrides **remplaçaient** les sons de WeaponConfig (tout autre marqueur ignoré) ; mêmes soucis de fondu/priorité que l'AWP | 1 |
| Butterfly | Equip | `ViewmodelSystem.equipTool` | Equip | suspect | même course de durée que l'AWP | 4 |
| Butterfly | Inspect | — | — | manquant | le flip de butterfly est l'inspect le plus attendu | 3 |
| Butterfly | Idle | — | — | manquant / à vérifier | idem AWP | 3 |
| Butterfly | Reload | n/a (melee) | — | ok | — | — |

## Corrigé en code dans cette PR (sans nouvel asset)

- Fondus explicites et configurables (`ANIM_FADE_IN` 0,08 s, `ANIM_FADE_OUT` 0,15 s, `IDLE_FADE_IN` 0,2 s) ; fondu croisé entre actions,
  relance d'une même piste sans fondu pour repartir de 0.
- Priorités forcées : `Action` pour Equip/Shoot/Reload/…, `Idle` bouclée pour la piste `Idle` si elle existe dans le dossier.
- Piste `Idle` jouée sous les actions dès l'equip : les fins d'action se fondent dans l'idle au lieu de « snapper ».
- Recharge : vitesse calée sur `ReloadTime` (`computePlaybackSpeed`, bornée 0,75–1,5, désactivable via `MATCH_RELOAD_TIME`).
- Une seule piste d'action à la fois (`actionTrack`), arrêtée sans fondu au switch/unequip pour que le modèle ne réapparaisse pas en fin de fondu.
- Pistes chargées à la volée désormais mises en cache et configurées (avant : un `LoadAnimation` par tir si le prewarm l'avait ratée).
- Sons : marqueurs dédoublonnés, toutes les connexions coupées avant chaque nouvelle action (la recharge ne le faisait pas),
  overrides melee qui complètent la config au lieu de la remplacer, bruitages Equip/Reload coupés à l'unequip (recharge annulée),
  garde `hookedTools` libérée à la destruction de l'outil.

## Reste à faire (humain / Studio)

1. Relever les `AnimationId` avec le snippet ci-dessus et compléter ce tableau.
2. Vérifier dans chaque animation que les marqueurs s'appellent exactement `"<Son> Sound"` (sinon le son est silencieusement ignoré)
   et que chaque son existe dans `Sounds`.
3. Refaire ou remplacer en priorité Shoot (AWP + stab), puis Reload, Inspect, Equip ; ajouter une piste `Idle` par viewmodel
   (aucun code supplémentaire requis : elle est jouée automatiquement si elle s'appelle `Idle`).
4. Inspect : nécessite une piste `Inspect` + une touche (hors périmètre, à câbler dans `InputModule`/`WeaponSystem`).
5. Course `EquipTime` / longueur de l'Equip dans `WeaponSystem` : à traiter après l'issue #5 pour éviter les conflits.
6. Bob/sway procédural : le sway caméra existe déjà (ressort dans le RenderStep) ; pas de bob de marche, laissé de côté.
