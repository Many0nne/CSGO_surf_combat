# Analyse de l'état du jeu et des améliorations possibles (2026-11-12, #269)

Rapport daté : il décrit le dépôt au commit `7331170` (main du 2026-11-12). Le document du domaine prime ensuite.

## Méthode et limites

- **Lecture du code par domaine**, en cinq passes parallèles (modèle `claude-fable-5-2`) : déplacement et map ; combat,
  rounds et données ; bots ; anti-triche et réseau ; interface, audio et performance client. Chaque passe a lu les docs
  de son domaine puis le code cité dans `docs/architecture.md`.
- **Recoupement** : les constats qui portent les propositions principales ont été relus dans le code, ou mesurés en
  Studio. Chaque constat porte sa provenance :
  - **[M]** mesuré en Studio le 2026-11-12 (valeurs dans « Mesures ») ;
  - **[V]** vérifié par relecture du code cité ;
  - **[L]** relevé à la lecture par une passe, non recoupé : à confirmer avant d'en faire une issue ;
  - **[D]** déduit d'un calcul ou d'un raisonnement, effet non observé.
- **Limites** : une seule session Studio de 84 s, un joueur immobile, pas de latence, pas de second client. Aucun
  jugement de game feel n'a été porté en jouant : ce qui ne se juge qu'en jeu est dans « À vérifier en jeu ». Rien n'a
  été mesuré dans le jeu publié.
- Aucun code n'est modifié par cette analyse. Les écarts entre docs et code sont listés, pas corrigés (proposition 27).

## Synthèse

Le socle technique est très au-dessus du contenu. La physique Source à 64 Hz, la validation serveur des tirs, les bots
et l'outillage (987 tests, contrôles de map, sondes de performance) sont solides et documentés. En face, un joueur a une
AWP, un couteau, une map et un mode ; rien ne se débloque, ses statistiques ne lui sont jamais montrées, et la manche se
termine par un nom à l'écran avant de le renvoyer au menu.

Trois choses pèsent sur la première minute de jeu, toutes mesurées ou vérifiées : aucune protection à l'apparition sur
Dizzy (et les bots tirent dès la fin de leur délai de grâce), aucune information sur sa propre vie ni sur les coups
reçus, et aucun apprentissage du surf en jeu (le seul texte d'aide donne les touches QWERTY).

Côté anti-triche, le socle est complet mais presque toute la géométrie du tir et du déplacement est en journal seul, et
le journal ne compte pas ce qu'il faudrait pour décider de passer en blocage.

L'ordre proposé : d'abord l'apparition et les retours de combat (ce qu'un nouveau joueur subit), ensuite la fin de
manche et les statistiques (une raison de rester), puis le premier déblocage (une raison de revenir), enfin la dette.

## Mesures (Studio, 2026-11-12)

| Sujet | Valeur |
|---|---|
| `bash tools/check.sh` | code de sortie 0 ; selene 0 erreur, 0 avertissement ; 987 tests réussis sur 57 specs |
| Dizzy, pièces par dossier de `Geometry` | Walls 6 196, Ceilings 2 994, Floors 1 868, Decor 1 416, Ramps 1 140, Clips 666 |
| Dizzy, autres dossiers | Dressing 236, Underside 52, GroundSpawns 24, Ladders 2 ; `SunLaunch` et `Boosts` absents ; `KillHeight` = −88,77 |
| `Dizzy:FindFirstChild("Clips")` | nil (le dossier est `Geometry.Clips`, 666 pièces, toutes `CanQuery` et `CanCollide`) |
| Points d'apparition | 24 points en deux groupes de 12 : ouest (X 1 756 à 1 817, Z −146 à −81) et est (X 2 183 à 2 244, Z −439 à −374) ; sols de X 1 723 à 2 278 et Z −561 à 39 |
| Protection à l'apparition | 8 apparitions du joueur, `ForceField` absent les 8 fois (à 0 s et à 1,5 s) |
| Lieu des 8 apparitions | toutes dans le groupe est, sur 4 points distincts |
| Régénération | script `Health` de Roblox présent sur le personnage ; après 86 dégâts : 14 PV à +1 s, 16 PV à +3 s |
| Bots sans attribut de debug | 5 bots pour 1 joueur |
| Durée de vie du joueur immobile, 5 bots | 6,7 · 12,5 · 13,6 · 15,6 · 4,0 · 4,5 · 11,9 s (délai de grâce des bots : 4 s) |
| Bilan des bots à 70 s | 43 combats, 62 tirs, 28 touches, 25 kills, 0 coup de couteau, 1 783 visées retenues par le délai de grâce |
| Navigation à 70 s | 13 destinations atteintes, 0 arête ratée, 7 descentes, 3 sauts, 1 échelle, 0 rampe ; bhop : 66 studs/s au plus |
| Coût serveur des bots (`PerfServer`) | `srv bots` 0,70 à 1,27 ms par frame en moyenne, 11,6 ms au pire ; Heartbeat médian 16,9 ms, p99 19 à 39 ms |
| Construction du plan de navigation | 13,3 s (cases 7,7 · marche 1,4 · rebords 0,5 · rampes 0,9 · vue 2,5) ; 41 191 cases, 29 555 gardées |
| `DebugPlaytest` AWP | PASS 9/9, 115 dégâts reçus pour 115 attendus |
| `DebugPlaytest` M9 Bayonet | PASS 9/9, 50 dégâts reçus pour 50 attendus |

