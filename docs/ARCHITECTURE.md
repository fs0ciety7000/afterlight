# Architecture

> Comment AFTERLIGHT est découpé, pourquoi, et quelles règles tiennent le découpage. À lire avant d'ajouter un système.

## Choix techniques

| Besoin | Choix | Pourquoi |
|---|---|---|
| Moteur | **Godot 4.7.2**, GDScript typé | Vrai moteur 3D (animation, navigation, shaders, UI, audio), export web, open source, pilotable en ligne de commande |
| Rendu web | Renderer **Compatibility** (WebGL 2), export **sans threads** | Seul renderer disponible sur le web ; sans threads, pas besoin des en-têtes COOP/COEP |
| Assets | **Blender 5.2** (sans interface) + **fal.ai** | Génération concept → 3D → squelette, puis retouche, optimisation et export GLB scriptés |
| Données | **JSON** dans `game/data/`, validés au chargement | Lisibles, faciles à comparer en revue, éditables par un agent ; validation explicite plutôt que magie de l'éditeur |
| Sauvegarde | `user://` (IndexedDB sur le web), JSON versionné | Godot persiste `user://` dans IndexedDB sur le web sans code spécifique |
| Tests | Lanceur GDScript sans interface + **Playwright** sur l'export web | Le moteur se teste sans rendu ; le parcours joueur se teste dans un vrai navigateur |
| Lint | gdtoolkit (`gdlint`, `gdformat`) | Standard de la communauté GDScript |

Écarté : Three.js / React (moins de briques de jeu, tout serait à réécrire), Phaser (2D), C# (pas d'export web stable), addons de test (GUT, GdUnit4) : inutiles pour l'instant, le lanceur maison suffit et n'ajoute pas de dépendance.

## Les cinq couches

```
            ┌───────────── A. Application (game/app, game/ui) ─────────────┐
            │  scène principale, routeur d'écrans, écrans, thème, textes   │
            └──────┬───────────────────────┬──────────────────────┬────────┘
                   │ actions               │ lecture              │ demandes
                   ▼                       ▼                      ▼
   B. État (game/state)  ◄────  D. Rendu (game/world, game/combat)    E. Persistance (game/persistence)
   autoload GameState            scènes 3D, caméra, personnages,       SaveService : écrit, lit, valide,
   détient l'état joueur         effets ; écoute les événements        migre, exporte, importe l'état
        │                        du moteur, ne décide rien
        │ appelle
        ▼
   C. Moteur (game/engine) — logique pure, déterministe ── lit ──► Données (game/data, JSON validés)
```

| Couche | Dossier | Rôle | Peut dépendre de |
|---|---|---|---|
| A. Application | `game/app`, `game/ui` | Démarrage, routeur d'écrans, écrans et composants, thème jour / nuit, textes | tout |
| B. État | `game/state` | Autoload `GameState` : la seule source de vérité de la partie en cours (dictionnaire sérialisable), signaux `changed` | moteur, données |
| C. Moteur | `game/engine` | Règles : création de partie, combat, IA, formules, butin, hors ligne, aléatoire à graine | données (types) |
| D. Rendu | `game/world`, `game/combat` | Monde 3D, combat 3D, effets. Reçoit des événements, anime, n'écrit jamais l'état | moteur (événements), état (lecture) |
| E. Persistance | `game/persistence` | Format de fichier, somme de contrôle, migrations, écriture atomique, copie de secours, export / import | état, données |

### Règles qui ne se discutent pas

1. **Le moteur est pur.** Scripts `RefCounted`, sans nœud, sans `get_tree()`, sans fichier, sans horloge, sans aléatoire global. Le temps (`now_unix`) et la graine arrivent en paramètres. `tests/unit/test_architecture.gd` échoue sinon.
2. **Une seule source de vérité.** L'état de la partie vit dans `GameState.data` ; les nœuds 3D n'en gardent pas de copie qui fait foi. Un objet de scène n'est jamais rangé dans l'état.
3. **Le rendu écoute.** Le combat produit des événements (`encounter_started`, `attack_started`, `damage_dealt`, `spell_cast`, `cast_interrupted`, `character_healed`, `shield_applied`, `status_applied`, `status_expired`, `character_defeated`, `enemy_defeated`, `boss_phase_changed`, `loot_dropped`, `encounter_completed`). La scène les joue. Elle ne calcule jamais si un coup touche.
4. **Pas de nombre de gameplay hors de `game/engine/balance/`.** Les écrans affichent ce que le moteur calcule.
5. **Pas de contenu en dur.** Personnages, ennemis, sorts, objets, runes, régions, lieux, donjons, rencontres, quêtes : JSON avec ID stables.
6. **Textes par clé.** Tout texte visible passe par `tr("CLE")` (`game/i18n/strings.csv`, colonne `fr`).

