# DESIGN.md

> Direction visuelle d'AFTERLIGHT. Lue par les agents de design, de rendu et d'assets. Cibles visuelles validées : `art/concepts/directions/` (A = jour, B = nuit). Direction retenue : **hybride jour / nuit**.

## Principes

1. **Une identité, deux éclairages.** Exploration, village et menus : *Lumière d'après-midi* (jour, ivoire et or). Donjons et combats de nuit : *Crépuscule de mana* (ardoise et nacre). Les formes, les icônes, les couleurs de rareté et l'améthyste de Fern restent identiques.
2. **Le monde d'abord.** Le HUD occupe les coins et le bas ; le centre de l'écran reste au personnage et au décor. Les panneaux s'ouvrent au-dessus du monde, jamais à sa place.
3. **Contemplatif, pas criard.** Lumière douce, couleurs naturelles, magie lumineuse mais contenue. Pas de néon, pas de dégradés décoratifs, pas de verre dépoli.
4. **Lisible en mouvement.** Silhouettes nettes, contours encrés, chiffres alignés, contrastes francs sur ce qui demande une décision (PV, mana, recharge, cible).
5. **Original.** Aucun visuel, logo, icône ou musique de l'œuvre ni d'un autre jeu. Les références servent l'ambiance, pas la copie.

## Direction 3D

| Élément | Règle |
|---|---|
| Caméra exploration | 3/4 plongeante, ~50° de tangage, focale ~35 mm équivalent, suit le héros avec amorti ; zoom limité (2 crans) |
| Caméra combat | même angle, plus large ; le groupe à gauche, les ennemis à droite ; légère secousse sur les coups critiques uniquement |
| Rendu | renderer Compatibility (WebGL 2). Cel-shading 2 bandes (lumière / ombre) + bande de rebord fine ; ombre teintée (jamais grise) |
| Contours | coque inversée (inverted hull), épaisseur ~1,5 px à 1080p, encre brun-violet `#2a2233` (jour) ou bleu nuit `#0d1220` (nuit) |
| Personnages | proportions anime ~6,5 têtes ; visages simples, yeux lisibles de haut ; 15-25 k triangles héros, 8-15 k ennemis, 25-40 k boss |
| Décors | textures peintes à la main (1K objets, 2K terrain), variations par échelle / rotation / teinte plutôt que de nouveaux modèles ; 0,5-3 k triangles par objet |
| Lumière jour | soleil chaud bas (`#ffe2b0`), ciel lavande-bleu, ombres longues teintées bleu-vert, pétales ou poussière en suspension |
| Lumière nuit | lune froide (`#bcd0ff`), ambiance `#1a2433`, sources chaudes ponctuelles (fenêtres, lanternes), particules de mana pâles |
| Magie | cercles runiques blanc nacré (jamais de pentagramme), rayons fins et nets, particules contrôlées (< 200 par effet) |
| Passage jour → nuit | entrée en donjon : fondu de 600 ms vers la palette nuit, le HUD bascule de thème ; instantané si « réduire les animations » est actif |

## Couleurs de l'interface

Tokens du thème Godot (`game/ui/theme/`). Deux thèmes, mêmes noms de rôles.

| Rôle | Jour (A) | Nuit (B) |
|---|---|---|
| `surface` (panneaux) | `#f3ead6` | `#1c2431` |
| `surface_alt` (cartes, listes) | `#e6d9bb` | `#141b26` |
| `ink` (texte) | `#2b2620` | `#e7ebf2` |
| `ink_muted` | `#6b6152` | `#93a0b7` |
| `line` (filets, cadres) | `#b39253` (or) | `#c9d6f0` (nacre, 60 %) |
| `accent` (action principale, Fern) | `#6b4f8f` | `#a58ad6` |
| `mana` | `#3f7f9a` | `#a9c4ff` |
| `focus` | `#c79a3c` | `#a9c4ff` |
| `scrim` (fond derrière un panneau) | `#2b2620` à 45 % | `#05080d` à 60 % |

| États et jeu | Valeur (les deux thèmes) |
|---|---|
| `hp` | `#7fae6e` → `#d0a33a` (< 50 %) → `#c4553f` (< 25 %) |
| `danger` / `success` / `warning` | `#c4553f` / `#6f9f5e` / `#d0a33a` |
| Dégâts normaux / critiques / soins | blanc `#ffffff` / or `#f2c14e` / vert `#9ee08a` |
| Rareté commune / peu commune / rare / épique / légendaire | `#9a968c` / `#6f9f5e` / `#4f84b8` / `#8a66bf` / `#c79a3c` |

Contraste minimal 4,5:1 pour le texte courant, 3:1 pour les icônes et grands chiffres. La rareté n'est jamais portée par la couleur seule : libellé et motif de cadre (simple, double, orné).

## Typographie

