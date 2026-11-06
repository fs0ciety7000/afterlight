# Portraits des marchands (lot du 2026-11-06)

Personnages originaux, décrits en texte (`prompts/npc_portraits.txt`) : Bastien (forge), Maëlle (graveuse de runes),
la marchande d'Aubelin. Brouillon `fal-ai/flux/schnell` (`drafts/`), puis une seule image finale à trois panneaux
`fal-ai/nano-banana-pro/edit` (`npc_portraits.png`). Seule référence : notre `assets/textures/portraits/fern.png`,
pour le cadrage et le rendu (le prompt demande des personnes nouvelles). Journal : `fal_log.json` ; coûts :
`art/source/LOT_2026-11-06_assets.md`.

Découpe locale : `tools/fal/crop_panels.py` → `assets/textures/portraits/npc_{bastien,maelle,aubelin_merchant}.webp`
(256 px, comme `fern.png`). Comparaison : `portraits_compare.jpg` ; en jeu : `ui_forge_merchant_headers.jpg`.
Affichage : en-tête des écrans Forge, Graveuse et Marchande (`ProgressionScreen.NPCS`).
