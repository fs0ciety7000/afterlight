# Contenu du jalon 6 : donjon du Cloître du Cadran Éteint et terrains

> Version 0.1 (2026-11-06). Spécification pour `dungeons.json`, `encounters.json`, `locations.json` et les scènes (`game/world/`). Tout est `[H]`.
> Contrat des scènes : ARCHITECTURE § Scènes de lieu (1 unité = 1 m, -Z = nord, Fern 1,6 m). Budgets de rencontre : GAME_BALANCE §11 ; seuils : §22.1.

## 1. Contraintes communes

| Contrainte | Valeur | Raison |
|---|---|---|
| Disque d'arène | `ARENA_RADIUS_M` = 16 m (`game/engine/balance/combat.gd`) : chaque salle de combat contient un **disque plat et libre de 34 m de diamètre** (16 m + 1 m de marge), centré sur l'ancre de la rencontre | La simulation ne connaît pas le décor ; un mur dans l'arène ferait marcher Fern dans la pierre |
| Centre de l'arène en donjon | L'**ancre** de la salle, pas le point de contact (**nouveau** : champ `arena_center: "anchor"` sur les rencontres de donjon) | Le disque reste dans la salle quel que soit l'angle d'arrivée |
| Distance entre meutes (terrains) | ≥ 22 m entre deux ancres ; ≥ 12 m entre une ancre et un point d'apparition | Aggro max 11 m (lanterne) ; −30 % en exploration (Mana voilé) |
| Pièges d'environnement | **Aucun en combat** (pas de terrain dans la simulation). Les seules zones dangereuses sont les télégraphes ennemis | Lisibilité, déterminisme |
| Budget de rendu | Lieux : 40 à 80 m de côté. Donjon : ≤ 150 appels de dessin **par vue**, seules la salle courante et ses voisines sont visibles | ARCHITECTURE |

Mesure des budgets ci-dessous en « PV effectifs au même niveau » : `hp × (1 + def_ratio)` + `barrière × (1 + def_ratio) / 2`, rapportés à `ENCOUNTER_EHP_BUDGET` (1 080 en unités de niveau 1, ± 25 % : 810-1 350). Loup 360, lanterne 242, sentinelle 936. Un ennemi à `level_offset` k est compté × `(1 + 0,15 (Le + k − 1)) / (1 + 0,15 (Le − 1))`. Estimation à confirmer par le banc (critère 6.7).

## 2. Donjon : `dungeon.silent_dial_cloister`

### 2.1 Données

```json
{ "id": "dungeon.silent_dial_cloister", "origin": "original",
  "name_key": "dungeon.silent_dial_cloister.name", "desc_key": "dungeon.silent_dial_cloister.desc",
  "location": "location.watch_ruins", "level": 10, "map_pos": [0.86, 0.10],
  "scene": "res://game/world/dungeons/silent_dial_cloister.tscn",
  "unlock": { "quest_completed": "quest.main_03" },
  "rooms": [
    { "id": "vestibule",  "kind": "encounter",  "encounter": "encounter.cloister_vestibule" },
    { "id": "gallery",    "kind": "encounter",  "encounter": "encounter.cloister_gallery" },
    { "id": "fountain",   "kind": "rest",       "heal_pct": 0.3 },
    { "id": "courtyard",  "kind": "encounter",  "encounter": "encounter.cloister_courtyard" },
    { "id": "kennel",     "kind": "elite",      "encounter": "encounter.cloister_alpha" },
    { "id": "campfire",   "kind": "checkpoint", "heal_pct": 1.0 },
    { "id": "dial",       "kind": "boss",       "encounter": "encounter.cloister_boss" } ] }
```

Nouveaux champs : `scene`, `map_pos`, `desc_key`. Textes : `dungeon.silent_dial_cloister.name` « Cloître du Cadran Éteint », `.desc` « Cloître accroché à la falaise, derrière le guet. Son cadran est arrêté sur trois heures. » ; nom des salles `dungeon.silent_dial_cloister.room_<id>`.

### 2.2 Rencontres

