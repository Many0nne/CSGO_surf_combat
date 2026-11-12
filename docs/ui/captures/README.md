# Captures de référence de l'interface

Une image par écran, pour désigner ce qu'on veut changer (« dans `reglages-viseur.png`, le libellé APERÇU… ») sans
avoir à lancer le jeu. Direction artistique et construction de chaque écran : `docs/ui.md`.

- **Prises le 2026-11-12** sur `main` (`7331170`, après #280), en playtest Studio, map Dizzy, 5 bots.
- **Format :** viewport seul, 16:9, 1349 x 759 px (1079 x 607 px d'interface, échelle Windows 125 %).
- **Réglages du compte de test, pas les valeurs par défaut :** visée simplifiée activée avec un viseur ambre sans
  contour, affichage des touches en mode `simple`. Par défaut, la visée simplifiée est coupée (pas de crosshair) et
  les touches ne sont pas affichées.
- La barre en haut à gauche (logo, menu, chat, micro) est celle de Roblox, pas du jeu.
- Une capture périmée se refait : procédure dans `docs/ui.md`, section « Captures de référence ».

## Menu principal

| Capture | Écran | Code | Comment y arriver |
|---|---|---|---|
| [menu-accueil.png](menu-accueil.png) | Accueil : onglets, écran d'équipement sur l'emplacement SNIPER, fiche de l'arme | `MainMenu`, `EquipmentScreen`, `MenuScene` | Au lancement, ou onglet ARMES |
| [menu-equipement-couteau.png](menu-equipement-couteau.png) | Écran d'équipement sur l'emplacement COUTEAU (2 possédés) | `EquipmentScreen` | Clic sur « 2 · COUTEAU » |
| [menu-message-apparition-impossible.png](menu-message-apparition-impossible.png) | Message ponctuel sous les onglets (« IMPOSSIBLE DE REJOINDRE LA PARTIE, RÉESSAIE ») | `MainMenu.showNotice` | JOUER avec `workspace:SetAttribute("DebugSpawnFail", true)`, après 30 s |
| [transition-deploiement.png](transition-deploiement.png) | Volets blancs « DÉPLOIEMENT » | `Transition` | Juste après JOUER |
| [infos-surfer.png](infos-surfer.png) | Infos > SURFER | `InfosScreen`, `MenuPage` | Onglet INFOS |
| [infos-commandes.png](infos-commandes.png) | Infos > COMMANDES | `InfosScreen` | Onglet INFOS, catégorie COMMANDES |
| [infos-credits.png](infos-credits.png) | Infos > CRÉDITS | `InfosScreen` | Onglet INFOS, catégorie CRÉDITS |
| [infos-a-propos.png](infos-a-propos.png) | Infos > À PROPOS | `InfosScreen` | Onglet INFOS, catégorie À PROPOS |
| [reglages-souris.png](reglages-souris.png) | Réglages > SOURIS | `SettingsMenu`, `MenuPage` | Onglet RÉGLAGES |
| [reglages-mouvement.png](reglages-mouvement.png) | Réglages > MOUVEMENT | `SettingsMenu` | Onglet RÉGLAGES, catégorie MOUVEMENT |
| [reglages-son.png](reglages-son.png) | Réglages > SON | `SettingsMenu` | Onglet RÉGLAGES, catégorie SON |
| [reglages-touches.png](reglages-touches.png) | Réglages > TOUCHES | `SettingsMenu` | Onglet RÉGLAGES, catégorie TOUCHES |
| [reglages-graphismes.png](reglages-graphismes.png) | Réglages > GRAPHISMES | `SettingsMenu` | Onglet RÉGLAGES, catégorie GRAPHISMES |
| [reglages-viseur.png](reglages-viseur.png) | Réglages > VISEUR, avec l'aperçu du viseur | `SettingsMenu`, `Crosshair.draw` | Onglet RÉGLAGES, catégorie VISEUR |
| [feedback.png](feedback.png) | Feedback (champ vide) | `FeedbackScreen` | Onglet FEEDBACK |

## En partie

| Capture | Écran | Code | Comment y arriver |
|---|---|---|---|
| [hud-apparition.png](hud-apparition.png) | HUD à l'apparition, sans arme en main : timer et rang, kill feed, compteur de vitesse, touches, barre d'armes | `RoundHUD`, `KillFeed`, `Speedometer`, `KeyDisplay`, `WeaponBar`, `Crosshair` | JOUER |
| [hud-awp-barre-armes.png](hud-awp-barre-armes.png) | HUD avec l'AWP, barre d'armes affichée, munitions | `WeaponBar`, `AmmoCounter` | Dans les 2,5 s après avoir pris l'AWP |
| [hud-awp.png](hud-awp.png) | HUD avec l'AWP au repos (barre d'armes estompée) | `AmmoCounter`, `Crosshair` | AWP en main, plus de 2,5 s après |
| [hud-couteau-barre-armes.png](hud-couteau-barre-armes.png) | HUD avec le couteau, barre d'armes affichée (pas de munitions) | `WeaponBar` | Dans les 2,5 s après avoir pris le couteau |
| [hud-couteau.png](hud-couteau.png) | HUD avec le couteau au repos | `Crosshair` | Couteau en main, plus de 2,5 s après |
| [hud-lunette.png](hud-lunette.png) | Lunette de l'AWP, premier niveau de zoom (le second a le même réticule) | `ScopeOverlay`, `Reticle` | Clic droit avec l'AWP |
| [hud-timer-fin-de-manche.png](hud-timer-fin-de-manche.png) | Timer en rouge d'impact sous 30 s | `RoundHUD` | 30 dernières secondes de la manche |
| [classement.png](classement.png) | Classement | `RoundHUD` | Tab maintenu |
| [elimination.png](elimination.png) | Réapparition : « ÉLIMINÉ PAR », tueur, arme, compte à rebours, marqueur du tueur | `RoundHUD`, `DeathCamera` | Être tué par un autre joueur ou un bot |
| [fin-de-round.png](fin-de-round.png) | Fin de round : « ROUND TERMINÉ », vainqueur | `RoundHUD` | Fin du timer (6 s) |
| [menu-en-partie.png](menu-en-partie.png) | Menu en partie | `InGameMenu`, `MenuPage` | Touche P (au MCP : attribut `DebugInGameMenu`) |
| [reglages-en-partie.png](reglages-en-partie.png) | Réglages ouverts depuis le menu en partie | `SettingsMenu` (présentation `modal`) | Menu en partie, RÉGLAGES |
| [perf-overlay-f3.png](perf-overlay-f3.png) | Overlay de performance (outil de debug, cf. `docs/performance.md`) | `debug/PerfOverlay` | F3 |

## Ce qui manque

- **Hitmarker** : non capturé (bref, il faut un tir qui touche pendant une rafale de captures).
- **Affichage des touches en mode `full`**, viseur par défaut, échelle du HUD réduite : il aurait fallu changer les
  réglages enregistrés du compte de test.
- **Élimination sans tueur** (« ÉLIMINÉ », « CHUTE ») et fin de round gagnée par le joueur (bande rouge d'impact).
- **Second niveau de zoom de la lunette** : même réticule, seules les images avec le curseur simulé existaient.
- Manette et tactile : jamais essayés (cf. « Reste à faire » de `docs/ui.md`).
