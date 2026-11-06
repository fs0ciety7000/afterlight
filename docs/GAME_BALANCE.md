# AFTERLIGHT : équilibrage et formules

> Version 0.1 (2026-11-06). Toutes les valeurs sont des **hypothèses `[H]`** à confirmer en simulation puis en test de jeu.
> Chaque constante `UPPER_SNAKE` est définie une seule fois dans `game/engine/balance/` (règle 4 de `docs/ARCHITECTURE.md` : aucun nombre de gameplay ailleurs). Les formules y sont implémentées une seule fois, dans le moteur pur (sans nœud). Les valeurs propres à une entité (PV d'un ennemi, coeff d'un sort) sont dans les JSON de `game/data/`.

## 0. Conventions

| Règle | Valeur |
|---|---|
| Pas de simulation | `TICK_SECONDS = 0.05` (20 ticks/s). Durées et recharges en secondes, converties en ticks par `ceil(s / TICK_SECONDS)` |
| Nombres | Flottants pendant tout le calcul. **Un seul arrondi, à la fin** : dégâts et soins `roundi`, minimum 1 ; monnaies et XP `floori` |
| Aléatoire | Flux à graine de `game/engine/core/rng.gd` (`combat`, `loot`, `offline`, dérivés de la graine de partie et d'un compteur, cf. ARCHITECTURE). Dans ce document, `rng.uniform(a, b)` désigne un tirage dans le flux concerné |
| Pourcentages | Stockés en fraction (`0.08` = 8 %). Les bonus d'une même couche **s'additionnent**. Seules les couches différentes se multiplient |
| Niveau | `L` = niveau du personnage, `Le` = niveau de l'ennemi, `ilvl` = niveau d'objet |

## 1. Intention et carte de l'économie

**Intention** : des rencontres normales gagnées sans effort au bon niveau (le plaisir de voir sa puissance), une élite et un boss qui demandent de lire et de réagir, et une progression hors ligne qui donne envie de revenir sans rendre le jeu actif inutile.

| Ressource | Sources | Puits | Verrou |
|---|---|---|---|
| XP | Ennemis, quêtes, premières victoires, découvertes, hors ligne | Niveaux (plafond 20) | Pénalité de niveau (§12) |
| Or | Ennemis, quêtes, contrats, hors ligne | Amélioration, rangs de sorts, fusion, artefacts, consommables | - |
| Poussière de mana | Ennemis, recyclage | Amélioration | - |
| Éclat runique | Ennemis, recyclage des runes | Fusion, quête de l'horloger | - |
| Page de grimoire | Quêtes, élite, boss, coffres, 1 % par rencontre | Rangs de sorts | Niveau requis par rang |
| Essence de cendre | Élite, boss | Niveaux d'artefact | Élite et boss hors chasse hors ligne |
| Objets, runes | Butin, hors ligne (plafonné) | Recyclage, fusion | Inventaire de 60 cases |

## 2. Statistiques

| ID | Nom FR | Rôle | Plafond |
|---|---|---|---|
| `max_hp` | PV max | Survie | - |
| `max_mana` | Mana max | Réserve | - |
| `mana_regen` | Régénération de mana (/s) | Revenu de mana | - |
| `power` | Puissance | Base de tous les dégâts, soins et boucliers | - |
| `defense` | Défense | Mitigation (§3) | - |
| `crit_chance` | Chance de critique | | `CRIT_CHANCE_CAP = 0.60` |
| `crit_damage` | Dégâts critiques (multiplicateur) | | `CRIT_DAMAGE_CAP = 3.0` |
| `haste` | Hâte | Divise les recharges, l'intervalle d'attaque et l'incantation | `HASTE_CAP = 0.50` |
| `damage_bonus` | Dégâts augmentés | Couche additive des bonus | - |
| `element_bonus_<e>` | Dégâts de feu, givre, foudre, arcane | Même couche additive | - |
| `resist_all` | Résistance | `× (1 − resist_all)` sur les dégâts subis | `RESIST_CAP = 0.50` |
| `shield_bonus` | Puissance des boucliers | | - |
| `gold_find` | Or trouvé | | `GOLD_FIND_CAP = 1.0` |
| `move_speed` | Vitesse de déplacement | Exploration seulement | - |

### 2.1 Base de Fern et croissance

| Stat | Niveau 1 | Par niveau | Constante |
|---|---|---|---|
| `max_hp` | 420 | +38 | `FERN_HP_BASE`, `FERN_HP_PER_LEVEL` |
| `max_mana` | 100 | +4 | `FERN_MANA_BASE`, `FERN_MANA_PER_LEVEL` |
| `mana_regen` | 4,0 | 0 | `FERN_MANA_REGEN` |
| `power` | 30 | +4,5 | `FERN_POWER_BASE`, `FERN_POWER_PER_LEVEL` |
| `defense` | 12 | +2 | `FERN_DEF_BASE`, `FERN_DEF_PER_LEVEL` |
| `crit_chance` | 0,05 | 0 | `BASE_CRIT_CHANCE` |
| `crit_damage` | 1,5 | 0 | `BASE_CRIT_DAMAGE` |
| `move_speed` | 5,0 m/s | 0 | `FERN_MOVE_SPEED` |

`stat_base(L) = BASE + PER_LEVEL × (L − 1)`

### 2.2 Dérivation (couches de modificateurs)

```
final = clamp( (stat_base(L) + Σ flat) × (1 + Σ percent), 0, CAP )
```

Les modificateurs sont empilés par source (`source_id`) : équiper un objet ajoute ses modificateurs, le retirer enlève exactement les mêmes. Les statistiques dérivées sont recalculées et ne sont jamais sauvegardées comme vérité.

**Exemple** : Fern, niveau 10, porte un bâton rare ilvl 10 amélioré à +4 et une robe peu commune ilvl 9 à +2.
- Puissance de base : 30 + 4,5 × 9 = 70,5. Implicite du bâton : 6 × 2,35 × 1,2 × (1 + 0,06 × 4) = 20,98. Affixe +8 % de puissance.
  → `power = (70,5 + 20,98) × 1,08 = 98,80`
- PV : 420 + 38 × 9 = 762. Robe : 40 × 2,20 × 1,1 × 1,12 = 108,4. Affixe +5 % de PV.
  → `max_hp = (762 + 108,4) × 1,05 = 913,9`

## 3. Dégâts

```
K(L_att)     = DEFENSE_K_BASE + DEFENSE_K_PER_LEVEL × L_att
mitigation   = K / (K + defense_cible)
bonus        = 1 + damage_bonus + element_bonus[e] + bonus_sort (rune Puissance, Mana voilé...)
brut         = power × coeff × rank_mult × bonus
final        = brut × mitigation × affinité × réaction × (1 + choc) × crit × variance
               × (1 − resist_all_cible) × (1 − reduction_cible)
dégâts       = max(1, roundi(final))
```

| Constante | Défaut | Plage sûre | Justification |
|---|---|---|---|
| `DEFENSE_K_BASE` | 40 | 20-80 | Mitigation en ratio : pas d'immunité, rendements décroissants |
| `DEFENSE_K_PER_LEVEL` | 8 | 5-12 | K grandit avec le niveau de l'attaquant, donc la mitigation reste stable au même niveau |
| `DAMAGE_VARIANCE` | 0,08 | 0-0,15 | `variance = rng.uniform(1 − V, 1 + V)` : vivant sans être injuste |
| `BASE_CRIT_DAMAGE` | 1,5 | 1,3-2,0 | Le critique se sent sans dominer |
| `ENEMY_DAMAGE_REDUCTION_CAP` | 0,45 | 0,3-0,6 | Plafond des réductions de type « Lanternes liées » |

**Critique** : `est_crit = rng.uniform(0, 1) < min(crit_chance + bonus_crit_sort, CRIT_CHANCE_CAP)`, puis `crit = crit_damage` si c'est un critique, sinon 1. Les soins et les boucliers ne font jamais de critique.

**Barrière ennemie** : les dégâts vont d'abord à la barrière. Coup arcane : `dégâts_barrière = final × BARRIER_ARCANE_MULT`. Si la barrière cède, le surplus revient à l'échelle normale et passe sur les PV : `surplus_pv = (dégâts_barrière − barrière) / BARRIER_ARCANE_MULT`.

**Exemple** : Zoltraak de Fern (niveau 10, `power` 98,8, rang 2, Mana voilé actif) sur une sentinelle niveau 10.
- `K(10) = 40 + 80 = 120` ; défense de la sentinelle = 0,6 × K(10) = 72 ; mitigation = 120 / 192 = 0,625.
- brut = 98,8 × 3,2 × 1,12 × 1,30 = 460,3 ; × 0,625 = 287,7 ; variance tirée 1,03 → 296,3 ; pas de critique.
- Barrière de la sentinelle : 25 % × 1 222 = 305,5. Dégâts arcane sur la barrière : 296,3 × 2 = 592,6, donc la barrière est brisée.
- Surplus : (592,6 − 305,5) / 2 = 143,6, arrondi à 144 PV. La sentinelle passe de 1 222 à 1 078 PV.
- En cas de critique, le même coup aurait fait 296,3 × 1,5 = 444,5.

## 4. Éléments et réactions

| Constante | Défaut | Plage | Effet |
|---|---|---|---|
| `AFFINITY_WEAK` | 1,5 | 1,25-2,0 | Faiblesse |
| `AFFINITY_NEUTRAL` | 1,0 | - | |
| `AFFINITY_RESIST` | 0,6 | 0,4-0,8 | Résistance. Jamais d'immunité dans la tranche |
| `BARRIER_ARCANE_MULT` | 2,0 | 1,5-3,0 | Arcane contre les barrières |
| `REACTION_MELT_MULT` | 1,5 | 1,25-2,0 | Feu sur Gelé, retire Gelé |
| `REACTION_OVERLOAD_COEFF` | 0,8 | 0,5-1,2 | Foudre sur Brûlé : explosion de zone (`power × coeff`), retire 1 cumul |
| `REACTION_OVERLOAD_RADIUS_M` | 3,0 | 2-4 | |
| `SHOCK_BONUS` | 0,15 | 0,1-0,25 | Le prochain coup subi, puis Choc est consommé |

Pas de réaction en chaîne : un coup déclenche au plus une réaction, et l'explosion de Surcharge ne peut pas en déclencher d'autre.

## 5. Kit de Fern (valeurs au rang 1)

| Sort | `coeff` | Coups | Mana | Recharge (s) | Incantation (s) | Portée (m) | Notes |
|---|---|---|---|---|---|---|---|
| `spell.mana_bolt` | 1,0 | 1 | 0 | intervalle 1,2 | - | 9 | `AUTO_MANA_RESTORE = 3` par coup ; projectile à 25 m/s |
| `spell.zoltraak` | 3,2 | 1 | 25 | 6 | 0,3 | 12 | Interrompt ; arcane |
| `spell.mana_volley` | 0,6 | 5 | 35 | 10 | 0,4 | 10 | 5 projectiles répartis à tour de rôle, en commençant par la cible focalisée |
| `spell.defensive_barrier` | bouclier (§8) | - | 30 | 18 | 0 | soi | Hors temps de recharge global ; retire 1 altération |
| `spell.afterlight` | 0,9 | 12 | 0 | charge 100 | canalisation 2,0 | 14 | 50 % des rayons sur la cible focalisée, le reste au hasard |
| `passive.veiled_mana` | +0,30 | - | - | 4 s sans actif | - | - | `VEILED_MANA_BONUS`, `VEILED_MANA_DELAY_S` ; −30 % de rayon d'aggro en exploration |

| Constante | Défaut | Plage |
|---|---|---|
| `GLOBAL_COOLDOWN_S` | 0,5 | 0,3-0,8 |
| `REPOSITION_HOLD_S` (temps pendant lequel Fern tient la position choisie par le joueur, GDD §7.2) | 4,0 | 2-6 |
| `INPUT_BUFFER_S` | 0,30 | 0,15-0,40 |
| `INTERRUPT_STUN_S` | 1,0 (boss : × `BOSS_CC_DURATION_MULT`) | 0,5-1,5 |

## 6. Mana, recharges, hâte

```
recharge_eff   = recharge × (1 − rune_celerite) / (1 + haste)
intervalle_eff = intervalle_auto / (1 + haste)
incant_eff     = incantation / (1 + haste)
coût_eff       = coût × (1 − rune_economie)
revenu_mana/s  = mana_regen + AUTO_MANA_RESTORE / intervalle_eff
```

| Constante | Défaut | Plage | Note |
|---|---|---|---|
| `AUTO_MANA_RESTORE` | 3 | 2-5 | |
| `OOC_DELAY_S` | 2,0 | 1-4 | Délai avant la régénération hors combat |
| `OOC_HP_PCT_PER_S` | 0,10 | 0,05-0,2 | Nulle en donjon (`DUNGEON_OOC_HP_PCT_PER_S = 0`) |
| `OOC_MANA_PCT_PER_S` | 0,20 | 0,1-0,3 | Aussi en donjon |
| `MANA_COST_REDUCTION_CAP` | 0,40 | 0,3-0,5 | Plafond de la réduction de coût totale d'un sort |
| `COOLDOWN_REDUCTION_CAP` | 0,40 | 0,3-0,5 | Plafond de la réduction de recharge des runes (la hâte s'applique en plus) |

**Budget de mana** (niveau 1, sans hâte, en lançant tout dès que possible) :
- Dépense : 25/6 + 35/10 + 30/18 = 4,17 + 3,50 + 1,67 = **9,33 mana/s**.
- Revenu : 4 + 3/1,2 = **6,5 mana/s**.
- Ratio soutenu `r = 6,5 / 9,33 = 0,696`. Une réserve pleine (100) tient 100 / (9,33 − 6,5) ≈ **35 s** de rotation complète.
- Conséquence voulue : une rencontre normale (~17 s) se joue sans arbitrage ; l'élite et le boss obligent à choisir. La réserve de mana des tactiques (20 %) garde de quoi poser une Barrière.

## 7. Charge d'ultime

| Constante | Défaut | Plage |
|---|---|---|
| `ULT_CHARGE_MAX` | 100 | - |
| `ULT_CHARGE_PER_AUTO` | 2 | 1-4 |
| `ULT_CHARGE_PER_ACTIVE` | 5 | 3-10 |
| `ULT_CHARGE_PER_HP_PCT_LOST` | 0,5 | 0,25-1 | Multipliée par 1,2 sur la rangée avant (`FRONT_ROW_ULT_CHARGE_MULT`) |

La charge persiste entre les rencontres d'une session et retombe à 0 au chargement.

Rythme soutenu : 2/1,2 + 5 × (1/6 + 1/10 + 1/18) × 0,696 = 1,667 + 1,122 = 2,79/s. La jauge est pleine en ~36 s, donc un ultime toutes les ~38 s avec la canalisation. Cela fait environ 1 ultime toutes les 2 rencontres normales et 5 à 6 contre le boss.

## 8. Soins et boucliers

```
bouclier = (SHIELD_HP_RATIO × max_hp + SHIELD_POWER_COEFF × power) × rank_mult × (1 + shield_bonus)
soin     = valeur × (1 + 0)   # pas de bonus de soin dans la tranche, pas de critique
```

| Constante | Défaut | Plage | Note |
|---|---|---|---|
| `SHIELD_HP_RATIO` | 0,25 | 0,15-0,35 | |
| `SHIELD_POWER_COEFF` | 1,5 | 1-2,5 | |
| `SHIELD_DURATION_S` | 4,0 | 3-6 | Un nouveau bouclier remplace l'ancien s'il est plus grand ; sinon, il rafraîchit seulement la durée |
| `HEALING_DRAUGHT_PCT` | 0,35 | 0,25-0,5 | Infusion de soin |
| `MANA_ELIXIR_AMOUNT` | 50 | 30-80 | |
| `CONSUMABLE_SHARED_CD_S` | 20 | 15-30 | |
| `CONSUMABLE_CARRY_MAX` | 5 | 3-10 | |

**Exemple** : Fern niveau 10 (914 PV, `power` 98,8) → 0,25 × 914 + 1,5 × 98,8 = 228,5 + 148,2 = **376,7**, soit 41 % de ses PV.

## 9. Statuts

| ID | Effet | Durée (s) | Cumuls max | Règle de cumul | Boss |
|---|---|---|---|---|---|
| `status.burn` | DoT `BURN_COEFF = 0.15 × power_source` par seconde et par cumul, ticks toutes les 0,5 s | 4 | 3 | Ajoute un cumul et rafraîchit la durée commune | Normal |
| `status.chill` | −10 % de vitesse d'attaque et de déplacement par cumul | 3 | 3 | Au 3e cumul → `status.frozen`, Refroidi retiré | 2 cumuls max, jamais gelé |
| `status.frozen` | Ne peut pas agir | 1,5 | 1 | Puis immunité `FREEZE_IMMUNITY_S = 4` | Immunisé |
| `status.shock` | +`SHOCK_BONUS` au prochain coup subi | 5 | 1 | Rafraîchit | Normal |
| `status.weaken` | −30 % de `power` | 8 | 1 | Rafraîchit | × 0,5 de durée |
| `status.stun` | Ne peut pas agir (après une interruption) | 1,0 | 1 | Ne se cumule pas | × 0,5 |
| `status.haste_buff` (Frénésie) | +25 % de vitesse d'attaque | 8 | 1 | Rafraîchit | - |
| `status.shield` | Absorbe les dégâts (§8) | 4 | 1 | Le plus grand reste | - |

`BOSS_CC_DURATION_MULT = 0.5`. Les DoT appliquent la mitigation et l'affinité, calculées à chaque tick, mais ne font jamais de critique. Chance d'appliquer un statut : celle de la rune de conversion (§17) par coup. Les projectiles ennemis ont leur propre chance (lanterne : 0,3 de Brûlure).

## 10. Ennemis

### 10.1 Croissance par niveau

```
hp(Le)      = HP_L1 × (1 + ENEMY_HP_GROWTH × (Le − 1))
power(Le)   = POWER_L1 × (1 + ENEMY_POWER_GROWTH × (Le − 1))
defense(Le) = def_ratio × K(Le)          # la mitigation au même niveau vaut toujours 1 / (1 + def_ratio)
barrier     = barrier_ratio × hp(Le)
```

| Constante | Défaut | Justification |
|---|---|---|
| `ENEMY_HP_GROWTH` | 0,15 | Suit la puissance d'une Fern « équipement typique » (§21), donc des rencontres de durée constante au même niveau |
| `ENEMY_POWER_GROWTH` | 0,095 | Suit les PV de Fern, donc une pression constante |

### 10.2 Table des ennemis (niveau 1)

| Ennemi | `HP_L1` | `POWER_L1` | `def_ratio` | `barrier_ratio` | Intervalle d'attaque (s) | `coeff` attaque | Portée (m) | Vitesse (m/s) | Aggro (m) | `xp_mult` | `gold_mult` | Faible / Résiste |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| `enemy.mist_wolf` | 300 | 14 | 0,20 | 0 | 1,4 | 1,0 | 1,8 | 5,5 | 9 | 1,0 | 1,0 | feu / - |
| `enemy.wandering_lantern` | 220 | 17 | 0,10 | 0 | 2,2 | 1,3 (feu) | 10 | 3,0 | 11 | 1,0 | 1,0 | givre / feu |
| `enemy.stone_sentinel` | 520 | 20 | 0,60 | 0,25 | 2,6 | 1,2 | 2,2 | 2,5 | 7 | 1,6 | 1,5 | foudre / givre |
| `enemy.mist_wolf_alpha` (élite) | 1 800 | 21 ¹ | 0,30 | 0 | 1,2 | 1,1 | 2,0 | 6,0 | 12 | 6,0 | 5,0 | feu / givre |
| `enemy.morvaine` (boss) | 7 500 | 18 ¹ | 0,35 | 0,15 (phase 2) | 2,5 | 0,6 (feu) ¹ | 12 | 2,0 | - | 30 | 25 | givre / feu |

¹ Recalé par le banc de simulation du jalon 3 (2026-11-06, `tools/combat_bench.gd`, Fern typique). Valeurs d'origine : `POWER_L1` de l'alpha 22, de Morvaine 24, `coeff` du Trait de cendre 0,9. Avec elles : alpha `idle` 10 % de victoires (cible 30-60 %) ; Morvaine `script_optimal` 0 % (cible ≥ 80 %), Fern tombe vers 125-145 s. Cause : le budget du §11 compte ~10 Barrières pleines (4 290), alors qu'un bouclier de 4 s n'absorbe qu'environ 100 points de dégâts continus ; seule la Barrière posée sur le Sceau sert en entier. Après recalage : alpha `idle` 34 %, `script_optimal` 100 % ; Morvaine `script_optimal` 86 % (p50 157 s), `idle` 0 %, `confus` 0 %. Le Sceau non bouclié fait encore ~380, soit 35 % des PV de Fern niveau 11.

### 10.3 Capacités

| ID | Coeff | Télégraphe ou canalisation (s) | Recharge (s) | Interruptible | Détail |
|---|---|---|---|---|---|
| `ability.wolf_lunge` | 1,8 | 0,6 | 8 | non | Ligne de 6 m |
| `ability.lantern_blaze` | 0,5 par 0,5 s | 2,0 (canalisation) | 12 | **oui** | Zone de 3 m pendant 4 s ; l'IA de Fern en sort après `ALLY_DODGE_REACTION_S = 0.4` |
| `ability.sentinel_slam` | 2,4 | 1,2 | 7 | non | Cercle de 3 m |
| `ability.sentinel_barrier` | - | - | revient après 8 s sans dégâts arcane | - | Revient pleine |
| `ability.alpha_howl` | - | 1,5 | à 70 % et 35 % des PV | **oui** | 2 loups au niveau `Le − 1` + Frénésie |
| `ability.alpha_chain_lunge` | 1,5 × 3 | 0,8 chacun | 14 | non | |
| `ability.morvaine_ash_bolt` | 0,6 ¹ | - | 2,5 (1,9 en phase 3) | - | Brûlure 0,3 |
| `ability.morvaine_bound_lanterns` | - | - | 30 (phase 1) | - | 2 lanternes au niveau `Le − 2`, 4 au plus ; −0,15 de dégâts subis par lanterne, plafonné à `ENEMY_DAMAGE_REDUCTION_CAP` |
| `ability.morvaine_veil` | - | - | revient après 10 s sans arcane (phase 2) | - | 15 % des PV max |
| `ability.morvaine_false_word` | - | 2,0 | 18 | **oui** | Affaibli sur Fern |
| `ability.morvaine_ash_seal` | 15,0 | 3,0 | 25 (15 en phase 3) | non | Le gros coup à bouclier |
| `ability.morvaine_enrage` | 99 | - | à 300 s | non | Enrage dur |

Phase 3 : +0,30 de `haste`. Seuils de phase : `MORVAINE_PHASE_2_HP = 0.65`, `MORVAINE_PHASE_3_HP = 0.30`.

**Exemple de niveau** : loup niveau 5 → PV 300 × 1,6 = 480 ; puissance 14 × 1,38 = 19,3 ; défense 0,2 × K(5) = 0,2 × 80 = 16.

## 11. Durée des rencontres

| Type | Cible (au même niveau, équipement typique) | Budget de PV effectifs |
|---|---|---|
| Normale | 15-30 s | `ENCOUNTER_EHP_BUDGET = 1080 × (1 + 0.15 × (Le − 1))` ± 25 % (soit l'équivalent de 3 loups) |
| Élite | 45-75 s | 1 élite + renforts possibles |
| Boss | 150-210 s, enrage à 300 s | - |

```
PV_effectifs_i = hp_i / (mitigation_i × affinité_i) + barrier_i / (mitigation_i × mult_barrière_i × affinité_i)
DPS_eff        = power × ROT × crit_factor × OFFLINE_DPS_CALIBRATION
crit_factor    = 1 + crit_chance × (crit_damage − 1)
```

`ROT` est le coefficient de rotation soutenu, en coeff par seconde (§20.2). Il vaut **1,70** pour le kit de rang 1 sans rune.

**Vérification au même niveau** (3 loups, Fern équipement typique, crit 0,08) :
- PV effectifs : 3 × 300 × m × 1,2 = 1 080 m.
- DPS : 1,70 × 1,04 × 0,85 × `power` = 1,503 × `power`.
- Niveau 1 : `power` 42,8, donc 64,3 DPS et 1 080 / 64,3 = **16,8 s**. Niveau 10 : 2 538 / 151,2 = **16,8 s**. La durée reste constante au même niveau.

**Élite** (alpha niveau 11, Fern niveau 10 typique) :
- PV effectifs : 4 500 / 0,758 = 5 937, soit 39 s.
- Avec 2 hurlements non interrompus, il faut ajouter 4 loups (3 384 PV effectifs), soit 61 s au total.

**Boss** (Morvaine niveau 12, Fern niveau 11 typique, `power` 107,1) :
- PV : 7 500 × 2,65 = 19 875. Mitigation : 128 / 175,6 = 0,729, soit 27 263 PV effectifs.
- Il faut ajouter le voile (~2 700) et les lanternes de la phase 1 (~2 240), soit ~32 200 PV effectifs.
- DPS : 161, donc **~200 s**. L'enrage à 300 s laisse une marge de ×1,5.

**Pression subie par Fern contre le boss** (Fern : 1 075 PV, défense 61,3, mitigation 136 / 197,3 = 0,689) :
- Trait de cendre : 49,1 × 0,9 × 0,689 = 30,4 toutes les 2,5 s, soit 12,2 dégâts/s.
- Sceau de cendre : 49,1 × 15 × 0,689 = 507, soit **47 % des PV**. Le bouclier (429) le ramène à 78.
- Bien joué (Sceau bouclié, lanternes tuées), la moyenne est ~21 dégâts/s, soit ~4 200 sur 200 s.
- Budget de Fern : PV + ~10 Barrières (4 290) + 3 infusions (1 128) ≈ 6 500. Marge ×1,55.
- Sans bouclier sur le Sceau : ~38 dégâts/s, soit ~7 600 > 6 500, donc défaite probable. **C'est le test de compétence voulu.**
- *Calcul fait avec les valeurs d'avant le banc du jalon 3 (`POWER_L1` 24, Trait 0,9) : voir la note ¹ du §10.2. Mesuré en simulation avec les valeurs actuelles : ~25 dégâts/s subis en jouant bien, dont lanternes et Brûlure ; les Barrières hors Sceau absorbent ~100 chacune.*

## 12. XP et niveaux

```
xp_to_next(L)   = round_to_10( XP_TO_NEXT_BASE × L ^ XP_EXPONENT )
xp_ennemi(Le)   = ENEMY_XP_BASE × (1 + ENEMY_XP_GROWTH × (Le − 1)) × xp_mult
écart           = L − Le
pénalité        = 1                                  si écart ≤ 2
                = max(XP_PENALTY_FLOOR, 1 − XP_PENALTY_PER_LEVEL × (écart − 2))   sinon
```

| Constante | Défaut | Plage |
|---|---|---|
| `LEVEL_CAP` | 20 | - |
| `XP_TO_NEXT_BASE` | 40 | 30-60 |
| `XP_EXPONENT` | 2,6 | 2,2-3,0 |
| `ENEMY_XP_BASE` | 8 | 6-12 |
| `ENEMY_XP_GROWTH` | 0,25 | 0,15-0,35 |
| `XP_PENALTY_PER_LEVEL` | 0,20 | 0,1-0,3 |
| `XP_PENALTY_FLOOR` | 0,20 | 0,1-0,3 |
| `FIRST_CLEAR_XP_MULT` | 3 | 2-5 | XP de la première victoire sur chaque rencontre |
| `QUEST_XP_MAIN` / `QUEST_XP_SIDE` / `DISCOVERY_XP` | 0,6 / 0,3 / 0,1 × `xp_to_next(niveau_de_la_quête)` | |

**La table ci-dessous fait foi** (`XP_TO_NEXT_TABLE`, critère 4.1) : la formule donne 8 910, 12 110, 73 410 et 84 490 aux niveaux 8, 9, 18 et 19, au lieu de 8 920, 12 100, 73 400 et 84 470 *(écart relevé au jalon 4 ; provisoire, jalon 4 : on garde la table)*.

Au niveau maximum, l'XP en surplus est perdue et l'écran le signale. Plusieurs niveaux peuvent être gagnés d'un coup ; les statistiques sont alors recalculées une fois.

| L | `xp_to_next` | XP cumulée pour atteindre L+1 | XP par rencontre normale (3 ennemis, Le = L) | Rencontres pour passer le niveau |
|---|---|---|---|---|
| 1 | 40 | 40 | 24 | 1,7 |
| 2 | 240 | 280 | 30 | 8,0 |
| 3 | 700 | 980 | 36 | 19,4 |
| 4 | 1 470 | 2 450 | 42 | 35,0 |
| 5 | 2 630 | 5 080 | 48 | 54,8 |
| 6 | 4 220 | 9 300 | 54 | 78,1 |
| 7 | 6 300 | 15 600 | 60 | 105,0 |
| 8 | 8 920 | 24 520 | 66 | 135,2 |
| 9 | 12 100 | 36 620 | 72 | 168,1 |
| 10 | 15 920 | 52 540 | 78 | 204,1 |
| 11 | 20 400 | 72 940 | 84 | 242,9 |
| 12 | 25 580 | 98 520 | 90 | 284,2 |
| 13 | 31 500 | 130 020 | 96 | 328,1 |
| 14 | 38 190 | 168 210 | 102 | 374,4 |
| 15 | 45 700 | 213 910 | 108 | 423,1 |
| 16 | 54 050 | 267 960 | 114 | 474,1 |
| 17 | 63 270 | 331 230 | 120 | 527,3 |
| 18 | 73 400 | 404 630 | 126 | 582,5 |
| 19 | 84 470 | 489 100 | 132 | 639,9 |

## 13. Or et matériaux

```
or_ennemi(Le) = roundi( ENEMY_GOLD_BASE × (1 + GOLD_GROWTH × (Le − 1)) × gold_mult × rng.uniform(0.8, 1.2) × (1 + gold_find) )
```

`ENEMY_GOLD_BASE = 4`, `GOLD_GROWTH = 0.20`.

| Butin | Ennemi normal (par ennemi) | Élite | Boss | Constante |
|---|---|---|---|---|
| Poussière de mana | 15 %, 1-2 | 100 %, 4-6 | 100 %, 12-16 | `DROP_MANA_DUST_*` |
| Éclat runique | 4 %, 1 | 100 %, 2-3 | 100 %, 6-8 | `DROP_RUNE_SHARD_*` |
| Page de grimoire | 1 % **par rencontre** | 100 %, 1 | 100 %, 3 | `DROP_GRIMOIRE_PAGE_*` |
| Essence de cendre | - | 50 %, 1 | 100 %, 2-3 (premier kill : 5) | `DROP_ASHEN_ESSENCE_*` |
| Objet d'équipement | 25 % **par rencontre** | 1 garanti + 50 % | 2 garantis | `DROP_ITEM_*` |
| Rune | 3 % **par rencontre** | 30 % | 100 % | `DROP_RUNE_*` |

Les quantités sont tirées uniformément dans la plage. Le recyclage d'un objet donne `SALVAGE_DUST[rareté] × (1 + 0.1 × (ilvl − 1))` poussières. `SALVAGE_DUST` vaut 2, 5, 12, 30 et 80 pour commune, peu commune, rare, épique et légendaire.

*(provisoire, jalon 4)* Arrondis : la poussière de recyclage est arrondie à l'entier inférieur (`floori`, comme les monnaies). Au premier kill du boss, les 5 essences **remplacent** les 2-3 habituelles (entrées `when: first_clear` / `repeat` de la table). Sac (`INVENTORY_SLOTS = 60`) : seuls les objets non portés comptent ; retirer un objet est refusé si le sac est plein ; un consommable de butin au-delà de 5 reste sur place et un artefact déjà possédé est signalé (ligne de résumé dans les deux cas).

## 14. Butin d'équipement

### 14.1 Rareté par source (poids sur 100)

| Source | Commune | Peu commune | Rare | Épique | Légendaire |
|---|---|---|---|---|---|
| `normal` (et hors ligne) | 68 | 25 | 6 | 0,9 | 0,1 |
| `elite` | 0 | 40 | 42 | 15 | 3 |
| `boss` | 0 | 0 | 50 | 40 | 10 |
| `boss_first_kill` | 0 | 0 | 0 | 80 | 20 |
| `chest` (découvertes) | 0 | 30 | 50 | 17 | 3 |

### 14.2 Niveau d'objet et implicite

```
ilvl       = Le_source + (élite ? 1 : 0) + (boss ? 2 : 0)
ilvl_mult  = 1 + ILVL_GROWTH × (ilvl − 1)              # ILVL_GROWTH = 0.15
implicite  = SLOT_IMPLICIT[slot] × ilvl_mult × RARITY_IMPLICIT_MULT[rareté] × (1 + ENH_STAT_PER_LEVEL × amélioration)
```

| Emplacement | `SLOT_IMPLICIT` (ilvl 1) |
|---|---|
| `weapon` | `power` 6 |
| `head` | `max_hp` 25, `defense` 2 |
| `chest` | `max_hp` 40, `defense` 4 |
| `hands` | `power` 2, `defense` 1 |
| `feet` | `max_hp` 20, `defense` 2 |
| `amulet` | `crit_chance` 0,02 (suit le palier, §14.3, pas `ilvl_mult`) |

`RARITY_IMPLICIT_MULT` vaut 1,0, 1,1, 1,2, 1,35 et 1,5. `AFFIX_COUNT` vaut 1, 2, 3, 4 et 4 (+ 1 effet légendaire).

*(provisoire, jalon 4)* Choix de la base : l'emplacement est tiré uniformément parmi ceux qui ont une base de `min_ilvl ≤ ilvl`, puis la base uniformément dans cet emplacement. Un objet légendaire n'est tiré que sur un emplacement qui a un effet légendaire (`weapon`, `feet`, `amulet` dans la tranche).

### 14.3 Affixes

```
palier        = min(4, 1 + floori((ilvl − 1) / 5))
échelle_flat  = ilvl_mult
échelle_pct   = 1 + 0.25 × (palier − 1)      # pour les % et pour mana_regen et max_mana
valeur        = lerp(min, max, u) × échelle,  u = rng.uniform(0, 1)  (légendaire : rng.uniform(0.5, 1))
```

Le tirage se fait sans remise, pondéré par `weight`, et au plus un affixe par `group` (ex. `power`).

| ID | Stat | Min-Max (ilvl 1 / palier 1) | Échelle | Emplacements | Poids |
|---|---|---|---|---|---|
| `affix.power_flat` | `power` | 2-4 | flat | weapon, hands, amulet | 100 |
| `affix.power_pct` | `power` % | 0,04-0,08 | pct | weapon, amulet | 80 |
| `affix.max_hp_flat` | `max_hp` | 15-30 | flat | head, chest, feet | 100 |
| `affix.max_hp_pct` | `max_hp` % | 0,03-0,06 | pct | head, chest | 70 |
| `affix.defense_flat` | `defense` | 2-4 | flat | head, chest, hands, feet | 100 |
| `affix.crit_chance` | `crit_chance` | 0,02-0,04 | pct | weapon, hands, amulet, head | 70 |
| `affix.crit_damage` | `crit_damage` | 0,08-0,15 | pct | weapon, hands, amulet | 60 |
| `affix.haste` | `haste` | 0,02-0,05 | pct | hands, feet, amulet | 50 |
| `affix.mana_regen` | `mana_regen` | 0,4-0,8 | pct | head, amulet | 60 |
| `affix.max_mana` | `max_mana` | 8-15 | pct | head, chest | 60 |
| `affix.element_bonus_<e>` (4) | `element_bonus_<e>` | 0,06-0,12 | pct | weapon, amulet | 40 chacun |
| `affix.resist_all` | `resist_all` | 0,03-0,06 | pct | chest, feet | 40 |
| `affix.shield_bonus` | `shield_bonus` | 0,08-0,15 | pct | chest, amulet | 40 |
| `affix.gold_find` | `gold_find` | 0,05-0,10 | pct | feet, amulet | 30 |
| `affix.move_speed` | `move_speed` % | 0,03-0,06 | pct | feet | 30 |

Il n'existe volontairement **aucun affixe d'XP** : il dominerait dans un jeu idle.

*(provisoire, jalon 4)* Groupes et couches : chaque affixe a son propre `group`, sauf les 4 bonus d'élément qui partagent `element_bonus` (un seul élément par objet). `power_flat` et `power_pct` peuvent coexister (exemple ci-dessous). Couche de §2.2 : `power_pct`, `max_hp_pct` et `move_speed` vont dans la couche `percent` ; tous les autres affixes s'ajoutent à la stat (`flat`), y compris les stats déjà exprimées en fraction (critique, hâte, résistance...).

| Effet légendaire | ID | Emplacement | Effet |
|---|---|---|---|
| Écho du maître | `legendary.echo_of_the_master` | weapon | Zoltraak frappe une 2e fois à 40 % |
| Pas léger | `legendary.light_step` | feet | Après une Barrière, +0,30 de hâte pendant 4 s |
| Braise éternelle | `legendary.everburning` | amulet | Brûlure : jusqu'à 5 cumuls |

**Exemple** : bâton rare ilvl 10. `ilvl_mult = 2,35`, palier 2 (échelle pct 1,25).
- Implicite : 6 × 2,35 × 1,2 = 16,92 de puissance.
- Affixe 1, `power_pct` (u = 0,5) : 0,06 × 1,25 = **+7,5 %**.
- Affixe 2, `crit_chance` (u = 0,2) : 0,024 × 1,25 = **+3,0 %**.
- Affixe 3, `power_flat` (u = 0,9) : 3,8 × 2,35 = **+8,9**.

## 15. Amélioration

```
coût_or(n → n+1)   = roundi( ENH_GOLD_BASE × ilvl_mult × ENH_GOLD_GROWTH ^ n )
coût_poussière     = ENH_DUST_BASE × (n + 1)
chance(n+1)        = min(1, ENH_SUCCESS[n+1] + pitié),  pitié += ENH_PITY_PER_FAIL à chaque échec, remise à 0 au succès
```

| Constante | Défaut |
|---|---|
| `ENH_MAX_BY_RARITY` | 4 / 6 / 8 / 10 / 10 |
| `ENH_STAT_PER_LEVEL` | 0,06 (implicite **et affixes flat** seulement ; les % ne changent pas) |
| `ENH_GOLD_BASE` / `ENH_GOLD_GROWTH` | 60 / 1,35 |
| `ENH_DUST_BASE` | 4 |
| `ENH_SUCCESS` (+1 → +10) | 1, 1, 1, 1, 1, 0,9, 0,8, 0,7, 0,6, 0,5 |
| `ENH_PITY_PER_FAIL` | 0,10 |
| `ENH_FAIL_GOLD_REFUND` | 0,5 (la poussière est perdue) |

**Anti-rechargement** : le tirage d'amélioration utilise une graine dérivée de `(graine de partie, item_uid, nombre_de_tentatives)`, sans consommer le flux `loot`. Recharger la sauvegarde ne change donc pas l'issue.

*(provisoire, jalon 4)* La pitié est sauvegardée comme le nombre d'échecs consécutifs (`pity`) de l'objet : bonus = `pity × ENH_PITY_PER_FAIL`. L'or rendu après un échec est arrondi à l'entier inférieur.

Exemple, objet ilvl 10 (`ilvl_mult` 2,35) :

| Palier visé | Or | Poussière | Chance | Tentatives attendues (avec pitié) |
|---|---|---|---|---|
| +1 | 141 | 4 | 1,0 | 1,00 |
| +6 | 632 | 24 | 0,9 | 1,10 |
| +8 | 1 152 | 32 | 0,7 | 1,37 |
| +10 | 2 100 | 40 | 0,5 | 1,77 |
| Total de +0 à +10 (sans échec) | ≈ 7 700 | 220 | | |

## 16. Rangs des sorts

```
rank_mult(r)        = 1 + SPELL_RANK_STEP × (r − 1)        # SPELL_RANK_STEP = 0.12 (coeff ou bouclier)
coût(r → r+1)       = or 250 × r²,  pages 2 × r
niveau_requis(r+1)  = 3 × r
emplacements        = 1 (rangs 1-2), 2 (rangs 3-4), 3 (rang 5)
```

| Passage | Or | Pages | Niveau |
|---|---|---|---|
| 1 → 2 | 250 | 2 | 3 |
| 2 → 3 | 1 000 | 4 | 6 |
| 3 → 4 | 2 250 | 6 | 9 |
| 4 → 5 | 4 000 | 8 | 12 |
| Total par sort | 7 500 | 20 | |

Pour les 4 sorts : 30 000 or et 80 pages. Sources de pages : 11 par les quêtes, ~6 par les coffres, l'élite et le boss quand on les rejoue, ~5 par nuit hors ligne.

## 17. Runes et fusion

| Rune | ID | Groupe | Palier 1 / 2 / 3 / 4 / 5 |
|---|---|---|---|
| Braise | `rune.ember` | conversion (feu) | Chance de Brûlure 0,20 / 0,30 / 0,40 / 0,50 / 0,60 |
| Givre | `rune.frost` | conversion (givre) | Chance de Refroidi, mêmes valeurs |
| Orage | `rune.storm` | conversion (foudre) | Chance de Choc, mêmes valeurs |
| Acuité | `rune.acuity` | modification | Chance de critique du sort +0,04 / 0,06 / 0,09 / 0,13 / 0,18 |
| Économie | `rune.thrift` | modification | Coût −0,08 / 0,12 / 0,16 / 0,20 / 0,25 |
| Célérité | `rune.swiftness` | modification | Recharge −0,06 / 0,09 / 0,12 / 0,15 / 0,20 |
| Écho | `rune.echo` | modification | Chance de relancer à 50 % (gratuit, sans relance en chaîne) 0,10 / 0,15 / 0,20 / 0,27 / 0,35 |
| Puissance | `rune.potency` | modification | Dégâts du sort +0,08 / 0,12 / 0,17 / 0,23 / 0,30 (couche additive) |

Une rune de conversion au plus par sort. Pas de doublon d'ID sur un même sort. Les runes se sertissent sur les sorts actifs et l'ultime, jamais sur l'attaque auto.

```
fusion : 3 × rune(id, n) → rune(id, n+1),  or = FUSION_GOLD_BASE × 3^(n−1),  éclats = FUSION_SHARD_BASE × n,  succès 1.0
```

`FUSION_GOLD_BASE = 150`, `FUSION_SHARD_BASE = 5`. Le recyclage d'une rune donne `2 × 3^(n−1)` éclats.

| Fusion | Or | Éclats | Runes P1 équivalentes |
|---|---|---|---|
| P1 → P2 | 150 | 5 | 3 |
| P2 → P3 | 450 | 10 | 9 |
| P3 → P4 | 1 350 | 15 | 27 |
| P4 → P5 | 4 050 | 20 | 81 |

Paliers à l'obtention : normale 90 / 10 / 0, élite 60 / 35 / 5, boss 0 / 70 / 30 (P1 / P2 / P3). Type : conversions 12 chacune, modifications 12,8 chacune.

*(provisoire, jalon 4)* Coffre (`chest`) : paliers de l'élite ; premier kill du boss : paliers du boss. La rune Écho (`echo_chance`) est transmise à la simulation dans `spell_mods` mais pas encore jouée par elle.

## 18. Artefacts

| ID | Niveau 1 / 2 / 3 / 4 / 5 |
|---|---|
| `artifact.cracked_hourglass` | Efficacité hors ligne +0,03 / 0,05 / 0,07 / 0,09 / 0,12 (additive à `OFFLINE_EFFICIENCY`) |
| `artifact.pressed_flower` | Soin unique sous 30 % des PV : 0,15 / 0,18 / 0,21 / 0,25 / 0,30 des PV max |
| `artifact.traveler_compass` | `gold_find` +0,08 / 0,11 / 0,14 / 0,17 / 0,20 |
| `artifact.ashen_bell` | Un actif sur 4 : +0,40 / 0,50 / 0,60 / 0,70 / 0,80 de dégâts (couche additive du sort) |

Passer du niveau n à n+1 coûte `ARTIFACT_ESSENCE_COST[n]` essences (1 / 2 / 3 / 5) et `500 × n²` or. Deuxième emplacement au niveau 15 (`ARTIFACT_SLOT_2_LEVEL`).

*(provisoire, jalon 4)* Premier emplacement au niveau 6 (`ARTIFACT_SLOT_1_LEVEL`), sans condition de quête tant que la quête de l'horloger n'existe pas. Les effets de la Fleur pressée, de la Cloche de cendre et des effets légendaires sont exposés par le moteur (`ArtifactRules.worn_effects`, `legendary` de l'objet) mais pas encore appliqués par la simulation de combat ; la Boussole (`gold_find`) l'est, par les statistiques.

## 19. Prix

| Objet | Prix | Constante |
|---|---|---|
| Infusion de soin | `roundi(30 × (1 + 0.1 × (L − 1)))` | `PRICE_HEALING_DRAUGHT_BASE` |
| Élixir de mana | `roundi(25 × (1 + 0.1 × (L − 1)))` | `PRICE_MANA_ELIXIR_BASE` |

Pas de revente d'objets contre de l'or : seul le recyclage existe, pour éviter une boucle or contre butin.

## 20. Progression hors ligne

### 20.1 Entrées et règles

| Constante | Défaut | Plage | Note |
|---|---|---|---|
| `OFFLINE_CAP_S` | 28 800 (8 h) | fixe | Exigence du propriétaire |
| `OFFLINE_MIN_S` | 60 | 30-300 | |
| `OFFLINE_EFFICIENCY` | 0,25 | 0,20-0,40 | 8 h hors ligne valent 2 h de chasse active (décision du propriétaire, 2026-11-06) |
| `OFFLINE_DPS_CALIBRATION` | 0,85 | 0,7-1,0 | Déplacements, surplus de dégâts, changements de cible. Calibré sur la simulation (§22) |
| `ENGAGE_S` | 2,0 | | Approche en début de rencontre |
| `ENCOUNTER_RESPAWN_S` | 6,0 | 4-10 | Entre deux rencontres de la boucle « Chasser ici » |
| `CLEAR_TIME_MIN_S` / `CLEAR_TIME_MAX_S` | 8 / 120 | | Au-delà du maximum, la rencontre n'est pas éligible |
| `OFFLINE_INCOMING_ALIVE_FACTOR` | 0,6 | | Part moyenne des ennemis vivants pendant la rencontre |
| `OFFLINE_SAFETY_FACTOR` | 1,25 | 1,0-2,0 | |
| `OFFLINE_ITEM_KEEP_MAX` | 30 (et ≤ cases libres) | | |
| `OFFLINE_ITEM_SAMPLE_MAX` | 500 | | Au-delà, recyclage à l'espérance |
| `OFFLINE_RUNE_KEEP_MAX` | 20 | | Au-delà, recyclage en éclats |

Entrées : `last_save_unix` (= `meta.last_active_at` de l'état), `now_unix` (passé en paramètre au moteur), la rencontre de chasse (`farming.encounter_id`) (définition + niveau), l'instantané des statistiques dérivées du groupe et de ses sorts, runes et tactiques au moment de la sauvegarde, et la table de butin. Le calcul ne fait tourner **aucun tick**.

```
Δ = now − last_save
si Δ < 0           → gains nuls, last_save inchangé, mention « horloge »
si Δ < OFFLINE_MIN_S → pas de résumé
Δ_eff = min(Δ, OFFLINE_CAP_S)
éligible = rencontre.offline_eligible ∧ déjà vaincue ∧ type == normal
```

### 20.2 Rotation analytique (`ROT`)

```
taux_s   = 1 / recharge_eff_s                              pour chaque actif lancé
S        = Σ coût_eff_s × taux_s                          (Barrière comprise)
I        = mana_regen + AUTO_MANA_RESTORE / intervalle_eff
r        = min(1, I / S)
ROT      = coeff_auto / intervalle_eff
         + Σ_dégâts coeff_s × coups_s × rank_mult_s × (1 + bonus_s) × (1 + echo_s × 0.5) × taux_s × r
         + coeff_ult_total / (ULT_CHARGE_MAX / charge_par_s + canalisation_ult)
charge_par_s = ULT_CHARGE_PER_AUTO / intervalle_eff + ULT_CHARGE_PER_ACTIVE × Σ taux_s × r
```

Mana voilé est ignoré (hypothèse prudente). L'affinité de chaque ennemi est la moyenne des affinités, pondérée par la part de dégâts de chaque élément dans `ROT`.

### 20.3 Durée de cycle, survie, gains

```
DPS        = power × ROT × crit_factor × OFFLINE_DPS_CALIBRATION
clear_time = clamp(Σ PV_effectifs_i / DPS + ENGAGE_S, CLEAR_TIME_MIN_S, ∞)
cycle      = clear_time + ENCOUNTER_RESPAWN_S

subi       = Σ_i power_i × coeff_par_s_i × mitigation_i(def du groupe) × OFFLINE_INCOMING_ALIVE_FACTOR
réserve    = max_hp + bouclier × (clear_time / recharge_barrière_eff + 1)
survit     = réserve / subi ≥ OFFLINE_SAFETY_FACTOR × clear_time      (sinon gains nuls + explication)

N          = Δ_eff × (OFFLINE_EFFICIENCY + bonus_sablier) / cycle     (flottant)
XP         = floori(N × E[xp/rencontre] × pénalité)                   (appliquée avec le plafond de niveau)
Or         = floori(N × E[or/rencontre] × (1 + gold_find))
Matériau m = floori(N × p_m × qté_moy_m) + (rng < partie_fractionnaire ? 1 : 0)
Objets     = même règle → tirage individuel de la rareté et des affixes (≤ OFFLINE_ITEM_SAMPLE_MAX),
             on garde les meilleurs (rareté, puis ilvl) jusqu'à OFFLINE_ITEM_KEEP_MAX, le reste est recyclé
Runes      = même règle, plafond OFFLINE_RUNE_KEEP_MAX, le reste est recyclé en éclats
```

`rng` est le flux `offline`, initialisé à partir de la graine de partie, de `last_save_unix` et de `now_unix`. Les mêmes entrées donnent donc exactement le même résumé (test unitaire). La puissance est figée au départ : les niveaux gagnés pendant l'absence n'accélèrent pas le calcul.

### 20.4 Exemple chiffré

Paramètres de l'exemple :
- Fern niveau 8 : `power` 80, crit 0,08 / 1,5, 895 PV, défense 48,2. Sorts au rang 1, sans rune.
- Chasse : rencontre niveau 7, 2 lanternes et 1 loup. Absence de 10 h.

1. `Δ_eff` = min(36 000, 28 800) = 28 800 s.
2. `ROT` :
   - Attaque auto : 1/1,2 = 0,8333.
   - Sorts : (3,2/6 + 3,0/10) × 0,6964 = 0,5804.
   - Ultime : 10,8 / (100 / 2,7887 + 2) = 0,2853.
   - Total : **1,6990**.
3. DPS = 80 × 1,699 × 1,04 × 0,85 = **120,2**.
4. PV effectifs :
   - Lanternes : 2 × 418 / (104/113,6 = 0,9155) = 913,2.
   - Loup : 570 / (104/123,2 = 0,8442) = 675,2.
   - Total : 1 588,4.
5. `clear_time` = 1 588,4 / 120,2 + 2 = 15,21 s, donc `cycle` = 21,21 s.
6. Survie :
   - Dégâts subis : (2 × 10,5 + 13,75) × 0,6 = 20,85/s.
   - Réserve : 895 + 343,75 × (15,21/18 + 1) = 1 529.
   - Survie : 73,3 s ≥ 1,25 × 15,21 = 19,0. Condition remplie.
7. N = 28 800 × 0,25 / 21,21 = **339,46** rencontres.
8. Gains :

| Gain | Espérance par rencontre | Total |
|---|---|---|
| XP | 3 × 20 = 60 (écart de 1 : pas de pénalité) | 20 368 → niveau 8 → 9 (11 454 / 12 104) |
| Or | 3 × 8,8 = 26,4 | 8 962 |
| Poussière de mana | 3 × 0,15 × 1,5 = 0,675 | 229 + Bernoulli(0,14) |
| Éclat runique | 0,12 | 40 + Bernoulli(0,74) |
| Page de grimoire | 0,01 | 3 + Bernoulli(0,39) |
| Objets | 0,25 | 84 + Bernoulli(0,87) tirés ; 30 gardés ; ~55 recyclés ≈ 324 poussières (espérance 5,89 par objet ilvl 7) |
| Runes | 0,03 | 10 + Bernoulli(0,18) |

## 21. Tables de cohérence

### 21.1 Courbe de puissance

L'équipement typique est un bâton et des gants peu communs, ilvl = L, à +3, avec +6 % de puissance. Le bon équipement est épique à +8, avec +15 %.

| L | `power` de base | `power` typique | `power` bon | PV typiques | Multiplicateur de PV ennemi | Rencontre normale typique |
|---|---|---|---|---|---|---|
| 1 | 30 | 42,8 | 52 | 530 | 1,00 | 16,8 s |
| 5 | 48 | 68,6 | 84 | 719 | 1,60 | 16,8 s |
| 10 | 70,5 | 100,6 | 124 | 1 021 | 2,35 | 16,8 s |
| 15 | 93 | 132,7 | 164 | 1 302 | 3,10 | 16,8 s |
| 20 | 115,5 | 164,8 | 204 | 1 566 | 3,85 | 16,8 s (bon : ~13,6 s) |

Rapport `power` typique niveau 20 / niveau 1 = 3,85, égal à la croissance des PV ennemis. Le bon équipement accélère d'environ 20 %, et c'est ce qui récompense le butin.

### 21.2 Temps pour monter de niveau

Base : chasse au même niveau, 145 rencontres/h (cycle de 24,8 s). Les quêtes ajoutent ~30 % d'XP jusqu'au niveau 12.

| Atteindre | Rencontres cumulées | Heures de chasse seule | Estimation réelle (quêtes + 1 nuit hors ligne par jour) |
|---|---|---|---|
| L5 | 64 | 0,44 | 1re session (~30 min) |
| L10 | 605 | 4,2 | Fin du jour 1 ou jour 2 (donjon accessible) |
| L12 | 1 052 | 7,3 | Jour 2-3 (boss) |
| L15 | 2 039 | 14,1 | Jour 4-5 |
| L20 | 4 686 | 32,3 | ~2 semaines en jeu léger |

Gain par nuit de 8 h (équivalent à 2 h de chasse avec `OFFLINE_EFFICIENCY = 0,25`) : ~+1 niveau vers L8, ~+0,6 niveau vers L15. La colonne « estimation réelle » ci-dessus a été établie avec 0,40 : le banc (§22) doit la recaler ; si L20 dépasse nettement 2 semaines, compenser par l'XP des quêtes plutôt que par le hors ligne. **Point à surveiller** en test (T6) : voir §22.

### 21.3 Économie de l'or (ordre de grandeur sur la tranche)

| Poste | Or |
|---|---|
| Revenu : ~4 700 rencontres × ~38 or (niveau moyen 12) | ~180 000 |
| Revenu : quêtes, contrats, hors ligne déjà compté dans les rencontres | ~20 000 |
| Dépense : 6 objets de +0 à +8 (ilvl ~10) | ~24 000 |
| Dépense : rangs de sorts (4 × 7 500) | 30 000 |
| Dépense : 2 artefacts au niveau 5 | 30 000 |
| Dépense : fusion (2-3 runes P5, plusieurs P3-P4) | 40 000-60 000 |
| Dépense : consommables, réaméliorations après de nouveaux objets | 30 000+ |

Les puits absorbent 85 à 100 % des revenus. Il ne doit pas y avoir d'or « inutile » avant le niveau 18.

## 22. Méthode de test de l'équilibrage

### 22.1 Banc de simulation (tests GDScript sans interface)

- Le module de combat tourne seul, sans rendu, à pleine vitesse. Pour chaque rencontre et chaque profil : **200 graines**.
- **Profils d'équipement** : nu, typique, bon (§21.1), et malchanceux (tous les tirages au 10e centile).
- **Profils de joueur** :
  - `idle` : tactiques par défaut, aucune action manuelle.
  - `script_optimal` : un script interrompt, bouclie le Sceau et focalise les lanternes.
  - `confus` : rune de feu contre les lanternes, Barrière en manuel jamais lancée.
- **Mesures** : taux de victoire, durée p50 et p90, PV restants, temps passé sans mana, part de dégâts par sort, interruptions réussies.

| Cible | Seuil |
|---|---|
| Normale, `idle`, typique, même niveau | victoire ≥ 95 %, durée p50 15-30 s |
| Normale, `idle`, malchanceux, même niveau | victoire ≥ 85 % |
| Élite, `idle` / `script_optimal`, typique | 30-60 % / ≥ 90 % |
| Boss, `idle` / `script_optimal`, typique niveau 11 | ≤ 20 % / ≥ 80 %, durée p50 150-210 s |
| Boss, `confus` | ≤ 10 % (la défaite doit enseigner quelque chose) |
| Hors ligne : `clear_time` analytique vs p50 simulé | écart ≤ 15 % sur chaque rencontre éligible. Sinon, recalibrer `OFFLINE_DPS_CALIBRATION` |
| Déterminisme | même graine + mêmes entrées ⇒ même hachage du journal d'événements |

### 22.2 Stratégies dominantes à chercher

| Suspect | Test | Réponse prévue |
|---|---|---|
| Économie + Écho sur tous les sorts : mana infinie | Simuler `r` avec des runes P5 ; temps sans mana = 0 et DPS > +35 % | Plafond de réduction de coût total à 0,4 (`MANA_COST_REDUCTION_CAP`) |
| Puissance qui écrase Écho et Acuité | Comparer le DPS par rune au palier égal avec +50 % de bonus déjà présent | Écart ≤ 10 % entre les modificateurs offensifs |
| Chasser la rencontre la plus faible hors ligne | XP/h hors ligne par rencontre éligible ; le maximum doit être au niveau du joueur ±2 | Pénalité d'XP (§12) |
| Sablier toujours équipé | Comparer l'or et l'XP par jour avec le Sablier et avec la Cloche, pour 1 h active par jour | Le Sablier ne doit pas gagner pour un joueur actif plus de 2 h par jour |
| Accumulation de `gold_find` | Or/h avec le maximum de `gold_find` | Plafond 1,0 ; il coûte des emplacements d'affixe offensifs |
| Rechargement pour l'amélioration | Recharger avant une tentative | Graine par objet et par tentative (§15) |
| Ultime gardé entre les rencontres pour le boss | Charge pleine en entrant contre le boss | Voulu : c'est un choix tactique, pas un abus |
| Rangée avant meilleure en solo | DPS et survie de Fern à l'avant et à l'arrière | Arrière meilleur pour un lanceur, avant utile seulement pour la charge d'ultime |

### 22.3 Cas limites (passe de réglage)

Pour chacun, noter le résultat et la règle à changer si besoin :
- Joueur au skill minimal (`idle`), expert (`script_optimal`), malchanceux, optimisateur (meilleure rune P5 partout), joueur qui comprend mal (`confus`).
- Fern niveau 20 dans la rencontre niveau 1 : pas de division par zéro, `clear_time` borné à `CLEAR_TIME_MIN_S`.
- Fern niveau 1 contre le boss : enrage atteint, aucune erreur.
- Hors ligne pendant exactement 0 s, 59 s, 8 h, 8 h + 1 s et −1 h.
- Inventaire plein avant le retour hors ligne.

### 22.4 Télémétrie locale (debug uniquement, aucun serveur)

Journal local optionnel, exportable : durée par rencontre, défaites (cause : dernier coup subi), temps sans mana, utilisation des sorts, runes serties, gains hors ligne. Il sert pendant les tests de jeu à confirmer ou réfuter les `[H]`.
