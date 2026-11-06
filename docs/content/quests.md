# Contenu du jalon 6 : quêtes

> Version 0.1 (2026-11-06). Spécification pour `game/data/original/quests.json`, `npcs.json` et `strings.csv`. Statut : tout est `[H]` (hypothèse non jouée) sauf mention contraire.
> Références : GDD §5, §10.5, §13 ; GAME_BALANCE §12, §13, §16, §21 ; CONTENT_PIPELINE §5.4. Dialogues : `dialogues.md`. Lieux et rencontres : `dungeon.md`.

## 1. Règles communes

### 1.1 États

`available` (prérequis remplis, pas encore parlé au donneur) → `active` → `completed` (tous les objectifs remplis, pas encore rendue) → `turned_in` (rendue, récompenses créditées).

| Règle | Comportement attendu (testable) |
|---|---|
| Acceptation | Il n'y a pas de bouton « Refuser » : la fin du dialogue d'offre du donneur passe la quête à `active`. L'ignorer ne coûte rien |
| Exception | `quest.main_01` est `active` dès la création de la partie (après l'intro), pour tenir le premier combat en moins de 3 minutes (GDD §16.1) |
| Prérequis | `quest_completed: X` signifie « X est `turned_in` » |
| Étapes | Chaque objectif porte un `step` (1, 2…). Les objectifs d'une même étape avancent en parallèle ; un objectif d'étape n+1 n'avance pas tant que l'étape n n'est pas finie |
| Rendu | Parler au donneur quand la quête est `completed` → dialogue de rendu → `turned_in` → récompenses → sauvegarde automatique |
| Récompenses | Créditées une seule fois, au passage à `turned_in` (un rechargement ne recrédite rien) |
| Suivi | Le HUD suit la quête principale active, ou la dernière quête secondaire acceptée si aucune principale n'est active. Le journal liste tout |

### 1.2 Événements d'objectif

Noms en snake_case comme dans ARCHITECTURE ; la colonne « schéma » donne la valeur du champ `event` de CONTENT_PIPELINE §5.4.

| Événement moteur (charge utile) | Schéma | `target` accepté | Compte | Source |
|---|---|---|---|---|
| `encounter_completed {encounter_id, location_id, victory}` | `EncounterCompleted` | `encounter.*` ; ou `location.*` = toute rencontre listée dans `location.encounters` (donc **hors donjon**) | +1 par victoire, rejouée ou non | combat |
| `enemy_defeated {enemy_id, encounter_id}` | `EnemyDefeated` | `enemy.*` | +1 par ennemi, invocations comprises | combat |
| `talked_to {npc_id, dialogue_id}` | `TalkedTo` | `npc.*` | +1 à la fin du dialogue | état |
| `discovery_found {discovery_id, location_id}` | `DiscoveryFound` | `discovery.*` | 0 ou 1 | état |
| `item_collected {item_id, qty}` | `ItemCollected` | `material.*`, `artifact.*` | + qty ramassée | état |
| `location_visited {location_id}` **(nouveau)** | `LocationVisited` | `location.*` | 0 ou 1 | état |
| *(pas d'événement)* **(nouveau)** | `ItemDelivered` | `material.*` | quantité **détenue**, plafonnée à `count` ; retirée du portefeuille au rendu | état |

- **Victoires hors ligne** : elles ne font avancer **aucun** objectif (quête, contrat, bestiaire). Seuls les combats joués dans la scène comptent, y compris la boucle « Chasser ici ».
- **Objectifs d'état** (`DiscoveryFound`, `LocationVisited`, `ItemCollected` d'un objet unique, `ItemDelivered`) : évalués aussi à l'activation de la quête et au chargement. Une découverte déjà trouvée avant d'accepter la quête compte donc tout de suite.
- **Objectifs à compteur** (`EncounterCompleted`, `EnemyDefeated`, `TalkedTo`, `ItemCollected` d'un matériau ramassable) : seul le compteur sauvegardé fait foi ; rien n'est compté avant l'activation.
- **Défaite** : `encounter_completed` avec `victory = false` ne compte pas.

### 1.3 État sauvegardé (dans `progress.quests`, clé existante)

```
progress.quests[quest_id] = { "state": "active", "step": 2, "counts": { "<objective_id>": 3 } }
```

Au chargement : on relit `state`, `step` et `counts`, puis on réévalue les objectifs d'état. Si un objectif d'état n'est plus rempli (ex. éclats dépensés), une quête `completed` repasse `active`, sans message d'erreur. Une quête `turned_in` ne change plus jamais.

### 1.4 Récompenses

`xp = xp_factor × xp_to_next(level)` (GAME_BALANCE §12 : `QUEST_XP_MAIN` = 0,6, `QUEST_XP_SIDE` = 0,3). Le champ `level` de la quête (**nouveau**) est le niveau du contenu où se jouent les objectifs.

| Quête | `level` | XP | Or | Pages | Autre |
|---|---|---|---|---|---|
| `quest.main_01` | 3 | 420 | 100 | 1 | Débloque la Tourbière |
| `quest.main_02` | 6 | 2 532 | 400 | 2 | `rune.frost` palier 1 ; débloque les Ruines |
| `quest.main_03` | 9 | 7 260 | 900 | 3 | Débloque le donjon |
| `quest.main_04` | 12 | 15 348 | 2 000 | 3 | Épilogue |
| `quest.side_clockmaker` | 6 | 1 266 | 500 | 0 | Emplacement d'artefact 1 + `artifact.cracked_hourglass` |
| `quest.side_herbalist` | 6 | 1 266 | 300 | 1 | `artifact.traveler_compass` |
| `quest.side_statue` | 3 | 210 | 150 | 1 | Souvenir (texte de lore) |
| **Total** | | **28 302** | **4 350** | **11** | |

Cohérence : 11 pages = « 11 par les quêtes » (GAME_BALANCE §16). L'or des quêtes (4 350) plus les contrats (`contracts.md`, ~13 000) reste dans les ~20 000 de §21.3. XP des quêtes avant le boss : 12 954, soit ~18 % de l'XP cumulée jusqu'au niveau 12 (72 940) ; avec les premières victoires et les découvertes, ~22 %. §21.2 suppose ~30 % : **écart à mesurer au banc (critère 6.7)** ; levier prévu : `QUEST_XP_MAIN`, pas le hors ligne.

## 2. PNJ (`npcs.json`)

| ID | Nom | Rôle (`role`) | Lieu | Ancre | Modèle |
|---|---|---|---|---|---|
| `npc.odile` **(nouveau)** | Odile | `quest` | `location.aubelin` | `npc_well` (existe) | vieille femme, châle, cordelette de sonneuse nouée au poignet |
| `npc.aubelin_merchant` (existe) | Rosalie | `merchant` | `location.aubelin` | `npc_stall` (existe) | |
| `npc.bastien` (existe) | Bastien | `smith` | `location.aubelin` | `npc_forge` **(nouvelle ancre)** | |
| `npc.maelle` (existe) | Maëlle | `runecarver` | `location.aubelin` | `npc_runecarver` **(nouvelle ancre)** | |
| `npc.tobias` **(nouveau)** | Tobias | `quest` | `location.aubelin` | `npc_clockmaker` **(nouvelle ancre)** | horloger, loupe frontale |
| `npc.ysaline` **(nouveau)** | Ysaline | `quest` | `location.aubelin` | `npc_herbalist` : **renommer** l'ancre `discovery_bridge`, aucune découverte n'est prévue dans le hub | herboriste, panier |
| `npc.notice_board` **(nouveau)** | Tableau des contrats | `board` **(nouvelle valeur d'énumération)** | `location.aubelin` | `board` (existe) | panneau de bois |

Tous `origin: "original"`. Un PNJ qui a une quête à proposer porte un marqueur au-dessus de la tête : losange plein (offre), losange creux (en cours), losange doré (à rendre). Forme + couleur, jamais la couleur seule.

## 3. Les 7 quêtes

Chaîne principale : `main_01` → `main_02` → `main_03` → `main_04` (`next`). Les secondaires sont indépendantes entre elles.

### 3.1 `quest.main_01` : Une cloche qui ne sonne plus

| Champ | Valeur |
|---|---|
| `kind` | `main` |
| `giver` | `npc.odile` (rendu chez elle) |
| Prérequis | `{"start": true}` ; `active` dès la nouvelle partie |
| `next` | `quest.main_02` |

| `step` | `id` | `event` | `target` | `count` | Texte (`quest.main_01.objective_<id>`) |
|---|---|---|---|---|---|
| 1 | `clear_wood` | `EncounterCompleted` | `location.whispering_wood` | 3 | Vaincre des meutes dans le Bois des Murmures ({n}/3) |
| 1 | `meet_odile` | `TalkedTo` | `npc.odile` | 1 | Parler à Odile, près du puits d'Aubelin |

Les deux objectifs sont parallèles : le joueur peut aller au Bois sans passer par Odile (E2E 6.4 : intro passée, premier combat ≤ 60 s). Le premier combat (`encounter.whispering_wood_01`) compte.

Récompenses : 420 XP, 100 or, 1 page. `unlocks` : `location.lantern_mire`. La Barrière est déjà acquise au niveau 2 (rien à donner).

Rechargement : compteur `clear_wood` sauvegardé ; `meet_odile` aussi. Rechargement pendant un combat : la rencontre en cours n'est pas comptée.

### 3.2 `quest.main_02` : Lueurs sur la tourbière

| Champ | Valeur |
|---|---|
| `kind` | `main` |
| `giver` | `npc.maelle` |
| Prérequis | `{"quest_completed": "quest.main_01"}` |
| `next` | `quest.main_03` |

| `step` | `id` | `event` | `target` | `count` | Texte |
|---|---|---|---|---|---|
| 1 | `reach_mire` | `LocationVisited` | `location.lantern_mire` | 1 | Se rendre à la Tourbière aux Lanternes |
| 2 | `clear_mire` | `EncounterCompleted` | `location.lantern_mire` | 4 | Disperser les lueurs de la tourbière ({n}/4) |
| 2 | `find_journal` | `DiscoveryFound` | `discovery.ferryman_journal` | 1 | Retrouver le journal du passeur |

Récompenses : 2 532 XP, 400 or, 2 pages, `rune.frost` palier 1 (réponse directe aux lanternes : T7). `unlocks` : `location.watch_ruins`.

Rechargement : `reach_mire` et `find_journal` réévalués depuis l'état ; `clear_mire` depuis le compteur.

### 3.3 `quest.main_03` : Le guet abandonné

| Champ | Valeur |
|---|---|
| `kind` | `main` |
| `giver` | `npc.bastien` |
| Prérequis | `{"quest_completed": "quest.main_02"}` |
| `next` | `quest.main_04` |

| `step` | `id` | `event` | `target` | `count` | Texte |
|---|---|---|---|---|---|
| 1 | `sentinels` | `EnemyDefeated` | `enemy.stone_sentinel` | 4 | Abattre les sentinelles du guet ({n}/4) |
| 1 | `key` | `ItemCollected` | `material.cloister_key` | 1 | Récupérer la clé du cloître |

La clé (`material.cloister_key`, **nouveau**, `stack_max` 1, étiquettes `key` et `no_salvage`) est la récompense de première victoire (`first_clear_rewards`) de `encounter.watch_ruins_05`, « Gardiens de la tour » (`dungeon.md` §3). Les 4 rencontres à sentinelle des Ruines (01, 02, 04, 05) suffisent pour `sentinels`. Si la clé est déjà possédée à l'activation, `key` est rempli tout de suite.

Récompenses : 7 260 XP, 900 or, 3 pages. `unlocks` : `dungeon.silent_dial_cloister`.

### 3.4 `quest.main_04` : Le cadran éteint

| Champ | Valeur |
|---|---|
| `kind` | `main` |
| `giver` | `npc.odile` |
| Prérequis | `{"quest_completed": "quest.main_03"}` |
| `next` | aucun |

| `step` | `id` | `event` | `target` | `count` | Texte |
|---|---|---|---|---|---|
| 1 | `enter` | `LocationVisited` | `dungeon.silent_dial_cloister` | 1 | Entrer dans le cloître du Cadran Éteint |
| 2 | `morvaine` | `EncounterCompleted` | `encounter.cloister_boss` | 1 | Vaincre ce qui habite le cloître |
| 3 | `return` | `TalkedTo` | `npc.odile` | 1 | Revenir auprès d'Odile |

`LocationVisited` accepte ici un `dungeon.*` (`location_visited` est émis à l'entrée du donjon avec l'ID du donjon). À la victoire contre Morvaine : séquence de la cloche (`dialogues.md` §9), puis retour libre. Le rendu chez Odile joue l'épilogue (`dialogue.odile_epilogue` puis les cartes `story.epilogue.*`).

Récompenses : 15 348 XP, 2 000 or, 3 pages. Pas d'`unlocks` : la tranche continue (niveau 20, contrats, rejouer le donjon).

Rechargement : si la partie est rechargée après la victoire contre le boss mais avant le rendu, l'étape 3 est active et la cloche reste « sonnée » (`progress.cleared_encounters` contient `encounter.cloister_boss`). La séquence de la cloche ne se rejoue pas.

### 3.5 `quest.side_clockmaker` : Les rouages de Tobias

| Champ | Valeur |
|---|---|
| `kind` | `side` |
| `giver` | `npc.tobias` |
| Prérequis | `{"level_at_least": 6}` |

| `step` | `id` | `event` | `target` | `count` | Texte |
|---|---|---|---|---|---|
| 1 | `shards` | `ItemDelivered` | `material.rune_shard` | 10 | Apporter des éclats runiques à Tobias ({n}/10) |

Au rendu, 10 éclats sont retirés. La graveuse de runes affiche un avertissement si une fusion ferait passer les éclats sous 10 pendant que la quête est `completed` (« Tobias attend 10 éclats »), sans bloquer.

Récompenses : 1 266 XP, 500 or, `unlocks` : `artifact_slot_1` (jeton d'emplacement), objet `artifact.cracked_hourglass` niveau 1. Remplace la règle provisoire « emplacement 1 au niveau 6 sans quête » (GAME_BALANCE §18) : l'emplacement s'ouvre **au rendu**, qui demande déjà le niveau 6.

Cohérence : à ~120 rencontres jouées (niveau 6), l'espérance d'éclats est ~14 (3 × 0,04 par rencontre) plus le recyclage de runes ; 10 éclats ne demandent pas de chasse dédiée `[H]`.

### 3.6 `quest.side_herbalist` : Herbes de brume

| Champ | Valeur |
|---|---|
| `kind` | `side` |
| `giver` | `npc.ysaline` |
| Prérequis | `{"quest_completed": "quest.main_01"}` |

| `step` | `id` | `event` | `target` | `count` | Texte |
|---|---|---|---|---|---|
| 1 | `herbs` | `ItemDelivered` | `material.mist_herb` | 6 | Cueillir des herbes de brume ({n}/6) |

Les 6 herbes sont des découvertes ramassables qui ne comptent pas dans « Découvertes n/2 » (`bestiary_discoveries.md` §2.3) : 3 dans le Bois, 3 dans la Tourbière. Elles n'apparaissent que si la quête est `active` ou `completed`, ne réapparaissent jamais, et donnent chacune 1 `material.mist_herb` (**nouveau**, `stack_max` 6, étiquette `quest`). Elles sont retirées au rendu.

Récompenses : 1 266 XP, 300 or, 1 page, `artifact.traveler_compass` niveau 1.

### 3.7 `quest.side_statue` : Une statue sous la mousse

| Champ | Valeur |
|---|---|
| `kind` | `side` |
| `giver` | `npc.aubelin_merchant` (Rosalie) |
| Prérequis | `{"quest_completed": "quest.main_01"}` |
| `canon_refs` | `character.himmel` (à créer dans `canon/characters.json`, `playable: false`, `canon_note` relue par le propriétaire) |

| `step` | `id` | `event` | `target` | `count` | Texte |
|---|---|---|---|---|---|
| 1 | `clean` | `DiscoveryFound` | `discovery.moss_statue` | 1 | Nettoyer la statue à l'orée du Bois |

La découverte se déclenche par une interaction maintenue 1,5 s (« Nettoyer la mousse »), avec ou sans la quête. Trouvée avant l'acceptation : l'objectif est rempli dès l'offre, Rosalie a une ligne dédiée (`dialogues.md` §6).

Récompenses : 210 XP, 150 or, 1 page, texte de souvenir `quest.side_statue.memory` affiché dans le journal (Découvertes).

## 4. Chemin critique et vérification V15 / V16

```
start → main_01 (Bois) → [Tourbière] → main_02 → [Ruines] → main_03 (clé : watch_ruins_05) → [Donjon] → main_04
side_herbalist : après main_01 (herbes Bois + Tourbière, toutes atteignables à ce moment)
side_statue    : après main_01 (statue dans le Bois)
side_clockmaker: niveau 6 (éclats obtenables dès le Bois)
```

Aucune condition ne dépend d'un objet obtenable seulement derrière elle : la clé est dans les Ruines, débloquées avant `main_03`. Témoins invalides à ajouter : `quest_completed` en cycle ; `EnemyDefeated` vers un `discovery.*` ; `ItemDelivered` vers un `enemy.*`.

## 5. Données à changer (pour l'ingénieur, pas fait ici)

| Fichier | Changement |
|---|---|
| `locations.json` | `location.lantern_mire.unlock` → `{"quest_completed": "quest.main_01"}` ; `location.watch_ruins.unlock` → `{"quest_completed": "quest.main_02"}` |
| `artifacts.json` | Les `unlock` provisoires : la source réelle est la récompense (quête, découverte, butin). Garder un `unlock` toujours vrai (`{"start": true}`) et retirer les `notes` de substitution |
| `materials.json` | `material.cloister_key`, `material.mist_herb` |
| `schemas.gd` | `quest.level`, `objective.step`, événements `LocationVisited` et `ItemDelivered`, cible `location.*` pour `EncounterCompleted`, `role: board`, condition `quest_state` (voir `dialogues.md` §1) |
