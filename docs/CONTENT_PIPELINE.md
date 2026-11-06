# AFTERLIGHT : pipeline de contenu

> Version 0.1 (2026-11-06). Ce document couvre le contenu de jeu en données. Le chargeur (`game/data/content_db.gd`, autoload `Content`), les schémas (`game/data/schemas.gd`) et la persistance sont décrits dans `docs/ARCHITECTURE.md`. En cas d'écart, ARCHITECTURE fait foi pour la technique, ce document pour les champs de contenu. Les valeurs numériques suivent `docs/GAME_BALANCE.md`.

## 1. Principes

1. **Tout le contenu est en données** : JSON versionné, chargé et validé au démarrage. Aucun ennemi, sort ou objet n'est écrit dans le code.
2. **Des ID stables** : un ID publié ne change jamais, car les sauvegardes le référencent. Pour renommer, on change le texte, pas l'ID. Pour retirer une entrée, on la marque `deprecated: true` et on ajoute une migration.
3. **Canon séparé de l'original** : les dossiers et le champ `origin` sont tous deux obligatoires et doivent concorder.
4. **Aucun texte affiché dans les données** : les entités portent des clés de traduction, et les textes français vivent dans le fichier de traduction.
5. **La validation bloque** : une donnée invalide fait échouer les tests et la construction. Le jeu ne démarre pas sur un contenu invalide en mode debug ; en export, il affiche un écran d'erreur clair.

## 2. Arborescence

```
game/data/
├── canon/                    # uniquement ce qui existe dans l'œuvre (origin = "canon")
│   ├── characters.json       # character.fern, character.himmel (référence seulement)
│   ├── spells.json           # spell.zoltraak
│   └── lore.json             # lore.demons, lore.defensive_magic, lore.mana_concealment
├── original/                 # tout le contenu de fan (origin = "original")
│   ├── characters.json       # (vide dans la tranche)
│   ├── spells.json           # spell.mana_bolt, spell.mana_volley, spell.defensive_barrier, spell.afterlight, passive.*
│   ├── abilities.json        # capacités ennemies ability.*
│   ├── statuses.json
│   ├── enemies.json
│   ├── ai_profiles.json
│   ├── equipment.json        # bases d'objets item.*
│   ├── affixes.json
│   ├── legendaries.json
│   ├── runes.json
│   ├── artifacts.json
│   ├── consumables.json
│   ├── materials.json        # matériaux et monnaies
│   ├── regions.json
│   ├── locations.json
│   ├── dungeons.json
│   ├── encounters.json
│   ├── loot_tables.json
│   ├── quests.json
│   ├── npcs.json
│   ├── dialogues.json
│   ├── discoveries.json
│   └── shops.json            # stock des marchands shop.*
├── schemas.gd                # schémas de validation (ARCHITECTURE)
└── content_db.gd             # autoload Content : chargement, validation, index
game/engine/balance/          # constantes UPPER_SNAKE de GAME_BALANCE.md (pas de JSON : règle 4 d'ARCHITECTURE)
game/i18n/
└── strings.csv               # keys,fr  (clés de traduction → texte français)
```

Un fichier par type d'entité et par origine. Il est inutile de créer un fichier vide dans `canon/` pour un type qui n'a pas d'entrée canon. Enveloppe commune :

```json
{
  "schema_version": 1,
  "type": "enemy",
  "entries": [ { "id": "enemy.mist_wolf", "origin": "original" } ]
}
```

## 3. Conventions d'ID

Format : `<préfixe>.<snake_case>`, avec l'expression régulière `^[a-z]+\.[a-z0-9_]+$`, en anglais, 48 caractères au plus.