- **Titres et noms** : Cormorant Garamond SemiBold (OFL). Titres d'écran, noms de lieux, de boss, d'objets légendaires.
- **Texte et chiffres** : Alegreya Sans Regular / Medium / Bold (OFL), chiffres tabulaires (`tnum`, `lnum`) pour PV, mana, dégâts, prix.
- **Échelle (à 1080p)** : 40 / 28 / 22 / 18 / 16 / 13. Corps 16 minimum sur desktop, 15 sur mobile ; jamais sous 12.
- Dégâts flottants : Alegreya Sans Bold 28 (critique 36), contour 3 px couleur `ink` nuit.
- Polices embarquées dans `assets/fonts/` ; réglage « taille du texte » (90 / 100 / 115 / 130 %).

## Espacements, rayons, ombres

- **Grille** : 4 px. Échelle : 4, 8, 12, 16, 24, 32, 48, 64.
- **Marges d'écran** : 24 px desktop, 16 px mobile, plus les zones sûres (encoches).
- **Rayons** : 3 px panneaux et boutons, 50 % boutons ronds (sorts, portrait, mini-carte). Pas de grands arrondis.
- **Cadres** : filet 1 px `line`, coins ornés discrets (petit losange) uniquement sur les panneaux principaux.
- **Ombres** : une seule, douce, sous les panneaux flottants (`0 8 24`, noir 25 %). Pas d'ombre sur les éléments posés.
- **Texture** : grain papier très léger (jour) ou bruit fin (nuit) à 4-6 % d'opacité dans les panneaux, jamais sur le texte.

## Composants

- **HUD exploration** : portrait rond + niveau (haut gauche) ; mini-carte ronde à cadre fin + suivi de quête sur une ligne (haut droite) ; barre de 5 boutons-icônes (Sac, Sorts, Carte, Journal, Réglages) en bas au centre ; ressources (or, matériaux) en pastilles sous le portrait.
- **HUD combat** : barres PV / mana fines sous chaque allié ; barres ennemies au-dessus des têtes ; barre du boss en haut au centre avec phases marquées ; 3 sorts ronds + 1 ultime plus grand en bas au centre, recharge en balayage radial avec secondes restantes ; vitesse ×1 / ×2 / ×4 et pause en haut à droite ; journal de combat repliable.
- **Boutons** : principal (fond `accent`, texte clair), secondaire (filet `line`, fond transparent), icône (rond 48 px). Libellé = verbe d'action (« Voyager », « Améliorer », « Équiper »).
- **Carte d'objet** : icône sur cadre de rareté, nom en Cormorant, statistiques en Alegreya tabulaire, comparaison avec l'équipé en vert / rouge + flèche.
- **Panneau** : titre, contenu défilant, actions en pied ; fermeture par Échap, bouton retour ou geste.
- **Icônes** : jeu maison au trait (1,5 px à 24 px), même famille partout. Jamais d'emoji.
- **États obligatoires** : survol (filet `focus` + léger éclaircissement), focus clavier / manette (anneau `focus` 2 px), appuyé (assombri 8 %), désactivé (50 % + raison au survol), vide (texte d'aide + action), chargement (cercle runique qui tourne), erreur (message clair + action de reprise).

## Adaptation aux écrans

- **Desktop (≥ 1280 px)** : HUD complet, panneaux latéraux (inventaire à droite, détail au centre), raccourcis clavier affichés (1-3, R pour l'ultime, Espace pour pause).
- **Tablette (768-1279 px)** : panneaux en surimpression pleine hauteur, cibles tactiles 48 px, mini-carte réduite.
- **Mobile (< 768 px, paysage prioritaire)** : joystick virtuel à gauche, sorts en arc à droite à portée du pouce, navigation regroupée dans un bouton menu, inventaire en grille 4 colonnes et fiche en feuille du bas. Pas de survol requis pour une information.

## Mouvement

- Durées : 120 ms (survol, appui), 200 ms (ouverture de panneau), 320 ms (changement d'écran), 600 ms (jour → nuit).
- Courbes : sortie douce (`ease_out` cubique) à l'ouverture, entrée douce à la fermeture. Pas de rebond sauf récompense légendaire.
- Coup : arrêt sur image 40-60 ms sur critique et coup de boss ; secousse caméra seulement sur critique, boss et ultime.
- `Réduire les animations` (réglage, activé si le système le demande sur le web) : fondus remplacés par des coupes, pas de secousse, particules réduites de moitié.

## Accessibilité

- Navigation complète au clavier et à la manette (ordre de focus défini dans chaque panneau), touches remappables.
- Taille du texte réglable, contraste minimal respecté dans les deux thèmes, rareté et éléments jamais codés par la couleur seule.
- Sous-titres et textes pour tout son porteur d'information ; volume par bus (musique, effets, ambiance).
- Pause possible à tout moment en combat ; vitesse réglable.
