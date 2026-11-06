# AFTERLIGHT : feuille de route

> Version 0.1 (2026-11-06). Prototype privé, sans échéance : on avance jalon par jalon. Un jalon n'est **terminé** que si tous ses critères passent : tests GDScript sans interface (« unitaires ») et Playwright sur l'export web (« E2E »), plus typecheck et lint au vert. Les résultats réels sont rapportés.
> Références : `docs/GDD.md`, `docs/GAME_BALANCE.md`, `docs/CONTENT_PIPELINE.md`, `docs/ARCHITECTURE.md` (rédigé par le lead), `DESIGN.md`.

## Vue d'ensemble

| # | Jalon | Statut | Dépend de |
|---|---|---|---|
| 1 | Fondations | **En cours** | - |
| 2 | Monde | À faire | 1 |
| 3 | Combat | À faire | 1 (simulation) ; 2 (combat dans la scène) |
| 4 | Progression | À faire | 3 |
| 5 | Idle | À faire | 3, 4 |
| 6 | Contenu | À faire | 2, 3, 4, 5 |
| 7 | Finition | À faire | 6 |
| A | Piste art (parallèle) | À faire (essai Fern d'abord) | Rien pour démarrer ; alimente 2, 3, 6, 7 |

Règle commune à tous les jalons : **aucune interaction factice**. Un bouton visible fait quelque chose de réel, ou il est absent. Un bouton désactivé affiche sa raison.

---

## Jalon 1 : Fondations (en clôture : 1.11 et l'E2E de 1.4 restent à faire)

**Objectif** : un squelette d'application jouable de bout en bout, sans contenu de jeu. Il démarre dans le navigateur, navigue entre les écrans, crée, sauvegarde et recharge une partie, et refuse les données ou les sauvegardes invalides.

**Périmètre**
- Configuration du projet Godot 4.7 : renderer Compatibility, export web, structure des dossiers et commandes `install`, `dev`, `test`, `lint`, `build` documentées dans AGENTS.md.
- Système de design : thèmes Godot Jour et Nuit avec les jetons de DESIGN.md, polices embarquées, composants de base (boutons principal, secondaire et icône ; panneau ; carte d'objet vide ; états survol, focus, appuyé, désactivé, vide, chargement, erreur).
- Coquille d'application : écran titre, chargement, réglages (audio par bus, taille du texte, réduire les animations), routage des scènes avec transitions (320 ms, coupe si « réduire les animations » est actif).
- État de jeu : modèle central (personnage, inventaire vide, lieu courant, drapeaux, horodatage), sans nœud de rendu.
- Modèles de données et chargeur : enveloppe JSON, registre d'ID, validation (règles V1 à V9 et V19 de CONTENT_PIPELINE §8 au minimum), module `game/engine/balance/`, `strings.csv` et `tr()`.
- Persistance (ARCHITECTURE § Sauvegarde) : `user://` (IndexedDB sur le web), sauvegarde JSON versionnée avec somme de contrôle, écriture atomique et copie de secours, sauvegarde automatique et manuelle, migrations, export et import en fichier, écran de récupération sans écraser une sauvegarde valide.

**Critères d'acceptation**

| # | Critère | Type |
|---|---|---|
| 1.1 | L'export web démarre dans Chromium et Firefox ; l'écran titre est visible en < 8 s sur la machine de référence, sans erreur dans la console | E2E |
| 1.2 | « Nouvelle partie » → état initial créé → retour au titre → « Continuer » restaure le même état (comparaison du hachage de l'état) | E2E |
| 1.3 | Rechargement de la page après une sauvegarde automatique → l'état est restauré | E2E |
| 1.4 | Une sauvegarde corrompue (JSON tronqué, `version` inconnue, somme de contrôle fausse) est refusée et copiée dans `user://saves/corrupt/` ; la copie de secours valide reste intacte ; l'écran de récupération propose de restaurer la copie de secours, d'exporter le fichier endommagé ou de commencer une nouvelle partie (avec confirmation) | unitaire + E2E |
| 1.5 | Une migration v1 → v2 sur une sauvegarde témoin donne l'état attendu ; une migration inconnue échoue proprement | unitaire |
| 1.6 | Un export, suivi d'un import dans un profil de navigateur vierge, restaure le même état | E2E |
| 1.7 | Chaque témoin invalide (V1-V9, V19) fait échouer la validation avec un message qui donne le fichier, l'ID et la règle ; les témoins valides passent | unitaire |
| 1.8 | Aucun texte affiché en dur : un test parcourt les scènes et vérifie que chaque `Label` et `Button` utilise une clé présente dans `strings.csv` | unitaire |
| 1.9 | Thèmes : les jetons de couleur des deux thèmes égalent DESIGN.md ; le contraste du texte est ≥ 4,5:1 (test sur les paires de jetons) | unitaire |
| 1.10 | Navigation complète au clavier sur le titre et les réglages (ordre de focus défini, Échap ferme) | E2E |
| 1.11 | Le réglage « taille du texte » à 130 % ne tronque aucun libellé du titre ni des réglages (capture comparée) | E2E |

**Sortie** : `test`, `lint` et `build` au vert ; le web s'exporte en local.

**État au 2026-11-06** (59 tests unitaires, 21 E2E desktop / mobile paysage / tablette, lint propre) :

| # | État | Preuve ou reste à faire |
|---|---|---|
| 1.1 | Fait pour Chromium | `boot.spec.ts` ; Firefox et WebKit ne sont pas installés dans l'environnement de test |
| 1.2, 1.3 | Fait | `boot.spec.ts` (nouvelle partie, sauvegarde, rechargement, Continuer) |
| 1.4 | Fait en unitaire | `test_save_store.gd`, `test_save_codec.gd` ; l'E2E de l'écran de récupération demande d'injecter un fichier abîmé dans IndexedDB : à ajouter |
| 1.5 | Fait | `test_migrations.gd` (chaîne v0 → v1 synthétique, étape manquante) |
| 1.6 | Fait | `save_transfer.spec.ts` (export, profil vierge, import) + refus d'un fichier modifié |
| 1.7 | Fait, au-delà | `test_content.gd` couvre V1-V14, V17-V19 ; V15, V16, V20 arrivent avec les quêtes et le voyage |
| 1.8 | Fait | `test_no_hardcoded_text.gd` (analyse statique + clés existantes) |
| 1.9 | Fait | `test_theme_builder.gd` (contraste ≥ 4,5:1, mêmes rôles jour / nuit) |
| 1.10 | Fait pour le titre et les réglages | `keyboard.spec.ts` |
| 1.11 | À faire | Capture à 130 % comparée |
| Réglages audio par bus | Reporté au jalon 7 | Aucun son dans le jeu pour l'instant : un réglage sans effet serait factice |
| Composants « carte d'objet », bouton icône, état de chargement | Reportés au jalon 4 | Construits avec l'inventaire, quand ils ont un contenu réel |

---

## Jalon 2 : Monde

**Objectif** : explorer à pied le Val d'Aubelin en 3D et voyager depuis la carte du monde.

**Périmètre** : scène 3D par lieu (blocs gris acceptés, puis assets de la piste A), caméra 3/4 avec amorti, déplacement (clic, ZQSD et WASD, joystick tactile), interaction (E ou appui), carte du monde (zoom, déplacement, lieux et brouillard), règles de déblocage, voyage, HUD exploration (portrait, ressources, mini-carte, suivi, barre de 5 boutons). Données : `region`, `location` et leurs conditions (V16).

| # | Critère | Type |
|---|---|---|
| 2.1 | Fern se déplace au clavier, à la souris et au toucher (émulation tactile Playwright) : après 2 s d'appui, la position a changé d'au moins 8 m | E2E |
| 2.2 | La carte s'ouvre (M ou bouton), zoome sur 2 crans et se déplace | E2E |
| 2.3 | « Voyager » vers un lieu débloqué charge la scène en ≤ 1,5 s après la fin du chargement initial | E2E |
| 2.4 | Un lieu verrouillé affiche la raison (texte de la condition) et ne permet pas de voyager | E2E |
| 2.5 | Le brouillard se lève à la visite ; l'état survit à une sauvegarde et un rechargement | E2E |
| 2.6 | Le chemin critique est vérifié : tous les lieux sont atteignables dans l'ordre des conditions (V16) ; un témoin à blocage échoue | unitaire |
| 2.7 | Les sorties de zone mènent au bon lieu et au bon point d'apparition | unitaire + E2E |
| 2.8 | Performance : ≥ 50 i/s sur desktop de référence, ≥ 30 i/s sur la tablette de référence, dans Aubelin | E2E (mesure) |
| 2.9 | Mobile paysage < 768 px : joystick à gauche, bouton menu, mini-carte réduite ; aucun élément ne sort des zones sûres | E2E (capture) |

---

## Jalon 3 : Combat

**Objectif** : le combat hybride complet de la tranche, déterministe, avec Fern, 3 archétypes, l'élite et le boss.

**Périmètre**
- Simulation pure à 20 ticks/s, RNG à graine, événements (GDD §7.1), formules de GAME_BALANCE §3 à §11.
- Kit de Fern : auto, 3 actifs (dont la Barrière), ultime et passif. Tactiques (GDD §7.4), focalisation, consommables.
- IA : machine à états partagée, profils `rusher`, `caster` et `bulwark`, élite, boss à 3 phases avec enrage.
- Statuts, éléments, réactions, barrières, interruptions.
- Rendu : combat sur place dans la scène, barres PV et mana, barre de boss avec les phases, sorts avec recharge en balayage et secondes, chiffres flottants, vitesse ×1, ×2 et ×4 (plafond par rencontre), pause tactique, victoire et défaite, journal de combat.
- Banc de simulation sans interface (GAME_BALANCE §22.1).

| # | Critère | Type |
|---|---|---|
| 3.1 | Déterminisme : même graine + mêmes entrées ⇒ même hachage du journal d'événements, sur 50 graines × 6 rencontres | unitaire |
| 3.2 | Chaque formule de GAME_BALANCE (dégâts, mitigation, critique, barrière, réactions, bouclier, statuts, mana, charge d'ultime) a un test qui reproduit son exemple chiffré au centième près | unitaire |
| 3.3 | Seuils de §22.1 atteints par le banc : normale `idle` ≥ 95 % ; élite `script_optimal` ≥ 90 % ; boss `idle` ≤ 20 % et `script_optimal` ≥ 80 % ; durées dans les cibles | unitaire (sim) |
| 3.4 | La simulation ne dépend d'aucun nœud de rendu : un test l'exécute sans scène | unitaire |
| 3.5 | Premier combat gagné sans aucune action manuelle (tactiques par défaut) | E2E |
| 3.6 | La touche 1 lance Zoltraak : `SpellCast` émis au plus 1 tick après l'entrée ; recharge visible avec les secondes restantes ; mana insuffisante ⇒ refus + raison affichée | E2E |
| 3.7 | En pause, aucun tick n'avance (le compteur de ticks ne bouge pas pendant 2 s) ; un sort mis en file part au premier tick après la reprise | E2E |
| 3.8 | ×2 et ×4 multiplient les ticks par seconde réelle ; le boss refuse ×4 | E2E |
| 3.9 | Interrompre une lanterne avec Zoltraak annule `ability.lantern_blaze` et émet `CastInterrupted` | unitaire + E2E |
| 3.10 | Le boss passe en phase 2 à 65 % et en phase 3 à 30 % (`BossPhaseChanged`) ; l'enrage a lieu à 300 s | unitaire |
| 3.11 | Défaite : retour à l'entrée du lieu, PV pleins, inventaire inchangé | E2E |
| 3.12 | Le journal de combat affiche une ligne par `DamageDealt`, `SpellCast` et `StatusApplied`, et filtre par source | E2E |
| 3.13 | Au toucher : sorts en arc à droite, appui sur un ennemi pour le focaliser ; cibles tactiles ≥ 48 px | E2E |

---

## Jalon 4 : Progression

**Objectif** : grandir après chaque combat : niveaux, butin, équipement, sorts, runes, artefacts.

**Périmètre** : XP et niveaux (plafond 20), génération du butin (rareté par source, ilvl, implicites, affixes, légendaires), inventaire (60 cases, onglets, recyclage groupé), 6 emplacements d'équipement, comparaison, amélioration (pitié, anti-rechargement), rangs de sorts et emplacements de runes, runes et fusion, artefacts (2 emplacements), or et matériaux, marchande de consommables. Écrans Personnage, Sac, Grimoire, Forge, Graveuse et Marchande.

| # | Critère | Type |
|---|---|---|
| 4.1 | Courbe d'XP : `xp_to_next` égale la table de GAME_BALANCE §12 pour L1-L19 ; gain multi-niveaux ; XP perdue au plafond et signalée | unitaire |
| 4.2 | Butin : sur 100 000 tirages à graine, les fréquences de rareté par source sont à ±0,5 point des poids ; aucun doublon d'affixe ni de `group` sur un objet | unitaire |
| 4.3 | Les valeurs d'affixe restent dans leur plage mise à l'échelle ; les légendaires tirent dans la moitié haute | unitaire |
| 4.4 | Équiper puis déséquiper rend exactement les statistiques d'origine (modificateurs par source) | unitaire |
| 4.5 | Amélioration : coûts égaux à la table ; succès garanti jusqu'à +5 ; la pitié s'ajoute puis se remet à 0 ; le même objet au même nombre de tentatives donne le même résultat après un rechargement | unitaire + E2E |
| 4.6 | Fusion : 3 runes identiques de palier n donnent 1 rune de palier n+1, avec les coûts de la table ; refus de 2 runes de conversion sur un sort | unitaire |
| 4.7 | Inventaire plein ⇒ recyclage automatique du butin d'objets + ligne dans le résumé ; rien n'est perdu en silence | unitaire + E2E |
| 4.8 | Parcours E2E : gagner un combat → objet au sol → « Équiper » → la statistique affichée change → « Améliorer » à la forge → sauvegarde → rechargement → l'état est identique | E2E |
| 4.9 | La comparaison vert/rouge est juste sur 20 paires d'objets témoins | unitaire |
| 4.10 | Tous les boutons des écrans de progression sont fonctionnels ; un bouton désactivé affiche sa raison (« Or insuffisant : 141 requis ») | E2E |

---

## Jalon 5 : Idle

**Objectif** : la progression qui continue sans le joueur, juste et compréhensible.

**Périmètre** : mode « Chasser ici » (boucle active en temps réel), choix de la chasse hors ligne (lieu ou carte), calcul hors ligne analytique (GAME_BALANCE §20), plafond de 8 h, cas de l'horloge, test de survie, écran « Pendant votre absence ».

| # | Critère | Type |
|---|---|---|
| 5.1 | L'exemple chiffré de §20.4 est reproduit exactement (N, XP, or, niveaux) | unitaire |
| 5.2 | Le calcul ne fait tourner aucun tick : un test vérifie que le compteur de ticks de la simulation ne bouge pas, et la durée d'exécution pour 8 h est < 50 ms | unitaire |
| 5.3 | Bornes : 0 s et 59 s ⇒ pas de résumé ; 8 h et 8 h + 1 s ⇒ gains identiques ; −1 h ⇒ gains nuls et horodatage conservé | unitaire |
| 5.4 | Mêmes entrées ⇒ même résumé (graine) ; une entrée différente ⇒ un tirage différent | unitaire |
| 5.5 | Une rencontre élite ou boss, ou jamais vaincue, ne peut pas être choisie ; le bouton affiche la raison | unitaire + E2E |
| 5.6 | Le `clear_time` analytique est à ≤ 15 % du p50 simulé pour chaque rencontre éligible de la tranche | unitaire (sim) |
| 5.7 | E2E avec horloge simulée : sauvegarde → avancer de 3 h → rechargement → résumé affiché avec les bonnes valeurs → « Récupérer » → ressources créditées une seule fois (un second rechargement ne recrédite rien) | E2E |
| 5.8 | « Chasser ici » rejoue la rencontre en boucle, s'arrête à la défaite, et chaque victoire donne son butin | E2E |

---

## Jalon 6 : Contenu

**Objectif** : la tranche verticale complète et jouable de bout en bout.

**Périmètre** : les 3 lieux de terrain et Aubelin avec PNJ (forge, graveuse, marchande, tableau), le donjon de 7 salles, toutes les rencontres et tables de butin, 7 quêtes, contrats du jour, bestiaire, 6 découvertes, dialogues originaux, introduction et épilogue. Toute la validation (V1-V20).

| # | Critère | Type |
|---|---|---|
| 6.1 | La validation complète passe sur les données réelles ; chaque témoin V1-V20 échoue | unitaire |
| 6.2 | Toutes les entrées canon ont un `canon_note` relu ; aucune ligne de dialogue n'est marquée comme citation | unitaire + relecture du propriétaire |
| 6.3 | Parcours complet E2E (outils de debug autorisés : gain d'XP accéléré, vitesse ×4 hors boss) : nouvelle partie → quêtes 1-3 → donjon → boss vaincu → cloche → sauvegarde → rechargement → gains hors ligne | E2E |
| 6.4 | Nouvelle partie → `EncounterStarted` ≤ 180 s en entrées scriptées « humaines » (intro lue), ≤ 60 s en passant l'intro | E2E |
| 6.5 | Le bestiaire se débloque à 1, 5 et 25 victoires ; les découvertes lèvent le brouillard et s'affichent par lieu | unitaire + E2E |
| 6.6 | Quêtes : chaque objectif avance avec le bon événement ; les états survivent à un rechargement en cours de quête | unitaire + E2E |
| 6.7 | Seuils d'équilibrage (§22.1) toujours tenus avec les données finales | unitaire (sim) |
| 6.8 | Les tests de jeu T1 à T8 du GDD sont menés ; les observations sont notées et les `[H]` concernés passent à `[V]` ou sont corrigés | test de jeu |

---

## Jalon 7 : Finition

**Objectif** : une tranche qui se ressent premium.

**Périmètre** : audio (musique d'ambiance originale par lieu, effets par bus, sous-titres des sons porteurs d'information), effets visuels des sorts (< 200 particules), game feel (GDD §14), passage jour → nuit en donjon, accessibilité (remappage, manette, réduire les animations, taille du texte), adaptation tablette et mobile, performance et temps de chargement, écrans vides, d'erreur et de chargement partout.

| # | Critère | Type |
|---|---|---|
| 7.1 | Performance : ≥ 55 i/s sur desktop de référence pendant le boss ; ≥ 30 i/s sur la tablette de référence ; mémoire WebGL < 1 Go | E2E (mesure) |
| 7.2 | Taille de l'export ≤ cible fixée dans ARCHITECTURE ; premier écran interactif < 10 s en réseau simulé à 20 Mb/s | E2E |
| 7.3 | « Réduire les animations » coupe les secousses, remplace les fondus par des coupes et divise les particules par 2 (vérifié par drapeaux de rendu) | unitaire + E2E |
| 7.4 | Arrêt sur image : la simulation ne consomme aucun tick pendant l'arrêt (déterminisme 3.1 toujours vert) ; désactivé à ×4 | unitaire |
| 7.5 | Chaque action du joueur a un retour en ≤ 120 ms (bouton, son ou effet visuel) | E2E |
| 7.6 | Remappage d'une touche de sort ; il survit au rechargement | E2E |
| 7.7 | Captures de référence desktop, tablette et mobile pour chaque écran du GDD §17, sans débordement ni troncature à 130 % | E2E (capture) |
| 7.8 | Aucun son, image ou texte de l'œuvre : audit des assets et de leurs sources | relecture |

---

## Piste A : pipeline art (en parallèle)

**Objectif** : des assets 3D cel-shading conformes à DESIGN.md, produits par concept → fal.ai → Blender 5.2 → GLB → Godot. Procédure : `docs/CONTENT_PIPELINE.md` §9. **A1 : essai fait (Fern v0, prototype), à refaire avec les améliorations §9.2 avant validation.**

| Étape | Contenu | Critères d'acceptation | Alimente |
|---|---|---|---|
| A1 Essai Fern | Fiche de description écrite (originale) → concept → modèle généré → retopologie, UV, squelette → animations `idle`, `run`, `cast`, `cast_channel`, `hit`, `death`, `victory` → GLB → shader cel-shading 2 bandes + contour en coque inversée | 15-25 k triangles ; contour ~1,5 px à 1080p ; lisible de haut à la caméra 3/4 (test de silhouette) ; boucles sans saut ; import Godot sans erreur ; 60 i/s dans une scène de test web ; validation du propriétaire | J2 (exploration), J3 (combat) |
| A2 Ennemis | Loup des brumes (+ variante alpha par échelle et teinte), Lanterne errante, Sentinelle de pierre, Morvaine | 8-15 k triangles (boss 25-40 k) ; animations `idle`, `run`, `attack`, `cast`, `hit`, `death` (+ phases du boss) ; télégraphes lisibles ; validation du propriétaire | J3, J6 |
| A3 Kits d'environnement | Aubelin (maisons, place, forge), Bois (bouleaux, rochers, sous-bois), Tourbière (eaux, roseaux, lanternes), Ruines (murs, tour), Cloître (intérieur nuit, horloge-cloche) | 0,5-3 k triangles par objet ; textures peintes 1K/2K ; variations par échelle, rotation et teinte ; **aucun kit low-poly générique** ; budget de draw calls fixé dans ARCHITECTURE et tenu | J2, J6, J7 |
| A4 Interface et icônes | Jeu d'icônes maison au trait, cadres de rareté, cercles runiques | Famille cohérente au trait de 1,5 px ; jamais d'emoji ; rareté portée aussi par le motif | J1 (base), J4, J7 |

Dépendances : A1 doit être validée avant A2 et A3, car elle fixe le shader, l'échelle et le budget. En attendant, les jalons 2 et 3 avancent avec des blocs gris et des silhouettes de substitution, refusées en `release` (CONTENT_PIPELINE §7.1).
