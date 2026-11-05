# CLAUDE.md

> Lu automatiquement à chaque session. Court exprès. Les règles générales (langue, secrets, routage des skills et des agents) sont dans `~/.claude/CLAUDE.md`.

@AGENTS.md

## Projet courant

- **Type** : `gamedev-web` (jeu navigateur : React + Phaser 4 + moteur TS pur). Voir `~/.claude/skills-registry.md`.
- **Stack** : Vite 8, React 19, TypeScript 6 strict, React Router, Zustand 5 + Immer, Zod 4, Phaser 4, IndexedDB (`idb`), Vitest, Playwright. pnpm.
- **Commandes** : voir `AGENTS.md` (`pnpm install`, `pnpm dev`, `pnpm typecheck`, `pnpm lint`, `pnpm test`, `pnpm e2e`, `pnpm build`).
- **Déploiement** : aucun pour l'instant (prototype privé, site statique `dist/`).

## Documents du projet

- `docs/brief.md` : objectif, périmètre, contraintes.
- `docs/GDD.md`, `docs/ARCHITECTURE.md`, `docs/GAME_BALANCE.md`, `docs/CONTENT_PIPELINE.md`, `docs/ROADMAP.md` : conception et jalons.
- `DESIGN.md` : direction visuelle. À respecter pour toute interface.

## Spécifique à ce projet

- **Fan-game non officiel, privé** (univers *Frieren*). Aucune image, musique ou réplique de l'œuvre dans le dépôt : tout l'art est original. Le contenu canon (`src/data/canon/`) est séparé du contenu original (`src/data/original/`) et porte `origin: 'canon' | 'original'`.
- **Textes du jeu en français**, centralisés (pas de chaînes en dur dans les composants) ; code et commentaires en anglais.
- **Phaser 4** (pas 3) : utiliser les skills officiels `phaserjs/phaser` dans `.claude/skills/`, pas la doc v3.
- **Couches** : `src/engine` est pur et déterministe (règles ESLint qui l'imposent) ; tout calcul de jeu passe par l'agent `game-engine-dev`, toute règle nouvelle par `game-designer` d'abord.
- Pas de variables d'environnement ni de secrets pour l'instant.
