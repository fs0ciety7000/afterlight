# Brief du projet

> Rempli en phase 1 de `/new-project`. Court : une page. Le cahier des charges complet (prompt maître) sera repris dans `docs/GDD.md` et `docs/ARCHITECTURE.md`.

## Objectif
AFTERLIGHT : un RPG idle / aventure / donjon en **3D** jouable dans le navigateur, fan-game non officiel situé dans l'univers de *Frieren*. Il doit se jouer et se ressentir comme un RPG fantasy soigné (monde 3D en vue 3/4 façon AFK Journey, personnages modélisés en cel-shading anime, combats temps réel, butin et builds), pas comme un clicker idle générique.

## Public
Fans de *Frieren* et joueurs d'idle RPG (type AFK Journey). Session courte sur mobile, session longue sur desktop ; le jeu progresse hors ligne entre deux visites.

## Indispensable (MVP jouable)
- **Monde 3D explorable** en vue 3/4 (déplacement à pied, régions, lieux, brouillard, déblocage) et **carte du monde** (zoom, déplacement, voyage), à la souris, au clavier et au toucher.
- **Combat hybride temps réel** dans le décor 3D : simulation GDScript pure et déterministe, rendu Godot piloté par événements ; auto-attaques, 3 sorts actifs, 3 archétypes d'ennemis, 1 élite, 1 boss, vitesse, pause, victoire / défaite.
- **Progression** : niveau, équipement (rareté, affixes, amélioration), sorts, runes, butin, or et matériaux ; formules centralisées et documentées.
- **Progression hors ligne** calculée (pas de ticks en boucle), plafond 8 h, résumé au retour.
- **Sauvegarde** IndexedDB versionnée : auto + manuelle, validation, migrations, export / import, récupération sans écraser une sauvegarde invalide.

## Hors périmètre (MVP)
- Multijoueur, comptes, serveur, classement, monétisation.
- Plus d'un personnage jouable au départ (les 4 emplacements de groupe existent, un seul est rempli).
- Œuvres protégées : aucune image, musique ou réplique copiée de l'anime ou du manga. Les images fournies servent seulement de référence d'ambiance ; les modèles sont produits à partir de descriptions écrites (concept art généré, puis 3D générée et retravaillée dans Blender).
- Kits low-poly génériques (Polyfork et équivalents) : refusés, rendu trop « cubique ».

## Contraintes
- Interface en **français** uniquement (textes centralisés pour permettre une traduction plus tard).
- Personnage jouable initial : **Fern** (canon).
- **Prototype privé** : pas de publication publique ; aucune échéance, avancement jalon par jalon.
- Web, desktop d'abord, responsive tablette et mobile (interfaces adaptées, pas réduites).
- Moteur **Godot 4.7** (renderer Compatibility / WebGL 2), export web statique ; pas de backend.
- Visuel : **cel-shading anime** (aplats, contours encrés), interface fantasy épurée.
- Chaîne d'assets : concept art et image → 3D via fal.ai (`FAL_KEY`), retopologie, squelette, animation et export GLB dans Blender 5.2.
- Fan-game non commercial : contenu canon (personnages, lieux, sorts nommés dans l'œuvre) séparé du contenu original, et marqué comme tel dans les données.
- Livraison incrémentale en 7 jalons ; chaque jalon testé (tests GDScript sans interface + Playwright sur l'export web) avant d'être déclaré fini.

## Critères de réussite
- Une partie complète : nouvelle partie → monde 3D → donjon → combat avec sorts → butin → équipement amélioré → sauvegarde → rechargement → gains hors ligne.
- Typecheck, tests unitaires et E2E au vert à chaque jalon.
- Aucune interaction factice : chaque bouton visible fait quelque chose de réel.