Les 8 apparitions dans le même groupe ne prouvent rien : `SpawnManager.pickPoint` tire au hasard uniforme parmi les
24 points, et un tel tirage arrive moins d'une fois sur cent. À reprendre sur 50 apparitions avant de conclure.

## État et constats par domaine

### Déplacement, caméra, map

**État.** Physique Source maison partagée par le joueur et les bots (`CharacterMotor`), tick fixe de 64 Hz avec
affichage interpolé, auto-bhop réglable, coyote et buffer de saut, accroupi, échelles. La caméra FPS ne fait que la
rotation et la position. Une seule map, Dizzy, dont les rampes sont contrôlées à la génération. Les règles pures sont
bien testées ; ce qui dépend des raycasts ne l'est pas.

1. **Saut d'échelle inopérant à mi-hauteur** · bug probable · [V] · `MovementController.step` décroche de l'échelle sur
   `shouldJump`, que `CoyoteJump.update` ne rend vrai qu'au sol ou dans la fenêtre coyote. Sur l'échelle, le moteur est
   en l'air (`setAirborne` à chaque tick) : Espace ne décroche qu'au pied. `docs/maps.md` annonce « saut = poussée
   hors du mur ». Effet en jeu non mesuré.
2. **Second saut par coyote après un saut d'auto-bhop** · fragilité · [V] à la lecture, [D] pour l'effet ·
   `BhopSystem.update` force le saut (`forceJump`) sans que `CoyoteJump` le sache (`didTriggerJump` reste faux) : au
   tick suivant la fenêtre coyote s'ouvre, et un nouvel appui d'Espace dans `COYOTE_TIME` relance `JUMP_VELOCITY` par
   `CharacterMotor.airPhysics`. L'état de `CoyoteJump` est au niveau du module et n'est jamais remis à zéro à
   l'apparition.
3. **Air strafe dépendant du framerate sous 64 FPS** · fragilité · [D] · le cap de la caméra est lu une fois par frame :
   quand une frame joue deux ticks, le second se fait au même cap et n'ajoute presque rien. Le « même trajet quel que
   soit le FPS » ne vaut qu'à entrées égales par tick. À mesurer avant toute décision (cf. « À vérifier en jeu »).
4. **Constantes inertes et code mort** · dette · [L] · `AIR_ACCEL` sans effet au-dessus d'environ 12,8 et
   `SURF_FRICTION = 1` neutre ; jamais appelés : `SlopeSystem.slideStep`, `HeadCollisionResolver.sweep` et
   `getHeadHitAlongMove`, `CrouchSystem.getCamHeight` ; deux seuils de pente (`SLOPE_ANGLE_MAX` et 0,7) ; valeurs en
   dur (`PUSH_OUT`, `CAST_SKIN`, le `- 0.4` de `FPSCamera.setCamHeight`).
5. **Hauteur de marche non bornée par `STEPUP_HEIGHT`** · fragilité · [D] · le recollage au sol de `moveGrounded`
   monterait sur des obstacles d'environ 1,8 à 2,1 studs pour 1,2 annoncé.
6. **La map compense deux défauts du mouvement** · fragilité · [L] · enfoncement d'environ 0,3 stud à l'atterrissage sur
   une rampe (compensé par `RampEdges.SKIN`) et perte de vitesse aux jointures de virage : toute nouvelle rampe exige
   la peau, et les rampes courbes restent exclues.
7. **Accroupi approximatif** · fragilité · [L] · `CharacterDimensions.getCrouch` n'atteindrait jamais
   `CHAR_HEIGHT_CROUCH`, pas de saut accroupi, `CrouchSystem.canUncrouch` ne tire qu'un rayon central.
8. **Aucun retour de déplacement** · game feel · [L] · ni amorti d'atterrissage, ni lissage des marches, ni effet de
   vitesse sur la caméra ; `GroundInfo.material` est calculé et jamais lu. Les sons recoupent #146.
9. **Une seconde map coûte cher** · dette · [L] · propre à Dizzy : `extract_dizzy.py` (sources hors dépôt),
   `DizzyDressing` (1 881 lignes), `dizzy_patches`. Réutilisable : `RampEdges`, `RampCheck`, `ShadowCulling`,
   `audit_map`, `verify_place`. Bloquant pour une rotation : `MapSelection.activate` détruit les autres maps,
   l'éclairage est unique, `NavPlan.start` ne s'exécute qu'une fois.