| ID | Salle | `kind` | `level` | Ennemis | Budget | `loot_table` | `offline_eligible` | `speed_cap` |
|---|---|---|---|---|---|---|---|---|
| `encounter.cloister_vestibule` **(nouveau)** | 1 | `normal` | 10 | `stone_sentinel` × 1, `mist_wolf` × 1 | 1 296 (×1,20) | `loot.field_normal` | `false` | 4 |
| `encounter.cloister_gallery` **(nouveau)** | 2 | `normal` | 10 | `wandering_lantern` × 3, `mist_wolf` × 1 | 1 086 (×1,01) | `loot.field_normal` | `false` | 4 |
| `encounter.cloister_courtyard` **(nouveau)** | 4 | `normal` | 11 | `stone_sentinel` × 1, `wandering_lantern` × 2 (`level_offset` −3) | ~1 330 (×1,23) | `loot.field_normal` | `false` | 4 |
| `encounter.cloister_alpha` (existe) | 5 | `elite` | 11 | `mist_wolf_alpha` × 1 | élite, §11 | `loot.elite_alpha` | `false` | 4 |
| `encounter.cloister_boss` (existe) | 7 | `boss` | 12 | `morvaine` × 1 | boss, §11 | `loot.boss_morvaine` | `false` | 2 |

**Écart avec le GDD §5.3** (décision du jalon 6) : les compositions du GDD dépassaient le budget de §11 (vestibule 2 sentinelles + 1 loup ≈ ×2,1 ; cour 2 loups + lanterne + sentinelle ≈ ×1,8). Les compositions ci-dessus gardent l'intention de chaque salle (rappel de la barrière, interruption sous pression, combinaison) dans ± 25 %.

Les rencontres de salle normales ne sont **pas** éligibles au hors ligne ni à « Chasser ici » : les Ruines (terrain) servent à la chasse, le donjon est une expédition. Elles gardent `location: "location.watch_ruins"` (champ requis) mais ne figurent pas dans `location.encounters`. Mettre à jour les `notes` de l'alpha et du boss (« Temporarily at the Watch Ruins… ») et leurs ancres : `room5_encounter`, `room7_encounter`.

### 2.3 Règles du donjon

| Règle | Comportement attendu (testable) |
|---|---|
| Entrée | `interact` sur la poterne (`Anchors/dungeon_gate` des Ruines). Verrouillée : « Terminez *Le guet abandonné* ». Émet `location_visited {dungeon.silent_dial_cloister}` |
| Palette | Thème Nuit du HUD et éclairage nuit dès l'entrée (DESIGN.md : fondu de 600 ms au jalon 7, coupe au jalon 6) |
| Portes | La porte vers la salle suivante est fermée (grille) tant que la rencontre de la salle n'est pas gagnée ; elle s'ouvre à `encounter_completed` (victoire) avec un son de grille. Les salles de repos sont toujours ouvertes. Revenir en arrière est permis |
| Entre deux salles | Les PV ne remontent pas ; la mana remonte à `mana_regen` par seconde ; la charge d'ultime persiste (GDD §6) |
| Fontaine (3) | `interact` : +30 % des PV max, une fois par expédition ; ensuite « La fontaine est calme » |
| Feu de camp (6) | Premier passage : point de reprise. `interact` : PV et mana pleins (à volonté), sauvegarde, ouverture possible des tactiques |
| Défaite | Retour au dernier point de reprise (entrée ou feu de camp), PV et mana pleins, aucune perte. Les salles gagnées le restent ; la rencontre perdue repart à neuf |
| Sortie | Par la porte de l'entrée, par la sortie après le boss, ou « Voyager » depuis la carte (hors combat). Si au moins une salle est gagnée : confirmation `ui.dungeon.leave_confirm` « Quitter le cloître ? Les salles nettoyées seront de nouveau occupées. » |
| Remise à zéro | Sortir remet tout à zéro : rencontres, fontaine, point de reprise |
| Raccourci `[H]` | Après la première victoire contre Morvaine, l'« escalier du sonneur » relie le vestibule (1) au feu de camp (6). Il rend le boss et l'élite rejouables sans refaire 2 à 4 |
| Coffre | `discovery.cloister_chest` dans la cour (4), ouvrable une fois par partie, après la victoire de la salle |

**État à sauvegarder** (à coordonner avec la refonte du format de sauvegarde en cours) :

