# Effets visuels (VFX) : direction, système et catalogue

> Sorts et retours de combat d'AFTERLIGHT. Renderer Compatibility (WebGL 2) uniquement. Couche **Rendu** (`game/combat/vfx/`) : un effet dessine ce qu'on lui dit, il ne décide rien (ni touche, ni dégâts, ni durée de jeu). Les durées de jeu viennent du moteur et des données.
>
> Code : `game/combat/vfx/`. Shaders : `assets/vfx/shaders/`. Recettes (données) : `assets/vfx/recipes/`. Aperçu : `game/world/prototype/vfx_preview.tscn`. Clips de référence : `art/source/vfx/clips/`.

## 1. Direction

La magie de Fern est **précise, nette et contenue** (DESIGN.md « Direction 3D ») : cercles runiques blanc nacré, rayons fins, peu de particules, une lueur sans néon.

Règles :

1. **Cœur blanc-chaud + frange colorée.** Toutes les formes ont un cœur presque blanc (`core`) et une frange teintée par l'élément (`fringe`). La couleur dit l'élément, la forme dit l'effet : on reconnaît un sort sans la couleur.
2. **Formes nettes.** Traits fins et bords francs (anti-crénelés dans le shader), halos courts. Pas de nuage flou plein écran.
3. **Cercles runiques originaux.** Dessin procédural maison (`vfx_rune_circle.gdshader`) : double anneau, bande de glyphes générés (traits, crochets, points, aucun alphabet existant), anneau gradué, trois cercles en orbite, œil central. **Jamais de pentagramme ni d'étoile**, aucun symbole repris de l'œuvre.
4. **Lueur, pas néon.** Le glow de l'environnement ne prend que les cœurs (seuil HDR 0,85) ; les franges restent désaturées vers le nacré. En plein jour, les effets **couvrent** un peu le fond (alpha prémultiplié) au lieu de s'y additionner, sinon ils se délavent.
5. **Lisible à la caméra 3/4** (50°, ~11 m) : épaisseurs et tailles pensées pour cette distance (trait de cercle ≈ 2,5 cm, rayon de Zoltraak 0,42 m halo compris, chiffres 28 px à 1080p).

### 1.1 Palette par élément

Rôles : `core` (centre), `fringe` (halo), `spark` (particules), `dark` (fumée, cendre, braises de brûlure). Source : `game/combat/vfx/vfx_palette.gd`.

| Palette | core | fringe | spark | dark | Forme distinctive |
|---|---|---|---|---|---|
| `arcane` (Fern) | `#f1f4ff` nacre | `#9d8fe0` améthyste-violet | `#a9c4ff` lueur | `#3a2f5c` | traînées droites, cercles runiques |
| `fire` | `#fff3dc` | `#ff8a3d` | `#ffc067` | `#5a2a1a` | braises qui montent, gravité inversée |
| `frost` | `#f4fbff` | `#7cc8ef` | `#c9ecff` | `#24445c` | losanges lents, éclats de cristal |
| `lightning` | `#fffbe8` | `#e9c95a` | `#fff1a8` | `#4a3f1a` | arcs brisés qui clignotent, étincelles rapides |
| `heal` | `#f4ffe8` | `#9ee08a` | `#cdf5b8` | | colonne + motes qui montent |
| `gold` (critique, niveau) | `#fff6dc` | `#f2c14e` | `#ffe39a` | | éclat à 4 rayons, cercle doré |
| `danger` (télégraphes) | `#ffd9c4` | `#c4553f` | `#ff9a6a` | | aplat hachuré + contour + front de remplissage |
| `ash` (démons) | `#ffcf9a` | `#ff7a3a` | `#ff9a55` | `#2a2426` | flocons sombres + braises |
| `mist` (loups, esprits) | `#eef3ff` | `#b8c6dd` | `#dfe7f5` | `#8a96ad` | bouffées pâles qui dérivent |

### 1.2 Jour et nuit

| | Jour (A) | Nuit (B) |
|---|---|---|
| `cover` (part du fond couverte) | 0,5 | 0 (purement additif) |
| `intensity` | 0,95 | 1,0 |
| Glow de l'environnement (`glow_intensity`) | 0,4 | 1,0 |

`Vfx.night` bascule la palette de tous les effets créés ensuite (les effets en cours gardent la leur).

