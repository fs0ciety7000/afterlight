# Lot fal : PNJ d'Aubelin, lot 2, squelettes et clips (2026-11-06)

Lot approuvé par le propriétaire (« NPC lot 2 »), estimé 2,16 USD, **plafond 2,20 USD**. Chaque appel facturé est
inscrit ici AVANT d'être lancé, au prix catalogue : `fal-ai/meshy/rigging/multi-animation` 0,20 + 0,12 par clip.
Aucun nouvel essai au-delà du plafond. Entrée : le modèle Tripo déjà construit (`assets/models/npcs/<pnj>.glb`,
réexporté avec une texture JPEG dans `art/source/npcs/rig/<pnj>_rig_in.glb`, Meshy ne lisant pas forcément le WebP).
Clips de la bibliothèque Meshy : `243` Idle_3 (idle calme, celui de Fern et de Morvaine) ; `313`
Talk_with_Hands_Open (parole, Odile et Maëlle). Journal détaillé : `art/source/npcs/rig/fal_log.json`.

| # | Heure | Endpoint | Nom | PNJ | Clips (ids) | Résultat | Coût | Cumul |
|---|---|---|---|---|---|---|---|---|
| 1 | 13:03 UTC | fal-ai/meshy/rigging/multi-animation | `odile_rig` | Odile | idle 243, talk 313 | OK (maillage accepté ; poids corrigés en local) | 0,44 | 0,44 |
| 2 | 13:10 UTC | fal-ai/meshy/rigging/multi-animation | `maelle_rig` | Maëlle | idle 243, talk 313 | OK | 0,44 | 0,88 |
| 3 | 13:11 UTC | fal-ai/meshy/rigging/multi-animation | `bastien_rig` | Bastien | idle 243 | OK | 0,32 | 1,20 |
| 4 | 13:11 UTC | fal-ai/meshy/rigging/multi-animation | `rosalie_rig` | Rosalie | idle 243 | OK | 0,32 | 1,52 |
| 5 | 13:12 UTC | fal-ai/meshy/rigging/multi-animation | `tobias_rig` | Tobias | idle 243 | OK | 0,32 | 1,84 |
| 6 | 13:13 UTC | fal-ai/meshy/rigging/multi-animation | `ysaline_rig` | Ysaline | idle 243 | OK | 0,32 | 2,16 |

**Total du lot : 6 appels facturés, 2,16 USD sur 2,20** (marge non dépensée : 0,04). Aucun appel refusé, aucun
nouvel essai. Durée par appel : 37 à 45 s.

| Élément | Estimé | Dépensé |
|---|---|---|
| Odile, idle + talk (essai) | 0,44 | 0,44 |
| Maëlle, idle + talk | 0,44 | 0,44 |
| Bastien, Rosalie, Tobias, Ysaline, idle | 1,28 | 1,28 |

## Essai sur Odile et décision

Meshy accepte le maillage Tripo tel quel (11 995 triangles, UV et matière gardés, 24 os, repos = pose modélisée).
Les poids bruts n'étaient pas utilisables en l'état : la main et l'avant-bras gauches tiraient tout le tablier
et la pointe du châle (bras collés au corps), et le bras gauche plié autour de la cloche entrait dans le ventre,
les clips Meshy supposant un bras pendant. Deux corrections locales, sans nouvel appel, les rendent propres
(planches `qa_odile_anim.jpg`) ; le lot a donc continué :

1. **Poids des bras** : sous l'aisselle, les poids des os de bras s'effacent entre 14 et 20 cm d'écart latéral
   à la colonne et passent à l'os du tronc à cette hauteur (`build_npc_rigged.py --arm-gap`, défaut 0,14).
2. **Bras figé** pour un bras modélisé plié autour d'un objet : `LeftShoulder`, `LeftArm`, `LeftForeArm`, `LeftHand`
   restent dans la pose modélisée dans tous les clips (Odile et sa cloche, Ysaline et son panier) ; le bras suit le
   buste. Le `talk` d'Odile ne gesticule donc que de la main droite.

## Chaîne et résultats

Relance : `tools/fal/npcs_rig.sh input | rig <pnj> | build | qa` (`input` part des GLB statiques du lot 1,
commit 092ebf7). Sorties brutes (`art/source/npcs/rig/<pnj>/`, ~8 Mo par PNJ) non commitées : `_0` rig au repos,
`_8` Idle_3, `_10` Talk_with_Hands_Open. Journal fusionné : `art/source/npcs/rig/fal_log.json`.

| PNJ | Clips | Triangles | GLB | Particularités |
|---|---|---|---|---|
| Odile | idle 10 s, talk 4 s | 11 995 | 684 Ko | bras gauche figé (cloche) |
| Bastien | idle 10 s | 11 991 | 601 Ko | |
| Maëlle | idle 10 s, talk 4 s | 11 987 | 676 Ko | |
| Rosalie | idle 10 s | 11 984 | 606 Ko | |
| Tobias | idle 10 s | 11 988 | 627 Ko | |
| Ysaline | idle 10 s | 11 988 | 668 Ko | bras gauche figé (panier) |

Mêmes chemins (`assets/models/npcs/<pnj>.glb`), mêmes noms de matière et de texture (albédo WebP 512 px),
regard vers glTF **+Z**, pieds à y = 0, 4 influences par sommet, clips `idle` et `talk` en boucle (4 dernières clés
fondues vers la première). En jeu (`WorldInteractables`) : `idle` en boucle avec un décalage tiré de l'id,
`talk` pendant un dialogue avec le PNJ s'il existe, sinon `idle`. Contrôle `blender-asset-qa` (`qa_glb.py`) :
l'« Icosphere » signalée est la forme d'os créée par l'importeur Blender (absente du GLB) ; 1 à 2 paires de
triangles coplanaires (Odile, Tobias, Ysaline) et les avertissements du lot 1 (coutures UV, faces dos à dos dans
les franges) acceptés. Planches de déformation (6 images par clip, face et profil) : `art/source/npcs/qa_<pnj>_anim.jpg`.