```
progress.dungeon_run = { "dungeon_id": "dungeon.silent_dial_cloister", "checkpoint": "entrance" | "campfire",
                         "cleared_rooms": ["vestibule", "gallery"], "fountain_used": true }   # ou absent
progress.cleared_encounters  # existe : premières victoires (XP ×3, butin first_clear, raccourci)
```

Rechargement en cours d'expédition : Fern réapparaît au point de reprise sauvegardé, salles gagnées conservées. Si la sauvegarde ne porte pas `dungeon_run` (repli possible) : réapparition aux Ruines (`from_cloister`), expédition remise à zéro, sans perte d'objet.

### 2.4 Salles

Plan d'ensemble (centres en mètres, scène `silent_dial_cloister.tscn`, -Z = nord). Couloirs de 4 m de large.

```
                       [7 Cadran Ø40, +6 m]   centre (-18, 6, -176)
                              | escalier 12 m
                       [6 Feu 12×14]          centre (-18, 0, -137)
                              | 8 m
      [5 Chenil 36×36] --10 m-- [4 Cour 40×40]   centres (-18, 0, -104) / (30, 0, -104)
                                     | 11 m
                               [3 Fontaine 14×14]  centre (30, 0, -66)
                                     | 5 m (porte est de la galerie)
      [2 Galerie 36×44]  centre (0, 0, -50)
             | 10 m
      [1 Vestibule 36×36]  centre (0, 0, 0)
             | escalier de la poterne, 20 m
      Spawns/default (0, 0, 24)
```

| # | Salle | Rôle (intention) | Taille (m) | Rencontre et placement | Points d'apparition / sorties | Lumière (palette nuit) | Intensité |
|---|---|---|---|---|---|---|---|
| 1 | Vestibule | **Rappel** de la barrière ennemie, sans surprise | 36 × 36, plafond 10 m, toit à demi effondré | `cloister_vestibule` sur `room1_encounter` (centre) ; la sentinelle au centre, le loup couché à 4 m derrière elle | `Spawns/default` (0, 0, 24) ; `Exits/to_watch_ruins` sur l'escalier de la poterne (`to: location.watch_ruins`, `spawn: from_cloister`) ; départ de l'escalier du sonneur au mur ouest (fermé avant le 1er boss) | Puits de lune par le toit effondré, sur le centre : la sentinelle est découpée en contre-jour. Braseros éteints | 0,4 |
| 2 | Galerie des cloches | **Interruption sous pression** : 3 lanceurs, une seule Zoltraak toutes les quelques secondes | 36 × 44, nef ; piliers seulement aux bords (x = ± 17) | `cloister_gallery` sur `room2_encounter` (centre) ; lanternes en arc à 8-10 m du centre côté nord, loup au centre | Porte nord → couloir vers rien (murée) ; porte est à z = -66 → Fontaine | Fenêtres hautes à l'est : rais de lune sur 3 cloches muettes suspendues dans l'axe. Les lanternes ennemies sont les seules sources chaudes : cibles lisibles | 0,6 |
| 3 | Fontaine | **Repos** et récit | 14 × 14 | Aucune. Fontaine au centre (`room3_fountain`) | Porte nord → Cour | Eau qui luit d'un nacre pâle ; une bougie dans une niche (chaud, rassurant). Ligne de Fern | 0,1 |
| 4 | Cour du préau | **Combiner** : barrière à briser + incantations à couper + choix de cible | 40 × 40 à ciel ouvert, arcades au-delà du disque | `cloister_courtyard` sur `room4_encounter` (centre) ; sentinelle au centre, lanternes aux angles nord-est et nord-ouest à 9 m. Coffre `room4_chest` sous l'arcade sud-est | Porte ouest → Chenil | Pleine lune haute ; au nord, au-dessus des arcades, la silhouette du clocher et son cadran arrêté sur trois heures : **repère** du boss | 0,7 |
| 5 | Chenil | **Élite** : interrompre le Hurlement | 36 × 36, deux grilles de chenil (est, ouest) | `cloister_alpha` sur `room5_encounter` (centre) ; l'alpha couché au fond (nord), se lève à l'entrée. Les renforts du Hurlement sortent visuellement des grilles | Porte nord → Feu de camp (ouverte après victoire) | La plus sombre : deux torches aux grilles, yeux pâles de l'alpha. Les télégraphes gardent couleur + contour + hachures (lisibles sans lumière) | 0,8 |
| 6 | Feu de camp | **Point de reprise** avant le boss | 12 × 14 | Aucune. `room6_campfire` | `Spawns/checkpoint_campfire` ; arrivée de l'escalier du sonneur à l'ouest ; escalier nord vers le Cadran | Feu orangé dominant, rayon 6 m : signal de sécurité | 0,1 |
| 7 | Salle du Cadran | **Boss** : tout ce qui précède | Circulaire Ø 40, 6 m plus haut ; cadran gravé au sol Ø 24 ; cloche suspendue 20 m au-dessus, puits ouvert | `cloister_boss` sur `room7_encounter` (centre) ; Morvaine au centre. Déclenchement : franchir le cercle du cadran (rayon 12 m) → `dialogue.morvaine_intro` → `encounter_started`. 4 alcôves (`room7_lantern_a..d`) pour l'apparition visuelle des lanternes liées | Après la victoire : porte nord → escalier extérieur → `Exits/to_watch_ruins_back` (`spawn: from_cloister`) | Lune froide par le puits ; fils de cendre rouge braise entre Morvaine et ses lanternes (lien visible, GDD §9.3). **À la victoire** : la cloche sonne, une lumière chaude descend du puits en 3 s (« lumière d'après ») | 1,0 |

