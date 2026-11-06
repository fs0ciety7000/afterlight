# Ennemis du jalon 3 et test A/B Tripo / Meshy (2026-11-06)

Aucune image de l'œuvre ni aucune image envoyée par l'utilisateur n'a servi d'entrée. Les seules références de
style sont nos images `art/concepts/directions/A_world.jpg` et `B_combat.jpg`. Morvaine est un personnage
**original** (fiche écrite ci-dessous), pas un personnage canon.

## Incident : crédit fal épuisé

Après 3 appels réussis, le compte fal a été verrouillé : `HTTP 403 "User is locked. Reason: Exhausted balance"`.
Toutes les générations suivantes ont échoué au téléversement des images, avant l'envoi de la tâche (rien n'a été
facturé). Conséquences :

- le A/B **végétation** est complet (Meshy et Tripo sur la même image) ;
- le A/B **créatures** (loup des brumes, Meshy multi-image contre Tripo multivue) n'a pas pu tourner. Concept,
  vues et découpes sont prêts : `tools/fal/enemies.sh ab-wolf-meshy` puis `ab-wolf-tripo` (≈ 1,6 USD) ;
- les **4 ennemis** ont été construits de façon procédurale dans Blender (`tools/blender/build_enemies.py`).
  Ils respectent tout le contrat du jeu (échelle, base à y = 0, regard -Z, aplats, clips) et pourront être
  remplacés par des modèles générés sans changer le code.

## A/B végétation : bouleau principal (`birch_a`), même image

Image d'entrée : notre découpe `art/source/env/cut/birch_a.png` (planche `sheet2_nature`). Côté Meshy, la sortie du
kit d'environnement (même endpoint, même image, `art/source/env/raw/birch_a`) a été réutilisée ; côté Tripo, un appel
neuf. Les deux résultats de `birch_b` et du buisson, faits plus tôt avec les deux outils sur la même image, sont ajoutés.

| | Meshy v7.1 image-to-3d | Tripo H3.1 image-to-3d |
|---|---|---|
| Paramètres | `enable_pbr=false`, `topology=triangle`, `target_polycount=8000`, `symmetry_mode=auto` | `pbr=false`, `texture_quality=detailed`, `geometry_quality=standard`, `face_limit=8000` |
| birch_a : triangles / GLB / texture / durée | 8 381 / 2,46 Mo / 2K / 166 s | 7 686 / 1,41 Mo / 4K / 127 s |
| birch_b | 8 334 / 2,92 Mo / 88 s : **plat comme une feuille** de profil | 7 804 / 1,83 Mo / 198 s : profondeur ≈ 45 % de la largeur |
| Buisson | 5 203 / 2,58 Mo / 166 s : plat | 7 442 / 1,60 Mo / 256 s : volumineux |
| Texture | fidèle au concept : écorce blanche à marques noires, taches de feuilles peintes | plus terne et boueuse, écorce brune (bouleau perdu), 4K inutile pour le web |
| Orientation | face au concept | tournée de 90° |
| Coût catalogue | ≈ 1,20 USD (avec texture) | ≈ 0,40 USD |

Images : `ab_birch_turnaround.jpg` (Blender, face / profil / dos / 3/4 haut, Meshy puis Tripo, birch_a puis birch_b) et
`ab_birch_game.jpg` (Godot, caméra 50°, shaders du projet : Meshy brut, Tripo brut, nouveau bouleau à cartes).

## Verdict par classe d'asset

| Classe | Verdict | Raison |
|---|---|---|
| **Végétation** | **Ni l'un ni l'autre tel quel.** Le maillage généré ne sert qu'au tronc et au volume ; le feuillage devient des cartes peintes (`tools/blender/build_foliage.py`). Tripo pour les formes clairsemées (plusieurs troncs, buissons : Meshy les aplatit), Meshy quand l'écorce compte (tronc unique) | Les deux outils rendent des masses lisses « en pâte à modeler », exactement ce que la revue du propriétaire reproche. Tripo coûte 3 fois moins et garde le volume ; Meshy garde la texture |
| **Créatures** | **Non tranché** (test bloqué par le crédit). À lancer : `enemies.sh ab-wolf-meshy` et `ab-wolf-tripo` | Ni Meshy ni Tripo ne rigge un quadrupède sur fal (le rig Meshy est humanoïde, aucun endpoint de rig Tripo sur fal) : le squelette et les cycles du loup se font de toute façon dans Blender (`build_enemies.py`) |
| **Humanoïdes** | **Meshy** (multi-image + `rigging/multi-animation`) | Pipeline Fern v1 éprouvé (dos propre, squelette et clips en 2 appels). Tripo n'a pas de rig sur fal, il faudrait rigger dans Blender |