10. **Code dormant sur Dizzy** · dette · [M] pour l'absence des dossiers · `BoostSystem`, `SpawnLaunch`, `applyLaunch` et
    `SPAWN_PROTECTION` ne servent à rien sur la seule map jouée (ni `Boosts` ni `SunLaunch`).

### Combat, rounds, données, progression

**État.** AWP (zones de dégâts, cadence, chargeur, lunette à deux niveaux) et deux couteaux aux statistiques identiques.
Un mode FFA de 5 minutes où le serveur fait autorité. La demande d'apparition, la mort et le retour au menu sont très
soignés et testés. `InventoryStore` est robuste ; `StatsStore` est rudimentaire.

11. **Aucune protection à l'apparition** · manque · [M] [V] · `SpawnManager.place` ne pose le `ForceField` que dans la
    branche du lancement depuis le soleil, absente de Dizzy. `pickPoint` ignore les ennemis. Les 24 points tiennent dans
    deux zones d'environ 60 studs de côté : un joueur qui tient une zone à l'AWP voit apparaître ses cibles.
12. **Les PV remontent** · game feel, à trancher · [M] · le script `Health` par défaut de Roblox régénère environ 1 PV
    par seconde. [D] Deux coups de couteau à 50 (0,4 s d'écart) ne tuent plus si un pas de régénération tombe entre
    les deux. Aucun module du jeu n'en tient compte.
13. **Statistiques persistantes presque vides et jamais montrées** · manque · [V] · `StatsStore.getStats` et
    `StatsStore.recordRoundEnd` n'ont aucun appelant : les rounds joués et gagnés restent à 0, et aucun remote n'expose
    les stats. [L] Tout kill impliquant un bot est exclu (`ParticipantRules.killCountsInStats`) alors que les bots
    comblent le serveur à 6 : un joueur seul n'enregistre que ses morts.
14. **`StatsStore` fragile** · fragilité · [V] pour `SetAsync` et la constante, [L] pour le reste · écriture du profil
    entier par `SetAsync` (une écriture tardive d'un autre serveur écrase une session), échec d'écriture muet, une
    écriture toutes les 120 s par joueur même sans changement, arrêt du serveur séquentiel. `InventoryStore` fait déjà
    mieux (`UpdateAsync` avec fusion).
15. **Rien à débloquer** · manque · [V] · `InventoryStore.grant` n'a aucun appelant. [L] La M9 Bayonet est hors de
    l'inventaire par défaut, donc réservée à l'admin ; aucun skin au catalogue (#268) : l'écran d'équipement n'offre
    qu'un choix par emplacement à un joueur normal.
16. **Fin de manche sans enjeu ni enchaînement** · manque · [V] · `RoundManager.endRound` détruit les personnages et
    envoie `{ winnerName, scores }` ; le client n'affiche que le nom du vainqueur puis revient au menu au bout de
    `RESULT_DURATION`, et il faut recliquer JOUER. Ni podium, ni bilan personnel, ni série de kills.
17. **Vainqueur aux cas limites** · bug mineur · [V] pour `computeWinner`, [L] pour l'inscription dès la connexion ·
    à égalité de kills, le moins de morts l'emporte : un joueur resté au menu (0 mort) passerait devant un joueur
    actif ; un vainqueur est proclamé avec 0 kill ; à égalité complète, l'ordre de `pairs` décide.
18. **Kill attribué sans limite de temps** · fragilité · [L] · le dernier attaquant ne s'efface qu'à la mort : une chute
    plusieurs minutes après une touche crédite le tireur.
19. **Tir sans aucune imprécision** · game feel, à trancher · [L] · simulé : zones, cadence, chargeur, temps de sortie,
    vitesse selon l'arme, coup dans le dos. Non simulé : dispersion (en course, en saut, sans lunette), pénétration
    (`Penetration` est un `TODO`), ralentissement quand on est touché, ralentissement à la lunette. `Accuracy` et `RPM`
    ne servent qu'à la fiche du menu. Un tir sans lunette en plein saut est aussi précis qu'un tir posé.
20. **Lunette perdue pendant toute la culasse** · game feel · [L] · le tir quitte la lunette et le clic droit est ignoré
    pendant l'état `FIRING` (1,46 s), sans mise en mémoire.
21. **Freins à l'ajout d'une arme** · dette · [L] · identité sur cinq clés (id d'item, nom du Tool, `WeaponName`,
    `ViewmodelName`, clé de `WeaponConfig`), tables par arme hors config (`DeathRules.PUSH_BY_WEAPON`,
    `BotCombatRules`, `MenuPoses`, `WeaponThirdPerson.POSES`), emplacements figés (`InventoryRules.SLOTS`), un clic par
    tir (pas d'arme automatique), deux niveaux de zoom imposés.
22. **Trois stockages, trois implémentations** · dette · [V] pour les constantes, [L] pour le reste · `withRetry`
    recopié dans `SettingsStore` et `InventoryStore`, `StatsStore` à part ; `GameConfig.AUTO_SAVE_INTERVAL` n'est lu
    nulle part (constante locale dans `StatsStore`) ; `RoundManager.endRound` code `6` en dur au lieu de
    `GameConfig.RESULT_DURATION`, que le client lit.

### Bots

**État.** Série #137 à #145 livrée : plan de navigation automatique, bhop, quatre états, combat validé comme celui d'un
joueur. La population automatique tourne aussi hors Studio (`BotManager.init` lance `adjustPopulation` hors de la garde
`IsStudio`) : 6 moins le nombre de joueurs, 5 au plus. Navigation solide ; combat fonctionnel mais brut.

23. **Murs d'air : branche morte** · bug · [M] [V] · `BotManager.init` et `NavBuilder.build` cherchent
    `map:FindFirstChild("Clips")`, qui vaut nil. La vue des bots et les notes de couvert sont donc arrêtées par des murs
    invisibles, à l'inverse de ce que dit `docs/bots.md`. Corriger le chemin seul ne suffit pas : [L] les tirs des bots
    et des joueurs s'arrêtent aussi sur ces 666 pièces. Décision à prendre : les murs d'air arrêtent-ils les balles ?
24. **Tir dès la fin du délai de grâce** · game feel · [V] pour le mécanisme, [M] pour l'indice · le temps de réaction
    (`seenSince`) court pendant la grâce ; seul `canFire.inGrace` retient le tir, qui part donc dès la fin des 4 s de
    `SPAWN_GRACE`. Deux des sept vies mesurées ont duré 4,0 et 4,5 s. Joueur immobile : indice, pas preuve.
25. **Population comptée sur les connectés** · manque · [V] · `adjustPopulation` lit `#Players:GetPlayers()`, menu
    compris. [L] Six connectés dont cinq au menu : aucun bot ; à l'inverse, 5 bots tournent à 64 Hz pendant que le seul
    joueur est au menu.
26. **Pas de réaction aux dégâts hors combat** · game feel · [L] · un bot blessé de dos ou de loin continue sa course ;
    le couteau est muet pour lui.
27. **Difficulté unique, couteau inutilisé** · manque · [M] pour le couteau · 0 coup de couteau en 62 attaques ; les
    réglages de combat sont des constantes globales, tous les bots sont identiques.
28. **Pas de chien de garde** · fragilité · [D] · un bot posé dans une zone sans sortie resterait immobile sans
    avertissement. Non observé : 0 arête ratée sur la session.
29. **Coût non mesuré en jeu publié** · manque · [L] · `docs/performance.md` laisse la mesure « à faire dans le client
    publié ». En Studio, le coût reste faible (cf. « Mesures »).
30. **Surf minimal** · dépendance · [M] pour le résultat · 0 rampe franchie sur la session ; [L] seules 4 pièces de
    `Ramps` sont éligibles (blocs d'au moins 1 000 studs²), les 1 048 `WedgePart` sont ignorées. Une map de surf
    laisserait les bots à pied.

### Anti-triche, réseau, serveur

**État.** Garde commune sur tous les remotes client → serveur, journal par joueur, résumé au webhook, kick à
3 violations fortes. Bloquant : débit, types, seau de distance, cadence, chargeur, temps de sortie, portée, arme
possédée, délai de réapparition. Aucune fuite par joueur ni erreur non rattrapée trouvée à la lecture.

31. **Presque toute la géométrie est en journal seul** · faille · [L] · origine, direction, ligne de vue, instant du
    tir, orientation et ligne de vue de la mêlée, noclip, vol, statistiques de visée : journalisés, pas bloqués. Seules
    `RemoteArgs` et `shape` sont des violations fortes [V : le kick ne compte que les fortes]. Une triche qui envoie
    des paquets bien formés n'est donc ni refusée ni expulsée. Recoupe #179.
32. **Le journal ne permet pas de décider du passage en blocage** · manque · [L] · compteurs par catégorie et gravité,
    pas par contrôle ; pas de dénominateur (tirs jugés, paquets jugés), pas de ping ; rien n'est émis avant le départ du
    joueur ; résumé perdu si le webhook échoue. La procédure « Passer un contrôle en `block` » de `docs/anticheat.md`
    est infaisable en l'état.
33. **Rembobinage et interpolation supposent une faible latence** · faux positif probable · [D] · le client affiche les
    autres à `INTERP_DELAY` de retard sans extrapoler, et le serveur rembobine du même délai quel que soit le ping.
    Au-delà d'environ 50 ms d'aller simple : affichage par pas, et la parade `direction` refuserait des touches honnêtes
    si elle passait en blocage.
34. **Tir résolu contre une position peut-être non affichée** · fragilité · [D] · le CFrame posé par le serveur se
    réplique aux clients, qui ne replacent les autres personnages qu'au rendu ; le raycast part de `tool.Activated`.
    Entre un paquet et le rendu suivant, la cible serait à sa position serveur, environ 0,1 s en avance. L'ordre exact
    des étapes du moteur n'est pas vérifié : à mesurer.
35. **Seau de distance en cas de saccade serveur** · faux positif probable · [D], calcul non exécuté ·
    `CharacterSyncRules.tryMove` ne rendrait le crédit de silence qu'au premier paquet d'une rafale : après une saccade
    de 0,5 s, un joueur rapide serait renvoyé en arrière, vitesse nulle.
36. **Mêlée : portée jugée sur les positions actuelles, refus muet** · faux positif probable · [L] · la doc relève déjà
    un coup honnête perdu sur 11 en Studio sans latence. Les refus muets ne laissent aucune trace, donc la perte n'est
    pas mesurable.
37. **Tolérance de cadence absolue** · faille mineure · [L] · 0,15 s de tolérance : couteau accepté à 0,25 s au lieu de
    0,4 en continu.

### Interface, entrées, audio, accueil, performance client

**État.** Menu sur la map, équipement, Réglages sauvegardés, menu en partie, HUD complet. Couleurs presque toutes en
tokens, règles de visibilité centralisées et testées. Entrées : clavier et souris. Audio : armes, tirs des autres, ding
de tête. Performance client outillée ; aucune fuite à la réapparition trouvée à la lecture.

38. **Infos : touches fausses en AZERTY** · bug · [V] · `InfosScreen.SECTIONS` écrit « W A S D », « Maintiens A ou D »,
    « Ne touche jamais à W » en dur, alors que `KeyDisplay` et `WeaponBar` passent par `LocalSettings.keyText`. C'est le
    seul texte d'aide du jeu. [L] Clic droit, marche lente et changement d'arme n'y figurent pas.
39. **Aucun apprentissage en jeu** · manque · [L] · le menu ouvre sur ARMES, l'écran de réapparition ne donne aucun
    conseil, l'affichage des touches et le viseur sont coupés par défaut. Recoupe #285.
40. **Ni vie ni dégâts reçus à l'écran** · manque · [L] · aucune lecture de `Health` dans l'interface hors `WeaponBar`,
    et `HitConfirm` ne prévient que le tireur. Avec 86 dégâts aux jambes et la régénération (constat 12), le joueur
    survit sans le savoir et sans savoir d'où vient le coup.
41. **Audio limité aux armes** · manque · [L] · sans son : saut, atterrissage, vent de vitesse, échelle, touche au
    corps, kill, dégâts reçus, mort, impact, clics de menu, fin de round. Pas et musique : #146 et #286.
42. **Mobile et console injouables** · manque · [L] · précisions pour #276 : caméra à la souris seule
    (`FPSCamera.init`), menu en partie sur P, curseurs des Réglages à la souris, équipement au survol. Marchent déjà :
    `Tool.Activated`, `MenuShot`, `WeaponBar`.
43. **Échelle de l'interface bornée de 0,75 à 1,6** · fragilité · [D] · sous 540 px de haut, le bas des écrans sort du
    cadre ; au-delà de 1 152 px, le HUD rétrécit. Aggrave #282.
44. **Tokens et briques à l'abandon** · dette · [L] · 39 tailles de texte littérales dans 10 écrans, huit briques
    `UIKit` sans appelant, voile central recopié trois fois.
45. **Écarts de DA entre écrans** · à juger en jeu · [L] · sous-titre ambre de 12 px sans ombre dans
    `MainMenu.buildTitle`, `FeedbackScreen` en minuscules, anglais mêlé au français (`HUDRules.SPEED_TIERS`,
    « FREE FOR ALL »).
46. **Boucles hors repères de performance** · fragilité · [L] · `KeyDisplay`, `AmmoCounter`, `DeathCamera`,
    `DeathRagdoll` sans `PerfMarkers.wrap` ; `SoundChannels.init` écoute `game.DescendantAdded` pour toute instance.
47. **Fichiers trop gros** · dette · [V] pour les tailles · `SettingsMenu` (969 lignes), `Validator` (853), `RoundHUD`
    (836), `init.server.luau` (672, qui mêle remotes, arme 3P, relais des tirs, mort, bots et cycle de vie).

## Améliorations priorisées

Impact : fort (ce qu'un joueur subit ou ce qui le fait rester), moyen, faible. Effort : S (une demi-journée), M (un à
trois jours), L (plus). Les numéros entre parenthèses renvoient aux constats. Aucune de ces propositions ne double une
issue ouverte ; les recoupements sont indiqués.

### Issues créées le 2026-11-12

Les propositions 1 à 13 et 19 sont devenues des issues. La proposition 1 est scindée en deux (apparition, bots). Les
priorités suivent la définition des labels (`high` = cassé ou bloquant pour jouer) : toutes sont en `medium`.

| Proposition | Issue |
|---|---|
| 1 | #288 Apparition : protection au sol et point choisi loin des ennemis ; #298 Bots : tir dès la fin du délai de grâce |
| 2 | #299 HUD : vie affichée et direction des dégâts reçus |
| 3 | #289 PV : régénération par défaut de Roblox, à garder ou à retirer |
| 4 | #290 Infos : touches écrites en QWERTY et actions manquantes |
| 5 | #291 Aide de première partie |
| 6 | #292 Murs d'air : dossier `Clips` introuvable pour les bots, et règle des balles (reprend le contrôle de `verify_place` de la proposition 24) |
| 7 | #293 Échelle : Espace ne décroche qu'au pied |
| 8 | #294 Saut : second saut possible par coyote après un saut d'auto-bhop |
| 9 et 14 (vainqueur) | #295 Fin de manche : podium, bilan du joueur et vainqueur aux cas limites |
| 10 | #300 Manches enchaînées sans repasser par le menu |
| 11 | #296 Stats persistantes : rounds jamais comptés, kills sur bots ignorés, écriture fragile |
| 12 | #301 Menu : fiche de statistiques du joueur (bloquée par #296) |
| 13 | #302 Premier déblocage : M9 Bayonet obtenue à N kills (bloquée par #296) |
| 19 | #297 Anti-triche : journal mesurable |

Les autres propositions (15 à 18, 20 à 30, et le dernier attaquant périmé de la 14) restent sans issue.

### 1. D'abord : ce qu'un nouveau joueur subit

| # | Proposition | Impact | Effort | Labels |
|---|---|---|---|---|
| 1 | Apparition protégée : `ForceField` court au sol, point choisi loin ou hors de vue des ennemis, temps de réaction des bots relancé à la fin de la grâce (11, 24) | fort | M | `type:feature` `scope:gameplay` `scope:bots` `priority:high` |
| 2 | Vie affichée et indicateur de la direction des dégâts reçus (40) | fort | M | `type:feature` `scope:ui` `scope:gameplay` `priority:medium` |
| 3 | Régénération des PV : trancher, puis retirer le script `Health` ou l'assumer (12) | moyen | S | `type:bug` `scope:gameplay` `priority:medium` |
| 4 | Infos : touches lues dans `LocalSettings.keyText`, actions manquantes ajoutées (38) | moyen | S | `type:bug` `scope:ui` `priority:medium` |
| 5 | Aide de première partie : touches affichées à la première apparition, conseil sur l'écran de mort (39, complète #285) | fort | S à M | `type:feature` `scope:ui` `priority:medium` |
| 6 | Murs d'air : règle des balles à trancher, puis chemin de `Clips` et tirs alignés (23) | moyen | M | `type:bug` `scope:bots` `scope:map` `priority:medium` |
| 7 | Échelle : Espace décroche à toute hauteur (1) | moyen | S | `type:bug` `scope:movement` `priority:medium` |
| 8 | `CoyoteJump` : saut forcé pris en compte, remise à zéro à l'apparition, spec (2) | moyen | S | `type:bug` `scope:movement` `priority:medium` |

### 2. Ensuite : une raison de rester et de revenir

| # | Proposition | Impact | Effort | Labels |
|---|---|---|---|---|
| 9 | Fin de manche : classement final et bilan personnel depuis les `scores` déjà envoyés (16) | fort | S | `type:feature` `scope:ui` `scope:gameplay` `priority:medium` |
| 10 | Manches enchaînées sans repasser par le menu (16) | fort | M | `type:feature` `scope:gameplay` `priority:medium` |
| 11 | Statistiques : `recordRoundEnd` branché, kills sur bots comptés à part, `StatsStore` en `UpdateAsync` par écarts avec échec signalé (13, 14) | fort | M | `type:bug` `scope:player-data` `priority:medium` |
| 12 | Fiche de statistiques du joueur au menu, après 11 (13) | moyen | M | `type:feature` `scope:ui` `scope:player-data` `priority:medium` |
| 13 | Premier déblocage : M9 Bayonet à N kills par `InventoryStore.grant`, après 11 (15) | fort | S à M | `type:feature` `scope:player-data` `priority:medium` |
| 14 | Vainqueur : participants jamais apparus exclus, égalité sans kill déclarée, dernier attaquant périmé après un délai (17, 18) | faible | S | `type:bug` `scope:gameplay` `priority:low` |
| 15 | Sons de combat et d'interface : touche, kill, dégâts reçus, clics, fin de round (41) | moyen | M | `type:feature` `scope:audio` `scope:ui` `priority:medium` `status:needs-ref` |
| 16 | Imprécision de l'AWP (sans lunette, en l'air) et clic droit mis en mémoire pendant la culasse : décision d'abord (19, 20) | moyen | M | `type:question` `scope:weapons` |
| 17 | Bots : population selon les joueurs en round, suspendus sans humain en jeu (25) | moyen | S | `type:feature` `scope:bots` `scope:perf` `priority:medium` |
| 18 | Bots : réaction aux dégâts reçus, puis variation par bot (26, 27) | moyen | S à M | `type:feature` `scope:bots` `priority:low` |

### 3. Anti-triche et réseau

| # | Proposition | Impact | Effort | Labels |
|---|---|---|---|---|
| 19 | Journal mesurable : compteurs par contrôle, dénominateurs, ping, relevé périodique, nouvel essai du webhook (32). Prérequis de 22 et de #179 | fort | S à M | `type:feature` `scope:anticheat` `priority:medium` |
| 20 | Mesurer puis corriger le tir contre une position non affichée (34) | moyen | S | `type:bug` `scope:weapons` `scope:anticheat` `priority:medium` |
| 21 | `tryMove` : crédit de silence gardé sur la rafale, avec un test de saccade (35) | moyen | S | `type:bug` `scope:anticheat` `priority:medium` |
| 22 | Campagne de mesure en latence réelle, puis passage en blocage par étapes, après 19 à 21 (31, 33) | fort | M | `type:feature` `scope:anticheat` `priority:medium` |
| 23 | Durcissements : cadence en seau à jetons, portée de mêlée rembobinée, refus muets journalisés (36, 37) | faible | S | `type:bug` `scope:anticheat` `priority:low` |

### 4. Dette et outillage

| # | Proposition | Impact | Effort | Labels |
|---|---|---|---|---|
| 24 | `verify_place` : contrôler les conventions de map lues par le code (`Geometry.Clips`, `Ramps`, points d'apparition), ce qui aurait signalé le constat 23 | moyen | S | `type:feature` `scope:tooling` `scope:map` `priority:low` |
| 25 | Module DataStore commun aux trois stockages ; `RESULT_DURATION` et `AUTO_SAVE_INTERVAL` lus dans `GameConfig` (22) | faible | M | `type:refactor` `scope:player-data` `priority:low` |
| 26 | Mouvement : constantes inertes et code mort retirés, règles pures extraites avec tests chiffrés (4) | faible | M | `type:refactor` `scope:movement` `priority:low` |
| 27 | Docs : corriger les écarts listés plus bas, scinder `docs/anticheat.md` (état courant d'un côté, mesures datées dans `docs/notes/`) | faible | S à M | `type:docs` `scope:tooling` `priority:low` |
| 28 | Interface : briques mortes retirées, tailles en tokens, `SettingsMenu` et `RoundHUD` découpés (44, 47) | faible | M | `type:refactor` `scope:ui` `priority:low` |
| 29 | Mesures dans le jeu publié : coût des bots côté client et serveur, reliquat de #145 (29) | moyen | S | `type:docs` `scope:perf` `scope:bots` `priority:medium` |
| 30 | Socle multi-map : éclairage par map, rotation, générateur commun (9) | moyen | L | `type:feature` `scope:map` `priority:low` |

Non proposés ici, car à mesurer d'abord : air strafe sous 64 FPS (3), hauteur de marche (5), enfoncement sur les rampes
(6), accroupi (7), échelle de l'interface (43, à traiter avec #282).

## Écarts entre docs et code

Relevés à la lecture [L], sauf mention. À corriger par la proposition 27.

- `docs/architecture.md`
  - « Bots » : plan sondé « ~8 s » ; mesuré 13,3 s en Studio [M].
  - Entrée `StatsStore` : annonce les rounds, jamais comptés [V].
  - Entrée `GameConfig` : recopie des valeurs (contre la règle de l'en-tête) et omet `RESPAWN_MARGIN` et `ACTIVE_MAP`.
  - Entrée `PhysicsStepGround` : bhop des bots « sur une ligne droite du sol », abandonné selon `docs/bots.md`.
  - Entrée `BotRules` : « nombre demandé » est passé dans `BotPopulationRules.debugCommand`.
  - Repère « timer de round » cité, absent du code.
  - « À chaque frame » pour les boosts et les échelles : c'est par tick.
- `docs/bots.md`
  - « Murs d'air ignorés » pour la vue et le couvert : faux sur Dizzy [M].
  - « Ils tombent du soleil » : Dizzy n'a pas de lanceur [M].
  - « Destination tirée au hasard » : `BotBrain` choisit depuis #141.
  - `setBhopAllowed(false)` : jamais appelé.
- `docs/maps.md`
  - Hauteur de mort : « le client détecte la chute » ; c'est `KillZone.check` côté serveur depuis #75.
  - `BoostFx` cité, absent du code ; « son et effet d'un boost » encore à faire alors qu'aucune map n'a de boost.
- `docs/anticheat.md`
  - « Classer les violations » cite des violations que le code refuse en silence.
  - Plan : rembobinage annoncé d'une seconde ; l'effectif est `PositionHistory.MAX_REWIND` = 0,4 s.
  - Colonne « Manque » des remotes : `GetSettings` et `SaveSettings` y sont dits non bornés, `RemoteGuard.RULES` les
    borne.
  - Numéros de ligne d'autres docs cités (`docs/bots.md`, `docs/performance.md`).
- `docs/performance.md`
  - « Ombres pas sauvegardées » : faux depuis #100.
  - Chiffres de map périmés (16 000 pièces ; 17 500 dans `docs/ui.md`) : l'audit en compte 19 927.
- `docs/assets.md`
  - « Ajouter un couteau » ne mentionne pas le champ `slot` de `InventoryRules.ITEMS`, sans lequel l'arme n'est jamais
    équipable (#280) ; l'étape 1 renvoie aux aperçus three.js, abandonnés ; aucune procédure pour une arme à distance.
- `CLAUDE.md` : annonce des « écrans restant à refaire » dans `docs/ui.md`, qui dit la DA appliquée partout.
- Commentaires de code : `FPSCamera` (« sans interpolation ni retard »), `WallSlide` (raisonne à 60 FPS),
  `NavBuilder.build` (« point d'apparition le plus central »), « à tirer » dans `InfosScreen`, `FeedbackScreen` et
  `Transition` (périmé depuis #130).

## Trous de tests

- **Mouvement** : `CoyoteJump` (aucune spec, dépend d'`InputModule` en dur), `CharacterMotor.updateState`,
  `clipVelocity` de `WallSlide`, gain de strafe à 64 Hz, apex du saut ; `PhysicsStep.spec` utilise un pas de 1/60.
- **Rounds et données** : `StatsStore`, `SettingsStore`, `InventoryStore` et `SpawnManager` sans spec ; rien sur le
  timer, `endRound` et les égalités de `computeWinner` ; choix du point d'apparition sans règle pure.
- **Bots** : `BotNavigator`, `BotBrain` (enchaînement vue, grâce, tir), `BotArsenal`, `adjustPopulation`.
- **Anti-triche** : `src/server/CharacterSync.luau` sans spec ; aucune rafale de plus de 0,25 s dans les tests de
  `tryMove` ; aucun test du débit moyen accepté par la cadence.
- **Interface** : `InputModule.getWishDir` (à couvrir avant #276), calcul d'échelle de `UIKit.scaledRoot`,
  `LocalSettings`, `SoundChannels` ; aucun test ne lie les touches d'Infos à `KeyBindings`.

## À vérifier en jeu

Ce qui ne se juge qu'en jouant, par ordre d'utilité pour les propositions ci-dessus.

1. **Apparition** (propositions 1 et 17) : 50 apparitions, répartition entre les deux groupes de points ; 5 bots, joueur
   mobile, un round entier : part des morts entre 4,0 et 4,5 s après l'apparition.
2. **Échelle et double saut** (7, 8) : à mi-hauteur d'une échelle, Espace décroche-t-il ? Espace tenu à l'atterrissage
   puis nouvel appui sous 90 ms : hauteur maximale de la racine (6,6 studs attendus, environ 9,5 si le défaut existe).
3. **Murs d'air** (6) : `DebugBotsFreeze`, se placer derrière un mur d'air ; le bot passe-t-il en combat, son tir et
   celui du joueur traversent-ils ?
4. **Couteau et régénération** (3) : deux coups à 0,4 s d'écart sur un joueur à 100 PV, 20 essais : nombre de survies.
5. **Air strafe selon le framerate** : balayage scripté (vitesse angulaire fixe, touche de côté tenue) à 30, 60 et
   144 FPS, vitesse après 2 s.
6. **Latence** (20, 22) : 100 puis 150 ms simulés ; 30 tirs sur des bots à 60 à 90 studs/s, nombre de lignes
   `direction` au journal ; écart entre la racine d'un bot à `tool.Activated` et sa position au dernier rendu.
7. **Fin de manche** (9, 10) : attribut `RoundDuration` court ; temps entre la bannière et le retour en jeu ; vainqueur
   avec un second compte resté au menu.
8. **Interface** : clavier AZERTY (Infos contre l'affichage des touches) ; émulateur d'appareil (téléphone en paysage,
   1 024 × 768, 2 560 × 1 440) : bouton RETOUR des Réglages visible, chevauchements du HUD.
9. **Jeu publié** (29) : `PerfServer` avec 5 bots pendant 3 minutes, overlay F3 côté client avec et sans bots.

## Fichiers lus

- Docs : `docs/architecture.md`, `docs/maps.md`, `docs/bots.md`, `docs/anticheat.md`, `docs/ui.md`,
  `docs/performance.md`, `docs/assets.md`, `docs/animations.md` (survol).
- Code : `src/shared/movement/`, `src/client/systems/movement/`, `src/client/camera/`, `src/client/systems/weapon/`,
  `src/client/systems/game/`, `src/client/systems/network/`, `src/client/ui/`, `src/client/input/`,
  `src/client/debug/`, `src/server/` (dont `bots/`), les règles et configs de `src/shared/`.
- Outils : `tools/map/build_dizzy.luau`, `RampEdges`, `RampCheck`, `tools/perf/audit_map.luau`,
  `tools/rbxm/verify_place.luau`, `tools/check.sh`, `.github/workflows/ci.yml`.
- Tests : `tests/specs/` (intitulés et specs des domaines cités).