### 2.5 Chemin critique

```
Ruines (poterne, clé via main_03) → 1 Vestibule [combat] → 2 Galerie [combat] → 3 Fontaine [soin 30 %]
→ 4 Cour [combat, coffre] → 5 Chenil [élite] → 6 Feu de camp [reprise] → 7 Cadran [boss] → sortie vers les Ruines
```

Longueur à pied ≈ 300 m (≈ 60 s à 5 m/s). Durée d'une première expédition au bon niveau : 3 rencontres × ~20 s + élite ~60 s + boss ~180 s + marche et lecture ≈ 7 à 9 min `[H]`. Toutes les portes sont sur le chemin : rien n'est optionnel sauf le coffre et la fontaine.

Courbe en dents de scie : 0,4 → 0,6 → 0,1 → 0,7 → 0,8 → 0,1 → 1,0 (GDD §5.3).

### 2.6 Lumière : jalon 6 et jalon 7

| Jalon | Livré |
|---|---|
| 6 | `Environment` nuit par salle (lune `#bcd0ff`, ambiance `#1a2433`, sources chaudes ponctuelles), HUD en thème Nuit dès l'entrée, retour au thème Jour à la sortie. Coupe nette |
| 7 | Fondu de 600 ms à la poterne (coupe si « Réduire les animations ») ; lumière chaude de 3 s à la mort de Morvaine ; particules de poussière dans le vestibule (< 200) |

## 3. Ruines du Guet (`location.watch_ruins`, terrain, niveaux 7-9)

Brief court : seulement ce qu'exigent les quêtes et le donjon. Scène 80 × 80 m, colline ; la tour effondrée au nord-est est le repère.

| Élément | Ancre / nœud | Position indicative | Note |
|---|---|---|---|
| Arrivée de la Tourbière | `Spawns/from_lantern_mire`, `Spawns/default` | (0, 0, 36) | Sentier qui monte vers le nord |
| Sortie vers la Tourbière | `Exits/to_lantern_mire` | (0, 0, 39) | `spawn: from_watch_ruins` |
| Retour du donjon | `Spawns/from_cloister` | (24, 0, -30) | À ≥ 12 m de toute meute |
| Poterne du donjon | `Anchors/dungeon_gate` | (26, 0, -36) | Sous la tour ; `interact` |
| Découvertes | `discovery_01` (tour), `discovery_02` (salle des gardes) | (30, 0, -26) / (-24, 0, -10) | `bestiary_discoveries.md` §2.2 |
| Coffre | `chest_01` | (-32, 0, -32) | |