## Ennemis livrés (procéduraux, Blender 5.2)

`blender -b --factory-startup -P tools/blender/build_enemies.py -- [ids]`, ou `tools/fal/enemies.sh build|qa|shots`.
Chaque ennemi : un seul maillage, un matériau, une texture palette WebP 1K (une case par couleur, filtrage au plus
proche : aplats purs, aucune ombre cuite), squelette, clips à 24 i/s exportés en pistes NLA, regard glTF -Z,
base à y = 0. Sources : `<id>.blend`, `<id>_palette.png`.

| ID | Fichier | Triangles | GLB | Os | Taille (l × L × h) | Clips (s) |
|---|---|---|---|---|---|---|
| `mist_wolf` | `assets/models/enemies/mist_wolf/mist_wolf.glb` | 5 916 | 345 Ko | 19 | 0,72 × 2,19 × 1,37 m (garrot ≈ 0,95 m, oreilles 1,37 m) | idle 2,0 (boucle), run 0,67 (boucle), attack 1,21, cast 1,96 (hurlement), hit 0,54, death 1,21 |
| `mist_wolf_alpha` | même modèle | | | | ×1,3 + teinte `albedo_tint` (0,62 ; 0,64 ; 0,74) | idem |
| `wandering_lantern` | `.../wandering_lantern/wandering_lantern.glb` | 1 612 | 98 Ko | 3 | 0,54 × 0,60 × 1,75 m (pointe de la flamme à 0) | idle 2,0 (boucle, flottement), run 0,46, attack 1,04, cast 1,96 (Embrasement : montée, rotation, pulsation), hit 0,46, death 1,21 |
| `stone_sentinel` | `.../stone_sentinel/stone_sentinel.glb` | 1 320 | 257 Ko | 12 | 1,92 × 0,76 × 2,21 m | idle 2,5 (boucle), run 1,0 (marche lourde), attack 2,29 (Fracas : armé 0,7 s, frappe, reprise), cast 1,96 (garde), hit 0,62, death 1,38 |
| `morvaine` | `.../morvaine/morvaine.glb` | 18 500 | 749 Ko | 17 | 1,09 × 1,18 × 1,95 m (cornes comprises) | idle 2,5 (boucle, tissage), run 0,71 (glisse), attack 1,38 (Trait de cendre), cast 2,21, hit 0,62, death 1,79, **phase** 1,62 |

Lisibilité à 50° (`shot_*_11m.jpg`, `shot_*_6m.jpg`) : loup = crinière en pointes et queue claire ; alpha plus gros et
plus sombre ; lanterne = toit noir et verre chaud ; sentinelle = masse carrée, épaules moussues, runes bleu pâle (la
couleur de la barrière arcane) ; Morvaine = cornes, visage et mains pâles sur robe sombre, anneau de braise à l'ourlet.
Les télégraphes de l'attaque de la sentinelle (bras levés 0,7 s) et du bond du loup (recul 0,3 s) sont lisibles dans le clip lui-même.

### Fiche de Morvaine (création originale, texte seul)

Démone grande et mince (1,9 m), peau gris cendre légèrement lavande, yeux or pâle, deux cornes sombres qui partent
des tempes vers l'arrière, pointes braise. Longs cheveux charbon jusqu'aux hanches, deux mèches devant. Robe longue
à col montant, cendre sombre, coutures et ourlet braise comme un tissu qui couve, manches évasées. Trois fils de
braise tournent autour de son avant-bras droit : elle tisse la cendre en liens. Pas de jambes visibles : elle glisse.

## Contrôle qualité

- Blender : `qa_<id>_turnaround.jpg` (face, profil, dos, 3/4 haut), `qa_<id>_poses.jpg` (6 images par clip).
- Godot : `game/world/prototype/enemy_preview.tscn` (clairière du Bois des Murmures, toon + contour, caméra de jeu
  50° / 11 m ; touches Espace / 1-7 pour les clips, Z pour 6 m) ; `-- --shots` écrit `shot_<clip>_11m.jpg` et `_6m.jpg`.
- `game/world/prototype/ab_preview.tscn` : n'importe quels GLB côte à côte à la caméra de jeu (`--models=...`).

## Appels fal et coût

| Endpoint | Nom | Résultat | Coût estimé |
|---|---|---|---|
| `fal-ai/nano-banana-pro/edit` | `mist_wolf_concept` (profil, refs A_world + B_combat) | OK | 0,15 |
| `fal-ai/nano-banana-pro/edit` | `mist_wolf_views` (face + dos depuis notre concept) | OK | 0,15 |
| `tripo3d/h3.1/image-to-3d` | `birch_a_tripo` | OK | 0,40 |
| `meshy/v7.1/multi-image-to-3d`, `tripo3d/h3.1/multiview-to-3d` | `mist_wolf_meshy`, `mist_wolf_tripo` (3 tentatives) | refusés au téléversement (crédit épuisé), non facturés | 0 |
| **Total** | **3 appels facturés** sur 45 | | **≈ 0,70 USD** |

