# Architecture

> Comment AFTERLIGHT est découpé, pourquoi, et quelles règles tiennent le découpage. À lire avant d'ajouter un système.

## Choix techniques

| Besoin | Choix | Pourquoi |
|---|---|---|
| Moteur | **Godot 4.7.2**, GDScript typé | Vrai moteur 3D (animation, navigation, shaders, UI, audio), export web, open source, pilotable en ligne de commande |
| Rendu web | Renderer **Compatibility** (WebGL 2), export **sans threads** | Seul renderer disponible sur le web ; sans threads, pas besoin des en-têtes COOP/COEP |
| Assets | **Blender 5.2** (sans interface) + **fal.ai** | Génération concept → 3D → squelette, puis retouche, optimisation et export GLB scriptés |
| Données | **JSON** dans `game/data/`, validés au chargement | Lisibles, faciles à comparer en revue, éditables par un agent ; validation explicite plutôt que magie de l'éditeur |
| Sauvegarde | `user://` (IndexedDB sur le web), JSON versionné | Godot persiste `user://` dans IndexedDB sur le web sans code spécifique |
| Tests | Lanceur GDScript sans interface + **Playwright** sur l'export web | Le moteur se teste sans rendu ; le parcours joueur se teste dans un vrai navigateur |
| Lint | gdtoolkit (`gdlint`, `gdformat`) | Standard de la communauté GDScript |

Écarté : Three.js / React (moins de briques de jeu, tout serait à réécrire), Phaser (2D), C# (pas d'export web stable), addons de test (GUT, GdUnit4) : inutiles pour l'instant, le lanceur maison suffit et n'ajoute pas de dépendance.

## Les cinq couches

```
            ┌───────────── A. Application (game/app, game/ui) ─────────────┐
            │  scène principale, routeur d'écrans, écrans, thème, textes   │
            └──────┬───────────────────────┬──────────────────────┬────────┘
                   │ actions               │ lecture              │ demandes
                   ▼                       ▼                      ▼
   B. État (game/state)  ◄────  D. Rendu (game/world, game/combat)    E. Persistance (game/persistence)
   autoload GameState            scènes 3D, caméra, personnages,       SaveService : écrit, lit, valide,
   détient l'état joueur         effets ; écoute les événements        migre, exporte, importe l'état
        │                        du moteur, ne décide rien
        │ appelle
        ▼
   C. Moteur (game/engine) — logique pure, déterministe ── lit ──► Données (game/data, JSON validés)
```

| Couche | Dossier | Rôle | Peut dépendre de |
|---|---|---|---|
| A. Application | `game/app`, `game/ui` | Démarrage, routeur d'écrans, écrans et composants, thème jour / nuit, textes | tout |
| B. État | `game/state` | Autoload `GameState` : la seule source de vérité de la partie en cours (dictionnaire sérialisable), signaux `changed` | moteur, données |
| C. Moteur | `game/engine` | Règles : création de partie, combat, IA, formules, butin, hors ligne, aléatoire à graine | données (types) |
| D. Rendu | `game/world`, `game/combat` | Monde 3D, combat 3D, effets. Reçoit des événements, anime, n'écrit jamais l'état | moteur (événements), état (lecture) |
| E. Persistance | `game/persistence` | Format de fichier, somme de contrôle, migrations, écriture atomique, copie de secours, export / import | état, données |

### Règles qui ne se discutent pas

1. **Le moteur est pur.** Scripts `RefCounted`, sans nœud, sans `get_tree()`, sans fichier, sans horloge, sans aléatoire global. Le temps (`now_unix`) et la graine arrivent en paramètres. `tests/unit/test_architecture.gd` échoue sinon.
2. **Une seule source de vérité.** L'état de la partie vit dans `GameState.data` ; les nœuds 3D n'en gardent pas de copie qui fait foi. Un objet de scène n'est jamais rangé dans l'état.
3. **Le rendu écoute.** Le combat produit des événements (`encounter_started`, `attack_started`, `damage_dealt`, `spell_cast`, `cast_interrupted`, `character_healed`, `shield_applied`, `status_applied`, `status_expired`, `character_defeated`, `enemy_defeated`, `boss_phase_changed`, `loot_dropped`, `encounter_completed`). La scène les joue. Elle ne calcule jamais si un coup touche.
4. **Pas de nombre de gameplay hors de `game/engine/balance/`.** Les écrans affichent ce que le moteur calcule.
5. **Pas de contenu en dur.** Personnages, ennemis, sorts, objets, runes, régions, lieux, donjons, rencontres, quêtes : JSON avec ID stables.
6. **Textes par clé.** Tout texte visible passe par `tr("CLE")` (`game/i18n/strings.csv`, colonne `fr`).

## Déterminisme

- `game/engine/core/rng.gd` enveloppe `RandomNumberGenerator` (PCG32) : graine et état sont sauvegardables, donc une rencontre ou un butin se rejoue à l'identique.
- Une graine par usage (`combat`, `loot`, `offline`), dérivée de la graine de partie et d'un compteur, pour qu'un tirage de butin n'en décale pas un autre.
- La simulation de combat avance par tics fixes (`TICK_SECONDS`), indépendants du nombre d'images par seconde. Vitesse ×2 / ×4 = plus de tics par image, pas des tics plus longs.

## État de la partie (format v1)

Dictionnaire de types simples (nombres, chaînes, tableaux, dictionnaires), pour être sérialisé tel quel :

