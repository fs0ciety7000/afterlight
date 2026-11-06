# Fern : essai du pipeline personnage (2026-11-06)

Objectif : prouver qu'on obtient un personnage jouable cel-shadé, riggé et animé, pour le build web
(Godot 4.7, renderer `gl_compatibility`), de bout en bout. Fern est décrite en texte seulement.
Aucune image officielle et aucune image envoyée par l'utilisateur n'a servi d'entrée. Les seules
références de style sont nos propres images `art/concepts/directions/A_world.jpg` et `B_combat.jpg`.

## Verdict court

Le pipeline fonctionne de bout en bout : 4 appels fal, environ 2 USD, environ 4 minutes de génération.
On obtient un GLB de 22 k triangles et 4,2 Mo, avec 4 clips (idle, walk, run, cast), à l'échelle
(1,60 m, pieds à y = 0, regard vers -Z), affiché en toon et contour dans Godot Compatibility.
La qualité est **en dessous de la cible « AFK Journey »** :

- lisible et propre à distance de jeu ;
- en revanche, la surface a un aspect « plastique » : la texture contient des ombres cuites, les mains
  sont trop grandes et pâles, les cheveux sont un bloc rigide, et la robe s'étire entre les jambes
  pendant la marche ;
- les scènes de test ne contiennent qu'un sol plat. La comparaison avec les images cibles ne porte
  donc que sur le personnage.

## Étapes et paramètres retenus

| # | Étape | Endpoint / outil | Paramètres clés | Durée |
|---|---|---|---|---|
| 1 | Concept de face en A-pose | `fal-ai/nano-banana-pro/edit` | `image_urls` = A_world.jpg + B_combat.jpg (style), `aspect_ratio=2:3`, `resolution=2K`, `output_format=png`, prompt dans `prompt_concept.txt` | 27 s |
| 2 | Détourage | `fal-ai/birefnet/v2` | `model="General Use (Heavy)"`, `operating_resolution=2048x2048` | 3 s |
| 3 | Image vers 3D | `meshy/v7.1/image-to-3d` | `pose_mode=a-pose`, `should_texture=true`, `enable_pbr=false`, `target_polycount=30000`, `topology=triangle`, `symmetry_mode=auto` | 123 s |
| 4 | Rig et clips | `fal-ai/meshy/rigging/multi-animation` | `model_url` = GLB de l'étape 3, `animation_action_ids=[0,1,14,125]` (Idle, Walking_Woman, Run_02, Charged_Spell_Cast), `height_meters=1.6` | 71 s |
| 5 | Assemblage | Blender 5.2.3, `tools/blender/build_character.py` | décimation collapse à 22 000 triangles, matériau réduit à la couleur de base, rotation de 180° appliquée au repos, pieds à 0, export GLB avec `NLA_TRACKS` et JPEG q90 | ~20 s |
| 6 | QA | `tools/blender/render_turnaround.py` + `compose_sheet.py` (Workbench, texture) | `qa_turnaround.jpg`, `qa_poses.jpg` | ~10 s |
| 7 | Rendu Godot | `game/world/prototype/fern_preview.tscn` + `.gd`, `assets/shaders/toon.gdshader`, `outline.gdshader` | `xvfb-run ... godot --rendering-driver opengl3 ... -- --shots` | 9 s |

Toutes les commandes exactes sont dans `tools/fal/fern_character.sh` (une sous-commande par étape).

