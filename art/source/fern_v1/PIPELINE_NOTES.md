# Fern v1 : refonte du personnage jouable (2026-11-06)

Fern est décrite en texte uniquement. Aucune image de l'œuvre ni aucune image envoyée par
l'utilisateur n'a servi d'entrée. Les seules références de style sont nos images
`art/concepts/directions/A_world.jpg` et `B_combat.jpg`. Les vues de profil et de dos ont été
générées à partir de notre propre concept de face.

## Verdict court

v1 est **nettement meilleure que v0** et remplace `assets/models/characters/fern/fern.glb`. Comparaison à la
même caméra : `compare_v0_v1.jpg`.

| Cible | v0 | v1 |
|---|---|---|
| Texture en aplats | ombres cuites, aspect plastique | aplats par matière (k-means), yeux, bouche et boutons préservés |
| Robe qui se déchire à la marche | oui, entre les cuisses | non : 8 chaînes de jupe sous `Hips`, sans poids de cuisse, avec suivi des jambes précalculé |
| Cheveux, manteau, jupe mobiles | bloc rigide | 5 chaînes de cheveux et 8 de jupe, `SpringBoneSimulator3D` ajouté à l'import |
| Visage lisible à 50° | frange sur les yeux | frange courte, tête relevée de 10° dans tous les clips, normales du visage sphériques |
| Mains | grandes et pâles | plus petites (réduites de 12 %), peau un peu plus chaude |
| Dos (vue la plus fréquente) | masse violette | cheveux longs et nets (concept multi-vues) |
| Bâton | absent | bâton en bois, poignée violette, os `Staff` dans la main droite, qui reste droit à la marche |
| Poids web | 4,2 Mo, JPEG 2K | **1,88 Mo**, WebP 1K (140 Ko) |
| Clips | idle, walk, run, cast | idem, plus hit, death et victory ; cast actif dès 0,3 s |

Ce qui reste en dessous de la cible « AFK Journey » est listé à la fin (§ Problèmes restants).

## Étapes et paramètres

Toutes les commandes sont dans `tools/fal/fern_v1.sh` (une sous-commande par étape ;
`all-local` relance tout ce qui ne coûte rien).

| # | Étape | Outil / endpoint | Paramètres clés | Durée |
|---|---|---|---|---|
| 1 | Concept de face, A-pose, **aplats sans ombres**, frange courte, 6,5 têtes | `fal-ai/nano-banana-pro/edit` | refs de style A_world + B_combat, `2:3`, `2K`, `prompt_concept_front.txt` | 27 s |
| 2 | Profil et dos du même personnage | `fal-ai/nano-banana-pro/edit` | seule entrée : notre concept de face, `4:3`, `2K`, `prompt_concept_views.txt` | 25 s |
| 3 | Détourage des 3 vues | local : `tools/fal/cutout_views.py` (remplissage depuis les bords sur le gris uni) | même hauteur de personnage sur les 3 vues | 2 s |
| 4 | Image vers 3D, multi-vues | `meshy/v7.1/multi-image-to-3d` | `image_urls`=[face, profil, dos], `pose_mode=a-pose`, `enable_pbr=false`, `target_polycount=30000`, `topology=triangle`, `texture_prompt` « flat unshaded base colors… » | 154 s |
| 5 | Rig et clips | `fal-ai/meshy/rigging/multi-animation` | `animation_action_ids=[0,1,14,125,129,130,131,178,189,59]`, `height_meters=1.6` | 113 s |
| 6 | Idle plus calme | `fal-ai/meshy/rigging/multi-animation` | `[11,12,243,244,245,246]`, Idle_3 (243) retenu | 91 s |
| 7 | Aplatir l'albédo | `tools/blender/flatten_albedo.py` | k = 9, filtre de mode 3×3, détails nets (Sobel > 1,6) conservés, manteau `#37323b`, blanc ≤ 0,93, peau ×(1, 0,95, 0,9), 1024² | 3 s |
| 8 | Assemblage | Blender 5.2, `tools/blender/build_character_v1.py` | voir détail ci-dessous | 12 s |
| 9 | QA Blender | `render_turnaround.py`, `render_pose_strip.py`, `compose_sheet.py`, `compose_strip.py` | `qa_turnaround.jpg`, `qa_poses.jpg` | 15 s |
| 10 | Rendu Godot | `fern_preview.tscn -- --shots`, sous xvfb, `--rendering-driver opengl3` | `shot_*.jpg` ; `--no-springs` pour un A/B | 15 s |
| 11 | Comparaison | `tools/fal/compare_shots.py` | `compare_v0_v1.jpg` | 1 s |

Correspondance des sorties de rigging (`fern_v1_rig_*`) : `_0` rig ; `_8` Idle ; `_10` Walking_Woman ;
`_12` Run_02 ; `_14` Charged_Spell_Cast ; `_16` mage_soell_cast (**cast** retenu) ; `_18`/`_20`
mage_soell_cast_1/_2 ; `_22` Hit_Reaction ; `_24` dying_backwards ; `_26` Victory_Cheer.
`fern_v1_rig_idle_*` : `_8` Idle_02, `_10` Idle_03, `_12` Idle_3 (**idle** retenu), `_14` Idle_4,
`_16` Idle_5, `_18` Idle_6. Les rigs des deux appels ont les mêmes os, avec un écart de repos de 1,5 cm au plus.