| Rencontre | `level` | Ennemis | Budget | Ancre | Note |
|---|---|---|---|---|---|
| `encounter.watch_ruins_01` (existe) | 7 | sentinelle × 1, loup × 1 | ×1,20 | `encounter_01` (0, 0, 18) | Porte des ruines : introduit la barrière |
| `encounter.watch_ruins_02` **(nouveau)** | 7 | sentinelle × 1, lanterne × 1 | ×1,09 | `encounter_02` (-22, 0, 4) | Barrière + interruption |
| `encounter.watch_ruins_03` **(nouveau)** | 8 | loup × 2, lanterne × 1 | ×0,89 | `encounter_03` (14, 0, -2) | Respiration, sans sentinelle |
| `encounter.watch_ruins_04` **(nouveau)** | 8 | sentinelle × 1, loup × 1 | ×1,20 | `encounter_04` (-14, 0, -24) | Fracas télégraphié + Bond |
| `encounter.watch_ruins_05` **(nouveau)** « Gardiens de la tour » | 9 | sentinelle × 1, lanterne × 1 | ×1,09 | `encounter_05` (10, 0, -26) | `first_clear_rewards` : `material.cloister_key` × 1 |

Tous `normal`, `loot.field_normal`, `offline_eligible: true`, `speed_cap: 4`. `location.watch_ruins.encounters` = ces 5 ID. Les 4 meutes à sentinelle (01, 02, 04, 05) remplissent `quest.main_03.sentinels` (4). Écarts entre ancres ≥ 22 m (vérifiés sur les positions ci-dessus) ; `from_cloister` est à 14,6 m de `encounter_05`.

## 4. Tourbière aux Lanternes (`location.lantern_mire`, terrain, niveaux 4-6)

### 4.1 Intention

Introduire l'**interruption** et les **éléments** (GDD §5.2). Courbe d'apprentissage : introduire (01) → tester (02) → combiner (03) → tordre (04) → conclure (05). Ambiance : eau basse, roseaux, pontons de bois, lueurs flottantes ; au nord-est, le clocher du cloître au-dessus de la colline des Ruines.

### 4.2 Plan (scène 80 × 80 m, origine au centre, -Z = nord)

| Zone | Étendue indicative | Contenu | Rythme |
|---|---|---|---|
| A. Pilotis de l'ouest | x -40 à -18 | Arrivée d'Aubelin, ponton, `herb_01`. Première meute visible à ~13 m | Calme → introduction |
| B. Roselière centrale | x -18 à 14 | `encounter_02`, `encounter_03`, `herb_02`. Repère : le grand fanal noyé (poteau de 8 m) en (0, 0, 8). Roseaux de 1,5 m, en fondu quand ils passent entre la caméra et Fern | Tension |
| C. Îlots de l'est | x 14 à 40, z -20 à 30 | Patrouille `encounter_04`, îlot de la fleur (`discovery_02`) par un chemin de pierres de 2 m, ponton brisé avec `chest_01` | Exploration récompensée |
| D. Bac du nord-ouest | autour de (-30, 0, -24) | Cabane du passeur (`discovery_01`), aucune meute à moins de 26 m | Repos, récit |
| E. Chaussée nord | x -10 à 14, z -40 à -18 | `encounter_05` garde la montée vers les Ruines, `herb_03` | Conclusion |

Chemin principal (sentier plus clair, GDD §5.4) : pontons de A → fanal (B) → chaussée (E). Les bras vers D et C sont des détours visibles depuis le fanal.

| Nœud | Position | Note |
|---|---|---|
| `Spawns/default`, `Spawns/from_aubelin` | (-34, 0, 6), regard vers +X | À 12,6 m de `encounter_01` |
| `Exits/to_aubelin` | (-39, 0, 6), boîte 5 × 3 × 5 | `to: location.aubelin`, `spawn: from_lantern_mire` |
| `Spawns/from_watch_ruins` | (10, 0, -34), regard vers +Z | À 17,2 m de `encounter_05` |
| `Exits/to_watch_ruins` | (10, 0, -39) | `to: location.watch_ruins`, `spawn: from_lantern_mire`. Verrouillée : raison affichée (« Terminez *Lueurs sur la tourbière* ») |
| `Anchors/discovery_01` | (-30, 0, -24) | Journal du passeur |
| `Anchors/discovery_02` | (32, 0, 24) | Fleur pressée |
| `Anchors/chest_01` | (34, 0, -32) | Coffre |
| `Anchors/herb_01..03` | (-32, 0, 14) / (0, 0, 6) / (4, 0, -36) | Herbes de brume (quête) |

### 4.3 Rencontres

