# DESIGN — SLIPSTREAM

Direction artistique du jeu (issue #3). Les tokens vivent dans `src/shared/UITheme.luau` : aucun écran ne code de couleur ni de police en dur.

## Identité

- **Nom** : `SLIPSTREAM` (le sillage d'air dans lequel on prend de la vitesse). Sous-titre : `SURF · FFA`.
- **Logo** : textuel, `SLIPSTREAM` en Michroma, blanc, avec la barre verticale cyan à gauche des panneaux comme signature.
- **Ton** : compétitif, sobre et précis, façon HUD d'instrument. Peu de mots, en majuscules pour les titres, chiffres en monospace. Aucun effet décoratif : la vitesse et le score sont l'info.

## Palette

Deux accents avec un rôle chacun : le **cyan** pour le mouvement et les actions, le **rouge** pour le combat. Un joueur lit la couleur avant de lire le texte.

| Token | RGB | Rôle |
|---|---|---|
| `BG` | 7, 11, 18 | fond plein écran (nuit profonde) |
| `BG_GRAD_TOP` / `BG_GRAD_BOTTOM` | 12, 20, 32 / 4, 7, 12 | dégradé du menu |
| `SURFACE` | 13, 20, 31 | panneaux, cartes |
| `SURFACE_RAISED` | 19, 29, 44 | boutons secondaires, champs, lignes paires |
| `SURFACE_HOVER` | 26, 40, 60 | survol |
| `TRACK` | 24, 36, 54 | rail de slider |
| `BORDER` | 31, 46, 68 | contours, séparateurs |
| `BACKDROP` | 0, 0, 0 | voile derrière une modale |
| `TEXT` | 230, 238, 248 | texte principal |
| `TEXT_DIM` | 168, 182, 200 | texte courant, libellés |
| `MUTED` | 107, 127, 156 | en-têtes de colonne, unités, texte tertiaire |
| `FAINT` | 46, 62, 84 | version, mentions discrètes |
| `ACCENT` | 34, 211, 238 | cyan : Play, vitesse, sliders, 1er du classement |
| `ACCENT_HOVER` | 103, 232, 249 | survol de l'accent |
| `ON_ACCENT` | 4, 18, 26 | texte posé sur l'accent |
| `COMBAT` | 244, 63, 94 | rouge : mort, réapparition, fin de round |
| `WARN` | 245, 158, 11 | timer sous 30 s |
| `HANDLE` | 255, 255, 255 | poignée de slider |

Justification : l'ancien rouge unique servait à tout (Play, vitesse, mort). Le cyan évoque l'air et la vitesse, contraste fortement sur le bleu nuit et laisse le rouge au seul combat, où il garde son poids. `MUTED` est éclairci par rapport à l'ancien (72, 92, 120) qui était illisible sur `SURFACE`.

## Typographie

| Token | Police | Usage |
|---|---|---|
| `DISPLAY` | `Enum.Font.Michroma` | logo, titres d'écran (INFOS, SETTINGS, LEADERBOARD) : large et technique, signature du jeu |
| `HEADING` | `Enum.Font.GothamBlack` | bouton PLAY, bannière de résultat, rang n°1 |
| `LABEL` | `Enum.Font.GothamBold` | libellés, en-têtes, boutons secondaires |
| `BODY` | `Enum.Font.Gotham` | texte courant |
| `MONO` | `Enum.Font.RobotoMono` | timer, vitesse, valeurs, K/D : chiffres à chasse fixe, qui ne bougent pas |

Michroma est très large : on la réserve aux titres courts. Tailles (`TextSize`) : LOGO 26, BANNER 20, TIMER 20, TITLE 18, BUTTON 15, BODY 13, LABEL 11, CAPTION 10, NUMERIC 28.

## Autres tokens

- `Radius` : SM 2 (barres, lignes), MD 3 (boutons, champs, timer), LG 6 (panneaux), PILL 7 (poignée). Angles presque droits : rendu net, compétitif.
- `Space` : XS 4, SM 8, MD 12, LG 24, XL 32 (marges internes des panneaux : 32 à gauche pour la barre, 24 ailleurs).
- `Stroke` : THIN 1 (contours), STRIPE 3 (barre signature, scrollbar).
- `Transparency` : OVERLAY 0.15 (fond Infos), BACKDROP 0.55 (voile Settings), ROW_ODD 0.5 (lignes impaires), HUD 0.2 (cartouche du timer, laisse voir la map).
- `Motion` : FAST 0.1 s (survols).

## Maquettes

Les dispositions existantes sont conservées ; seuls couleurs, polices et tailles changent.

### Menu principal

```text
+------------------------------------------------------------+
|  (dégradé BG_GRAD_TOP -> BG_GRAD_BOTTOM)                   |
|               +-------------------------------+            |
|               || SURF · FFA        (cyan, LABEL)            |
|               || SLIPSTREAM        (Michroma 26, TEXT)      |
|               || ---------------------------- (BORDER)      |
|               || [          PLAY          ]  (fond cyan)    |
|               || [          INFOS         ]  (SURFACE_RAISED)|
|               || [        FEEDBACK        ]                 |
|               +-------------------------------+            |
|  | = barre signature cyan                           v0.1   |
+------------------------------------------------------------+
```

### Infos (overlay)

```text
+------------------- 480 px, 88 % de hauteur ---------------+
|| INFOS (Michroma 18)                                 [ X ] |
| ---------------------------------------------------------- |
|| | HOW TO SURF  (cyan, LABEL)                             |
|    texte courant (TEXT_DIM, BODY 13)                       |
|| | CONTROLS / CREDITS / ABOUT ...           scrollbar cyan |
+------------------------------------------------------------+
```

### Réglages (touche P)

```text
voile noir 55 %
+------------------- 420 x 256 -------------------+
|| SETTINGS (Michroma 18)                         |
| ----------------------------------------------- |
|| Sensitivity   ====o-----------------   [1.00] |
|| Scope Sens    ======o---------------   [0.50] |
|                                       [ CLOSE ] |
+-------------------------------------------------+
  rail TRACK, remplissage cyan, poignée blanche, valeur en RobotoMono
```

### HUD de round

```text
+------------------------------------------------------------+
|                       [ 4:59 ]   timer RobotoMono, WARN < 30 s
|                                                            |
|        +--- LEADERBOARD (Tab) -------------+               |
|        || #  JOUEUR             K     D    |   n°1 en cyan |
|        || 1  Player1            12    3    |               |
|        ||  2  Player2           8     5    |               |
|        +-----------------------------------+               |
|                                                            |
|        +- Réapparition dans 2s -+  contour + barre rouges  |
|                                                            |
|                        SPD                                 |
|                        128 u/s   speedometer, chiffre cyan RobotoMono 28
+------------------------------------------------------------+
Fin de round : bannière 480 x 84, contour et trait haut rouges,
« 🏆  X  remporte le round ! » en GothamBlack 20.
```
