# AGENTS.md

Règles communes à tous les agents de code (Claude Code, Codex, Cursor...). Format neutre : rien ici n'est propre à Claude.

## Contexte

- **Nom** : AFTERLIGHT
- **Type** : jeu web (RPG idle / aventure / donjon), prototype privé
- **Résumé en une phrase** : RPG navigateur dans l'univers de *Frieren* (fan-game non officiel) : atlas illustré, combats 2D temps réel hybrides, butin et builds, progression hors ligne.

## Commandes

```bash
install:   pnpm install
dev:       pnpm dev
typecheck: pnpm typecheck
test:      pnpm test          # Vitest (moteur, données, sauvegarde)
e2e:       pnpm e2e           # Playwright (build + preview, desktop et mobile)
lint:      pnpm lint          # ESLint, y compris les garde-fous d'architecture
format:    pnpm format
build:     pnpm build         # dist/ statique
```

## Structure du dépôt

```
.
├── docs/                 # brief, GDD, architecture, équilibrage, pipeline de contenu, roadmap
├── public/assets/        # art original (carte, sprites, icônes) ; remplaçable sans toucher aux données
├── src/
│   ├── app/              # A. Application : shell React, routes, écrans
│   ├── ui/               # composants du design system (tokens dans ui/tokens)
│   ├── state/            # B. État du jeu : store Zustand (données sérialisables, jamais d'objet Phaser)
│   ├── engine/           # C. Moteur TS pur : combat, IA, formules (engine/balance), butin, hors ligne, RNG à graine
│   ├── renderer/         # D. Rendu Phaser 4 : écoute les événements du moteur, ne décide rien
│   ├── persistence/      # E. Sauvegarde IndexedDB : schéma versionné, migrations, export / import
│   └── data/             # contenu validé par Zod : canon/ et original/ séparés, ID stables
├── tests/e2e/            # Playwright
└── .claude/              # skills et agents du projet
```

Dépendances autorisées entre couches : `app → state, engine, renderer, persistence, data, ui` ; `state → engine, data` ; `renderer → engine (types et événements)` ; `persistence → state (types), data` ; `engine → data (types)`. Le moteur n'importe rien d'autre.

## Règles de travail

1. Lis avant d'écrire : ouvre les fichiers concernés avant de les modifier.
2. Plus petit changement qui résout le problème. Pas de refactor non demandé.
3. Suis le style existant (nommage, formatage, structure).
4. Ajoute ou mets à jour les tests avec chaque changement de comportement.
5. Lance `test` et `lint` avant de conclure ; rapporte les résultats réels.
6. Ne touche jamais à : `.env*`, `dist/`, `build/`, fichiers de lock modifiés à la main.
7. Tâche de plus de ~5 fichiers ou changement d'architecture : propose d'abord un plan.

## Sécurité

- Aucun secret dans le code, les logs ou les commits. Les secrets passent par `kit secrets`.
- Valide toutes les entrées externes ; requêtes SQL paramétrées uniquement.
- Confirmation avant toute action destructive (suppression, reset, migration ou déploiement en prod).
