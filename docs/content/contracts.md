# Contenu du jalon 6 : contrats du jour

> Version 0.1 (2026-11-06). Spécification pour `quests.json` (entrées `kind: "daily"`), le moteur (`game/engine`, tirage pur) et l'état. Tout est `[H]`.
> Décision du propriétaire (GDD §20, n° 4) : contrats gardés, optionnels, **sans série à entretenir**. Ils servent P4 (or et matériaux) sans jamais culpabiliser (P2).

## 1. Règles

| Règle | Comportement attendu (testable) |
|---|---|
| Nombre | 3 contrats par jour, ou moins s'il y a moins de 3 contrats éligibles (le premier jour : 2) |
| Activation | Pas d'acceptation : les contrats du jour sont actifs dès qu'ils sont tirés |
| Comptage | Événements de combat joués dans la scène (combat normal et « Chasser ici »). **Le hors ligne ne compte pas** |
| Fin | Objectif atteint → `completed`. « Récupérer » dans le journal (onglet Contrats) ou au tableau → récompense, `turned_in` |
| Changement de jour | Les contrats `completed` non récupérés sont **récupérés automatiquement** (ligne neutre : « Contrats d'hier récupérés : +{gold} or ») ; les contrats inachevés disparaissent sans message de reproche |
| Moment du tirage | Au chargement de la partie et à chaque ouverture du journal ou du tableau, si `day_index` a augmenté. Jamais pendant un combat |
| Horloge reculée | `day_index` < jour stocké → on garde les contrats actuels, aucun tirage |
| Plusieurs jours d'absence | Un seul nouveau tirage (pas de rattrapage) |
| Éligibilité | Évaluée au tirage ; un contrat qui devient éligible en cours de journée attend le lendemain |

## 2. Jour et graine

```
day_index = floori((now_unix + tz_offset_s) / 86400)      # minuit local
rng       = Rng(derive(meta.seed, "contracts", day_index))  # nouveau flux, ne consomme ni loot ni combat
eligible  = pool trié par ID, filtré par `condition`
tirage    = jusqu'à 3 contrats sans remise, pondérés par `weight`
contrainte: au plus 1 contrat de palier L ; si un 2e est tiré, on l'écarte et on retire
```

Le moteur reçoit `now_unix` et `tz_offset_s` en paramètres (il ne lit pas l'horloge). La couche état fournit `tz_offset_s` depuis le système au moment du tirage.

Tests : même graine + même `day_index` + même éligibilité ⇒ mêmes 3 contrats ; sur 60 jours simulés, aucun jour n'a 2 contrats L ni un doublon ; chaque contrat éligible sort au moins une fois.

## 3. Pool

ID au format quête : `quest.daily_<nom>`. Objectifs : mêmes événements que `quests.md` §1.2, plus `CastInterrupted` et `StatusApplied` (**nouveaux** pour les objectifs, déjà émis par le combat).

| ID | Objectif (`event` → `target` × `count`) | Condition d'éligibilité | Palier | Poids | Texte (`quest.<id>.objective_main`) |
|---|---|---|---|---|---|
| `quest.daily_wolves` | `EnemyDefeated` → `enemy.mist_wolf` × 20 | `{"start": true}` | M | 10 | Vaincre des loups des brumes ({n}/20) |
| `quest.daily_wood_patrol` | `EncounterCompleted` → `location.whispering_wood` × 8 | `{"start": true}` | S | 8 | Patrouiller dans le Bois des Murmures ({n}/8) |
| `quest.daily_lanterns` | `EnemyDefeated` → `enemy.wandering_lantern` × 15 | `quest_completed: quest.main_01` | M | 10 | Éteindre des lanternes errantes ({n}/15) |
| `quest.daily_mire_patrol` | `EncounterCompleted` → `location.lantern_mire` × 8 | `quest_completed: quest.main_01` | S | 8 | Patrouiller sur la tourbière ({n}/8) |
| `quest.daily_interrupts` | `CastInterrupted` (source `character.fern`) × 10 | `quest_completed: quest.main_01` | L | 6 | Interrompre des incantations ({n}/10) |
| `quest.daily_sentinels` | `EnemyDefeated` → `enemy.stone_sentinel` × 6 | `quest_completed: quest.main_02` | M | 10 | Abattre des sentinelles de pierre ({n}/6) |
| `quest.daily_ruins_patrol` | `EncounterCompleted` → `location.watch_ruins` × 6 | `quest_completed: quest.main_02` | S | 8 | Patrouiller dans les Ruines du Guet ({n}/6) |
| `quest.daily_frozen` | `StatusApplied` → `status.frozen` (source `character.fern`) × 5 | `quest_completed: quest.main_02` (la rune de givre est donnée au rendu) | L | 6 | Geler des ennemis ({n}/5) |
| `quest.daily_alpha` | `EncounterCompleted` → `encounter.cloister_alpha` × 1 | `quest_completed: quest.main_03` | L | 5 | Vaincre le loup alpha du cloître |

Durées visées (au niveau, équipement typique, combat ~17 s + déplacements) : S ≈ 3 min, M ≈ 4-5 min, L ≈ 5-10 min (le loup alpha demande de traverser 4 salles du donjon). Un joueur qui fait ses 3 contrats y passe 10 à 20 minutes `[H]`.

`location.*` en cible ne compte que les rencontres de `location.encounters` : les salles du donjon ne comptent pas pour `daily_ruins_patrol`.

## 4. Récompenses

Calculées **au tirage**, avec le niveau de Fern à ce moment (`L`), et affichées sur la carte du contrat.

```
or       = roundi(CONTRACT_GOLD_BASE × (1 + GOLD_GROWTH × (L − 1)) × CONTRACT_TIER_MULT[palier])
poussière = CONTRACT_DUST[palier]
éclats    = CONTRACT_SHARDS[palier]
```

| Constante (**nouvelle**, à ajouter dans `game/engine/balance/`) | S | M | L |
|---|---|---|---|
| `CONTRACT_GOLD_BASE` | 100 | | |
| `CONTRACT_TIER_MULT` | 0,75 | 1,0 | 1,5 |
| `CONTRACT_DUST` (`material.mana_dust`) | 4 | 6 | 10 |
| `CONTRACT_SHARDS` (`material.rune_shard`) | 1 | 2 | 3 |

`GOLD_GROWTH` = 0,20 (GAME_BALANCE §13). Pas d'XP, pas de page de grimoire, pas d'objet : GAME_BALANCE §1 ne compte les contrats que comme source d'or ; les matériaux restent « petits » (un contrat M ≈ 9 rencontres de poussière).

Exemples : niveau 1, M → 100 or ; niveau 12, M → 320 or ; niveau 20, L → 720 or.

Cohérence avec §21.3 : ~14 jours × 3 contrats × ~320 or (niveau moyen 12) ≈ 13 400 or ; avec les quêtes (4 350), ~17 800 sur les ~20 000 prévus.

## 5. Interface (clés `ui.contracts.*`)

| Clé | Texte |
|---|---|
| `ui.contracts.title` | Contrats du jour |
| `ui.contracts.renews` | Nouveaux contrats à minuit |
| `ui.contracts.claim` | Récupérer |
| `ui.contracts.claimed` | Récupéré |
| `ui.contracts.empty` | Aucun contrat pour l'instant. Revenez demain. |
| `ui.contracts.new_day` | De nouveaux contrats sont affichés. |
| `ui.contracts.auto_claimed` | Contrats d'hier récupérés : +{gold} or. |
| `ui.contracts.offline_note` | Les victoires hors ligne ne comptent pas pour les contrats. |

Pas de compte à rebours en secondes, pas de notification, pas de pastille rouge : seule une icône discrète sur le bouton Journal quand un contrat est `completed`.

## 6. État à sauvegarder (à fournir par le format de sauvegarde)

```
progress.contracts = { "day_index": 20398,
                       "offers": [ { "id": "quest.daily_wolves", "count": 12, "state": "active",
                                     "reward": { "gold": 320, "dust": 6, "shards": 2 } } ] }
```

Clé **nouvelle** dans `progress` : à coordonner avec la refonte en cours du format de sauvegarde (migration : absente ⇒ tirage au premier chargement).

## 7. Plan de test de jeu

| Observation | Seuil |
|---|---|
| Le joueur lit les contrats sans y être invité ? | ≥ 1 ouverture de l'onglet Contrats dans la première heure |
| Les contrats orientent-ils le choix de la chasse ? | Le joueur cite un contrat comme raison d'aller dans un lieu |
| Sentiment d'obligation (P2) | À la question « Vous sentez-vous obligé de revenir chaque jour ? », réponse non |
| `daily_frozen` compris | Le joueur sertit la rune de givre pour le remplir, sans aide |