Correspondance des sorties de rigging (l'ordre des fichiers suit la sortie fal) :

| Fichier | Contenu |
|---|---|
| `_0` | personnage riggé |
| `_2` / `_4` | walking de base, avec ou sans maillage |
| `_5` / `_7` | running de base |
| `_8` | Idle |
| `_10` | Walking_Woman |
| `_12` | Run_02 |
| `_14` | Charged_Spell_Cast |

Les FBX, OBJ, USDZ et STL ont été supprimés après coup ; le journal les liste encore.

Identifiants d'animation : https://docs.meshy.ai/en/api/animation-library. Autres sorts possibles :
129 à 137 (`mage_soell_cast*`, sous-catégorie CastingSpell).

## Appels fal et coût

| Endpoint | Appels | Prix catalogue | Coût |
|---|---|---|---|
| nano-banana-pro/edit | 1 | 0,15 USD par image | 0,15 |
| birefnet/v2 | 1 | à la seconde de calcul (~3 s) | ~0,01 |
| meshy v7.1 image-to-3d (texturé) | 1 | 0,80 + 0,40 pour la texture | 1,20 |
| meshy rigging multi-animation | 1 | 0,20 + 0,12 × 4 clips | 0,68 |
| **Total** | **4** sur un budget de 25 | | **≈ 2,04 USD** |

Une seule variation de concept a suffi. Tripo H3.1 n'a pas été essayé, car le résultat Meshy était
correct dès le premier essai.

## Mesures

| Élément | Valeur |
|---|---|
| Triangles Meshy | 30 560 |
| Triangles après décimation | 22 000 (silhouette et visage conservés, voir qa_turnaround) |
| Squelette | 24 os, de type Mixamo (Hips, Spine, Spine01, Spine02, neck, Head, bras, jambes ; pas de doigts, pas d'os de cheveux ni de manteau) |
| Influences | Blender signale plus de 4 influences par sommet ; l'export garde les 4 plus fortes |
| Clips | idle 4,0 s ; walk 1,0 s ; run 0,7 s ; cast 2,7 s (24 i/s). Clips sur place : les hanches ne bougent que de quelques cm, aucun nettoyage du root motion n'a été nécessaire |
| `assets/models/characters/fern/fern.glb` | 4,2 Mo, dont une texture JPEG 2048² de 2,4 Mo ; Godot l'extrait dans `fern_Image_0.jpg` à l'import |
| Sources | `art/source/fern/` fait environ 55 Mo (GLB bruts de rigging d'environ 5 Mo chacun, à ne pas commiter tels quels ; voir plus bas) |

## Ce qui a mal tourné et pourquoi

1. **Orientation.** Le GLB riggé regarde vers glTF +Z. Mettre `rotation_euler` sur l'armature
   restait sans effet, parce que l'import glTF règle l'objet en `rotation_mode = QUATERNION`. Le script
   passe donc en XYZ et applique la rotation au repos (`transform_apply`). C'est vérifié avec l'os
   `headfront`.
2. **Objet « Icosphere » de 2 m.** L'importeur glTF de Blender le crée comme forme d'os. Il faussait
   les bornes et le cadrage QA. Il est supprimé avant export ; il n'était pas dans le GLB lui-même.
3. **Piste NLA parasite.** L'importeur pousse le clip `clip0` en NLA. Elle est supprimée, sinon le
   GLB contiendrait une 5e animation.
4. **Rendu headless.** Blender comme Godot ont besoin de libEGL et de Mesa. Il a fallu installer
   `apt-get install -y libegl1 libegl-mesa0 libgl1-mesa-dri libgles2` ; xvfb était déjà présent.
   Godot tourne sur llvmpipe en OpenGL 4.5, ce qui est fidèle au chemin Compatibility.
5. **Premier rendu Godot surexposé** (sol jaune, robe blanche brûlée). Avec `light()` personnalisé,
   `LIGHT_COLOR / PI` plus l'ambiance donnaient près de 2× l'albédo. Valeurs retenues pour le jour :
   soleil 0,72, ambiance 0,32 ; tonemap Linear.
6. **Qualité du modèle**, ce qui pèse le plus sur la note :
   - *ombres cuites dans la texture* : Meshy peint des plis sombres sur le manteau et la robe. Elles se
     mélangent à nos 2 bandes et salissent le cel-shading ;
   - *cheveux* : un seul maillage rigide, rattaché à la tête et à la colonne, sans os propre. Ils ne
     bougent pas et forment un bloc ; vus de dos (la vue la plus fréquente en jeu), c'est une masse
     violette ;
   - *robe et manteau longs* : peints sur les jambes. À la marche, la robe s'étire et se déchire
     entre les cuisses (visible dans qa_poses.jpg, vue de côté) ;
   - *mains* : grandes, pâles, sans doigts riggés ;
   - *frange* : elle cache les yeux à 50° de tangage. Le visage n'est lisible qu'en gros plan ;
   - *clip cast* : il commence par un long accroupissement ; le moment de lancer arrive vers 1,7 s ;
   - *proportions* : le concept fait environ 7 têtes, au lieu des 6,5 demandées ;
   - *bâton* : volontairement absent du concept, pour que le rig ne soude pas le bâton à la main.
     Il reste à faire en accessoire séparé, attaché à `RightHand` par un BoneAttachment3D.
7. **Contour** : à 1,5 px il est très fin vu de loin. Il est correct pour la direction artistique,
   mais les normales lissées de Meshy sont fragmentées aux coutures UV, et la coque peut se fendre
   aux arêtes vives. Ce n'est pas visible sur les captures.

## Fichiers produits

| Catégorie | Fichiers |
|---|---|
| Concept et détourage | `art/source/fern/fern_concept_v1.jpg`, `fern_cutout.png`, `prompt_concept.txt` |
| Sorties fal brutes | `fern_meshy_0.glb` (maillage), `fern_meshy_7.png` (texture 2K), `fern_meshy_1.png` (vignette), `fern_rig_*.glb` |
| Blender | `art/source/fern/fern.blend` (scène assemblée avant export) |
| QA | `qa_turnaround.jpg` (face, profil, dos, 3/4 haut, A-pose), `qa_poses.jpg` (marche et cast) |
| Captures Godot | `shot_day_idle_34.jpg`, `shot_day_closeup.jpg`, `shot_day_walk.jpg`, `shot_day_walk_back.jpg`, `shot_day_cast.jpg`, `shot_night_cast.jpg`, `shot_night_closeup.jpg` |
| Jeu | `assets/models/characters/fern/fern.glb`, `assets/shaders/toon.gdshader`, `assets/shaders/outline.gdshader`, `game/world/prototype/fern_preview.tscn`, `fern_preview.gd` |
| Outils | `tools/blender/build_character.py`, `inspect_glb.py`, `render_turnaround.py`, `compose_sheet.py`, `tools/fal/fern_character.sh` |
| Divers | `art/source/fern/.gdignore`, pour que Godot n'importe pas les sources brutes |

Touches de la scène de prévisualisation :

| Touche | Action |
|---|---|
| Espace ou flèches | clip suivant ou précédent |
| 1 à 4 | idle, walk, run, cast |
| N | jour ou nuit |
| C | gros plan |
| Q / E | tourner Fern |

## Changements recommandés pour le prochain personnage

1. **Demander au concept une texture « flat »** : couleurs plates, sans ombres ni plis peints,
   « unlit flat colors, no shading ». Essayer aussi `texture_model=meshy-n1`, qui donne une couleur
   de base 2K à partir de l'image seule. Le cel-shading gagne beaucoup quand l'albédo est propre.
   Sinon, aplatir l'albédo dans Blender : posterisation et quantification par matériau.
2. **Séparer les éléments mous** : cheveux longs, manteau et jupe longue doivent être des pièces
   distinctes, avec des os secondaires (2 ou 3 chaînes de cheveux, des pans de manteau) et un ressort
   simple dans Godot (SpringBoneSimulator3D). Avec Meshy, essayer `model_type=smart-topology`, qui
   découpe le maillage en parties natives, puis riggar en Blender (Rigify ou game rig).
   Le rig automatique Meshy ne convient pas aux robes longues.
3. **Fournir une planche multi-vues** (face, profil, dos) et tester Hunyuan 3D Pro (vues
   supplémentaires) ou Tripo H3.1 pour le dos et les cheveux. La caméra montre surtout le dos.
4. **Retoucher la tête à la main** dans Blender : frange raccourcie ou relevée pour garder les yeux
   lisibles à 50°, normales du visage lissées (custom normals), yeux en décalque ou atlas à part,
   mains réduites. C'est la partie qui donne le look « AFK Journey ».
5. **Optimiser pour le web** : texture 1K en WebP (environ 300 Ko au lieu de 2,4 Mo), compression
   meshopt du GLB. Ne commiter que le GLB final et le `.blend`. Les GLB bruts de rigging (~45 Mo)
   doivent rester hors du dépôt, sur un stockage d'assets ou via LFS.
