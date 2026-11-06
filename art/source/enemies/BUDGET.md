# Budget fal : lot ennemis générés (2026-11-06)

Lot approuvé par le propriétaire, **plafond 5,00 USD**. Prix catalogue (consigne du lot) : nano-banana-pro(/edit) 0,15 ;
tripo3d/h3.1 image-to-3d (et multiview-to-3d, même tarif à l'unité sur fal) 0,40 ; meshy/v7.1/multi-image-to-3d 1,20 ;
fal-ai/meshy/rigging/multi-animation 0,20 + 0,12 par clip. Les appels refusés sans facturation ne comptent pas.
Journal détaillé : `fal_log.json`.

| # | Heure | Endpoint | Nom | Résultat | Coût | Cumul |
|---|---|---|---|---|---|---|
| 1 | 03:10 UTC | tripo3d/h3.1/multiview-to-3d | `mist_wolf_tripo` (4 vues existantes) | OK | 0,40 | 0,40 |
| 2 | 03:10 UTC | fal-ai/nano-banana-pro/edit | `stone_sentinel_concept` | OK | 0,15 | 0,55 |
| 3 | 03:10 UTC | fal-ai/nano-banana-pro/edit | `morvaine_concept` (face, profil, dos) | OK | 0,15 | 0,70 |
| 4 | 03:14 UTC | tripo3d/h3.1/image-to-3d | `stone_sentinel_tripo` | OK | 0,40 | 1,10 |
| 5 | 03:14 UTC | meshy/v7.1/multi-image-to-3d | `morvaine_meshy` | OK | 1,20 | 2,30 |
| 6 | 03:16 UTC | fal-ai/meshy/rigging/multi-animation | `morvaine_rig` (6 clips : 243, 1, 125, 129, 178, 189) | OK | 0,92 | 3,22 |

**Total du lot : 6 appels facturés, 3,22 USD sur 5,00** (marge non dépensée : 1,78). Aucun appel refusé ni relancé.

Écart avec le plan (3,6 USD estimés) : la marge prévue pour un second essai n'a pas servi, tous les résultats ont
été retenus au premier essai. Le loup a utilisé `multiview-to-3d` (les 4 vues déjà prêtes) au lieu d'`image-to-3d` :
même endpoint Tripo H3.1, même prix unitaire fal (crédits Tripo), compté au prix catalogue 0,40.