### 1.3 Environnement requis (WorldEnvironment)

Le glow fonctionne dans le renderer Compatibility (vérifié sous `--rendering-driver opengl3`, même chemin de rendu que WebGL 2). Réglages de la scène d'aperçu, à reprendre dans la scène de combat :

```
tonemap_mode = Linear (0)          # ne décale pas la palette ; les cœurs saturent à 1
glow_enabled = true
glow_levels 1, 2, 3 = 1.0 ; 4 = 0.6 ; 5..7 = 0
glow_intensity = 1.0 (nuit) / 0.4 (jour)
glow_strength = 1.0, glow_bloom = 0.0
glow_blend_mode = Screen (1)
glow_hdr_threshold = 0.85, glow_hdr_scale = 2.0
```

`glow_bloom = 0` est important : sinon tout le décor clair (chemin, ciel) bave en plein jour.

## 2. Couches d'un effet

Chaque sort empile au plus ces couches (une couche = un appel de dessin) :

1. **Cœur chaud** : orbe ou trait blanc (petit, très lumineux, pris par le glow).
2. **Halo** : frange colorée douce autour du cœur.
3. **Anneau** : anneau qui s'ouvre (impact) ou cercle runique au sol (incantation).
4. **Étincelles** : `CPUParticles3D`, 6 à 26 par émetteur, étirées dans le sens de la vitesse (`align_y` + billboard axial).
5. **Traînées / rayons** : quads orientés entre deux points, face caméra autour de leur axe.
6. **Sol** : onde de choc, brûlure au sol, télégraphe (quads à plat).

## 3. Grammaire temporelle

Quatre temps, repris de la référence du propriétaire et adaptés : **anticipation → libération → impact → rémanence**, puis retour au repos.

| Temps | Rôle | Durée |
|---|---|---|
| Anticipation | cercle runique qui se dessine et se remplit, charge au bout du bâton | `cast_s` du sort (données), sinon défaut de la recette |
| Libération | trait, rayon ou projectiles | `channel_s` du sort pour une canalisation, sinon défaut ; plus le temps de vol (distance / vitesse) |
| Impact | flash, éclat, anneau, étincelles, onde au sol | 0,2 à 0,4 s, déclenché à l'arrivée de chaque projectile ou rayon |
| Rémanence | croissant, runes en orbite, brûlure au sol, cercle qui s'efface | 0 à 0,9 s |

| Sort | Recette | Anticipation | Libération | Impact | Rémanence | Total typique |
|---|---|---|---|---|---|---|
| Trait de mana | `vfx.projectile_bolt` | 0,12 s (charge courte) | vol à 25 m/s (≈ 0,3 s à 8 m) | 0,2 s | - | ≈ 0,65 s |
| Zoltraak | `vfx.beam_precise` | 0,3 s | 0,06 s (le rayon touche) puis tient 0,16 s | 0,3 s | 0,3 s | ≈ 1,0 s |
| Salve de mana | `vfx.volley_homing` | 0,4 s | 5 tirs espacés de 0,07 s, vol à 25 m/s | 0,25 s par cible | - | ≈ 1,3 s |
| Barrière défensive | `vfx.barrier_dome` | 0 (instantané) | dôme 0,2 s d'apparition, tient `duration` | ondulation 0,4 s par coup absorbé | éclatement 0,35 s ou fondu 0,25 s | 4 s |
| Lumière d'après | `vfx.sky_rain` | 0,5 s (cercles au sol et dans le ciel) | 2,0 s de canalisation, 12 rayons | 0,25 s par rayon | 0,9 s (onde finale, arrêt sur image 60 ms, secousse 0,5, runes en orbite) | ≈ 3,7 s |

Retour de jeu (GDD §14) : l'arrêt sur image et la secousse ne sont **demandés** que sur critique (`burst` avec `crit`, 50 ms, trauma 0,3), coup de boss (à demander par la scène, 60 ms, 0,6) et ultime (60 ms, 0,5). Jamais sur une attaque auto.

## 4. Budgets