| Type | Préfixe | Exemple |
|---|---|---|
| Personnage | `character.` | `character.fern` |
| Sort joueur | `spell.` | `spell.zoltraak` |
| Passif | `passive.` | `passive.veiled_mana` |
| Capacité ennemie | `ability.` | `ability.sentinel_slam` |
| Statut | `status.` | `status.burn` |
| Ennemi | `enemy.` | `enemy.mist_wolf` |
| Profil d'IA | `ai.` | `ai.rusher` |
| Base d'équipement | `item.` | `item.birch_staff` |
| Affixe | `affix.` | `affix.power_pct` |
| Effet légendaire | `legendary.` | `legendary.echo_of_the_master` |
| Rune | `rune.` | `rune.ember` |
| Artefact | `artifact.` | `artifact.cracked_hourglass` |
| Consommable | `consumable.` | `consumable.healing_draught` |
| Matériau | `material.` | `material.mana_dust` |
| Monnaie | `currency.` | `currency.gold` |
| Région | `region.` | `region.aubelin_vale` |
| Lieu | `location.` | `location.whispering_wood` |
| Donjon | `dungeon.` | `dungeon.silent_dial_cloister` |
| Rencontre | `encounter.` | `encounter.wood_pack_a` |
| Table de butin | `loot.` | `loot.wood_normal` |
| Quête | `quest.` | `quest.main_01` |
| PNJ | `npc.` | `npc.odile` |
| Dialogue | `dialogue.` | `dialogue.odile_intro` |
| Découverte | `discovery.` | `discovery.moss_statue` |
| Lore (canon) | `lore.` | `lore.demons` |
| Boutique | `shop.` | `shop.aubelin_merchant` |

Les éléments (`arcane`, `fire`, `frost`, `lightning`), les raretés (`common`, `uncommon`, `rare`, `epic`, `legendary`), les emplacements (`weapon`, `head`, `chest`, `hands`, `feet`, `amulet`) et les statistiques (`power`, `max_hp`...) sont des **énumérations fixes** sans préfixe. Ajouter une valeur à l'une d'elles est un changement de code.

**Clés de traduction** : chaque entité porte `name_key` (requis, ARCHITECTURE) et `desc_key` (requis pour les sorts, objets, runes, artefacts et quêtes). Leur valeur suit la convention `<id>.name` et `<id>.desc` ; la validation refuse une clé qui s'en écarte ou qui manque dans `strings.csv`. Les clés secondaires sont déduites de l'ID : `<id>.lore`, `<id>.line_<n>`, `<id>.objective_<objective_id>`. Exemple : `enemy.mist_wolf.name` = « Loup des brumes ».

## 4. Origine et règles canon