Journal : `fal_log.json` (aussi `art/source/env/fal_log.json` pour le bouleau). Sorties brutes ignorées par git
(`raw/`, `*_meshy_*`, `*_tripo_*`, `*_rig_*`).

## Verdict honnête et suite

- Les ennemis procéduraux sont des **remplaçants jouables**, lisibles et légers (tous sous les budgets), mais loin
  du rendu « AFK Journey » visé : formes de jouet, pas de visage sculpté pour Morvaine, pas de fourrure peinte.
  Ils débloquent le combat du jalon 3 ; la qualité finale demande les générations fal.
- Triangles **sous** les fourchettes de DESIGN.md (8-15 k ennemis, 25-40 k boss) : ce sont des plafonds, pas un objectif.
- Dès que le crédit fal est rechargé : `enemies.sh ab-wolf-meshy`, `ab-wolf-tripo`, comparer, puis pour la
  sentinelle et Morvaine le pipeline Fern v1 (concept → vues → Meshy multi-image → rig humanoïde Meshy), le loup
  restant riggé dans Blender (les os et clips de `build_enemies.py` se recalent sur un nouveau maillage).
- Le clip `death` de Morvaine aplatit la robe en disque (« elle retombe en cendre ») : à valider en combat.

## Lot généré du 2026-11-06 (crédit rechargé, plafond 5 USD)

Budget et journal : `BUDGET.md` (3,22 USD, 6 appels) et `fal_log.json`. Chaîne complète : `tools/fal/enemies.sh`
(`gen-*` pour fal, puis `cutout-gen`, `albedo`, `build-gen`, `qa`, `shots`, `compare`).

| ID | Source | Triangles | GLB | Os | Taille (l × L × h) | Clips |
|---|---|---|---|---|---|---|
| `mist_wolf` | Tripo H3.1 multiview (4 vues existantes) | 14 410 | 740 Ko | 19 (squelette procédural recalé) | 0,54 × 1,89 × 1,32 m | idle, run, attack, cast, hit, death (clips procéduraux inchangés) |
| `stone_sentinel` | concept nano-banana-pro + Tripo H3.1 image-to-3d | 14 000 | 765 Ko | 12 (idem) | 2,05 × 0,97 × 2,20 m | idem ; attack = Fracas, bras levés à 0,67 s, frappe à 1,2 s |
| `morvaine` | planche 3 vues nano-banana-pro + Meshy v7.1 multi-image + rig Meshy 6 clips | 27 999 | 2,03 Mo | 63 (24 Meshy + 24 jupe + 15 cheveux) | 1,9 m | idle (Idle_3, 5 s), run (Walking_Woman), attack (Charged_Spell_Cast), cast (mage_soell_cast), hit (Hit_Reaction, recul ramené à 15 %), death (dying_backwards) |
| `wandering_lantern` | procédural, inchangé | 1 612 | 98 Ko | 3 | | |

- Loup et sentinelle : le maillage généré remplace les pièces procédurales dans `build_enemies.py` (méthodes `Kit`
  remplacées par `tools/blender/build_enemies_gen.py`) ; les articulations sont recalées sur le maillage, poids par
  chaleur (bone heat), puis les mêmes clips clés s'appliquent. L'alpha reste le loup ×1,3 teinté.
- Morvaine : `build_character_v1.py` (pipeline Fern) avec `--class-mode robe` (robe = « robe blanche » de Fern :
  chaînes de jupe, jamais pilotées par les jambes), `--in-place` (recul de hit, attack, cast, death réduit) et
  `--no-staff`. `fern_import.gd` est déclaré comme script d'import (ressorts cheveux et robe). Le clip `phase` du
  remplaçant n'existe plus (aucun code de jeu ne le joue) ; `enemy_preview` ne le propose plus.
- Albédos : `flatten_albedo.py`, puis `tools/fal/tune_albedo.py` (loup éclairci ×1,12 ; runes et visière de la
  sentinelle ramenées à `#a9e4ff` et élargies ; robe de Morvaine assombrie ×0,7 pour se détacher de l'herbe).

Comparaison : `compare_placeholder_vs_generated.jpg` (Godot, même scène, même caméra ; `placeholder_shot_*` et
`placeholder_qa_*` = anciens remplaçants). Nouvelles vues : `qa_<id>_*.jpg`, `shot_*_11m.jpg`, `shot_*_6m.jpg`,
`shot_*_6m_right.jpg` (sentinelle et Morvaine à 6 m).
