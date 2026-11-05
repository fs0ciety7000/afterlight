# AGENTS.md

Règles communes à tous les agents de code (Claude Code, Codex, Cursor...). Format neutre : rien ici n'est propre à Claude.

## Contexte

- **Nom** : AFTERLIGHT
- **Type** : jeu 3D Godot exporté pour le web (RPG idle / aventure / donjon), prototype privé
- **Résumé en une phrase** : RPG 3D en vue 3/4 dans l'univers de *Frieren* (fan-game non officiel) : monde explorable, personnages cel-shading, combats temps réel hybrides, butin et builds, progression hors ligne.

## Commandes

```bash
install:   pnpm install          # Playwright seulement ; Godot et Blender viennent de /opt/tools
import:    pnpm godot:import     # obligatoire sur un clone neuf (.godot/ n'est pas commité)
test:      pnpm test             # tests GDScript sans interface (tests/unit)
lint:      pnpm lint             # gdlint + gdformat --check
format:    pnpm format
build:     pnpm build:web        # export web dans build/web/
serve:     pnpm serve            # sert build/web sur http://localhost:8060
e2e:       pnpm e2e              # Playwright sur l'export web (desktop et mobile)
```

## Structure du dépôt

```
.
├── project.godot, export_presets.cfg
├── game/
│   ├── app/          # A. Application : scène principale, routeur d'écrans
│   ├── ui/           # interface (Control, thème)
│   ├── state/        # B. État du jeu : autoload qui détient l'état du joueur (sérialisable)
│   ├── engine/       # C. Moteur pur : combat, IA, formules (engine/balance), butin, hors ligne, RNG à graine
│   ├── world/        # D. Rendu : monde 3D, caméra, personnages
│   ├── combat/       # D. Rendu du combat : écoute les événements du moteur, ne décide rien
│   ├── persistence/  # E. Sauvegarde user:// (IndexedDB sur le web), versions, migrations, export / import
│   └── data/         # contenu JSON validé au chargement : canon/ et original/, ID stables
├── assets/           # GLB, textures, shaders, polices, audio (originaux, prêts pour le jeu)
├── art/              # sources : concept art, .blend, journaux de génération
├── tools/            # lanceur de tests, scripts Blender et fal, serveur statique
└── tests/            # unit/ (GDScript), e2e/ (Playwright)
```

Dépendances autorisées : `app → tout` ; `ui → state` ; `state → engine, data` ; `world, combat → engine (événements), state (lecture)` ; `persistence → state, data` ; `engine → data` uniquement.

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