| Poste | Budget | Comment c'est tenu |
|---|---|---|
| Particules par effet | < 200 (DESIGN.md) ; visé < 80 (pic mesuré : 65) | comptes fixés par bloc, réduits de moitié en « Réduire les animations » et en qualité basse ; mesuré au §10 |
| Appels de dessin par effet | ≤ 50 au pic (ultime : 46 mesurés) ; ≤ 20 pour un sort courant (Zoltraak : 18), ≤ 35 pour la salve | une couche = un appel ; les particules d'un émetteur = un appel (multimesh) |
| Blocs vivants | 64 au plus (`Vfx.max_live_blocks`) | au-delà, le plus ancien termine plus tôt |
| Surdessin | gros quads transparents rares et brefs | le plus grand (cercle du ciel, 4 m) dure ≤ 3 s ; flashes < 0,15 s ; aucun plein écran |
| Matériaux | 1 shader par famille (8 shaders) | un `ShaderMaterial` par couche (paramètres animés), mêmes shaders donc mêmes programmes compilés |
| Compilation | 1 fois par shader | `Vfx.prewarm(camera)` au chargement du combat |
| Textures | aucune | tout est procédural ; aucun asset sous licence |

## 5. Réduire les animations

`Vfx.reduce_motion = Settings.reduce_motion` (DESIGN.md « Mouvement ») :

