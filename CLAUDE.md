# CLAUDE.md

> Lu automatiquement à chaque session. Court exprès. Les règles générales (langue, secrets, routage des skills et des agents) sont dans `~/.claude/CLAUDE.md`.

@AGENTS.md

## Projet courant

- **Type** : `gamedev-godot` (jeu 3D exporté pour le web). Voir `~/.claude/skills-registry.md`.
- **Stack** : Godot 4.7.2 (GDScript typé, renderer Compatibility), Blender 5.2 (modélisation, squelette, animation, export GLB), fal.ai (concept art, image → 3D), Playwright (E2E sur l'export web), gdtoolkit (lint).
- **Commandes** : voir `AGENTS.md` (`pnpm test`, `pnpm lint`, `pnpm build:web`, `pnpm e2e`).
- **Déploiement** : aucun pour l'instant (prototype privé, export statique `build/web/`).

## Documents du projet

- `docs/brief.md` : objectif, périmètre, contraintes.
- `docs/GDD.md`, `docs/ARCHITECTURE.md`, `docs/GAME_BALANCE.md`, `docs/CONTENT_PIPELINE.md`, `docs/ROADMAP.md` : conception et jalons.
- `DESIGN.md` : direction visuelle. À respecter pour toute interface et tout asset.

## Spécifique à ce projet

- **Fan-game non officiel, privé** (univers *Frieren*). Aucune image, musique ou réplique de l'œuvre dans le dépôt ; les images de référence de l'utilisateur ne servent jamais d'entrée à la génération. Contenu canon (`game/data/canon/`) séparé de l'original (`game/data/original/`), champ `origin: "canon" | "original"`.
- **Textes du jeu en français**, centralisés ; code et commentaires en anglais.
- **Couches** : `game/engine` est de la logique pure et déterministe (`RefCounted`, pas de nœud, pas de `randf()`, pas de `Time`) ; `tests/unit/test_architecture.gd` l'impose. Tout calcul de jeu passe par l'agent `game-engine-dev`, toute règle nouvelle par `game-designer` d'abord.
- **Outils hors dépôt** : Godot et Blender sont installés dans `/opt/tools` par le script de configuration de l'environnement cloud ; `godot` et `blender` sont dans le `PATH`.
- **Génération** : `FAL_KEY` est une variable de l'environnement cloud ; ne jamais l'afficher. Chaque génération est journalisée (prompt, modèle, graine) dans `art/` pour être reproductible.
- Web : renderer Compatibility uniquement (WebGL 2) ; export sans threads (pas de COOP/COEP requis).
