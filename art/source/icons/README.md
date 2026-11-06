# Icônes peintes (lot du 2026-11-06)

Quatre planches, chacune générée en UNE image puis découpée en cases (`tools/fal/icons.sh`) :

| Planche | Grille | Contenu | Génération |
|---|---|---|---|
| `icons_spells.png` | 3 × 2 | Zoltraak, Salve, Barrière, ultime, passif, trait de mana | `fal-ai/nano-banana-pro` (texte seul) |
| `icons_equipment.png` | 4 × 3 | 12 bases d'équipement (2 par emplacement) | `nano-banana-pro/edit`, seule référence : `icons_spells.png` (style) |
| `icons_runes.png` | 4 × 2 | 8 runes | idem |
| `icons_misc.png` | 5 × 2 | 4 matériaux, 2 consommables, 4 artefacts | idem |

Brouillons de mise en page : `drafts/` (`fal-ai/flux/schnell`). Prompts : `prompts/`. Journal : `fal_log.json`.
Coûts : `art/source/LOT_2026-11-06_assets.md`. Aucune image de l'œuvre en entrée.

Chaîne locale : `split` (grille, fond de chaque case pris sur son bord) → `cut/` (non commité) → `export`
(128 px, WebP q90 avec alpha, marge 5 %) → `assets/textures/icons/<id>.webp` (36 fichiers, 284 Ko).
Contrôle : `icons_contact.jpg` (128 px sur fond jour, 48 px sur fond nuit), `ui_bag_with_icons.jpg` (sac en jeu).
Branchement : `GameIcons.for_id()` ; `SpellButton` et `ItemTile` gardent leurs glyphes si l'icône manque.
