# Taille de l'export web (critère 7.2)

Cible et règles : `docs/ARCHITECTURE.md`, « Taille de l'export et chargement (web) ».

## Mesurer

```bash
pnpm build:web                      # export dans build/web/
python3 tools/pck_report.py         # détail du pack : par type, par dossier, plus gros fichiers
python3 tools/pck_report.py --top 60
gzip -6 -c build/web/index.pck | wc -c ; gzip -6 -c build/web/index.wasm | wc -c
pnpm test                           # tests/unit/test_export_size.gd : budget du pack, exclusions, imports
```

`tools/pck_report.py` lit le répertoire du `.pck` (format 4.x) et rattache chaque fichier de `.godot/imported/` à son dossier source.

## Avant / après (2026-11-06, Godot 4.7.2)

| | Avant | Après |
|---|---|---|
| `index.pck` | **69,4 Mo** (1042 fichiers) | **25,7 Mo** (921 fichiers) |
| textures (`.ctex`) | 46,4 Mio | 7,0 Mio |
| scènes importées et exportées (`.scn`) | 11,7 Mio | 9,3 Mio |
| ressources (`.res` : maillages du décor, terrain) | 6,6 Mio | 6,6 Mio |
| code, polices, données, traductions | 1,4 Mio | 1,5 Mio |
| `index.pck` gzip | non mesuré | 22,6 Mo |
| `index.wasm` (modèle officiel) / gzip | 39,5 / 10,2 Mo | inchangé |

Par dossier, après : `assets/environment` 11,2 Mio (maillages 3,1, terrain 3,9, textures ~4), `assets/models` 7,1 Mio (Fern 1,2, Morvaine 1,2, chaque PNJ ~0,45), scènes de lieu (`.godot/exported`) 3,5 Mio, `assets/textures` 1,2 Mio, polices 0,4 Mio.

### Ce qui a changé

1. **Textures en WebP avec perte** (71 fichiers, `compress/mode` 0 → 1, qualité 0,8 ; 0,85 pour carte, titre et portraits). Elles étaient importées sans perte avec mipmaps : une maison 1024 px pesait 1,7 Mo, elle pèse 0,28 Mo. PSNR mesuré entre la source et le WebP importé : 36,8 dB au pire (maisons), 39,7 dB en médiane. `dial_dial_tex.jpg` limité à 1024 px (2048 px pour une seule pièce). Défaut du projet pour les nouvelles textures : `[importer_defaults]` dans `project.godot`.
2. **Exclusions de l'export** : `build/` (des captures y étaient emballées), `docs/`, les GLB de `assets/environment/` (2,3 Mio : sources des maillages `meshes/*.res`, jamais chargées par le jeu) et les 22 copies identiques de l'atlas d'accessoires extraites une par GLB (1,2 Mio). Les 19 matériaux concernés pointent vers `assets/environment/textures/village_props_atlas.webp` ; `location_builder.gd` fait de même au prochain passage (`_shared_texture`, par somme MD5).
3. **Serveur local** (`tools/serve.mjs`) : gzip pour `.wasm`, `.pck`, `.js`, `.html`, comme un hébergeur statique, pour que la mesure 7.2 compte ce qu'un joueur télécharge.

Comparaisons de rendu avant | après | écart ×4 : `compare_aubelin_vista.jpg`, `compare_cloister_dial_centre.jpg` (outil `location_preview.tscn --shots`). Les écarts visibles viennent du vent sur la végétation et des rayons animés, pas des textures. Sur les 15 vues d'Aubelin et du cloître, PSNR entre 28 et 50 dB, et les vues sans végétation ni effet animé restent au-dessus de 39 dB.

### Essayé, non retenu

- **Compression des animations** (`compression/enabled` sur l'`AnimationPlayer` à l'import) : Fern passe de 1,27 à 0,99 Mo, soit environ 1 Mo sur tous les modèles. Non retenu : perte quantifiée sur les clips, rendus mal vérifiables sans revue des animations.
- **Compression VRAM (S3TC + ETC2)** : deux copies par texture dans le pack, plus lourdes que le WebP.
- **Retirer les LOD ou les maillages d'ombre** : gain faible, risque sur 7.1 (images par seconde).

## Premier écran à 20 Mb/s

Le chargeur web télécharge le wasm puis le pack entier avant d'afficher le titre. À 2,5 Mo/s : 10,2 Mo (wasm gzip) + 22,6 Mo (pck gzip) ≈ 32,8 Mo, soit **≈ 13 s plus le démarrage : 7.2 n'est pas encore tenu** (avant : 39,5 + 69,4 Mo sans compression, soit ≈ 44 s). Le WebP ne se recompresse pas : le pack gzip reste proche de sa taille brute.

Ce qui sert vraiment au premier écran (code, thème, polices, données, image du titre) pèse environ 3 Mo. Les lieux et les modèles sont déjà chargés au voyage (`explore_view.gd`, `player.gd`), et les chargements sont protégés par `ResourceLoader.exists`.

**Proposition, non faite ici** (elle touche `game/app` et le démarrage) : un second pack.

1. Un preset d'export `Web content` (`--export-pack`) avec `assets/environment/*`, `assets/models/*`, `game/world/locations/*`, `game/world/dungeons/*` ; le preset `Web` les exclut.
2. Au titre, `HTTPRequest` télécharge `content.pck` dans `user://`, puis `ProjectSettings.load_resource_pack("user://content.pck")`. « Continuer » et « Nouvelle partie » attendent la fin du téléchargement, avec une barre de progression.
3. Gain attendu : ≈ 10,2 + 3 Mo avant le titre, soit ≈ 5-6 s à 20 Mb/s ; le reste (≈ 20 Mo, ≈ 8 s) se télécharge pendant le titre.
4. Points à vérifier : les `preload()` de modèles dans des scripts chargés au démarrage (aucun aujourd'hui hors `game/world/prototype`), le cache d'UID du pack principal, l'E2E hors ligne (le service worker n'est pas activé).