## Déterminisme

- `game/engine/core/rng.gd` enveloppe `RandomNumberGenerator` (PCG32) : graine et état sont sauvegardables, donc une rencontre ou un butin se rejoue à l'identique.
- Une graine par usage (`combat`, `loot`, `offline`), dérivée de la graine de partie et d'un compteur, pour qu'un tirage de butin n'en décale pas un autre.
- La simulation de combat avance par tics fixes (`TICK_SECONDS`), indépendants du nombre d'images par seconde. Vitesse ×2 / ×4 = plus de tics par image, pas des tics plus longs.

## État de la partie (format v6)

Dictionnaire de types simples (nombres, chaînes, tableaux, dictionnaires), pour être sérialisé tel quel :

| Clé | Contenu |
|---|---|
| `meta` | `seed`, `created_at`, `last_active_at` (secondes Unix), `play_time` |
| `party` | 4 emplacements : ID de personnage ou `""` |
| `characters` | par ID : `level`, `xp`, `equipment` (par emplacement : `uid` d'un objet de `inventory` ou `""`), `spells` (rang par ID de sort, 1 si absent), `loadout`, `runes` (par ID de sort : runes serties [{`id`, `tier`}]), `artifacts` (2 emplacements : ID ou `""`), `tactics` (v6 : tactiques sauvegardées, **seulement les écarts au défaut**, même forme que les `overrides` de `CombatTactics.build` : `targeting`, `mana_reserve`, `barrier_hp_pct`, `min_enemies`, `spells` {ID : mode}, `consumables` {ID : mode} ; `TacticsRules`, une valeur refusée est ignorée au chargement ; combat, « Chasser ici » et donjon les jouent, le hors ligne garde les défauts) |
| `wallet` | `gold`, `materials` (par ID) |
| `inventory` | toutes les instances d'objets, portées ou non (`uid`, `item_id`, `rarity`, `item_level`, `affixes` [{`id`, `value`}], `legendary`, `enhance`, `enhance_attempts`, `pity` = échecs d'amélioration consécutifs). Le sac compte les objets non portés (60 cases) |
| `runes` | réserve de runes non serties : ID → 5 quantités (paliers 1 à 5) |
| `consumables` | ID → quantité portée (5 au plus) |
| `artifacts` | artefacts possédés : ID → niveau (1-5) |
| `world` | `region_id`, `location_id`, `unlocked_regions`, `discovered_locations` |
| `progress` | `cleared_encounters` ; `quests` (ID → {`state` : `active`, `completed` ou `turned_in`, `step`, `counts` par objectif, `order` d'acceptation}) ; `bestiary` (ID d'ennemi → victoires jouées, 0 = rencontré) ; `discoveries` (ID trouvés) ; `contracts` ({`day_index` (-1 = jamais tiré), `offers` [{`id`, `count`, `state`, `reward` {`gold`, `dust`, `shards`}}]}) ; `dungeon_run` ({} hors donjon, sinon {`dungeon_id`, `checkpoint`, `room`, `cleared_rooms`, `fountain_used`, `vitals` {`hp_pct`, `mana_pct`, `ult_charge`}}) ; `unlocks` (jetons : `artifact_slot_1`) ; `tips_seen` (v6 : ID des conseils `tip.*` déjà montrés ; les conseils de défaite, `repeat`, n'y entrent jamais) |
| `farming` | rencontre farmée hors ligne (`encounter_id`) ou `""` |
| `offline` | `pending` : `[]` ou `[résumé]`, le résumé hors ligne pas encore récupéré (forme : `OfflineCalc`, schéma : `StateSchema.offline_summary_spec`) |
| `rng` | compteurs par flux (`combat` pour les combats de terrain et de « Chasser ici », `item` pour les `uid` d'objets) |

Les réglages (taille du texte, animations réduites, volumes) sont à part, dans `user://settings.cfg` : ils ne voyagent pas avec une sauvegarde exportée.

## Sauvegarde

Fichier `user://saves/slot_0.json` :

```json
{ "format": "afterlight-save", "version": 1, "saved_at": 1793900000,
  "checksum": "<sha256 du JSON canonique de state>", "state": { ... } }
```

- **Écriture atomique** : on écrit `slot_0.json.tmp`, on relit et on valide, puis l'ancien fichier devient `slot_0.bak.json` et le nouveau prend sa place.
- **Lecture** : JSON lisible → enveloppe valide → somme de contrôle juste → migrations `version → version + 1` jusqu'à la version courante → validation du schéma de l'état. Godot relit les nombres JSON en flottants : la validation reconvertit en entiers les champs entiers.
- **Sauvegarde invalide** : jamais écrasée en silence. Le fichier est copié dans `user://saves/corrupt/` avec l'horodatage, puis l'écran de récupération propose : restaurer la copie de secours (si elle est valide), exporter le fichier endommagé, ou commencer une nouvelle partie (après confirmation).
- **Automatique** : toutes les 30 s si l'état a changé, à chaque changement d'écran, et quand l'onglet passe en arrière-plan (web) ou que la fenêtre se ferme. **Manuelle** : bouton « Sauvegarder ».
- **Export / import** : le même JSON. Sur le web, export par téléchargement (`JavaScriptBridge.download_buffer`) et import par un sélecteur de fichier du navigateur ; ailleurs, `user://exports/` et `FileDialog`. Un import passe par la même validation et ne remplace la partie qu'après confirmation.

## Données

- Un fichier par type d'entité et par origine : `game/data/canon/characters.json`, `game/data/original/enemies.json`…
- Chaque entité : `id` stable (`type.snake_case`), `origin` (`canon` ou `original`), `name_key` (texte par clé), puis ses champs.
- `game/data/content_db.gd` (autoload `Content`) charge tous les fichiers via `content_loader.gd`, valide chaque entité contre `game/data/schemas.gd` puis les règles croisées de `content_rules.gd` (règles V de CONTENT_PIPELINE §8), vérifie l'unicité des ID et les références croisées (un sort cité par un personnage doit exister). Au moindre défaut, la liste d'erreurs est affichée et le jeu ne démarre pas une partie sur des données fausses.

## Application

- `game/app/main.tscn` : racine avec la couche 3D (vide au Milestone 1), la couche d'interface (`ScreenHost`) et un voile de transition.
- Autoload `Router` : `go_to(screen_id, params)`, fondu de 320 ms (sortie + entrée) (coupe nette si « réduire les animations »). Écrans du Milestone 1 : `title`, `camp`, `settings`, `save_recovery`.
- Thème : `game/ui/theme/tokens.gd` (couleurs, tailles, espacements de `DESIGN.md`) → `theme_builder.gd` construit un `Theme` jour et un `Theme` nuit. Les écrans n'écrivent aucune couleur en dur.
- Pont de test : autoload `UiProbe`. Les contrôles importants s'y enregistrent sous un nom (`title.new_game`) ; sur le web, `window.afterlight` expose leur position à Playwright, qui clique comme un joueur, et un résumé de l'état pour vérifier le résultat.

## Scènes de lieu (contrat entre le code et les décors)

Chaque lieu de `game/data/*/locations.json` pointe vers sa scène (`scene`), par exemple `res://game/world/locations/aubelin.tscn`. Les décors sont produits à part (piste art) ; le code d'exploration ne dépend que de ce contrat.

| Nœud (chemin depuis la racine) | Type | Rôle |
|---|---|---|
| `.` (racine) | `Node3D` | Aucun script requis. Origine au centre du lieu, Y vers le haut, 1 unité = 1 m, -Z = « nord » de la carte |
| `Spawns/<nom>` | `Marker3D` | Points d'apparition. `default` est obligatoire ; `from_<id_court>` pour chaque arrivée depuis un lieu voisin (ex. `from_whispering_wood`). Le -Z local du marqueur donne l'orientation de Fern |
| `Exits/<nom>` | `Area3D` (calque de collision 4) + `CollisionShape3D` | Sorties de zone. Métadonnées obligatoires : `to` (ID de lieu) et `spawn` (nom du point d'apparition dans le lieu cible) |
| `Walkable` | `NavigationRegion3D` ou corps statiques | Sol marchable : `StaticBody3D` au calque 1. Les obstacles (maisons, rochers, arbres) ont aussi une collision au calque 1. Les bords du lieu sont fermés par des collisions invisibles |
| `Anchors/<nom>` | `Marker3D` | Emplacements des rencontres, PNJ et découvertes (`anchor` dans les données) ; utilisés à partir du jalon 3 |
| `Environment` | `WorldEnvironment` + `DirectionalLight3D` | Lumière du lieu, selon DESIGN.md (jour ou nuit) |

Règles : taille utile de 40 à 80 m de côté ; Fern mesure 1,6 m (pieds à y = 0, regard vers -Z) ; budget web : moins de 150 appels de dessin et 300 k triangles visibles, végétation en `MultiMeshInstance3D`. Le joueur et la caméra sont ajoutés par le code (`game/world/explore/`), jamais par la scène.

Un test (`tests/unit/world/test_location_scenes.gd`) charge chaque scène citée par les données et vérifie ce contrat : nœuds présents, `default` défini, chaque sortie mène à un lieu et à un point d'apparition existants.

## Taille de l'export et chargement (web)

Critère 7.2 : premier écran interactif en moins de 10 s à 20 Mb/s (2,5 Mo/s). Le chargeur web de Godot télécharge `index.wasm` puis tout `index.pck` avant d'afficher le titre : chaque mégaoctet du pack retarde le premier écran.

| Mesure | Cible | Vérification |
|---|---|---|
| `build/web/index.pck` | **≤ 30 Mo** (25,7 Mo le 2026-11-06) | `tests/unit/test_export_size.gd` sur le dernier build ; détail : `python3 tools/pck_report.py` |
| Téléchargement avant le titre (wasm + pck, gzip) | ≤ 22 Mo, soit < 10 s avec le démarrage | `gzip -c build/web/index.{wasm,pck} \| wc -c` ; `pnpm serve` sert en gzip comme un hébergeur |

Règles d'import et d'export :

- **Textures** : WebP avec perte (`compress/mode=1`, qualité 0,8 ; 0,85 pour carte, titre et portraits). Défaut du projet (`[importer_defaults]` dans `project.godot`), donc aussi pour les textures extraites des GLB. Sans perte toléré pour les pictogrammes (`assets/textures/icons/`). Pas de compression VRAM : en WebGL 2 il faudrait livrer S3TC et ETC2, deux copies plus lourdes que le WebP ; la texture est décompressée en RGBA8 au chargement, la mémoire reste dans le budget 7.1 (un lieu chargé à la fois).
- **Tailles** : 1024 px maximum pour décor, accessoires et personnages (`process/size_limit`) ; toile de fond des lieux 2048 px ; carte et image du titre jusqu'à 2560 px. Mipmaps pour la 3D seulement.
- **Exclus du pack** (`export_presets.cfg`) : `art/`, `tools/`, `tests/`, `build/`, `docs/`, les GLB de `assets/environment/` (sources de `meshes/*.res`, cuits par `location_builder.gd`) et les copies de l'atlas d'accessoires extraites par GLB (les matériaux utilisent `assets/environment/textures/village_props_atlas.webp`). Le test vérifie qu'aucun matériau ni scène de `game/world` n'utilise un fichier exclu.
- **Chargement** : au démarrage, seuls le code, le thème, les polices, les données et l'image du titre servent ; lieux, personnages et ennemis sont chargés au voyage (`load()` dans `explore_view.gd`, `player.gd`).
- **Étape suivante si le téléchargement reste au-dessus de 22 Mo** : un second pack `content.pck` (preset d'export à part avec `assets/environment/`, `assets/models/`, `game/world/locations/`, `game/world/dungeons/`), téléchargé pendant l'écran titre puis monté par `ProjectSettings.load_resource_pack()` avant le premier voyage. Voir `art/source/perf/export_size.md`.

## Arborescence

```
game/
├── app/          main.tscn, main.gd, router.gd, screens/
├── ui/           theme/ (tokens, builder), kit.gd (composants), ui_probe.gd
├── i18n/         strings.csv (clé, fr)
├── state/        game_state.gd (autoload GameState), settings.gd
├── engine/       core/ (rng, new_game, state_schema), balance/, combat/, loot/, offline/
├── world/        scènes 3D d'exploration (Milestone 2)
├── combat/       scènes 3D de combat (Milestone 3)
├── persistence/  save_codec.gd (pur : enveloppe, somme, migrations), save_service.gd (autoload), web_file_bridge.gd
└── data/         schemas.gd, content_db.gd, canon/*.json, original/*.json
```

## Tests

- `pnpm test` : `tools/test_runner.gd` exécute chaque `tests/unit/**/test_*.gd` (classe `TestCase`). Moteur, schémas, codec de sauvegarde, migrations et service de sauvegarde (dans un dossier `user://` de test) y sont couverts.
- `pnpm e2e` : export web puis Playwright (desktop et mobile) : nouvelle partie, navigation, sauvegarde, rechargement de la page, reprise.
- Un système n'est pas terminé tant que ses tests ne passent pas.

## Combat : événements et instantané

Code : `game/engine/combat/` (`CombatSim` et ses modules `combat_rules`, `combat_actions`, `combat_ai`, `combat_tactics`, `combat_factory`, `combat_geometry`, `combat_rewards`). Constantes et formules : `game/engine/balance/` (`combat.gd`, `statuses.gd`, `enemies.gd`, `stats.gd`). Banc : `tools/combat_bench.gd` et `tests/unit/combat/`.

### Piloter la simulation

```gdscript
var sim := CombatSim.create({
	"encounter": "encounter.whispering_wood_02", "seed": seed,
	"party": [{"character": "character.fern", "level": 3, "slot": 3,
	           "flat": {...}, "percent": {...},        # modificateurs d'équipement (§2.2)
	           "spell_ranks": {}, "spell_mods": {},     # rangs, runes (élément, chances, bonus)
	           "ult_charge": 0.0, "hp_pct": 1.0, "mana_pct": 1.0}],
	"tactics": {...}, "consumables": {"consumable.healing_draught": 3},
	"first_clear": true,
}, Content.index())
sim.command({"type": "cast", "spell": "spell.zoltraak"})  # appliqué au tic suivant
var events := sim.step()                                    # un tic de TICK_SECONDS
var view := sim.snapshot()                                  # données simples pour le rendu
```

- `sim.error` est non vide (et `sim.finished` vrai) si la rencontre ou le groupe ne correspond pas au contenu.
- Pause : ne pas appeler `step()`. Vitesse ×2 / ×4 : plus d'appels par image. Le plafond est `speed_cap` (événement `encounter_started` et instantané). La simulation n'utilise jamais le temps d'image.
- Coordonnées : mètres sur le plan du sol `(x, z)`, relatives au marqueur `Anchors/<anchor>` de la rencontre. La meute est centrée sur l'origine ; le groupe se tient côté +z (rangée avant à 6 m, arrière à 10 m). Le rendu ajoute la transformation de l'ancre et interpole entre deux instantanés.
- `sim.event_log` garde tout le journal (désactivable par `"keep_log": false`) ; `CombatSim.hash_events(log)` sert aux tests de déterminisme.
- Unités : `uid` stable par combat (`p1`-`p4` selon l'emplacement, `e1`, `e2`... pour les ennemis et invocations dans l'ordre d'apparition).

### Commandes (`sim.command`)

| `type` | Champs | Effet |
|---|---|---|
| `cast` | `spell`, `target`? | Part au tic suivant ; sinon attend dans le tampon (`INPUT_BUFFER_S`) derrière une incantation, un déplacement, le GCD ou une recharge presque finie ; sinon `command_rejected` avec la raison (`locked`, `no_mana`, `no_charge`, `cooldown`, `no_target`, `expired`, `cc`, `dead`) |
| `set_focus` | `target` (`""` pour annuler) | Focalisation jusqu'à la mort de la cible |
| `move_to` | `x`, `z` | Repositionnement : annule l'incantation en cours (sans coût), pas d'attaque pendant le trajet, puis tenue de `REPOSITION_HOLD_S` |
| `stop` | - | Arrête le déplacement manuel (fin d'appui clavier ou joystick) |
| `use_consumable` | `consumable` | Recharge partagée `CONSUMABLE_SHARED_CD_S` |
| `set_tactic` | `key`, `value` | `targeting`, `mana_reserve`, `barrier_hp_pct`, `min_enemies` ou un ID de sort (mode) |

Champ optionnel `unit` (par défaut, le premier membre du groupe).

### Événements

Chaque événement est un dictionnaire `{"type", "tick", ...}`, dans l'ordre où il se produit. `step()` rend ceux du tic ; le premier appel commence par `encounter_started`.

| `type` | Champs |
|---|---|
| `encounter_started` | `encounter`, `kind`, `level`, `speed_cap`, `seed`, `units` [{`uid`, `def_id`, `side`, `level`, `position`, `max_hp`, `summoner`}] |
| `attack_started` | `unit`, `spell`, `target`, `travel_s` (0 en mêlée, durée du projectile sinon) |
| `spell_cast` | `unit`, `spell`, `target`, `kind`, `cast_s`, `channel_s` : un sort ou une capacité commence (instantané ou non) |
| `cast_started` | `unit`, `spell`, `phase` (`cast`, `channel`, `telegraph`), `duration_s`, `interruptible`, `target` : barre d'incantation |
| `cast_completed` | `unit`, `spell` |
| `cast_interrupted` | `unit`, `spell`, `by`, `reason` (`interrupt`, `cc`, `moved`, `death`, `no_mana`) |
| `telegraph_started` | `id`, `unit`, `spell`, `shape` (`circle`, `line`, `cone`), `size_m` (rayon ou longueur), `width_m`, `position`, `direction`, `duration_s` (≥ 0,6), `attached_to` (uid suivi, ou `""` si zone au sol esquivable), `interruptible`, `hit`, `hits` |
| `telegraph_ended` | `id`, `reason` (`impact`, `cancelled`) |
| `zone_spawned` / `zone_expired` | `id`, `unit`, `spell`, `element`, `shape`, `size_m`, `position`, `duration_s` / `id` |
| `damage_dealt` | `source`, `target`, `spell` (ou ID du statut pour un DoT, `reaction.overload` pour l'explosion), `amount` (affiché), `hp_damage`, `absorbed`, `crit`, `element`, `reaction` (`""`, `melt`, `overload`, `extinguish`), `shock`, `hp` (après le coup) |
| `character_healed` | `source`, `target`, `spell`, `amount`, `overheal`, `hp` |
| `mana_restored` | `unit`, `source`, `amount` |
| `shield_applied` | `source`, `target`, `kind` (`shield` ou `barrier` ennemie), `amount`, `total`, `duration_s` |
| `barrier_broken` | `unit`, `source` |
| `status_applied` | `target`, `status`, `stacks`, `duration_s`, `source` |
| `status_expired` | `target`, `status`, `reason` (`expired`, `consumed`, `converted`, `reaction`, `cleansed`, `depleted`) |
| `unit_spawned` | comme une unité de `encounter_started`, plus `unit` |
| `character_defeated` / `enemy_defeated` | `unit`, `def_id`, `killer` |
| `boss_phase_changed` | `unit`, `phase` (2, 3...), `phase_id`, `hp_pct` |
| `focus_changed` | `unit`, `target` |
| `move_ordered` / `hold_started` | `unit`, `position` / `unit`, `position`, `duration_s` |
| `consumable_used` | `unit`, `consumable`, `remaining` |
| `tactic_changed` | `unit`, `key`, `value` |
| `command_rejected` | `unit`, `command`, `ref`, `reason` |
| `loot_dropped` | `gold`, `materials` {ID: quantité}, `items` (objets tirés, sans `uid` : voir `ItemFactory`), `runes` [{`id`, `tier`}], `artifacts` [ID], `position` (dernier ennemi vaincu) |
| `encounter_completed` | `encounter`, `result` (`victory`, `defeat`), `duration_s`, `ticks`, `rewards` {`xp`, `gold`, `materials`, `items`, `runes`, `artifacts`, `consumables`}, `consumables_used` {ID: quantité}, `first_clear`, `last_hit` {`source`, `spell`, `target`} |

Les déplacements ne produisent pas d'événement par tic : le rendu lit les positions dans l'instantané.

### Instantané (`sim.snapshot()`)

Dictionnaire de types simples (sérialisable en JSON) :

- Racine : `tick`, `time_s`, `encounter`, `speed_cap`, `finished`, `result`, `units`, `telegraphs`, `zones`, `projectiles`, `tactics`.
- Unité : `uid`, `def_id`, `side`, `level`, `archetype`, `is_boss`, `alive`, `position` [x, z], `facing` [dx, dz], `moving`, `ai_state` (`aggro`, `approach`, `attack`, `ability`, `kite`, `dodge`, `move`, `hold`, `idle`, `dead`), `hp`, `max_hp`, `mana`, `max_mana`, `shield`, `barrier`, `barrier_max`, `damage_reduction`, `statuses` [{`id`, `stacks`, `remaining_s`}], `cast` ({} ou {`spell`, `phase`, `progress` 0-1, `remaining_s`, `interruptible`, `target`}), `cooldowns` {ID: secondes restantes}, `target`, `focus`, `summoner`.
- En plus pour un ennemi : `phase`, `phase_count`. Pour un membre du groupe : `slot`, `row`, `spells`, `ultimate`, `ult_charge`, `ult_charge_max`, `gcd_s`, `consumables`, `consumable_cd_s`, `hold_s`, `move_target` ([x, z] ou []), `queued` (sort en attente ou `""`).
- `telegraphs` : `id`, `unit`, `spell`, `shape`, `size_m`, `width_m`, `position`, `direction`, `remaining_s`, `duration_s`, `attached_to`. `zones` : `id`, `unit`, `spell`, `element`, `size_m`, `position`, `remaining_s`. `projectiles` : `id`, `unit`, `target`, `spell`, `progress` 0-1.

### Règles de simulation à connaître côté rendu

- Ordre d'un tic : commandes, statuts (DoT, expirations), minuteries et mana, projectiles, zones, progression des incantations, décisions (groupe puis ennemis), séparation des ennemis, fin de combat.
- Les sorts du groupe paient leur mana et lancent leur recharge à la résolution ; l'ultime dépense sa charge au début de la canalisation. Les capacités ennemies lancent leur recharge au début : une incantation interrompue est perdue.
- Les capacités ennemies ont, au début du combat ou de leur phase, la moitié de leur recharge à attendre (`ENEMY_OPENING_CD_FRACTION`).
- Les invocations (renforts de l'alpha, lanternes liées) ne donnent ni XP ni or.

## Progression (jalon 4)

Code : `game/engine/progression/` (moteur pur) et `game/state/progression_api.gd` (`GameState.progression`, appels de l'interface).

| Module | Rôle |
|---|---|
| `ItemFactory` | Tirage d'objets (rareté par source, ilvl, implicite, affixes sans doublon d'ID ni de `group`, effet légendaire) et de runes ; modificateurs d'un objet |
| `Inventory` | Sac (objets non portés, 60 cases), `uid` stables (`rng.item`), réception du butin avec recyclage automatique si le sac est plein, recyclage groupé, réserves de runes, consommables (plafond) et artefacts |
| `Equipment` | Porter / retirer, modificateurs par source (`item:<uid>`, `artifact:<id>`), statistiques finales, comparaison stat par stat |
| `Forge` | Amélioration : coûts, chance, pitié ; tirage dérivé de (graine, `uid`, tentatives) |
| `Grimoire`, `RuneRules`, `ArtifactRules`, `Merchant` | Rangs de sorts et sertissage, fusion et recyclage des runes, artefacts, boutique |
| `PartyBuild` | État sauvegardé → entrée de groupe de `CombatSim` (`flat`, `percent`, `spell_ranks`, `spell_mods`, consommables) |
| `CombatOutcome` | Applique `encounter_completed` : XP, or, matériaux, butin, consommables utilisés, lignes de résumé |

Chaque action rend `ActionResult` : `{ok, error, params, state, ...}`. Un refus porte une clé `error.*` de `strings.csv` et ses paramètres (`{"required": 141}`), que `GameState.reason_text(r)` traduit (« Or insuffisant : 141 requis »). Les devis (`*_quote`) ont la même forme et ne changent rien : un bouton désactivé affiche leur raison.

## Idle (jalon 5)

Code : `game/engine/idle/` (moteur pur), constantes `game/engine/balance/offline.gd` (GAME_BALANCE §20).

| Module | Rôle |
|---|---|
| `OfflineModel` | Modèle analytique d'un combat : rotation de chasse (tactiques par défaut), DPS, salve d'ouverture, PV effectifs, `clear_time`, dégâts subis, survie. Ne crée jamais de `CombatSim` |
| `OfflineCalc` | Éligibilité et devis de la chasse hors ligne, calcul d'une absence (résumé), récupération (une seule fois), lignes du résumé |
| `HuntLoop` | « Chasser ici » : vérification, démarrage (devient la chasse hors ligne si elle est éligible), réglage du combat suivant (graine du compteur `combat`, jamais de premier kill), arrêt à la défaite |

Horloge : le moteur reçoit `now_unix`. `GameState.now_unix()` lit `Time` et y ajoute `debug_clock_offset_s` seulement quand le canal de test est actif (`?test=1`, `UiProbe` le règle depuis `&clock_offset_s=<n>`). Le résumé est calculé à l'adoption d'une sauvegarde chargée (`GameState.adopt`), pas à l'import, puis gardé dans `offline.pending` jusqu'à « Récupérer ». `CombatSim.ticks_total` compte les ticks de toutes les simulations : le test du critère 5.2 vérifie qu'il ne bouge pas.

## Quêtes, contrats, bestiaire, découvertes, donjon (jalon 6)

Code : `game/engine/quests/` et `game/engine/world/` (moteur pur), constantes `game/engine/balance/story.gd` (GAME_BALANCE §23), actions de l'interface dans `game/state/content_api.gd` (`GameState.content_api`). Spécification : `docs/content/`.

| Module | Rôle |
|---|---|
| `QuestRules` | Machine à états des quêtes (`available` → `active` → `completed` → `turned_in`), étapes, objectifs à compteur (événements) ou d'état (découverte, lieu visité, objet détenu ou livré), récompenses créditées une fois, journal, quête suivie |
| `NpcRules` | Choix du dialogue d'un PNJ (première entrée dont la condition tient), fin de dialogue : `talked_to`, offre ou rendu de quête, dialogue suivant à enchaîner, marqueurs (offre, en cours, à rendre) |
| `Contracts` | Contrats du jour : tirage à graine par jour local, au plus un long, récupération automatique au changement de jour, comptage, récupération |
| `Bestiary` | Victoires par ennemi (invocations comprises), paliers par `bestiary_thresholds` |
| `Discoveries` | Découvertes, coffres (butin à graine `chest:<id>`), herbes de quête, trous du voile de la carte, compteur par lieu |
| `DungeonRun` | Expédition : portes, PV conservés entre salles, fontaine, feu de camp, défaite au point de reprise, raccourci après le premier boss, repli au chargement |
| `StoryEvents` | Routage : un combat joué (`encounter_completed` avec `tally`) va au bestiaire, au donjon, aux quêtes et aux contrats ; `talked_to`, `location_visited`, `discovery_found`, `item_collected` aux quêtes |

`encounter_completed` porte en plus `location`, `tally` ({`defeated`: {ennemi: n}, `interrupts`: {personnage: n}, `statuses`: {statut: {source: n}}}) et `leader` ({`hp_pct`, `mana_pct`, `ult_charge`}). Seul `GameState.apply_combat_result` (combat de la scène ou « Chasser ici ») passe par `StoryEvents` : la récupération hors ligne n'y passe jamais, donc les victoires hors ligne ne comptent ni pour les quêtes, ni pour les contrats, ni pour le bestiaire. `GameState.story_events(events)` relaie les événements produits (`quest_activated`, `quest_progress`, `quest_completed`, `quest_turned_in`, `bestiary_tier_unlocked`, `discovery_found`, `contracts_rolled`, `contracts_auto_claimed`, `dungeon_room_cleared`, `dungeon_respawn`, `dungeon_shortcut_opened`...) pour les bandeaux.


## Tactiques et conseils (jalon 6)

Code : `game/engine/progression/tactics_rules.gd` (`TacticsRules`, moteur pur) et `game/state/tactics_api.gd` (`GameState.tactics`, appels de l'interface). Décisions 22 à 31 du GDD et réponses du propriétaire.

| Module | Rôle |
|---|---|
| `CombatTactics` | Modes par rôle (sorts, et consommables : `heal` → `auto_low_hp`, `mana` → `auto_low_mana`), défauts, `build(defs, overrides)`, `set_value` |
| `TacticsRules` | Écarts sauvegardés (`characters.<id>.tactics`), vue de l'écran (lignes dans l'ordre Ciblage, sorts appris, consommables, Réserve), préréglages `tactics_preset.*` (écart puis application), nettoyage au chargement, conseils `tip.*` (`next_tip(context)`, `mark_tip_seen`) |
| `PartyBuild.setup` | Passe les écarts du chef au `CombatSim` (`tactics`) : combat de terrain, « Chasser ici », donjon. Le hors ligne (`OfflineModel`) n'en tient pas compte |