| Champ | Type | Règle |
|---|---|---|
| `origin` | `"canon"` ou `"original"` | Obligatoire. Doit être égal au dossier (`canon/` ou `original/`) |
| `canon_note` | string (anglais ou français, pour l'équipe, jamais affiché) | **Obligatoire si `canon`** : ce qui est canon, et seulement ce qui est sûr (ex. « Name and role are canon; stats are game interpretation ») |
| `canon_refs` | array<ID> | Optionnel sur une entrée `original` : les entités canon auxquelles elle fait référence (ex. Morvaine → `lore.demons`). Chaque ID doit exister dans `canon/` |

Règles :
1. Est **canon** ce qui existe tel quel dans l'œuvre : le nom d'un personnage, d'un lieu, d'un sort, d'une race ou d'un concept. Les statistiques, coefficients et comportements de jeu sont toujours une interprétation, et `canon_note` le dit.
2. En cas de doute sur un fait, l'entrée est **original**, avec un nom original. Cela vaut pour les noms de sorts, les lieux, l'histoire des personnages et leurs relations.
3. **Aucune réplique de l'anime ou du manga.** Tous les dialogues sont écrits pour le jeu, y compris ceux des personnages canon. Un personnage canon peut avoir un ton cohérent avec l'œuvre, jamais une citation.
4. Aucune image, musique ou icône issue de l'œuvre. Ces règles concernent les assets et sont reprises dans DESIGN.md.
5. Les personnages, sorts et lieux canon nommés dans la tranche : `character.fern`, `spell.zoltraak`, `character.himmel` (cité seulement, via une statue originale), et les concepts `lore.demons`, `lore.defensive_magic`, `lore.mana_concealment`. Tout ajout canon passe par une relecture du propriétaire.

## 5. Entités et champs

Légende : **R** = requis, O = optionnel. Champs communs à toutes les entités : `id` (R, string), `origin` (R), `name_key` (R), `desc_key` (R ou O, §3), `canon_note` (R si canon), `canon_refs` (O), `tags` (O, array<string>), `deprecated` (O, bool, défaut false), `notes` (O, string : note d'équipe, jamais affichée).

### 5.1 Combat

**`character`**

| Champ | Type | R/O | Note |
|---|---|---|---|
| `playable` | bool | R | `false` pour les personnages seulement cités |
| `role` | enum `caster`, `tank`, `fighter`, `support` | R si jouable | |
| `base_stats` | object<stat, number> | R si jouable | Valeurs au niveau 1 (§2.1 de l'équilibrage) |
| `growth` | object<stat, number> | R si jouable | Gain par niveau |
| `auto_attack` | ID `spell.` | R si jouable | `kind` doit être `auto` |
| `spells` | array<ID `spell.`> | R si jouable | Actifs, 3 dans la tranche |
| `ultimate` | ID `spell.` | R si jouable | |
| `passive` | ID `passive.` | O | |
| `unlocks` | array<{`level`: int, `ref`: ID}> | O | Déblocage progressif du kit |
| `model` | string (chemin `res://`) | R si jouable | |
| `portrait` | string (chemin) | R si jouable | |

**`spell`** (joueur) et **`ability`** (ennemi) partagent ce schéma.

| Champ | Type | R/O | Note |
|---|---|---|---|
| `kind` | enum `auto`, `active`, `ultimate`, `passive` (ability : `attack`, `skill`, `phase`) | R | |
| `element` | enum élément | R (sauf passif) | |
| `mana_cost` | number ≥ 0 | R pour un actif | |
| `cooldown_s` | number ≥ 0 | R (sauf auto : `interval_s`) | |
| `interval_s` | number > 0 | R si `auto` ou `attack` | |
| `cast_s` / `channel_s` | number ≥ 0 | O | |
| `telegraph` | {`shape`: `circle` ou `line` ou `cone`, `size_m`: number, `duration_s`: number ≥ 0.6} | O (R si `coeff` ≥ 1,5 chez un ennemi) | Le minimum de 0,6 s est vérifié |
| `interruptible` | bool | O, défaut false | |
| `interrupts` | bool | O | Peut interrompre (Zoltraak) |
| `ignores_gcd` | bool | O | |
| `range_m` | number > 0 | R sauf soi | |
| `targeting` | enum `focus`, `nearest`, `distributed`, `random_weighted_focus`, `self`, `area` | R | |
| `effects` | array<effect> (au moins 1) | R | Voir ci-dessous |
| `ult_charge_cost` | int | R si `ultimate` | |
| `ranks` | array de 5 {`rank`, `modifier`?} | R pour un actif ou un ultime | `modifier` : ID d'un effet débloqué au rang 5 |
| `trigger` | {`hp_below`: number ou liste de seuils} ou {`every_s`: number} ou {`on_time_s`: number} | O (ability) | Capacités de phase |
| `tags` moteur | `projectile`, `barrier`, `unavoidable` | O | Lus par la simulation : projectile (vitesse §5 d'équilibrage), barrière ennemie (×2 arcane), impossible à esquiver |
| `vfx`, `sfx`, `icon` | string | O | |

`effect` : `{ "type": "damage" | "heal" | "shield" | "apply_status" | "summon" | "interrupt" | "cleanse" | "damage_reduction" | "restore_mana", "coeff"?: number, "hits"?: int, "radius_m"?: number, "status"?: ID, "chance"?: 0-1, "duration_s"?: number, "summon"?: ID enemy, "count"?: int, "level_offset"?: int }`

**`status`** : `kind` (enum `buff`, `debuff`, `dot`, `cc`, `shield`), `duration_s` (> 0), `max_stacks` (int ≥ 1), `stack_rule` (enum `refresh`, `add_refresh`, `keep_highest`, `none`), `tick_s` (R si `dot`), `modifiers` (array<{`stat`, `kind`: `flat` ou `percent`, `value`}>), `boss_duration_mult` (O), `immunity_after_s` (O), `converts_to` (O, {`at_stacks`, `status`}), `icon` (R).

**`enemy`**

| Champ | Type | R/O |
|---|---|---|
| `archetype` | enum `rusher`, `caster`, `bulwark`, `elite`, `boss` | R |
| `family` | enum `beast`, `spirit`, `construct`, `demon` | R |
| `stats_l1` | {`hp`, `power`, `def_ratio`, `barrier_ratio`, `move_speed`, `aggro_m`} | R |
| `affinities` | {`arcane`, `fire`, `frost`, `lightning`} → `weak`, `neutral` ou `resist` | R (les 4 clés) |
| `attack` | ID `ability.` (kind `attack`) | R |
| `abilities` | array<ID `ability.`> | O |
| `phases` | array<{`id`, `hp_threshold`: 0-1 décroissant, `abilities`: array<ID>, `on_enter`: array<effect>, `haste`?: number}> | R si `boss` |
| `enrage_s` | number | R si `boss` |
| `ai_profile` | ID `ai.` | R |
| `xp_mult`, `gold_mult` | number > 0 | R |
| `cc_resist` | number 0-1 | O |
| `model`, `scale` | string, number | R, O |
| `bestiary_thresholds` | array<int> (défaut [1, 5, 25]) | O |

**`ai_profile`** : `states` (array d'états parmi `idle`, `patrol`, `aggro`, `approach`, `attack`, `ability`, `kite`, `dead`), `target_rule` (enum `nearest`, `lowest_hp`, `furthest`, `front_row`), `keep_distance_m` (O), `flee_below_m` (O), `ability_priority` (array<ID>), `repath_s` (number, défaut 0.5).

### 5.2 Objets

| Entité | Champs principaux |
|---|---|
| `item` (base d'équipement) | `slot` (R, enum), `implicit` (R, array<{`stat`, `base`}>), `min_ilvl` (R, int ≥ 1), `affix_pools` (O, sinon le pool par défaut de l'emplacement), `icon`, `model` (O) |
| `affix` | `stat` (R), `scaling` (R, `flat` ou `pct` : mise à l'échelle par `ilvl_mult` ou par palier), `layer` (O, `flat` ou `percent`, défaut `flat` : couche de modificateur de §2.2 d'équilibrage, `percent` pour `power_pct`, `max_hp_pct`, `move_speed`), `min`, `max` (R, min ≤ max), `slots` (R, au moins 1), `weight` (R, > 0), `group` (R : au plus un affixe par groupe sur un objet ; les 4 bonus d'élément partagent `element_bonus`) |
| `legendary` | `slot` (R), `effect` (R, objet `{kind, ...}` lu par le moteur : `spell_echo`, `haste_after_spell`, `status_max_stacks`), `weight` (R) |
| `rune` | `group` (R, `conversion` ou `modifier`), `element` (R si conversion), `values_by_tier` (R, 5 nombres croissants), `stat` (R si modifier : clé de modificateur de sort `crit_bonus`, `cost_reduction`, `cooldown_reduction`, `echo_chance` ou `damage_bonus`), `weight` (R : poids du type au tirage), `icon` |
| `artifact` | `max_level` (R, 5), `effect_type` (R : `offline_efficiency`, `low_hp_heal`, `gold_find` ou `active_bonus_damage`), `values_by_level` (R, `max_level` nombres croissants), `unlock` (R, `condition`), `icon` |
| `shop` | `location` (R), `stock` (R, au moins 1 ID `consumable.`) ; prix : `price_base` du consommable et §19 d'équilibrage |
| `consumable` | `effect` (R), `carry_max` (R), `shared_cooldown_group` (R), `price_base` (R) |
| `material` / `currency` | `stack_max` (O, défaut illimité), `icon` (R) |

### 5.3 Monde

| Entité | Champs principaux |
|---|---|
| `region` | `level_range` (R, [min, max]), `locations` (R, array<ID>), `hub` (R, ID de lieu), `map_texture` (R), `unlock` (R, `condition`) |
| `location` | `region` (R), `kind` (R, `hub`, `field` ou `dungeon_entrance`), `level` (R sauf hub), `scene` (R, chemin `.tscn`), `map_pos` (R, [x, y] normalisé 0-1), `encounters` (O, array<ID>), `discoveries` (O), `exits` (O, array<{`to`: ID, `spawn`: string}>), `unlock` (R), `fog_reveal` (O, array<ID>), `npcs` (O) |
| `dungeon` | `location` (R), `level` (R), `rooms` (R, array<{`id`, `kind`: `encounter`, `rest`, `elite`, `boss` ou `checkpoint`, `encounter`?: ID, `heal_pct`?: 0-1}>), `unlock` (R) |
| `encounter` | `location` (R), `kind` (R, `normal`, `elite` ou `boss`), `level` (R), `enemies` (R, array<{`enemy`: ID, `count`: int ≥ 1, `level_offset`?: int}>), `loot_table` (R), `offline_eligible` (R, bool), `speed_cap` (R, 1, 2 ou 4), `first_clear_rewards` (O), `anchor` (R, nom du nœud dans la scène), `respawn_s` (O, défaut 60) |
| `loot_table` | `rarity_profile` (R, `normal`, `elite`, `boss`, `boss_first_kill` ou `chest`), `entries` (R, au moins 1, array<{`kind`: `gold`, `material`, `item`, `rune`, `artifact` ou `consumable`, `ref`?: ID (facultatif pour `item` et `rune` : base ou rune tirée au hasard), `chance`: 0-1, `qty`: [min, max], `per`: `enemy` ou `encounter`, `when`?: `always` (défaut), `first_clear` ou `repeat`}>), `guaranteed` (O). Premier kill d'un boss : profil `boss_first_kill` |
| `discovery` | `location` (R), `kind` (R, `vista`, `lore`, `chest`, `memorial` ou `pickup`), `reward` (R), `reveals` (O), `anchor` (R) |

`condition` est un objet de déblocage, au choix : `{"start": true}`, `{"quest_completed": ID}`, `{"location_cleared": ID}`, `{"level_at_least": int}`, `{"item_owned": ID}` ou `{"all": [condition, …]}`.

### 5.4 Récit

| Entité | Champs principaux |
|---|---|
| `quest` | `kind` (R, `main`, `side` ou `daily`), `giver` (O, ID `npc.`), `prerequisites` (O, array<condition>), `objectives` (R, au moins 1, array<{`id`, `event`: `EnemyDefeated`, `EncounterCompleted`, `TalkedTo`, `DiscoveryFound` ou `ItemCollected`, `target`: ID, `count`: int ≥ 1}>), `rewards` (R, {`xp_factor`?, `gold`?, `items`?, `materials`?, `unlocks`?}), `next` (O, ID) |
| `npc` | `location` (R), `role` (O, `smith`, `runecarver`, `merchant` ou `quest`), `dialogues` (O), `model` (R) |
| `dialogue` | `lines` (R, array<{`speaker`: ID `npc.` ou `character.`, `key_suffix`: string, `condition`?: condition}>), `choices` (O, 3 au plus : {`key_suffix`, `sets_flag`?, `next`?}) |

Le texte d'une ligne de dialogue a pour clé `<dialogue_id>.<key_suffix>`, ex. `dialogue.odile_intro.line_01`.

## 6. Localisation

- **Fichier** : `game/i18n/strings.csv`, colonnes `keys,fr`, importé par Godot comme `Translation`. Il est prêt pour d'autres langues : on ajoute une colonne, rien d'autre à changer.
- Le code et les scènes affichent `tr(key)` et jamais de texte en dur. Même règle pour les libellés d'interface (`ui.button.travel` = « Voyager »).
- **Préfixes des clés hors entités** : `ui.` (interface), `tip.` (conseils), `log.` (journal de combat, avec des paramètres nommés : `log.damage_dealt` = « {source} inflige {amount} à {target} »), `offline.` (résumé), `error.` (erreurs).
- **Style** : vouvoiement dans l'interface, verbes d'action sur les boutons (DESIGN.md), majuscule seulement au premier mot (« Carte du monde »). Les noms propres canon gardent la graphie de l'édition française quand elle est sûre (Fern, Zoltraak). Dans le doute, demander au propriétaire.
- **Pluriels** : clés suffixées `_one` et `_other`, choisies par une fonction utilitaire.

## 7. Ajouter du contenu, pas à pas

### 7.1 Nouvel ennemi

1. Choisir l'ID (`enemy.<nom>`) et l'origine. Un ennemi est original, sauf s'il est nommé tel quel dans l'œuvre et vérifié.
2. Créer ses capacités dans `original/abilities.json` (attaque de base `kind: attack` + capacités). Mettre un télégraphe si `coeff` ≥ 1,5. Pour une incantation à contrer, `interruptible: true`.
3. Ajouter l'entrée dans `original/enemies.json` : archétype, `stats_l1`, les 4 affinités, `ai_profile` existant (ou en créer un dans `ai_profiles.json`), `xp_mult` et `gold_mult`.
4. Ajouter les textes `enemy.<nom>.name`, `.desc` et `.lore`, et chaque `ability.<…>.name` et `.desc`, dans `strings.csv`.
5. Le placer dans une rencontre (`encounters.json`) avec un niveau. Vérifier le budget de PV effectifs (`GAME_BALANCE.md` §11) avec le script de budget du banc de test.
6. Lancer la validation (§8) et les tests de simulation de la rencontre (200 graines, seuils de §22.1).
7. Asset : modèle GLB, animations `idle`, `run`, `attack`, `cast`, `hit`, `death` (voir §9). En attendant, une silhouette de substitution est permise en debug, mais refusée par la validation en mode `release`.

### 7.2 Nouveau sort

1. ID `spell.<nom>`. Un nom canon n'est permis que si le sort est nommé dans l'œuvre et vérifié, avec `canon_note`. Sinon, le sort est original.
2. Entrée dans `canon/spells.json` ou `original/spells.json` : `kind`, `element`, coût, recharge, incantation, ciblage, `effects`, 5 `ranks`.
3. Le rattacher à un personnage (`spells`, `ultimate` ou `unlocks`).
4. Textes : `.name`, `.desc` (avec les paramètres `{coeff}` et `{cooldown}` remplis par le code), et `.rank_5` pour le modificateur.
5. Mettre à jour le calcul `ROT` s'il s'agit d'un sort de dégâts. Le test « hors ligne vs simulation » doit rester sous 15 % d'écart.
6. Icône, effet visuel et son : sans eux, le sort passe en mode debug mais pas en `release`.

### 7.3 Nouvel objet (base d'équipement)

1. ID `item.<nom>`, dans `original/equipment.json` : `slot`, `implicit`, `min_ilvl`.
2. Le rendre obtenable : l'ajouter à au moins une table de butin, ou laisser le tirage par emplacement le choisir. Une base qu'aucune source ne peut donner fait échouer la validation (avertissement en debug, erreur en `release`).
3. Textes `.name` et `.desc`, icône.
4. Nouvel affixe : `affixes.json`, avec `group` pour l'exclusivité. Vérifier que sa `stat` existe dans l'énumération.

## 8. Validation

La validation tourne dans les tests GDScript sans interface (`test`) et au démarrage en debug. Pour chaque règle, un **fichier témoin invalide** dans `tests/fixtures/invalid/` doit échouer, et son pendant valide doit passer.

| # | Règle qui doit faire échouer | Exemple de témoin |
|---|---|---|
| V1 | JSON mal formé, `schema_version` absente ou inconnue, `type` différent du nom de fichier | `enemies.json` avec `"type": "spell"` |
| V2 | ID au mauvais format, ou préfixe qui ne correspond pas au type | `"id": "Enemy.MistWolf"`, `spell.*` dans `enemies.json` |
| V3 | ID en double (dans tous les fichiers, canon et original confondus) | `enemy.mist_wolf` deux fois |
| V4 | `origin` absent, ou différent du dossier | `origin: "original"` dans `canon/` |
| V5 | Entrée canon sans `canon_note` ; `canon_refs` vers un ID absent de `canon/` | |
| V6 | Référence vers un ID inexistant, ou vers le mauvais type | `loot_table: "loot.missing"`, `auto_attack: "enemy.mist_wolf"` |
| V7 | Champ requis absent, type faux, énumération inconnue | `element: "water"` |
| V8 | Nombre hors bornes : coût, recharge ou durée < 0 ; chance hors de [0, 1] ; `min > max` ; poids ≤ 0 ; `count < 1` ; `max_stacks < 1` | `chance: 1.2` |
| V9 | `name_key` ou `desc_key` absent, différent de `<id>.name` ou `<id>.desc`, ou absent de `strings.csv` | `"name_key": "wolf_name"` |
| V10 | Rencontre `boss` ou `elite` avec `offline_eligible: true` ; boss avec `speed_cap: 4` | |
| V11 | Boss sans `phases` ni `enrage_s` ; seuils de phase non décroissants | |
| V12 | Donjon sans salle `boss`, ou dont la dernière salle n'est pas le boss | |
| V13 | Télégraphe de moins de 0,6 s, ou capacité ennemie de `coeff` ≥ 1,5 sans télégraphe | |
| V14 | Table de butin vide, ou dont la somme des chances est nulle ; `rarity_profile` inconnu | |
| V15 | Quête : prérequis en cycle, objectif dont l'événement ne peut pas viser la cible (ex. `EnemyDefeated` vers une découverte), quête principale inatteignable depuis le départ | |
| V16 | Monde : lieu non atteignable depuis le départ en suivant les conditions de déblocage dans l'ordre (cf. vérification du chemin critique de `level-design`), ou condition qui dépend d'un objet obtenable seulement derrière elle | |
| V17 | Rune : `values_by_tier` sans exactement 5 valeurs ou non croissantes ; plus d'une rune de conversion par sort dans une sauvegarde de test | |
| V18 | Personnage jouable sans `auto_attack`, `spells` ou `ultimate` ; sort dont le `kind` ne convient pas à son emplacement | |
| V19 | Champ de texte affiché dans une donnée (tout champ `name`, `text` ou `label` littéral est refusé) | `"name": "Loup"` |
| V20 | ID présent dans une sauvegarde de référence mais retiré des données sans `deprecated` ni migration | |

Les messages d'erreur indiquent le fichier, l'ID, le champ et la règle (`V7 enemies.json enemy.mist_wolf affinities.water : élément inconnu`).

## 9. Pipeline d'assets 3D

Établi par l'essai Fern du 2026-11-06 (détails, mesures et coûts : `art/source/fern/PIPELINE_NOTES.md`). Chaque appel fal est journalisé (`fal_log.json` du dossier source) ; les sorties brutes lourdes (`*_rig_*.glb`, `*_meshy_*`) ne sont pas commitées et se régénèrent depuis le journal.

### 9.1 Personnage (procédure actuelle)

| # | Étape | Outil | Points de contrôle |
|---|---|---|---|
| 1 | Fiche écrite (jamais d'image de l'œuvre en entrée) | texte | Silhouette, couleurs, accessoires ; proportions ~6,5 têtes |
| 2 | Concept de face en A-pose, fond gris uni, **aplats sans ombres peintes** | `fal-ai/nano-banana-pro/edit`, références de style = nos images `art/concepts/directions/` | Bras à ~45°, accessoires tenus à part (bâton modélisé séparément) |
| 3 | Détourage | `fal-ai/birefnet/v2` | Bords nets |
| 4 | Image vers 3D | `meshy/v7.1/image-to-3d` (`pose_mode=a-pose`, `enable_pbr=false`, `target_polycount=30000`) ; Tripo ou Hunyuan 3D Pro à tester pour le dos | Rendu de contrôle face, profil, dos |
| 5 | Squelette et clips | `fal-ai/meshy/rigging/multi-animation` (`height_meters`, `animation_action_ids`) | idle, walk, run, cast au minimum |
| 6 | Assemblage | Blender 5.2 sans interface, `tools/blender/build_character.py` | 15-25 k triangles, couleur de base seule, pieds à y = 0, regard vers -Z, clips en pistes NLA |
| 7 | Contrôle qualité | `tools/blender/render_turnaround.py`, `compose_sheet.py` | Planche face / profil / dos / 3/4 haut, poses de marche et de sort |
| 8 | Intégration | `assets/shaders/toon.gdshader` (2 bandes, ombre teintée, rebord) + `outline.gdshader` (coque inversée) appliqués à toutes les surfaces | Lisible à la caméra 3/4 (50°) ; capture réelle sous xvfb avec `fern_preview.tscn -- --shots` |

Coût observé : 4 appels, ~2 USD, ~4 min de génération par personnage.

### 9.2 Limites connues et améliorations à appliquer au prochain personnage

1. **Texture à aplats** : demander un concept sans ombres, ou aplatir la texture dans Blender (les ombres cuites salissent le cel-shading).
2. **Cheveux, manteau et jupe en pièces séparées** avec os secondaires et ressort (`SpringBoneSimulator3D`) : le squelette automatique ne convient pas aux robes longues (déchirure entre les jambes à la marche).
3. **Tête retouchée à la main** dans Blender : frange raccourcie et yeux lisibles de haut, mains plus petites.
4. **Planche multi-vues** pour que le dos (la vue la plus fréquente en jeu) soit propre.
5. **Poids web** : texture 1K en WebP et compression meshopt du GLB (cible < 2 Mo par personnage).

### 9.3 Statut

**Fern v1** (`assets/models/characters/fern/fern.glb`, 2026-11-06) applique les points 9.2 : texture à aplats (`tools/blender/flatten_albedo.py`), concept multi-vues et `meshy/v7.1/multi-image-to-3d` pour un dos propre, chaînes d'os pour cheveux, manteau et jupe animées par `SpringBoneSimulator3D` (ajouté à l'import par `fern_import.gd`), bâton tenu par l'os `Staff`, clips `idle`, `walk`, `run`, `cast`, `hit`, `death`, `victory`. 1,88 Mo, ~22 k triangles, texture WebP 1K. Procédure complète : `art/source/fern_v1/PIPELINE_NOTES.md` ; relance : `tools/fal/fern_v1.sh`. Coût : 5 appels fal, ~3,8 USD.

Reste à améliorer : `cast` est un balayage du bâton plutôt que le rayon bras tendu des images cibles ; le manteau reste une masse sombre de dos ; `hit` déplace un peu la racine. Godot 4.7.2 n'importe ni meshopt ni la quantification glTF : les GLB restent non compressés, d'où l'importance des textures 1K en WebP.

Fern v0 est conservée pour mémoire dans `art/source/fern/` (comparaison : `art/source/fern_v1/compare_v0_v1.jpg`). Validation A1 du propriétaire : en attente.
