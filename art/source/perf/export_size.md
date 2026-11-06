# Taille de l'export web (critère 7.2)

Cible et règles : `docs/ARCHITECTURE.md`, « Taille de l'export et chargement (web) ».

## Mesurer

```bash
pnpm build:web                      # index.html, index.wasm, index.pck, content.pck, content.json
python3 tools/pck_report.py         # détail du pack de démarrage : par type, par dossier, plus gros fichiers
python3 tools/pck_report.py build/web/content.pck --top 60
for f in index.wasm index.pck content.pck; do echo $f $(gzip -6 -c build/web/$f | wc -c); done
pnpm test                           # tests/unit/test_export_size.gd : budgets des deux packs, avant le titre, répartition

# Temps à 20 Mb/s sans navigateur : pnpm serve (gzip), puis curl bridé à 2,5 Mo/s
for f in index.html index.js index.wasm index.pck; do
  curl -s --limit-rate 2500000 -H "Accept-Encoding: gzip" -o /dev/null \
    -w "$f %{size_download} B %{time_total}s\n" http://localhost:8060/$f; done
curl -s --limit-rate 2500000 -H "Accept-Encoding: gzip" -o /dev/null -w "%{time_total}s\n" http://localhost:8060/content.pck

# Build découpé sur le bureau (sans navigateur), lancé depuis un dossier hors du dépôt
godot --headless --main-pack <dépôt>/build/web/index.pck --quit-after 600 -- --content-base=http://localhost:8060/
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

## Second pack (2026-11-06, après le réencodage audio)

Avant le découpage, le pack unique pesait **31,8 Mo** (28,3 Mo gzip) : la musique (5,8 Mio) l'avait fait passer au-dessus du budget de 30 Mo.

| | Pack unique | Découpé |
|---|---|---|
| `index.pck` (avant le titre) | 31,8 Mo / 28,3 Mo gzip | **4,06 Mo / 3,59 Mo gzip** (573 fichiers) |
| `content.pck` (pendant le titre) | n/a | 25,8 Mo / 22,9 Mo gzip (451 fichiers) |
| `index.wasm` gzip | 10,1 Mo | 10,1 Mo |
| Avant le titre (html + js + wasm + pck, gzip) | 38,5 Mo, ≈ 15,4 s à 2,5 Mo/s | **13,85 Mo, ≈ 5,5 s** (curl bridé : 4,9 s) |
| Boutons « Continuer » / « Nouvelle partie » actifs | avec le titre | + 9,2 s de `content.pck` (curl bridé : 8,8 s), pendant le titre |

Premier écran interactif estimé à 20 Mb/s : ≈ 5,5 s de téléchargement + le démarrage du moteur (compilation du wasm, autoloads, ≈ 1 à 2 s) ≈ **7 s : 7.2 est tenu**. Le titre, les réglages et l'import sont utilisables tout de suite ; l'entrée dans le monde attend la fin du second pack (≈ 15 s après l'ouverture de la page à 20 Mb/s, ≈ 1 s en local).

Contenu du pack de démarrage : textures d'interface, carte et portraits 1,2 Mio, sons et musique du titre 1,1 Mio, code 0,8 Mio, polices 0,4 Mio, données et traductions 0,2 Mio.

Vérifié sans navigateur : `godot --headless --main-pack <index.pck> -- --content-base=<url>` sur un serveur local bridé : téléchargement, montage, chargement d'Aubelin, du cloître, de Fern et d'une musique, nouvelle partie jusqu'à l'écran d'exploration, sans erreur. Serveur absent (pas de réponse) et 404 : message d'erreur et « Réessayer ». Captures de l'écran titre en chargement et en échec relues sous xvfb.

## Premier écran à 20 Mb/s (avant le second pack)

Le chargeur web télécharge le wasm puis le pack entier avant d'afficher le titre. À 2,5 Mo/s : 10,2 Mo (wasm gzip) + 22,6 Mo (pck gzip) ≈ 32,8 Mo, soit **≈ 13 s plus le démarrage : 7.2 n'est pas encore tenu** (avant : 39,5 + 69,4 Mo sans compression, soit ≈ 44 s). Le WebP ne se recompresse pas : le pack gzip reste proche de sa taille brute.

Ce qui sert vraiment au premier écran (code, thème, polices, données, image du titre) pèse environ 3 Mo. Les lieux et les modèles sont déjà chargés au voyage (`explore_view.gd`, `player.gd`), et les chargements sont protégés par `ResourceLoader.exists`.

**Proposition** (faite, voir « Second pack » ci-dessus) : un second pack.

1. Un preset d'export `Web content` (`--export-pack`) avec `assets/environment/*`, `assets/models/*`, `game/world/locations/*`, `game/world/dungeons/*` ; le preset `Web` les exclut.
2. Au titre, `HTTPRequest` télécharge `content.pck` dans `user://`, puis `ProjectSettings.load_resource_pack("user://content.pck")`. « Continuer » et « Nouvelle partie » attendent la fin du téléchargement, avec une barre de progression.
3. Gain attendu : ≈ 10,2 + 3 Mo avant le titre, soit ≈ 5-6 s à 20 Mb/s ; le reste (≈ 20 Mo, ≈ 8 s) se télécharge pendant le titre.
4. Points à vérifier : les `preload()` de modèles dans des scripts chargés au démarrage (aucun aujourd'hui hors `game/world/prototype`), le cache d'UID du pack principal, l'E2E hors ligne (le service worker n'est pas activé).