### Détail de `build_character_v1.py`

1. Import du rig et des clips (rognage `name=path:first:last`), sans piste NLA parasite ni « Icosphere ».
2. **Soudure des sommets dupliqués aux coutures UV** (18 268 sommets ; les UV sont stockées par coin et survivent).
   Sans cette soudure, la classification et les poids différaient d'un côté à l'autre des coutures, et la surface se froissait en éclats.
3. Décimation (collapse) à 22 000 triangles ; mains réduites de 12 % vers le poignet.
4. Albédo aplati, 1K, exporté en WebP q88.
5. Classes de sommets par couleur d'albédo : cheveux, peau, blanc, noir.
6. Os secondaires :
   - `SKIRT_0..7_1..3` sous `Hips`. Ils couvrent tout le maillage sous la taille (manteau et robe), sauf bottes et semelles :
     distance 3D à la jambe inférieure < 9 cm, ou z sous l'ourlet. Interpolation angulaire entre chaînes et en hauteur
     entre segments, fondu avec les poids d'origine sur 16 cm autour de la taille, poids de jambes reportés sur `Hips`.
     Les faces qui relient la jupe aux bottes sont supprimées (132) ; le trou est caché par l'ourlet.
   - `HAIR_BL/BC/BR/FL/FR_1..3` sous `Spine` (la poitrine, pas la tête) : un hochement ne fait plus entrer les cheveux dans le dos.
   - `Staff` sous `RightHand`, à la poignée.
   - Lissage laplacien des nouveaux poids, puis 4 influences au plus.
7. Pour chaque clip : `SKIRT_*_1` est clé à chaque image, de sorte que l'ourlet couvre la jambe qui avance
   (poussée = jambe la plus avancée dans la direction de la chaîne, ×1,05 ; balancement latéral ×0,7 ; 32 cm au plus).
   Le `Staff` pivote dans la paume vers la verticale, avec un poids par clip :
   idle 1, walk 0,85, run 0,8, hit 0,6, cast 0,35, death et victory 0.
   La tête est relevée de 10° dans le repère de l'os `Head`, en modifiant les clés existantes : des clés aux images
   entières entre les clés fractionnaires feraient trembler la tête.
8. Boucles idle, walk et run : les 4 dernières clés sont fondues vers la première.
9. Normales du visage tirées à 75 % vers une sphère de tête.
10. Rotation de 180° appliquée au repos (face vers glTF -Z), pieds à y = 0, export GLB (NLA_TRACKS, WebP, 4 influences, animation optimisée).

### Import Godot

`assets/models/characters/fern/fern_import.gd` est le script de post-import déclaré dans `fern.glb.import`.
Il ajoute `SpringBones` (`SpringBoneSimulator3D`) sous le `Skeleton3D` : 5 chaînes de cheveux
(raideur 3,5, amortissement 0,7, sans gravité) et 8 chaînes de jupe sur les os `_2`/`_3`, puisque `_1` est animé
(raideur 4, amortissement 0,8, gravité 0,15). Deux sphères de collision aux genoux ne concernent que la jupe.
Tout utilisateur de `fern.glb` reçoit ces réglages. Le nœud `Staff` (MeshInstance3D) peut être masqué.

Pièges rencontrés :

- **Unités** : l'armature Meshy porte une échelle de 0,01, donc l'espace des os est en centimètres. Le script
  divise rayons, longueur de queue, gravité et colliders par cette échelle. Sans cette correction, les cheveux
  partaient de côté.
- Les sphères de collision sur la colonne repoussaient les mèches avant sur le côté. Elles ont été retirées pour les cheveux.
- Avec une raideur faible (1 à 2), les queues de manteau et les mèches flottaient trop et faisaient des pointes.
  À partir de 3,5, le mouvement secondaire reste discret et propre.
- Après une rotation brusque du personnage (téléportation, prévisualisation), appeler `SpringBoneSimulator3D.reset()`.
  La prévisualisation le fait (touches Q/E et captures).
- Godot 4.7.2 n'importe ni `EXT_meshopt_compression` ni `KHR_mesh_quantization` (absents du binaire).
  Seul `EXT_texture_webp` est pris en charge. Le GLB n'est donc pas compressé meshopt ; le poids vient de la décimation, du WebP 1K et de l'animation optimisée.

## Appels fal et coût

| Endpoint | Appels | Prix catalogue (estimé) | Coût |
|---|---|---|---|
| nano-banana-pro/edit | 2 | 0,15 USD par image | 0,30 |
| meshy v7.1 multi-image-to-3d (texturé) | 1 | ~0,80 + 0,40 pour la texture | ~1,20 |
| meshy rigging multi-animation (10 clips) | 1 | 0,20 + 0,12 × 10 | 1,40 |
| meshy rigging multi-animation (6 idles) | 1 | 0,20 + 0,12 × 6 | 0,92 |
| **Total** | **5** sur un budget de 20 | | **≈ 3,8 USD** |

