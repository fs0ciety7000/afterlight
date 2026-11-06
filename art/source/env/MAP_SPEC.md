# Carte peinte du Val d'Aubelin : spécification

Fichier : `assets/textures/map/aubelin_vale.jpg` (JPEG q90, 0,9 Mo).

## Format

| Élément | Valeur |
|---|---|
| Dimensions | 2560 × 1440 px (16:9 exact) |
| Style | atlas illustré, aquarelle sur papier, vue de dessus ; aucun texte, libellé, rose des vents ni icône |
| Source | `fal-ai/nano-banana-pro/edit`, référence de style `art/concepts/keyart/title_day.jpg`, prompt `prompts/map.txt` (journal : `fal_log.json`, nom `map_v1`) |
| Post-traitement | `tools/fal/process_env_textures.py map` : peinture réduite à 93 % et centrée (décalage 90, 50 px) sur un papier prolongé, pour que les lieux restent hors de la marge |
| Marge de sécurité | 6 % de chaque côté (154 px à gauche et à droite, 86 px en haut et en bas). Aucun lieu dans cette bande ; seule la pointe de la flèche du clocher du cloître l'effleure en haut (décor, pas le point du lieu) |

## Convention de coordonnées

`map_pos = [x, y]` normalisé de 0 à 1, origine en haut à gauche, x vers la droite, y vers le bas
(pixel = `x × 2560`, `y × 1440`). Le nord est en haut. Les valeurs désignent le centre visuel du lieu
(là où poser le marqueur).

## Lieux lus sur l'image finale

| Lieu | ID | map_pos | Repère visuel |
|---|---|---|---|
| Aubelin (hub) | `location.aubelin` | [0.44, 0.59] | place du village, au centre des maisons à colombages |
| Bois des Murmures | `location.whispering_wood` | [0.26, 0.39] | lisière de la grande forêt de bouleaux dorés, à l'ouest / nord-ouest |
| Tourbière aux Lanternes | `location.lantern_mire` | [0.72, 0.51] | mares brumeuses et lanternes, au nord-est du village, à l'est de la rivière |
| Ruines du Guet | `location.watch_ruins` | [0.79, 0.22] | tour en ruine sur la colline rocheuse au nord-est |
| Cloître du Cadran Éteint | `dungeon.silent_dial_cloister` | [0.57, 0.17] | cloître et tour-horloge sur la colline, au nord |

Les routes peintes relient déjà le village à la forêt (nord-ouest), au cloître (nord), à la tourbière
et aux ruines (pont à l'est). Zoom : la peinture tient au 2e cran (×2) sans flou visible ; au-delà,
prévoir une version 4K.