| Clé | Contenu |
|---|---|
| `meta` | `seed`, `created_at`, `last_active_at` (secondes Unix), `play_time` |
| `party` | 4 emplacements : ID de personnage ou `""` |
| `characters` | par ID : `level`, `xp`, `equipment` (par emplacement), `spells` (rangs), `runes` |
| `wallet` | `gold`, `materials` (par ID) |
| `inventory` | liste d'instances d'objets (`uid`, `item_id`, `rarity`, `item_level`, `affixes`, `enhance`, `sockets`) |
| `world` | `region_id`, `location_id`, `unlocked_regions`, `discovered_locations` |
| `progress` | `cleared_encounters`, `quests`, `bestiary`, `discoveries` |
| `farming` | rencontre farmée hors ligne (`encounter_id`) ou `""` |
| `rng` | compteurs par flux |

Les réglages (taille du texte, animations réduites, volumes) sont à part, dans `user://settings.cfg` : ils ne voyagent pas avec une sauvegarde exportée.

## Sauvegarde

Fichier `user://saves/slot_0.json` :

```json
{ "format": "afterlight-save", "version": 1, "saved_at": 1793900000,
  "checksum": "<sha256 du JSON canonique de state>", "state": { ... } }
```

- **Écriture atomique** : on écrit `slot_0.json.tmp`, on relit et on valide, puis l'ancien fichier devient `slot_0.bak.json` et le nouveau prend sa place.
- **Lecture** : JSON lisible → enveloppe valide → somme de contrôle juste → migrations `version → version + 1` jusqu'à la version courante → validation du schéma de l'état. Godot relit les nombres JSON en flottants : la validation reconvertit en entiers les champs entiers.
- **Sauvegarde invalide** : jamais écrasée en silence. Le fichier est copié dans `user://saves/corrupt/` avec l'horodatage, puis l'écran de récupération propose : restaurer la copie de secours (si elle est valide), exporter le fichier endommagé, ou commencer une nouvelle partie (après confirmation).
- **Automatique** : toutes les 30 s si l'état a changé, à chaque changement d'écran, et quand l'onglet passe en arrière-plan (web) ou que la fenêtre se ferme. **Manuelle** : bouton « Sauvegarder ».
- **Export / import** : le même JSON. Sur le web, export par téléchargement (`JavaScriptBridge.download_buffer`) et import par un sélecteur de fichier du navigateur ; ailleurs, `user://exports/` et `FileDialog`. Un import passe par la même validation et ne remplace la partie qu'après confirmation.

## Données

- Un fichier par type d'entité et par origine : `game/data/canon/characters.json`, `game/data/original/enemies.json`…
- Chaque entité : `id` stable (`type.snake_case`), `origin` (`canon` ou `original`), `name_key` (texte par clé), puis ses champs.
- `game/data/content_db.gd` (autoload `Content`) charge tous les fichiers via `content_loader.gd`, valide chaque entité contre `game/data/schemas.gd` puis les règles croisées de `content_rules.gd` (règles V de CONTENT_PIPELINE §8), vérifie l'unicité des ID et les références croisées (un sort cité par un personnage doit exister). Au moindre défaut, la liste d'erreurs est affichée et le jeu ne démarre pas une partie sur des données fausses.

## Application

- `game/app/main.tscn` : racine avec la couche 3D (vide au Milestone 1), la couche d'interface (`ScreenHost`) et un voile de transition.
- Autoload `Router` : `go_to(screen_id, params)`, fondu de 320 ms (sortie + entrée) (coupe nette si « réduire les animations »). Écrans du Milestone 1 : `title`, `camp`, `settings`, `save_recovery`.
- Thème : `game/ui/theme/tokens.gd` (couleurs, tailles, espacements de `DESIGN.md`) → `theme_builder.gd` construit un `Theme` jour et un `Theme` nuit. Les écrans n'écrivent aucune couleur en dur.
- Pont de test : autoload `UiProbe`. Les contrôles importants s'y enregistrent sous un nom (`title.new_game`) ; sur le web, `window.afterlight` expose leur position à Playwright, qui clique comme un joueur, et un résumé de l'état pour vérifier le résultat.

## Arborescence

```
game/
├── app/          main.tscn, main.gd, router.gd, screens/
├── ui/           theme/ (tokens, builder), kit.gd (composants), ui_probe.gd
├── i18n/         strings.csv (clé, fr)
├── state/        game_state.gd (autoload GameState), settings.gd
├── engine/       core/ (rng, new_game, state_schema), balance/, combat/, loot/, offline/
├── world/        scènes 3D d'exploration (Milestone 2)
├── combat/       scènes 3D de combat (Milestone 3)
├── persistence/  save_codec.gd (pur : enveloppe, somme, migrations), save_service.gd (autoload), web_file_bridge.gd
└── data/         schemas.gd, content_db.gd, canon/*.json, original/*.json
```

## Tests

- `pnpm test` : `tools/test_runner.gd` exécute chaque `tests/unit/**/test_*.gd` (classe `TestCase`). Moteur, schémas, codec de sauvegarde, migrations et service de sauvegarde (dans un dossier `user://` de test) y sont couverts.
- `pnpm e2e` : export web puis Playwright (desktop et mobile) : nouvelle partie, navigation, sauvegarde, rechargement de la page, reprise.
- Un système n'est pas terminé tant que ses tests ne passent pas.