- aucune demande de secousse (`shake_requested` n'est pas émis) ; l'arrêt sur image reste (ce n'est pas un mouvement) ;
- particules divisées par deux ;
- cercles runiques et halos sans rotation, apparition sans dessin progressif ;
- ondes de choc et anneaux sans expansion (taille fixe, fondu seul) ;
- chiffres flottants sans « pop » d'échelle et avec une montée réduite (0,4 m) ;
- pulsations (charge, givre, flamme) coupées.

Repli statique : tous les effets restent lisibles en image fixe (cercle plein, rayon, flash), aucune information ne passe que par le mouvement.

## 6. Architecture

```
Vfx (Node3D, dans la scène de combat)
├── play("vfx.<recette>", ctx) → VfxSequence   # recette = petite timeline de blocs (données)
├── play("<bloc>", params)     → VfxBlock      # un bloc seul
├── number(cible, montant, type)               # VfxDamageNumbers (Label3D)
├── flash(cible)                               # VfxHitFlash (material_overlay 60 ms)
├── signals hit_stop_requested(s), shake_requested(trauma)
└── night, reduce_motion, quality, max_live_blocks, stats(), prewarm(), stop_all()
```

| Fichier | Rôle |
|---|---|
| `vfx.gd` (`Vfx`) | point d'entrée, registre des blocs, drapeaux, demandes de retour de jeu |
| `vfx_block.gd` (`VfxBlock`) | base des blocs : paramètres, horloge propre, cycle de vie, fabriques de couches et de particules |
| `blocks/*.gd` | les 14 blocs (§7) |
| `vfx_sequence.gd` (`VfxSequence`) | joue une recette : temps, ancres, cibles, arrivées |
| `vfx_recipes.gd` (`VfxRecipes`) | charge et valide les recettes JSON, héritage `extends` |
| `vfx_palette.gd` (`VfxPalette`) | couleurs par élément, réglages jour / nuit |
| `vfx_damage_numbers.gd`, `vfx_hit_flash.gd` | chiffres flottants, flash de coup |

Chaque bloc avance avec son **propre `age`** (delta du `_process`), jamais avec `TIME` : les vitesses ×2 / ×4 (via `Engine.time_scale` ou en appelant plus vite) et l'enregistrement à images fixes restent exacts. L'arrêt sur image et la secousse appartiennent à la scène : `Vfx` ne fait qu'émettre des demandes.

Choix des particules : **`CPUParticles3D`**. Les `GPUParticles3D` existent en Compatibility (retour de transformation), mais pour < 30 particules par émetteur le coût CPU est négligeable, le rendu est identique partout, et il n'y a pas de compilation de shader de particules au premier tir.

## 7. Blocs (catalogue et paramètres)

Paramètres communs à tous les blocs : `element`, `intensity` (1), `scale` (1), `index` (rang de la cible), `seed`, `position` ou `follow` (Node3D suivi). Positions : un `Node3D` (suivi en direct) ou un `Vector3`.

| Bloc | Rôle | Paramètres (défaut) |
|---|---|---|
| `cast_circle` | cercle runique au sol ou dans le ciel, remplissage = progression d'incantation | `radius` 1,1 ; `duration` 0,3 (remplissage) ; `appear_s` 0,15 ; `fade_s` 0,25 ; `spin` 0,5 rad/s ; `sky` false ; `height` 0,03 ; `detail` 1 (0 = anneau + glyphes seuls) ; `glyphs` 24 ; `motes` 10 ; `progress` true ; `dark` false (anneau sombre plein des incantations non interruptibles) |
| `charge_orb` | charge au bout du bâton : orbe qui grossit, éclat fin, motes aspirés | `size` 0,34 ; `duration` 0,3 ; `gather` 14 |
| `projectile` | trait voyageur (tête + traînée étirée + motes), courbe, suit la cible, émet `arrived` | `from`, `to`, `to_offset` ; `speed` 25 m/s ; `size` 0,26 ; `trail` 0,9 m ; `arc` 0 ; `curve` 0 ; `curve_spread` 0 (éventail par rang) ; `trail_motes` 10 |
| `beam` | rayon fin : pousse, tient, s'amincit ; flare à la source ; émet `arrived` | `from`, `to` ; `width` 0,42 m ; `core_width` 0,1 ; `grow_s` 0,06 ; `hold_s` 0,16 ; `fade_s` 0,22 ; `flare` 0,6 ; `streaks` 1 |
| `burst` | impact : flash, éclat 4 rayons, anneau, étincelles par élément ; `crit` → plus grand, éclat or, demandes 50 ms / 0,3 | `size` 1 ; `crit` false ; `sparks` 14 ; `ring` true ; `glint` true ; `duration` 0,4 ; `hitstop_ms` 50 ; `shake` 0,3 |
| `shockwave` | anneau au sol qui s'ouvre | `radius` 2,4 ; `duration` 0,45 ; `width` 0,02 |
| `scorch` | brûlure au sol avec braises de l'élément | `size` 1,3 ; `duration` 2,4 |
| `slash_arc` | croissant fin (rémanence) | `size` 1,6 ; `sweep` 0,42 ; `yaw` 0 ; `tilt` 60° ; `duration` 0,3 |
| `rune_orbit` | runes protectrices en orbite | `count` 3 ; `radius` 0,9 ; `height` 0,9 ; `size` 0,32 ; `speed` 2,4 rad/s ; `duration` 1,2 |
| `shield` | dôme runique : treillis, bande de glyphes, ondulation au coup, éclatement | `radius` 1 ; `duration` 4 (< 0 = jusqu'à `stop()`) ; `appear_s` 0,2 ; méthodes `hit(position)`, `break_shield()` |
| `aura` | colonne + anneau + motes : `heal`, `level_up` (cercle doré), `cleanse` | `kind` ; `height` 2 ; `radius` 0,8 ; `duration` 1 ; `motes` 18 |
| `telegraph` | télégraphe ennemi : `circle`, `line`, `cone`, palette danger, hachures, contour, remplissage | `shape` ; `radius` 3 ; `length` 6 ; `width` 1,2 ; `angle` 30° (demi-angle) ; `toward` ; `duration` 1,2 (≥ 0,6) |
| `status` | statut en boucle jusqu'à `stop()` : `burn`, `chill`, `frozen`, `shock`, `stun` (halo runique, pas d'étoiles), `weaken`, `haste` | `kind` ; `height` 1,4 ; `radius` 0,4 ; `stacks` 1-3 ; `duration` -1 |
| `death` | dissolution du maillage de bas en haut + cendre ou brume ; cache la cible à la fin | `target` ; `style` `ash` / `mist` ; `height` 1,4 ; `duration` 1,3 |

Hors blocs :

- **Chiffres flottants** (`Vfx.number(cible, montant, type)`) : `normal` blanc 28, `crit` or 36, `heal` vert « +N », `absorbed` gris « (N) ». Alegreya Sans Bold, contour encre nuit, toujours devant (pas de test de profondeur). Montée 1,2 m en 0,8 s, pop 1,3 → 1 en 120 ms, fondu sur les 40 % finaux. Deux coups sur la même cible en moins de 100 ms sont fusionnés.
- **Flash de coup** (`Vfx.flash(cible)`) : blanc additif 60 ms via `material_overlay` sur chaque maillage (fonctionne sur les maillages skinnés et toon sans toucher leurs matériaux).

## 8. Recettes (données)

Une recette est un fichier `assets/vfx/recipes/<nom>.json`, identifiant `vfx.<nom>`. C'est elle que le champ `vfx` d'un sort ou d'une capacité référence (`docs/CONTENT_PIPELINE.md` §5.1). Les JSON sont inclus dans l'export web sans réglage (vérifié dans un `.pck` exporté).

```json
{
  "id": "vfx.beam_precise",
  "extends": "",                      // optionnel : hérite d'une autre recette
  "doc": "Ce que fait la recette.",
  "defaults": {"element": "arcane"},  // valeurs de contexte par défaut
  "beats": {"anticipation": 0.3, "release": 0.06, "impact": 0.3, "afterglow": 0.3},
  "blocks": [
    {"block": "cast_circle", "beat": "anticipation", "at": "caster", "follow": true,
     "until": "release", "params": {"radius": 1.0}},
    {"block": "beam", "beat": "release", "from": "tip", "to": "target"},
    {"block": "burst", "beat": "impact", "at": "target", "per_target": true}
  ],
  "patch": [{"block": "beam", "params": {"width": 0.5}}]   // avec extends seulement
}
```

Champs d'une entrée de `blocks` :

| Champ | Sens |
|---|---|
| `block` | identifiant du bloc (§7) |
| `beat` | `anticipation`, `release`, `impact` ou `afterglow` |
| `at`, `from`, `to`, `toward` | ancres : `caster` (sol sous le lanceur), `caster_chest`, `tip` (bout du bâton), `target` (torse de la cible), `target_ground`, `center` (centre des cibles), `sky` (au-dessus du centre), `sky_above` (au-dessus de chaque cible) |
| `follow` | le bloc suit le nœud de l'ancre `at` |
| `attach` | passe le nœud de l'ancre en `target` (dissolution) |
| `per_target` | une instance par cible ; avec `count`, nombre d'instances (les cibles sont reprises en boucle) |
| `stagger` / `spread` | décalage entre instances en secondes / réparties sur toute la durée de `release` |
| `delay` | décalage depuis le début du temps |
| `until` | la durée du bloc va jusqu'au début du temps nommé (`release`, `impact`, `afterglow`, `end`) |
| `homing` | `false` : la cible est une position figée au lancement (pas de poursuite) |
| `height`, `toward_view`, `jitter` | hauteur des ancres `sky*` ; part de recul vers la caméra (1 = à l'aplomb à l'écran) ; dispersion au sol déterministe (m) |
| `hitstop_ms`, `shake` | demandes de retour de jeu à l'apparition (sur la dernière instance si `per_target`) |
| `params` | paramètres du bloc (§7) |

Règles de temps : l'impact démarre à l'arrivée de chaque `projectile` ou `beam` lancé en `release` (par cible si `per_target`), sinon à la fin de `release`. La rémanence démarre `impact` secondes après la dernière arrivée.

Héritage : `defaults` et `beats` sont fusionnés, `blocks` est remplacé s'il est donné, `patch` fusionne des `params` dans les entrées du parent de même `block` (et même `beat` si précisé). Exemples : `vfx.ash_bolt`, `vfx.crit`, `vfx.enemy_cast_locked`.

**Contexte** passé à `Vfx.play` (clés toutes optionnelles) :

| Clé | Sens |
|---|---|
| `caster`, `tip` | nœuds (ou positions) du lanceur et du bout du bâton |
| `target` / `targets` | une cible ou une liste (répétitions permises : la liste du moteur, coup par coup) |
| `element` | élément courant, **changeable à l'exécution** (runes de conversion) : il prime sur la recette |
| `cast_s`, `channel_s`, `duration` | durées de jeu venues des données / du moteur |
| `crit`, `scale`, `intensity`, `seed` | critique, échelle, gain, graine (dispersion) |
| `overrides` | `{ "<bloc>": {params} }` : surcharge par bloc (taille d'un télégraphe venue des données, par exemple) |
| `target_height`, `caster_height`, `view_back`, `view_pitch_deg` | hauteur d'impact sur la cible (défaut : 55 % de la hauteur de ses maillages), hauteur du torse du lanceur, direction horizontale vers la caméra (+Z par défaut), tangage (50°) |

Validation : `godot --headless --path . --script res://tools/vfx_check.gd` charge chaque recette et vérifie blocs, temps et ancres.

### 8.1 Recettes livrées

| Recette | Usage |
|---|---|
| `vfx.projectile_bolt` | attaques auto à projectile (Trait de mana) |
| `vfx.beam_precise` | rayon rapide et précis (Zoltraak) |
| `vfx.volley_homing` | salve de projectiles à tête chercheuse (Salve de mana) |
| `vfx.barrier_dome` | bouclier personnel + purification (Barrière défensive) |
| `vfx.sky_rain` | pluie de rayons canalisée depuis le ciel (Lumière d'après) |
| `vfx.enemy_bolt`, `vfx.ash_bolt` | projectile ennemi (Lanterne : feu ; Morvaine, Trait de cendre : cendre) |
| `vfx.enemy_cast`, `vfx.enemy_cast_locked` | incantation ennemie interruptible (anneau nacré) / non interruptible (anneau sombre plein) |
| `vfx.telegraph_circle`, `_line`, `_cone` | télégraphes de zone ennemis |
| `vfx.hit`, `vfx.crit` | coup générique par élément / critique |
| `vfx.status_burn`, `_chill`, `_frozen`, `_shock`, `_stun`, `_weaken`, `_haste` | statuts en boucle |
| `vfx.death_ash`, `vfx.death_mist` | mort : cendre (démons, Morvaine, Sentinelle) / brume (loups, Lanterne) |
| `vfx.heal`, `vfx.level_up` | soin, montée de niveau |

### 8.2 Valeurs du champ `vfx` pour le contenu actuel

| Contenu | `vfx` |
|---|---|
| `spell.mana_bolt` | `vfx.projectile_bolt` |
| `spell.zoltraak` | `vfx.beam_precise` |
| `spell.mana_volley` | `vfx.volley_homing` |
| `spell.defensive_barrier` | `vfx.barrier_dome` |
| `spell.afterlight` | `vfx.sky_rain` |
| `ability.morvaine_ash_bolt` | `vfx.ash_bolt` |
| attaque de la Lanterne (projectile de feu) | `vfx.enemy_bolt` |
| `ability.lantern_blaze`, `ability.alpha_howl`, `ability.morvaine_false_word` (interruptibles) | `vfx.enemy_cast` |
| `ability.morvaine_ash_seal` (non interruptible) | `vfx.enemy_cast_locked` |
| `ability.wolf_lunge`, `ability.alpha_chain_lunge` | `vfx.telegraph_line` |
| `ability.sentinel_slam` | `vfx.telegraph_circle` |

Le schéma des statuts n'a pas de champ `vfx` : la scène construit `"vfx.status_" + id.trim_prefix("status.")` (ou un champ `vfx` peut être ajouté plus tard).

## 9. Événements du moteur → effets

La scène de combat (lead) traduit les événements ; la correspondance proposée :

| Événement | Appel |
|---|---|
| `spell_cast` (début d'incantation) | `seq = vfx.play(spell.vfx, {caster, tip, target(s), element, cast_s, channel_s, seed})` ; garder `seq` par lanceur |
| `cast_interrupted` | `seq.cancel()` + `vfx.play("vfx.hit", {target: lanceur, element: "arcane"})` |
| `attack_started` (ennemi avec télégraphe) | `vfx.play("vfx.telegraph_<shape>", {caster, target, cast_s: telegraph.duration_s, overrides: {telegraph: {radius / length / width}}})` |
| `damage_dealt` | `vfx.number(cible, montant, "crit" si critique)` + `vfx.flash(cible)` ; si la recette n'a pas d'impact propre ou si `crit` : `vfx.play("vfx.crit" ou "vfx.hit", {target, element})` ; si absorbé : `number(..., "absorbed")` et `seq.find_block("shield").hit(position de la source)` |
| `shield_applied` | recette `vfx.barrier_dome` avec `duration` ; bouclier détruit : `find_block("shield").break_shield()` |
| `character_healed` | `vfx.play("vfx.heal", {target})` + `number(..., "heal")` |
| `status_applied` / `status_expired` | `seq = vfx.play("vfx.status_<id>", {target, ...})` / `seq.cancel()` |
| `enemy_defeated` | `vfx.play("vfx.death_ash" ou "vfx.death_mist", {target})` selon la famille (`demon`, `construct` → cendre ; `beast`, `spirit` → brume) ; libérer le nœud après 1,3 s |
| coup de boss | `hit_stop` 60 ms + secousse 0,6 : la scène les applique elle-même (`Vfx.request_hit_stop / request_shake`) |
| `boss_phase_changed`, `encounter_completed` | `vfx.stop_all()` en fin de rencontre ; montée de niveau : `vfx.play("vfx.level_up", {caster})` |

Synchronisation : `VfxSequence.arrived(index, position)` est émis à l'arrivée de chaque projectile ou rayon. Si le moteur émet `damage_dealt` au moment de l'impact (vitesse 25 m/s commune), il suffit d'afficher les chiffres sur l'événement ; sinon la scène peut différer l'affichage jusqu'à `arrived`. `seq.beat(name)` sert à caler les sons.

## 10. Ajouter l'effet d'un nouveau sort

1. **Chercher une recette existante** (§8.1) qui a la bonne forme. Si elle convient telle quelle, mettre son ID dans le champ `vfx` du sort : c'est fini. L'élément suit le sort (et les runes de conversion) via `ctx.element`.
2. **Variante** (taille, vitesse, couleur fixe) : créer `assets/vfx/recipes/<nom>.json` avec `extends` + `defaults` / `beats` / `patch`. Pas de code.
3. **Nouvelle composition** des blocs existants : nouvelle recette avec sa liste `blocks`. Pas de code.
4. **Vérifier** : `godot --headless --path . --script res://tools/vfx_check.gd`, puis voir l'effet dans l'aperçu (ajouter une touche ou un clip dans `vfx_preview.gd` si utile) et enregistrer un clip (`tools/vfx_record.sh <nom>`).
5. **Nouveau bloc** seulement si aucune composition ne suffit : un script `game/combat/vfx/blocks/<bloc>.gd` qui étend `VfxBlock` (`defaults()`, `_build()`, `_tick(t)`, éventuellement `travel_time()` et `arrived`), enregistré dans `Vfx.BLOCKS`, documenté au §7, avec ses budgets.
6. Respecter les règles du §1 (pas de pentagramme, formes nettes) et les budgets du §4 ; mesurer avec l'aperçu.

## 11. Aperçu et enregistrement

- `godot --path . res://game/world/prototype/vfx_preview.tscn` : Fern (toon) face à trois cibles (modèles `assets/models/enemies/<id>/<id>.glb` s'ils existent, sinon capsules). Touches : 1 trait, 2 Zoltraak, 3 salve, 4 barrière (B coup, X éclatement), R ultime, 6 coup, 7 critique, 8 statut suivant, 9 télégraphe suivant, 0 morts, H soin, L niveau, E élément suivant, N jour / nuit, M réduire les animations, Espace remise à zéro. Surcouche : FPS, appels de dessin, objets, primitives, blocs, couches et particules VFX.
- `tools/vfx_record.sh [filtre]` : lance l'aperçu sous xvfb avec `--fixed-fps 30` (chaque image avance l'horloge de 1/30 s, donc les clips sont à vitesse réelle malgré le rendu logiciel), écrit les images dans `art/source/vfx/frames/` (ignoré par git), puis `art/source/vfx/clips/<clip>.mp4`, `<clip>_sheet.jpg` (planche 4 × 2) et `art/source/vfx/perf.json`.

- La commande brute `xvfb-run -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 res://game/world/prototype/vfx_preview.tscn -- --record [--only=<filtre>]` fonctionne aussi, mais sans `--fixed-fps 30` l'horloge suit le temps réel du rendu logiciel et les clips sont saccadés : passer par le script.
- `godot --headless --path . --fixed-fps 60 res://game/world/prototype/vfx_preview.tscn -- --bench` : coût CPU par sort, écrit `art/source/vfx/bench.json`.
- Textures : aucune. Tout est procédural (pas d'appel fal, aucun asset sous licence) ; un atlas de fumée ou d'étincelles pourra s'ajouter dans `assets/vfx/` si le rendu procédural ne suffit pas.

Clips : `mana_bolt`, `zoltraak_night`, `zoltraak_day`, `zoltraak_crit`, `mana_volley`, `barrier`, `afterlight_night`, `afterlight_day`, `hits_elements`, `statuses`, `telegraphs`, `deaths`, `heal_level_up`.

## 12. Coûts mesurés

Mesures de l'aperçu (1280 × 720, xvfb + Mesa llvmpipe, `--rendering-driver opengl3`), pics sur la durée du clip, moniteurs `Performance` (`RENDER_TOTAL_DRAW_CALLS_IN_FRAME`, particules et couches comptées par `Vfx.stats()`). Le décor seul (sol, Fern, trois cibles, ombres) coûte la « base ». Le surcoût de l'effet = pic − base. Les FPS sous rendu logiciel ne disent rien du web : seuls les appels de dessin, les couches et les particules sont retenus.

| Clip | Appels de dessin (base → pic) | Surcoût | Couches VFX vivantes (pic) | Particules vivantes (pic, somme des émetteurs) |
|---|---|---|---|---|
| `mana_bolt` | 52 → 58 | +6 | 6 | 16 |
| `zoltraak_night` / `_day` | 52 → 70 | +18 | 16 | 40 |
| `zoltraak_crit` | 52 → 71 | +19 | 17 | 49 |
| `mana_volley` | 52 → 87 | +35 | 35 | 65 |
| `barrier` (dôme, 2 coups, éclatement) | 52 → 58 | +6 | 6 | 24 |
| `afterlight_night` / `_day` | 52 → 98 | +46 | 38 | 59 |
| `hits_elements` (4 éléments + critique, flash de coup) | 52 → 68 | +16 | 6 | 16 |
| `statuses` (4 statuts simultanés) | 52 → 68 | +16 | 16 | 60 |
| `telegraphs` (cercle, ligne, cône simultanés) | 57 → 55 | ≈ 0 à +3 | 3 | 0 |
| `deaths` (cendre + brume) | 52 → 52 | ≈ 0 (les matériaux de dissolution remplacent ceux de la cible) | 3 | 52 |
| `heal_level_up` | 52 → 62 | +10 | 8 | 48 |

Le surcoût en appels de dessin dépasse parfois le nombre de couches : le flash de coup redessine les maillages de la cible pendant 60 ms (une passe par surface).

Coût CPU des scripts et des particules CPU (mode `-- --bench`, sans rendu, `--fixed-fps 60`, moyenne sur la durée du sort, deux passes ; poste de développement, pas un téléphone) :

| Cas | ms par image |
|---|---|
| scène sans effet | 0,05 |
| Trait de mana | 0,14-0,18 |
| Zoltraak | 0,13 |
| Salve de mana | 0,19-0,21 |
| Barrière | 0,07-0,08 |
| Lumière d'après | 0,30-0,32 |
| 4 statuts en boucle | 0,11-0,12 |

Le pire cas mesuré (ultime : +46 appels, 38 couches, 59 particules) reste sous le budget de particules (< 200) ; avec le décor d'un lieu (< 150 appels, ARCHITECTURE.md), l'ultime ferait monter un combat à ~200 appels pendant 2 s : acceptable sur desktop, à surveiller sur mobile (piste : fusionner les 12 rayons, impacts et brûlures dans un seul `MultiMeshInstance3D` par famille). Les FPS sur navigateur et téléphone ne sont **pas encore mesurés**.

## 13. Limites connues

- **Compatibility** : pas de décalques (`Decal`) ni de lecture de la profondeur utilisée ici ; les marques au sol sont des quads posés à 2-4 cm du sol : sur un terrain en pente ou bosselé, elles peuvent s'enfoncer ou flotter. Pas de distorsion d'écran (pas de `hint_screen_texture` dans ces effets) : les ondes de choc sont des anneaux, pas des réfractions.
- **Glow** : mesuré en OpenGL 3 sur poste ; même renderer que WebGL 2, mais pas encore vérifié dans un navigateur mobile (le glow coûte plusieurs passes plein écran : à couper en qualité basse).
- **Compilation des shaders** au premier usage sur le web : `Vfx.prewarm(camera)` couvre les familles principales, à appeler pendant le chargement du combat.
- **Statuts et dissolution sur modèles** : la dissolution remplace les matériaux de surface de la cible (le contour toon disparaît pendant 1,3 s) ; la cible est cachée à la fin, la scène la libère.
- **Ciel de l'ultime** : l'ancre `sky` suppose une caméra qui regarde vers −Z (`view_back` = +Z) ; à passer en contexte si la caméra de combat tourne.
- Pas de pool d'objets : chaque bloc crée ses nœuds et matériaux (≈ 2 à 8 nœuds). Suffisant aux budgets mesurés ; à revoir si le profilage web montre des à-coups de ramasse-miettes.