Le détourage est fait en local : le fond gris est uni, donc birefnet n'a pas été appelé. Hunyuan 3D Pro et Tripo
n'ont pas été essayés, car le dos de Meshy multi-vues est propre dès le premier essai (voir `qa_turnaround.jpg`).
Temps de génération total : environ 7 minutes.

## Mesures

| Élément | Valeur |
|---|---|
| Triangles | 30 464 (Meshy), puis 22 000 après décimation et **21 868** pour le corps après la découpe jupe et bottes ; bâton : 180 |
| Os | 64 : 24 Meshy, 24 de jupe, 15 de cheveux, 1 pour le bâton |
| Hauteur | 1,60 m, pieds à 0, regard vers -Z (vérifié avec l'os `headfront`) |
| Proportions | environ 6,6 têtes |
| Clips (24 i/s) | idle 5,0 s (boucle), walk 1,0 s (boucle), run 0,71 s (boucle), cast 2,29 s, hit 1,67 s, death 2,21 s, victory 4,1 s |
| `fern.glb` | **1 882 084 octets**, dont la texture WebP 1024² (environ 140 Ko). Godot l'extrait dans `fern_fern_albedo.webp` |
| Sources commitables | concepts PNG (2 × 3,8 Mo), découpes (3 × environ 0,8 Mo), `fern_albedo.png` (0,86 Mo), `fern_v1.blend` (2,5 Mo), prompts, QA, captures |
| Sources ignorées | `fern_v1_meshy_*`, `fern_v1_rig_*.glb`, `fern_v1_rig_idle_*.glb` (environ 130 Mo, régénérables depuis `fal_log.json`) |

## Fichiers

| Catégorie | Fichiers |
|---|---|
| Concepts | `fern_v1_concept_front.png`, `fern_v1_concept_views.png`, `fern_v1_{front,side,back}_cut.png`, `prompt_concept_front.txt`, `prompt_concept_views.txt` |
| Texture | `fern_albedo.png` (aplatie, 1K) |
| Blender | `fern_v1.blend` (scène assemblée, avant la rotation finale) |
| QA | `qa_turnaround.jpg` (repos), `qa_poses.jpg` (walk, run, cast, hit, death, victory, sans ressorts) |
| Godot | `shot_day_idle_34.jpg`, `shot_day_closeup.jpg`, `shot_day_walk.jpg`, `shot_day_walk_back.jpg`, `shot_day_run_back.jpg`, `shot_day_cast.jpg`, `shot_night_cast.jpg`, `shot_night_closeup.jpg` |
| Comparaison | `compare_v0_v1.jpg` (v0 à gauche, v1 à droite ; même scène, même caméra) |
| Jeu | `assets/models/characters/fern/fern.glb`, `fern_import.gd`, `fern.glb.import` (script d'import) |
| Outils | `tools/fal/fern_v1.sh`, `tools/fal/cutout_views.py`, `tools/fal/compare_shots.py`, `tools/blender/build_character_v1.py`, `flatten_albedo.py`, `render_pose_strip.py`, `compose_strip.py` ; `render_turnaround.py` corrigé (ne supprime plus un maillage non riggé) |
| Prévisualisation | `game/world/prototype/fern_preview.gd` : touches 5 à 7 (hit, death, victory), S (bâton), `--shots-dir=`, `--no-springs`, idle et marche filmés en lecture réelle |

## Problèmes restants (prochaines améliorations)

1. **Course vue de dos** : au coup de pied arrière, la botte pousse encore le manteau et quelques pointes
   sombres apparaissent sur le côté. Pistes : capsules de collision de jambe pour `SKIRT_*_2/3`, poussée plafonnée plus haut pour run.
2. **Cast** : mage_soell_cast est un geste du bras droit, donc le bâton balaie au-dessus de la tête. Il est lisible,
   mais moins « rayon tendu » que B_combat. Pistes : clip de sort à une main gauche, ou pose du bâton pointé vers l'avant avec un poids de redressement propre au clip.
3. **Manteau** : de dos, il reste une grande masse sombre, avec quelques traces de texture violette au col et aux épaules
   (mèches qui chevauchent le col). Pistes : retouche manuelle de l'albédo du col et pan arrière avec une ligne de couture claire.
4. **Hit** : Hit_Reaction recule de quelques dizaines de centimètres (mouvement des hanches). À neutraliser si le combat exige un clip sur place.
5. **Bâton** : primitive à 10 côtés, tête en pointe. À remodeler avec une crosse plus lisible ou une gemme.
6. **Matière** : peau et visage corrects ; le blanc de la robe est encore un peu brûlé au soleil de jour (0,93).
   À ajuster avec le shader (bande d'ombre de la robe) plutôt qu'avec l'albédo.
7. Les ressorts ne sont visibles que dans Godot. La QA Blender montre le mouvement précalculé seul.
