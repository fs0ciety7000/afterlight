# Contenu du jalon 6 : bestiaire et découvertes

> Version 0.1 (2026-11-06). Spécification pour `enemies.json` (`bestiary_thresholds`), `discoveries.json`, `loot_tables.json` et `strings.csv`. Tout est `[H]`. Tous les textes sont originaux.

## 1. Bestiaire

### 1.1 Règles

| Règle | Comportement attendu (testable) |
|---|---|
| Compteur | +1 par `enemy_defeated` de cet `enemy_id`, en combat joué (normal ou « Chasser ici »). Les invocations comptent (loups du Hurlement, lanternes liées de Morvaine). **Le hors ligne ne compte pas** |
| Paliers | `bestiary_thresholds` de l'ennemi ; défaut `[1, 5, 25]` (GDD §13) |
| Élite et boss | `enemy.mist_wolf_alpha` : `[1, 3, 10]` ; `enemy.morvaine` : `[1, 2, 5]` (**nouveau** : 25 victoires contre un boss exclu du hors ligne n'arriveraient jamais) |
| Retour | Événement `bestiary_tier_unlocked {enemy_id, tier}` (couche état) → bandeau « Bestiaire : {nom}, {palier} » (`ui.bestiary.tier_1` « nouvelle fiche », `ui.bestiary.tier_2` « affinités révélées », `ui.bestiary.tier_3` « statistiques révélées ») |
| Fiche verrouillée | Silhouette noire + « ??? » + « Vaincu 0 fois ». Une fiche n'apparaît dans la liste qu'une fois l'ennemi rencontré (`encounter_started` avec lui) |
| Sauvegarde | `progress.bestiary[enemy_id] = victoires` (clé existante). Les paliers se déduisent du compteur ; rien d'autre à sauvegarder |

| Palier | Contenu affiché |
|---|---|
| 1 | Nom, rendu 3D du modèle (vue fixe), description (`.desc`, existe), récit (`.lore`), nombre de victoires |
| 2 | Affinités (4 éléments, pictogramme + mot), capacités (nom + description des `ability.*`), conseil (`.tip`) |
| 3 | Statistiques au niveau de la dernière victoire : PV, puissance, défense, barrière, intervalle d'attaque, vitesse, rayon d'aggro, XP et or moyens |

L'infobulle de l'ennemi en combat montre toujours ses affinités (GDD §8), quel que soit le palier : le bestiaire est un aide-mémoire, pas un verrou.

### 1.2 Textes par ennemi

| Ennemi | `enemy.<id>.lore` (palier 1) | `enemy.<id>.tip` (palier 2) |
|---|---|---|
| `enemy.mist_wolf` | Avant que la cloche se taise, aucun loup ne chassait dans le val. Ceux-ci arrivent avec la brume et s'y défont quand on les abat. | Faible au feu. Le Bond s'annonce par une ligne au sol : c'est le moment de la Barrière. |
| `enemy.wandering_lantern` | Une flamme qui a perdu sa mèche. Le passeur de la tourbière disait qu'elles éclairent le mauvais chemin à ceux qui s'égarent. | Faible au givre, résiste au feu. Interrompez l'Embrasement avec Zoltraak pendant l'anneau nacré. |
| `enemy.stone_sentinel` | Les gardes du guet les ont taillées pour veiller à leur place la nuit. Les gardes sont partis ; personne n'a relevé les sentinelles. | Faible à la foudre, résiste au givre. L'arcane brise sa barrière deux fois plus vite. Sortez du cercle du Fracas. |
| `enemy.mist_wolf_alpha` | Le plus vieux de la meute. Les gens d'Aubelin disent qu'il hurle à l'heure où la cloche sonnait autrefois. | Faible au feu, résiste au givre. Interrompez le Hurlement, sinon la meute revient plus rapide. |
| `enemy.morvaine` | Une démone installée dans le cloître. Elle a arrêté la cloche pour que plus personne ne monte, et elle appelait cela le calme. | Faible au givre, résiste au feu. Abattez ses lanternes, gardez la Barrière pour le Sceau de cendre. |

`enemy.morvaine` garde `canon_refs: ["lore.demons"]` ; son texte ne décrit que Morvaine, pas les démons de l'œuvre.

## 2. Découvertes

### 2.1 Règles

| Règle | Comportement attendu (testable) |
|---|---|
| Nombre | **6** découvertes comptées : 2 par terrain (Bois, Tourbière, Ruines). Aubelin (hub) n'en a pas |
| Compteur | « Découvertes n/2 » par lieu, sur la carte et dans le journal ; seules les entrées `counts_for_location: true` (défaut) comptent |
| Déclencheur (`trigger`, **nouveau**) | `zone` : entrer dans un rayon de 3 m ; `interact` : E ou appui à ≤ 2,5 m ; `interact_hold` : maintenir 1,5 s (barre circulaire) |
| Récompense | XP = `DISCOVERY_XP` (0,1) × `xp_to_next(level)` ; `level` (**nouveau**) = niveau haut du lieu (Bois 3, Tourbière 6, Ruines 9) ; plus l'objet éventuel |
| Brouillard | Chaque découverte trouvée perce le voile de la carte peinte : disque de rayon `fog_radius` (normalisé 0-1) autour de `map_pos` (**nouveaux**). Le voile se déduit de `progress.discoveries` et des lieux visités : aucun état en plus. Certaines révèlent aussi un lieu (`reveals`) |
| Retour | Bandeau « Découverte : {nom} » + XP, texte de lore dans le journal, ligne de Fern éventuelle, sauvegarde automatique |
| Boussole | Avec `artifact.traveler_compass` équipé, les découvertes comptées non trouvées du lieu courant apparaissent en « ? » sur la mini-carte et la carte |
| Une seule fois | Une découverte trouvée ne se retrouve jamais (pas de réapparition) |

### 2.2 Les 6 découvertes

| ID | Lieu | `kind` | Ancre | Comment la trouver | Ce qu'elle révèle (texte `.lore`) | Récompense | Brouillard (`map_pos`, `fog_radius`, `reveals`) |
|---|---|---|---|---|---|---|---|
| `discovery.moss_statue` | Bois | `memorial` | `discovery_01` (existe) : déplacer à ≤ 20 m du sentier, côté Aubelin | `interact_hold` « Nettoyer la mousse ». La statue est visible du sentier, couverte de mousse | Plaque : « Au héros Himmel. Le village d'Aubelin se souvient. » Fern : La mousse avait couvert le nom. Il suffisait de l'enlever. | 70 XP ; objectif de `quest.side_statue` | (0,33 ; 0,47), 0,05, aucun |
| `discovery.dead_birch_vista` | Bois | `vista` | `discovery_02` (nouvelle) : au pied du grand bouleau mort, au centre | `zone` en haut du tertre de racines ; la caméra se tourne 2 s vers le nord-est (coupée si « Réduire les animations ») | Depuis les racines du grand bouleau, on aperçoit au nord-est la tour effondrée d'un ancien guet. | 70 XP | (0,24 ; 0,36), 0,10, `location.watch_ruins` |
| `discovery.ferryman_journal` | Tourbière | `lore` | `discovery_01` : cabane du bac, au nord-ouest | `interact` sur le carnet posé sur la table | Les lueurs sont venues l'automne où la cloche s'est tue. Elles ne brûlent que ceux qui s'attardent. J'ai cessé de passer les gens le soir. | 422 XP ; objectif de `quest.main_02` | (0,66 ; 0,46), 0,05, `location.watch_ruins` |
| `discovery.pressed_flower` | Tourbière | `pickup` | `discovery_02` : îlot de l'est, derrière la patrouille de `lantern_mire_04` | `interact` sur un livre ouvert sur une pierre | Une fleur pressée entre deux pages restées blanches. Quelqu'un voulait s'en souvenir, et a oublié tout le reste. | 422 XP + `artifact.pressed_flower` niveau 1 | (0,78 ; 0,56), 0,05, aucun |
| `discovery.fallen_tower_vista` | Ruines | `vista` | `discovery_01` : sommet de l'escalier de la tour effondrée | `zone` au sommet ; la caméra se tourne 2 s vers le cloître | Du haut de la tour, le cloître apparaît, accroché à la falaise. L'aiguille de son cadran est arrêtée sur trois heures. | 1 210 XP | (0,80 ; 0,17), 0,10, `dungeon.silent_dial_cloister` (point révélé, verrouillé) |
| `discovery.watch_roll` | Ruines | `lore` | `discovery_02` : salle des gardes | `interact` sur le registre posé sur un lutrin | Dernière ligne du registre : la cloche s'est arrêtée à trois heures, une femme en gris est montée au cloître. La garde n'a pas été relevée. | 1 210 XP | (0,74 ; 0,24), 0,05, aucun |

`discovery.moss_statue` porte `canon_refs: ["character.himmel"]` (entrée canon à créer, `playable: false`). La statue, son lieu et la plaque sont originaux ; la plaque ne prête aucun acte ni aucune parole au personnage.

Révélation des lieux : le Bois ne révèle plus les Ruines à la simple visite (`location.whispering_wood.fog_reveal` vidé, **changement de données**) ; elles se révèlent par le point de vue du bouleau, le journal du passeur, ou au rendu de `main_02` (un lieu débloqué est toujours révélé). Le chemin critique (V16) ne dépend donc d'aucune découverte.

Le donjon apparaît sur la carte comme un sous-point des Ruines (`dungeon.map_pos` **nouveau**, proposé (0,86 ; 0,10)), avec les états caché / révélé / débloqué des lieux. Il est révélé par le point de vue de la tour ou au rendu de `main_03`.

### 2.3 Objets de monde non comptés (même entité `discovery`, `counts_for_location: false`)

**Coffres** (GDD §5.2 : 1 à 2 par terrain ; un par terrain + un dans le donjon). `trigger: interact`, ouverture une seule fois, table `loot.field_chest`, niveau = niveau haut du lieu.

| ID | Lieu | Ancre | `level` |
|---|---|---|---|
| `discovery.wood_chest` | Bois | `chest_01` (existe) | 3 |
| `discovery.mire_chest` | Tourbière | `chest_01` | 6 |
| `discovery.ruins_chest` | Ruines | `chest_01` | 9 |
| `discovery.cloister_chest` | Donjon, salle 4 | `room4_chest` | 11 |

`loot.field_chest` (**nouvelle**, `rarity_profile: "chest"`) : or = `CHEST_GOLD_MULT` (**nouvelle constante**, 5) × `or_ennemi(level)` ; `material.mana_dust` 100 % 3-5 ; `material.rune_shard` 100 % 1-2 ; `material.grimoire_page` 100 % 1 ; `item` 100 % 1 ; `rune` 30 % 1. Les 4 coffres donnent donc 4 pages (GAME_BALANCE §16 : « ~6 par les coffres, l'élite et le boss »).

**Herbes de brume** (`quest.side_herbalist`) : `kind: pickup`, `trigger: interact`, `available_if: {"quest_state": {"id": "quest.side_herbalist", "state": "active"}}` (ou `completed`), récompense 1 `material.mist_herb`, pas de XP, pas de brouillard. Visuel : touffe bleu pâle qui luit faiblement (particules < 10).

| ID | Lieu | Ancre | Placement |
|---|---|---|---|
| `discovery.mist_herb_wood_01` | Bois | `herb_01` | Berge du ruisseau, à l'écart du sentier |
| `discovery.mist_herb_wood_02` | Bois | `herb_02` | Entre les racines du grand bouleau |
| `discovery.mist_herb_wood_03` | Bois | `herb_03` | Clairière du fond, derrière `encounter_05` |
| `discovery.mist_herb_mire_01` | Tourbière | `herb_01` | Pilotis de l'entrée ouest |
| `discovery.mist_herb_mire_02` | Tourbière | `herb_02` | Roselière centrale, entre `encounter_02` et `encounter_03` |
| `discovery.mist_herb_mire_03` | Tourbière | `herb_03` | Chaussée nord, avant `encounter_05` |

## 3. Plan de test

| Test | Type | Attendu |
|---|---|---|
| Paliers | unitaire | 0, 1, 4, 5, 24, 25 victoires de loup → paliers 0, 1, 1, 2, 2, 3 ; alpha 3 → palier 2 ; Morvaine 2 → palier 2 |
| Invocations | unitaire | Un Hurlement non interrompu puis la victoire : +1 alpha, +2 loups |
| Hors ligne | unitaire | Un résumé hors ligne ne change pas `progress.bestiary` |
| Découverte | unitaire + E2E (6.5) | Trouver `dead_birch_vista` : +70 XP, Ruines révélées sur la carte, compteur « 1/2 », état identique après rechargement |
| Herbes | unitaire | Invisibles et non ramassables sans la quête ; ramassées une fois, elles ne reviennent pas après rechargement |
| Coffre | unitaire | Ouvert une fois ; second `interact` sans effet ; tirage reproductible avec la graine |
| Test de jeu | observation | Le joueur ouvre le bestiaire après une défaite ? Il lit le conseil du palier 2 ? Il cherche la 2e découverte d'un lieu en voyant « 1/2 » ? |