| Rencontre | `level` | Ennemis | Budget | Ancre | Rôle |
|---|---|---|---|---|---|
| `encounter.lantern_mire_01` (existe) | 4 | lanterne × 2, loup × 1 | ×0,78 | `encounter_01` (-22, 0, 2) | **Introduire** : premier Embrasement, ligne de Fern à l'entrée |
| `encounter.lantern_mire_02` **(nouveau)** | 4 | loup × 2, lanterne × 1 | ×0,89 | `encounter_02` (-6, 0, 20) | **Tester** : la lanterne reste derrière les loups, focaliser ou interrompre |
| `encounter.lantern_mire_03` **(nouveau)** | 5 | lanterne × 3, loup × 1 | ×1,01 | `encounter_03` (6, 0, -2) | **Combiner** : trop d'incantations pour tout couper, le givre aide (runes au niveau 4) |
| `encounter.lantern_mire_04` **(nouveau)** | 5 | lanterne × 4 | ×0,90 | `encounter_04`, patrouille (28, 0, 12) ↔ (30, 0, -10) | **Tordre** : meute en mouvement (1,5 m/s, pause 3 s aux extrémités), engagement à découvert ; garde la fleur |
| `encounter.lantern_mire_05` **(nouveau)** | 6 | lanterne × 2, loup × 2 | ×1,11 | `encounter_05` (-4, 0, -24) | **Conclure** : garde la montée vers les Ruines |

Tous `normal`, `loot.field_normal`, `offline_eligible: true`, `speed_cap: 4`, `respawn_s` par défaut. `location.lantern_mire.encounters` = ces 5 ID. Distances entre ancres (positions ci-dessus) : 01-02 24,1 ; 02-03 25,1 ; 03-04 ≥ 22,5 (tout le trajet de patrouille) ; 03-05 24,2 ; 04-05 ≥ 36,8 ; 01-05 31,6 m. Patrouille : nouveau champ `patrol: [[x, z], …]` sur l'ancre (métadonnée de scène), lu par l'exploration seulement ; le combat démarre là où la meute est touchée.

`quest.main_02` demande 4 victoires sur ces rencontres (n'importe lesquelles, rejouées comprises).

## 5. Aubelin (`location.aubelin`, hub) : ajouts

| Nœud | Position indicative | Note |
|---|---|---|
| `Exits/to_lantern_mire` | bord est, ~(31, 0, 4) | `to: location.lantern_mire`, `spawn: from_aubelin` ; verrouillée avant `main_01` (raison affichée) |
| `Spawns/from_lantern_mire` | ~(26, 0, 4), regard vers -X | |
| `Anchors/npc_forge`, `npc_runecarver`, `npc_clockmaker` | près de la forge, d'un atelier, d'une maison à horloge | Bastien, Maëlle, Tobias |
| `Anchors/npc_herbalist` | renommer `discovery_bridge` | Ysaline, près du ruisseau |

`location.aubelin.exits` et `npcs` à remplir en conséquence.

## 6. Plan de test

| Test | Type | Attendu |
|---|---|---|
| Disque d'arène | unitaire (scène) | Pour chaque ancre de rencontre de donjon, aucun collisionneur de calque 1 dans un rayon de 17 m au-dessus du sol |
| Écarts | unitaire (scène) | Ancres de meutes ≥ 22 m ; ancres ↔ points d'apparition ≥ 12 m |
| Budgets | unitaire (banc) | Chaque nouvelle rencontre tient les seuils §22.1 (normale `idle` typique ≥ 95 %, p50 15-30 s) ; sinon ajuster `level_offset` avant les effectifs |
| Portes | E2E | La porte de la salle 2 est fermée avant la victoire de la salle 1, ouverte après |
| Défaite | E2E | Défaite en salle 4 → réapparition à l'entrée, salles 1 et 2 vides, PV pleins |
| Rechargement | E2E | Rechargement après le feu de camp → réapparition au feu de camp |
| V12 | unitaire | Dernière salle `boss` ; témoin invalide avec une salle après le boss |
| Test de jeu (T4, T5) | observation | Le joueur s'arrête-t-il à la fontaine ? Utilise-t-il le feu de camp pour régler ses tactiques avant le boss ? Combien d'essais à l'alpha (≤ 3) et au boss ? |
