# AFTERLIGHT : document de game design

> Version 0.1 (2026-11-06). Fan-game privé, non commercial, dans l'univers de *Frieren*. Godot 4.7, export web.
> Les chiffres sont dans `docs/GAME_BALANCE.md`, les données dans `docs/CONTENT_PIPELINE.md` et les jalons dans `docs/ROADMAP.md`.
> **Statut des règles** : `[H]` = hypothèse pas encore jouée, `[V]` = validée par un test de jeu (date + observation). Pour l'instant, tout est `[H]`.

## 1. Pitch

Fern voyage seule à travers une vallée oubliée, où une cloche ne sonne plus depuis quatre-vingts ans. Le joueur explore à pied un monde 3D en vue 3/4. Il combat en temps réel avec une magie offensive précise et rapide, ramasse du butin et façonne son grimoire avec des runes. Quand il ferme le jeu, Fern continue de chasser : au retour, le temps a passé et elle a progressé.

## 2. Piliers

| # | Pilier | Ce qu'il impose | Ce qu'il écarte |
|---|---|---|---|
| P1 | **Magie précise** | Peu de sorts, chacun nettement lisible ; Zoltraak est rapide et frappe fort ; chaque décision de lancer compte (mana, recharge, interruption) | Spam de boutons, 20 sorts, effets confus |
| P2 | **Le temps qui passe** | Progression hors ligne au cœur du jeu, récit mélancolique (souvenirs, lieux anciens), rythme posé hors combat | Minuteurs agressifs, notifications culpabilisantes, énergie |
| P3 | **Un monde à parcourir** | Exploration à pied, brouillard, découvertes, voyage depuis la carte | Menus de sélection de niveau à la place du monde |
| P4 | **Grandir par le butin** | Équipement à affixes, runes qui changent le comportement des sorts, chiffres qui montent visiblement | Clicker abstrait, progression uniquement numérique sans choix |

Toute fonctionnalité doit servir au moins un pilier. Sinon, elle va dans la section 18 (hors périmètre).

## 3. Fantasme du joueur

« Je suis une mage d'une précision redoutable. J'observe, je choisis le bon sort au bon moment et je vois mon grimoire devenir plus fort, même quand je ne joue pas. »

## 4. Boucles de jeu

| Échelle | Action | Retour | Récompense |
|---|---|---|---|
| **Secondes** (combat) | Lancer un sort, changer de cible, poser la Barrière avant un gros coup, interrompre une incantation | Rayon, chiffre flottant, arrêt sur image au critique, barre de recharge, icône de statut | Ennemi abattu, charge d'ultime, mana récupérée |
| **Minutes** (rencontre, lieu) | Enchaîner 3 à 6 rencontres, explorer un lieu, ouvrir un coffre, rendre une quête | Butin au sol, résumé de victoire, brouillard qui se lève | Objets, or, matériaux, XP, lieu suivant débloqué |
| **Session** (15-60 min) | Améliorer l'équipement à la forge, fusionner des runes, battre l'élite ou le boss, choisir la rencontre à chasser | Comparaison d'objets vert/rouge, puissance affichée, nouveau palier de sort | Saut de puissance, nouvelle zone, artefact |
| **Jours** (idle) | Choisir la chasse hors ligne, fermer le jeu, revenir | Écran « Pendant votre absence » | XP, or, matériaux, objets (8 h max) ; contrats du jour `[H]` |

**Boucle idle détaillée** : dans un lieu, le joueur bat une rencontre une première fois → il active « Chasser ici » (la rencontre se rejoue en boucle dans la scène, en temps réel) → cette rencontre devient la **chasse hors ligne** → à la fermeture, l'horodatage est sauvegardé → au retour, les gains sont calculés analytiquement (voir `GAME_BALANCE.md` §20) → écran résumé → le joueur dépense ses gains → il pousse une rencontre plus difficile, qui devient la nouvelle chasse.

## 5. Monde et tranche verticale

### 5.1 Carte du monde

- Une carte peinte par région, avec zoom (2 crans) et déplacement (souris, clavier, glisser au doigt).
- Les **lieux** sont des points sur la carte, dans trois états : caché (sous le brouillard), révélé (visible mais verrouillé, avec la raison au survol ou à l'appui : « Terminez *Lueurs sur la tourbière* »), débloqué.
- Le brouillard se lève par lieu : en visitant le lieu, en terminant une quête ou par une découverte.
- **Voyager** : depuis la carte, vers tout lieu débloqué. Transition ≤ 1,5 s (fondu + chargement), sans coût. Impossible pendant un combat.
- Dans un lieu, le joueur se déplace à pied. Les sorties de zone mènent aux lieux adjacents.

### 5.2 Région de départ : Val d'Aubelin (`region.aubelin_vale`, original)

Vallée d'automne, champs dorés, forêts de bouleaux, ruines d'un ancien poste de guet. Au fond se dresse un cloître dont l'horloge-cloche s'est tue. Thème : un village qui attend un son qu'il n'entend plus.

| Lieu | ID | Type | Niveaux | Ennemis | Rôle de design | Déblocage |
|---|---|---|---|---|---|---|
| Aubelin | `location.aubelin` | hub | - | aucun | Repos, forge, graveuse de runes, tableau des contrats, marchande | Départ |
| Bois des Murmures | `location.whispering_wood` | terrain | 1-3 | Loup des brumes | **Introduire** le combat auto, Zoltraak, la Barrière | Départ |
| Tourbière aux Lanternes | `location.lantern_mire` | terrain | 4-6 | Lanterne errante, loups | **Introduire** l'interruption et les éléments (runes) | `quest.main_01` terminée |
| Ruines du Guet | `location.watch_ruins` | terrain + entrée de donjon | 7-9 | Sentinelle de pierre, mélange | **Introduire** les barrières ennemies et les gros coups télégraphiés | `quest.main_02` terminée |
| Cloître du Cadran Éteint | `dungeon.silent_dial_cloister` | donjon | 10-12 | tous + élite + boss | **Tester puis combiner** tout le reste | `quest.main_03` + clé du cloître |

Chaque terrain contient de 4 à 6 rencontres visibles dans le décor (meutes immobiles ou en patrouille), 1 ou 2 coffres et 2 découvertes. Les rencontres réapparaissent 60 s après la sortie du lieu, ou immédiatement en mode « Chasser ici ».

### 5.3 Donjon : Cloître du Cadran Éteint

Parcours linéaire, sans retour arrière obligatoire. La lumière passe en palette nuit à l'entrée (DESIGN.md). Courbe en dents de scie :

| # | Salle | Contenu | Intensité | Mécanique |
|---|---|---|---|---|
| 1 | Vestibule | `encounter.cloister_vestibule` : 2 sentinelles + 1 loup | 0,4 | Barrière ennemie (rappel) |
| 2 | Galerie des cloches | `encounter.cloister_gallery` : 3 lanternes + 1 sentinelle | 0,6 | Interruption sous pression |
| 3 | Fontaine | repos : soigne 30 % des PV, lore | 0,1 | - |
| 4 | Cour du préau | `encounter.cloister_courtyard` : 2 loups, 1 lanterne, 1 sentinelle | 0,7 | Combinaison, choix de cible |
| 5 | Chenil | `encounter.cloister_alpha` : élite Loup alpha | 0,8 | Interrompre le Hurlement |
| 6 | Feu de camp | point de reprise : soin complet, sauvegarde, réglage des tactiques | 0,1 | - |
| 7 | Salle du Cadran | `encounter.cloister_boss` : Morvaine | 1,0 | Tout (voir §9.3) |

Défaite dans le donjon : retour au dernier point de reprise (entrée ou feu de camp), sans perte d'objets. Les salles déjà nettoyées le restent jusqu'à la sortie du donjon.

### 5.4 Repères visuels (niveaux)

- Le chemin principal est un sentier plus clair. Des lanternes chaudes marquent les portes de sortie et les feuilles mortes s'accumulent le long des bords.
- Points de repère visibles de loin : le clocher du cloître depuis tout le val, un grand bouleau mort au centre du Bois, la tour effondrée des Ruines.
- Rencontre visible avant contact : un cercle nacré au sol sous la meute, avec le niveau affiché au survol. Contact (entrée dans un rayon de 4 m) → le combat démarre sur place, l'arène est bornée par un anneau de brume.

## 6. Fern (`character.fern`, canon)

Ce qui est canon (et sûr) : Fern est une mage humaine, apprentie de Frieren. Elle se distingue par une magie offensive rapide et précise, centrée sur Zoltraak, et sait dissimuler son mana. **Tout le reste** (valeurs, noms des autres sorts, passif) est une interprétation de jeu, marquée `original` dans les données.

| Emplacement | Sort | ID | Origine | Comportement |
|---|---|---|---|---|
| Attaque auto | Trait de mana | `spell.mana_bolt` | original | Projectile arcane sur la cible courante, toutes les 1,2 s. Rend un peu de mana à chaque coup |
| Actif 1 (touche 1) | **Zoltraak** | `spell.zoltraak` | canon (nom) | Rayon arcane rapide (incantation 0,3 s), gros dégâts sur une cible. **Interrompt** les incantations marquées « interruptible ». Inflige ×2 aux barrières |
| Actif 2 (touche 2) | Salve de mana | `spell.mana_volley` | original | 5 projectiles répartis sur jusqu'à 5 ennemis à 10 m, en priorité sur la cible focalisée. Outil contre les groupes |
| Actif 3, défensif (touche 3) | Barrière défensive | `spell.defensive_barrier` | original (le concept de magie défensive existe dans l'œuvre, ce nom est générique) | Instantané, hors temps de recharge global. Bouclier de 4 s, retire 1 altération. Réponse aux gros coups télégraphiés |
| Ultime (touche R) | Lumière d'après | `spell.afterlight` | original | Canalisation de 2 s : 12 rayons tombent sur les ennemis (50 % sur la cible focalisée). Demande 100 de charge |
| Passif | Mana voilé | `passive.veiled_mana` | original (inspiré de la dissimulation du mana, canon) | Après 4 s sans lancer de sort actif, le prochain actif inflige +30 %. En exploration, le rayon d'aggro des ennemis est réduit de 30 % |

Déblocage du kit : Zoltraak au niveau 1, Barrière au niveau 2, Salve au niveau 3, Lumière d'après au niveau 5 (scène de quête), emplacements de runes au niveau 4. Chaque sort est introduit seul, puis testé dans la rencontre suivante.

Les ressources : la **mana** se dépense, se régénère et revient avec les attaques auto (voir `GAME_BALANCE.md` §6). La **charge d'ultime** monte avec les attaques auto, les sorts lancés et les dégâts subis. Elle persiste entre les rencontres de la session.

## 7. Combat

### 7.1 Principes

- **Temps réel hybride, dans la scène 3D.** Le combat démarre là où la meute a été touchée. Pas d'écran séparé.
- **Simulation pure et déterministe** : pas fixe de 20 ticks/s, RNG à graine, logique sans nœud de rendu. Le rendu écoute les événements et interpole. Même graine et mêmes entrées → même journal d'événements (test).
- **Événements** (convention snake_case de `docs/ARCHITECTURE.md` ; ce document les cite aussi en PascalCase, par exemple `EncounterStarted` = `encounter_started`) : `encounter_started`, `attack_started`, `spell_cast`, `cast_interrupted`, `damage_dealt`, `shield_applied`, `character_healed`, `status_applied`, `status_expired`, `enemy_defeated`, `character_defeated`, `boss_phase_changed`, `encounter_completed`, `loot_dropped`. Ceux qui ne figurent pas encore dans ARCHITECTURE sont à ajouter par le lead.

### 7.2 Ce qui est automatique et ce que fait le joueur

| Automatique (IA du personnage) | Joueur |
|---|---|
| Choisir la cible selon la priorité de ciblage | Focaliser une cible (clic ou appui sur un ennemi : anneau or sous lui) jusqu'à sa mort ou une nouvelle sélection |
| Se placer à portée, sortir d'une zone télégraphiée si c'est atteignable | Lancer Zoltraak, Salve, Barrière, l'ultime (touches 1, 2, 3, R ou boutons) |
| Attaques auto, génération de mana et de charge | Utiliser un consommable (touches 4 et 5) |
| Lancer les sorts réglés sur « Auto » ou « Auto si… » | Changer les tactiques (pendant la pause aussi) |
| | Vitesse ×1 / ×2 / ×4, pause (Espace) |

**Pause tactique** : en pause, le joueur peut sélectionner une cible et mettre un sort en file. Ils partent au premier tick après la reprise.

**Vitesse** : ×4 est interdit pendant un boss (plafond ×2), sinon les télégraphes deviennent illisibles. Le plafond est défini par rencontre (`speed_cap`).

### 7.3 Positions du groupe

- 4 emplacements en formation 2 × 2 : avant (1, 2) et arrière (3, 4). Seul Fern occupe un emplacement dans la tranche. Par défaut, elle est à l'emplacement 3.
- Avant : +15 % de défense, +20 % de charge d'ultime gagnée sur les dégâts subis. Arrière : position de départ à 4 m de plus des ennemis, donc les ennemis de mêlée arrivent plus tard.
- Les ennemis de mêlée visent l'allié le plus proche. Les règles de menace multi-personnages sont hors périmètre (§18).

### 7.4 Tactiques (priorités de combat)

| Réglage | Valeurs | Par défaut |
|---|---|---|
| Ciblage | Plus proche / PV les plus bas / Élites et boss d'abord / Lanceurs d'abord | Plus proche |
| Zoltraak | Manuel / Auto / Auto si élite ou boss / Auto pour interrompre | Auto pour interrompre |
| Salve de mana | Manuel / Auto / Auto si ≥ 3 ennemis | Auto si ≥ 3 ennemis |
| Barrière défensive | Manuel / Auto si PV < X % (X : 30-70, pas de 10) / Auto avant un coup télégraphé | Auto si PV < 50 % |
| Lumière d'après | Manuel / Auto dès que pleine | Manuel |
| Réserve de mana | 0-50 % (pas de 10) : les sorts auto ne descendent pas sous ce seuil | 20 % |

L'IA auto tient compte de ces réglages et jamais d'un savoir caché. Un joueur qui ne touche à rien gagne les rencontres normales de son niveau. L'élite et le boss demandent des actions manuelles ou des tactiques bien réglées `[H]`.

### 7.5 Fin de combat

- **Victoire** : tous les ennemis vaincus → bandeau « Victoire » (1,2 s), butin projeté au sol puis ramassé automatiquement après 0,8 s, résumé repliable (XP, or, objets). Hors donjon, les PV et la mana remontent en 2 à 5 s.
- **Défaite** : PV de Fern à 0 → bandeau « Défaite », conseil contextuel (« Les lanternes résistent au feu : essayez une rune de givre »), retour à l'entrée du lieu, PV pleins. **Aucune perte**. En mode « Chasser ici », une défaite arrête la boucle.
- **Journal de combat** : panneau repliable qui liste les événements en clair (« Zoltraak inflige 412 à Sentinelle de pierre (critique) »). On peut le filtrer par source.

## 8. Éléments et statuts

Quatre éléments. Fern est arcane par défaut. Les runes de conversion (§10.4) changent l'élément d'un sort.

| Élément | ID | Statut appliqué | Particularité |
|---|---|---|---|
| Arcane | `arcane` | aucun | ×2 contre les barrières ennemies |
| Feu | `fire` | Brûlure (dégâts sur la durée, se cumule) | - |
| Givre | `frost` | Refroidi (ralentit, 3 cumuls → Gelé) | - |
| Foudre | `lightning` | Choc (le prochain coup subi fait plus mal) | - |

**Affinités ennemies** : faible (×1,5), neutre (×1), résistant (×0,6). Elles sont affichées dans le bestiaire dès la 5e victoire contre l'ennemi, et dans l'infobulle de l'ennemi en combat.

**Réactions** (tableau complet de l'interaction) :

| Coup reçu → / état de la cible ↓ | Arcane | Feu | Givre | Foudre |
|---|---|---|---|---|
| Barrière active | ×2 sur la barrière | ×1 | ×1 | ×1 |
| Gelé | - | **Fonte** : ×1,5, retire Gelé | - | - |
| Brûlé | - | ajoute un cumul | **Extinction** : retire la brûlure, pas de bonus | **Surcharge** : explosion de zone, retire 1 cumul |
| Choc | consomme le Choc (+15 %) | idem | idem | rafraîchit le Choc |

Statuts de la tranche : `status.burn` (Brûlure), `status.chill` (Refroidi), `status.frozen` (Gelé), `status.shock` (Choc), `status.weaken` (Affaibli), `status.shield` (Bouclier), `status.stun` (Étourdi, après une interruption), `status.haste_buff` (Frénésie, buff ennemi). Durées et cumuls dans `GAME_BALANCE.md` §9. Les boss subissent les contrôles à 50 % de leur durée et ne peuvent pas être gelés.

Chaque statut a une icône au-dessus de la barre de PV avec son nombre de cumuls. Son effet n'est jamais porté par la seule couleur (pictogramme + forme).

## 9. Ennemis

### 9.1 Archétypes

L'IA repose sur une machine à états partagée : `Idle/Patrouille` → `Aggro` (rayon) → `Approche` → `Attaque` ↔ `Capacité` (télégraphe → exécution → récupération) → `Mort`. Seuls les états changent d'un archétype à l'autre.

| Ennemi | ID | Origine | Archétype | Comportement | Capacité lisible | Réponse attendue |
|---|---|---|---|---|---|---|
| Loup des brumes | `enemy.mist_wolf` | original | Rapide en mêlée (`rusher`) | Meute de 2 à 3, contourne pour venir au contact, vise l'allié le plus proche | **Bond** : ligne rouge au sol pendant 0,6 s, puis saut à 1,8× | Barrière si les PV sont bas, Salve sur la meute |
| Lanterne errante | `enemy.wandering_lantern` | original | Lanceur à distance (`caster`) | Garde 8-10 m de distance et recule si un allié s'approche à moins de 4 m. Projectile de feu (Brûlure) | **Embrasement** : canalisation de 2 s, anneau nacré + icône, interruptible. Si elle n'est pas interrompue, zone de feu de 3 m pendant 4 s | Interrompre avec Zoltraak ; convertir en givre (faiblesse) |
| Sentinelle de pierre | `enemy.stone_sentinel` | original | Rempart (`bulwark`) | Lente, très résistante. **Barrière** de 25 % des PV, qui se régénère après 8 s sans dégâts arcane | **Fracas** : cercle de 3 m qui se remplit en 1,2 s, 2,4× | Arcane pour briser la barrière ; foudre (faiblesse) ; l'IA de Fern sort du cercle si elle le peut |

Règles des télégraphes : 0,6 s minimum à ×1. Couleur `danger` + contour + motif (hachures). Les incantations interruptibles portent toujours l'anneau nacré, celles qui ne le sont pas un anneau plein sombre.

### 9.2 Élite : Loup alpha des brumes (`enemy.mist_wolf_alpha`, original)

- Gros loup aux yeux pâles. Il arrive seul et appelle des renforts.
- **Hurlement** (à 70 % et à 35 % des PV) : canalisation de 1,5 s, interruptible. S'il n'est pas interrompu, il fait apparaître 2 loups des brumes et donne Frénésie (+25 % de vitesse d'attaque, 8 s) à toute la meute.
- **Bonds en chaîne** : trois bonds successifs télégraphiés (0,8 s chacun) toutes les 14 s.
- **Ce qu'il enseigne** : l'interruption sous pression, après son introduction tranquille contre les lanternes.

### 9.3 Boss : Morvaine, Tisseuse de cendres (`enemy.morvaine`, original ; race : démon, `lore.demons` canon)

Une démone installée dans le cloître, qui a figé la cloche pour que plus personne ne vienne. Elle parle peu et ment avec douceur. C'est un trait général des démons dans l'œuvre ; ses répliques sont toutes originales.

| Phase | PV | Capacités | Ce que le joueur doit faire |
|---|---|---|---|
| 1. Le fil | 100-65 % | **Trait de cendre** (distance, toutes les 2,5 s). **Lanternes liées** : invoque 2 lanternes toutes les 30 s (4 au plus). Chaque lanterne vivante lui donne −15 % de dégâts subis (lien visible) | Changer de cible pour abattre les lanternes (tactique « Lanceurs d'abord » ou focalisation) |
| 2. Le voile | 65-30 % | **Voile de mana** : barrière de 15 % des PV max, qui revient après 10 s sans dégâts arcane. **Parole trompeuse** : canalisation de 2 s, interruptible, applique Affaibli (−30 % de puissance, 8 s). **Sceau de cendre** : incantation de 3 s, non interruptible, très gros coup toutes les 25 s | Zoltraak pour la barrière et l'interruption, Barrière défensive au Sceau |
| 3. L'heure creuse | < 30 % | Plus de voile. +30 % de hâte, Sceau toutes les 15 s, Trait toutes les 1,9 s | Course aux dégâts : ultime, gestion de la mana |

- **Changement de phase** : événement `BossPhaseChanged`, ralenti visuel de 400 ms, barre de boss marquée aux seuils de 65 % et 30 %, ligne de dialogue courte (sous-titrée).
- **Enrage dur** à 300 s : *Cendre totale*, coup mortel. Le combat dure donc au maximum 5 minutes (cible de 2,5 à 3,5 minutes).
- **Butin** : premier kill garanti épique ou mieux + l'artefact Cloche de cendre (§10.5). Le boss est exclu de la chasse hors ligne.
- **Récit** : à sa défaite, la cloche sonne. Une vieille villageoise d'Aubelin reconnaît le son entendu dans son enfance (épilogue original).

## 10. Progression

### 10.1 Niveaux

- Niveau maximum de la tranche : **20**. Courbe rapide au début, lente ensuite (`GAME_BALANCE.md` §12).
- Chaque niveau augmente les PV, la mana, la puissance et la défense. Pas de points à répartir dans la tranche : les choix de build passent par l'équipement, les runes et les artefacts.
- L'XP vient des ennemis, des quêtes, des découvertes et des premières victoires. Elle est pénalisée contre les ennemis de 3 niveaux ou plus en dessous.

### 10.2 Équipement

| Emplacement | ID | Statistique implicite |
|---|---|---|
| Bâton | `weapon` | Puissance |
| Coiffe | `head` | PV + défense |
| Robe | `chest` | PV + défense (plus élevés) |
| Gants | `hands` | Puissance + défense |
| Bottes | `feet` | PV + défense |
| Amulette | `amulet` | Chance de critique |

- **Raretés** : commune, peu commune, rare, épique, légendaire. Le nombre d'affixes est de 1, 2, 3, 4, puis 4 + un effet légendaire unique. Libellé et motif de cadre en plus de la couleur (DESIGN.md).
- **Niveau d'objet** (ilvl) = niveau de la source (+1 pour l'élite, +2 pour le boss). Il fixe la taille des statistiques.
- **Affixes** : tirés dans le pool de l'emplacement, sans doublon. La valeur est tirée dans une plage affichée (ex. « +7 % [5-9] »).
- **Amélioration** (forge, Bastien) : de +1 à +10 selon la rareté, en or et poussière de mana. Le succès est garanti jusqu'à +5, puis la chance baisse. Un échec ne détruit rien et ne fait pas perdre de niveau, et augmente les chances de la tentative suivante.
- **Recyclage** : un objet donne de la poussière de mana. Recyclage groupé par rareté, avec confirmation.

### 10.3 Sorts

- Rangs 1 à 5 par sort actif et pour l'ultime. Chaque rang augmente les dégâts ou l'effet. Le rang 3 ajoute un emplacement de rune, le rang 5 en ajoute un autre et un modificateur. Exemples : Zoltraak traverse et touche une 2e cible alignée ; Salve tire 7 projectiles ; Barrière renvoie 20 % des dégâts absorbés.
- Coût : or + pages de grimoire (`material.grimoire_page`).

### 10.4 Runes

- Les runes se sertissent dans les **emplacements des sorts** (1 au rang 1, 2 au rang 3, 3 au rang 5). On les retire gratuitement.
- Paliers 1 à 5. **Fusion** chez Maëlle, graveuse de runes : 3 runes identiques de palier N donnent 1 rune de palier N+1, en or et éclats runiques, avec succès garanti.
- **Conversion** (une seule par sort) : Braise (feu), Givre, Orage (foudre). Elle change l'élément et ajoute une chance d'appliquer le statut.
- **Modification** : Acuité (critique), Économie (coût en mana), Célérité (recharge), Écho (chance de relancer le sort à 50 %), Puissance (dégâts du sort). Une même rune ne peut pas figurer deux fois sur un sort.
- Ce sont les runes qui font le build. Exemple : Salve + Givre contre les lanternes, puis Zoltraak + Braise sur les ennemis gelés (Fonte).

### 10.5 Artefacts

Le premier emplacement s'ouvre au niveau 6 (quête de l'horloger), le second au niveau 15. Les artefacts montent du niveau 1 au niveau 5 avec l'essence de cendre (`material.ashen_essence`, butin d'élite et de boss).

| Artefact | ID | Source | Effet (niveau 1 → 5) |
|---|---|---|---|
| Sablier fêlé | `artifact.cracked_hourglass` | Quête `quest.side_clockmaker` | +efficacité hors ligne |
| Fleur pressée | `artifact.pressed_flower` | Découverte dans la Tourbière | Une fois par combat, sous 30 % des PV, soigne un pourcentage des PV max |
| Boussole du voyageur | `artifact.traveler_compass` | Quête `quest.side_herbalist` | +or trouvé, révèle les découvertes sous le brouillard |
| Cloche de cendre | `artifact.ashen_bell` | Boss Morvaine | Un sort actif sur quatre inflige un bonus de dégâts |

L'arbitrage voulu : progresser hors ligne (Sablier) ou être plus fort en combat (Cloche). Avec deux emplacements, le choix reste réel.

### 10.6 Ressources et inventaire

- **Or** (`currency.gold`), **poussière de mana** (`material.mana_dust`, amélioration), **éclat runique** (`material.rune_shard`, fusion), **page de grimoire** (`material.grimoire_page`, rangs des sorts), **essence de cendre** (`material.ashen_essence`, artefacts).
- **Consommables** (marchande d'Aubelin) : Infusion de soin (`consumable.healing_draught`), Élixir de mana (`consumable.mana_elixir`). Recharge partagée, 5 au plus de chaque sur soi.
- **Inventaire** : 60 cases d'équipement. Les matériaux, les runes et les consommables vont dans des onglets empilables à part, sans limite pratique. Inventaire plein : le butin d'objets est recyclé automatiquement, avec une ligne dans le résumé. Il n'est jamais perdu en silence.

## 11. Butin

- Chaque rencontre possède une **table de butin** (`loot.*`). Chaque tirage produit de l'or, des matériaux, éventuellement un objet, une rune ou une page.
- La rareté dépend de la source : normale, élite, boss ou coffre. Le premier kill du boss garantit un objet épique ou mieux.
- Le butin est généré au moment de `EncounterCompleted`, par la RNG à graine de la rencontre (reproductible en test).
- La comparaison avec l'objet équipé est immédiate (flèches vert/rouge). Un bouton « Équiper » apparaît si l'objet améliore la puissance estimée.
- **Puissance estimée** : un chiffre unique (DPS soutenu × survie), affiché sur la fiche de Fern. Il sert à comparer, pas à verrouiller du contenu.

## 12. Idle et progression hors ligne

| Règle | Détail |
|---|---|
| Mode actif « Chasser ici » | Uniquement sur une rencontre déjà vaincue ; ticks réels dans la scène, à la vitesse choisie |
| Chasse hors ligne | La dernière rencontre réglée sur « Chasser ici » (modifiable dans la carte). Seulement les rencontres `offline_eligible` : ni élite ni boss |
| Calcul | Analytique, par lot, à partir de l'horodatage de la dernière sauvegarde. Il ne fait jamais tourner de ticks. Formule dans `GAME_BALANCE.md` §20 |
| Plafond | 8 h. Au-delà, aucun gain (affiché : « Plafond de 8 h atteint ») |
| Minimum | 60 s. En dessous, pas de résumé |
| Horloge reculée | Aucun gain, horodatage conservé, mention neutre dans le résumé |
| Sécurité | Si le groupe ne survit pas assez longtemps selon le calcul, aucun gain, avec une explication et une suggestion (« Choisissez une chasse plus facile ») |
| Résumé « Pendant votre absence » | Durée prise en compte, rencontre, nombre de victoires estimé, XP (et niveaux gagnés), or, matériaux, objets (les meilleurs gardés, le reste recyclé), bouton « Récupérer » |

## 13. Quêtes, bestiaire, découvertes (léger)

**Quêtes** (états : disponible → active → terminée → rendue) :

| ID | Nom | Type | Objectifs | Récompense clé |
|---|---|---|---|---|
| `quest.main_01` | Une cloche qui ne sonne plus | principale | Parler à Odile la sonneuse ; vaincre 3 meutes dans le Bois | Débloque la Tourbière, Barrière déjà acquise |
| `quest.main_02` | Lueurs sur la tourbière | principale | Vaincre 4 rencontres ; trouver le Journal du passeur (découverte) | Débloque les Ruines, scène de l'ultime |
| `quest.main_03` | Le guet abandonné | principale | Vaincre les sentinelles du guet ; récupérer la clé du cloître | Débloque le donjon |
| `quest.main_04` | Le cadran éteint | principale | Vaincre Morvaine | La cloche sonne, épilogue |
| `quest.side_clockmaker` | Les rouages de Tobias | secondaire | Rapporter 10 éclats runiques | Emplacement d'artefact + Sablier fêlé |
| `quest.side_herbalist` | Herbes de brume | secondaire | Ramasser 6 herbes (découvertes ramassables) | Boussole du voyageur |
| `quest.side_statue` | Une statue sous la mousse | secondaire | Nettoyer une vieille statue de héros près d'Aubelin | XP + souvenir (lore) |

`quest.side_statue` fait référence (`canon_refs`) au héros Himmel et aux statues qui lui sont élevées dans l'œuvre. La statue, le lieu et le texte sont originaux.

- **Contrats du jour** `[H]` : 3 contrats tirés chaque jour local à minuit (« Vaincre 20 loups »), petite récompense en or et matériaux. Optionnels, sans série à entretenir.
- **Bestiaire** : une fiche par ennemi, débloquée à la 1re victoire (nom, illustration, lore). À 5 victoires : affinités. À 25 victoires : statistiques. Pas de récompense de collection dans la tranche.
- **Découvertes** (`discovery.*`) : 2 par terrain. Ce sont des points de vue, des stèles de lore, des coffres et des herbes. Chacune donne de l'XP ou un objet et lève le brouillard alentour sur la carte. Le compteur s'affiche par lieu (« Découvertes 1/2 »).

## 14. Game feel

| Paramètre | Valeur par défaut | Bornes | Note |
|---|---|---|---|
| Latence entrée → début d'incantation | ≤ 1 tick (50 ms) + retour visuel immédiat du bouton (120 ms) | - | Le bouton réagit même si la simulation refuse le sort (secousse du bouton + raison : « Mana insuffisante ») |
| Tampon d'entrée des sorts | 300 ms | 150-400 | Un sort demandé pendant une incantation part à la fin de celle-ci. Ce tampon remplace le tampon de saut (il n'y a pas de saut) |
| Temps de recharge global | 0,5 s | 0,3-0,8 | La Barrière l'ignore |
| Arrêt sur image | 50 ms sur critique, 60 ms sur coup de boss, 0 sur auto | 40-80 | La simulation ne consomme aucun tick pendant l'arrêt (déterminisme intact). Désactivé à ×4 |
| Secousse caméra | trauma 0,3 critique, 0,5 ultime, 0,6 coup de boss | 0-1 | Désactivée si « Réduire les animations » est actif |
| Chiffres flottants | 0,8 s de vie, montée de 1,2 m, pop d'échelle 1,3 → 1 en 120 ms | - | Les dégâts sur une même cible en moins de 100 ms sont regroupés |
| Déplacement en exploration | 5 m/s, accélération jusqu'à pleine vitesse en 0,1 s, rotation 720°/s | 4-6 m/s | Clic pour se déplacer (marqueur au sol), ZQSD/WASD, joystick |
| Amorti de la caméra | 0,15 s | 0,08-0,3 | DESIGN.md : 3/4, ~50° |
| Paliers de retour | petit (auto), moyen (Zoltraak, Salve), grand (critique, interruption réussie), majeur (ultime, phase de boss, mort du boss) | - | Une préréglage par palier pour garder les effets proportionnés |
| Interruption réussie | son net + mot « Interrompu ! » + arrêt sur image de 50 ms | - | Récompense une lecture juste |

## 15. Contrôles

| Action | Clavier/souris | Tactile (mobile paysage) |
|---|---|---|
| Se déplacer | Clic au sol, ZQSD ou WASD | Joystick virtuel à gauche |
| Interagir | E ou clic | Bouton contextuel |
| Sorts 1-3, ultime | 1, 2, 3, R | Arc de 4 boutons à droite, ultime plus grand |
| Consommables | 4, 5 | 2 petits boutons au-dessus de l'arc |
| Focaliser une cible | Clic sur l'ennemi | Appui sur l'ennemi |
| Pause / vitesse | Espace / F | Boutons en haut à droite |
| Carte, sac, sorts, journal | M, I, K, J | Bouton menu |

Toutes les touches sont remappables. Navigation complète au clavier et à la manette (DESIGN.md).

## 16. Parcours UX

### 16.1 Nouvelle partie → premier combat en moins de 3 minutes

| t (cible) | Étape | Règle testable |
|---|---|---|
| 0:00 | Écran titre → « Nouvelle partie » | 1 clic, sans formulaire |
| 0:05 | 3 cartes de récit (texte original, 1 phrase chacune), passables | « Passer » toujours visible |
| 0:30 | Fern apparaît sur la route d'Aubelin, à l'orée du Bois ; consigne de déplacement | Consigne adaptée au périphérique détecté |
| 0:50 | Après 25 m, une meute de 2 loups est visible ; consigne « Approchez-vous » | - |
| 1:10 | Contact → combat. Les attaques auto se lancent seules ; consigne « Appuyez sur 1 : Zoltraak » au 1er tick | `EncounterStarted` ≤ 180 s après le clic (E2E, intro passée : ≤ 60 s) |
| 1:30 | Victoire → bâton peu commun garanti → consigne « Équiper » | Le premier butin est garanti |
| 2:00 | Niveau 2, Barrière débloquée ; le chemin vers Aubelin s'éclaire | - |

### 16.2 Session type (retour du joueur)

Titre → chargement de la sauvegarde → **résumé hors ligne** → Récupérer → monde (là où Fern était) → forge ou runes → pousser la rencontre suivante → changer de chasse → fermer (sauvegarde auto).

### 16.3 Sauvegarde

Les règles techniques (périodicité, emplacement, copie de secours, récupération) sont dans ARCHITECTURE. Le design ajoute des déclencheurs de sauvegarde automatique : fin de rencontre, changement de lieu, achat, amélioration, fusion. Sauvegarde manuelle par le bouton « Sauvegarder ». Export et import en fichier. Une sauvegarde invalide n'écrase jamais la dernière valide.

## 17. Écrans

| Écran | ID | Contenu principal |
|---|---|---|
| Titre | `screen.title` | Continuer, Nouvelle partie, Sauvegardes, Réglages |
| Chargement | `screen.loading` | Cercle runique, conseil |
| Résumé hors ligne | `screen.offline_summary` | Voir §12 |
| Monde (HUD exploration) | `screen.world` | Portrait et niveau, ressources, mini-carte, suivi de quête, barre de 5 boutons |
| Combat (HUD combat) | `screen.combat_hud` | Barres, sorts, vitesse, pause, journal, barre de boss |
| Fin de combat | `panel.combat_result` | Victoire ou défaite, gains, conseil |
| Carte du monde | `screen.world_map` | Régions, lieux, brouillard, Voyager, chasse hors ligne |
| Personnage | `panel.character` | Statistiques détaillées, 6 emplacements, artefacts, puissance estimée |
| Sac | `panel.inventory` | Grille, filtres, comparaison, recyclage groupé |
| Grimoire | `panel.spellbook` | Sorts, rangs, emplacements de runes, tactiques |
| Forge | `panel.forge` | Amélioration (chance, coût, aperçu) |
| Graveuse de runes | `panel.runecarver` | Fusion |
| Marchande | `panel.merchant` | Consommables |
| Journal | `panel.journal` | Onglets Quêtes, Bestiaire, Découvertes, Contrats |
| Dialogue | `panel.dialogue` | Nom, portrait, texte, choix (au plus 3) |
| Réglages | `panel.settings` | Audio par bus, taille du texte, réduire les animations, touches, langue (FR seulement), sauvegardes |

## 18. Hors périmètre (tranche verticale)

- Plus d'un personnage jouable (Frieren, Stark et les autres sont des compagnons futurs) ; menace et soins multi-personnages ; synergies de groupe.
- Déplacement manuel de Fern pendant le combat `[H]` (voir questions ouvertes).
- Aura et tout autre antagoniste canon nommé en combat (prévus plus tard, avec vérification du canon).
- Deuxième région, donjons procéduraux, mode infini, boss du monde.
- Artisanat d'objets à partir de matériaux (seuls l'amélioration et la fusion sont prévus), reforge des affixes, sets d'objets.
- Contrats hebdomadaires, succès, collection du bestiaire récompensée.
- Cycle jour/nuit lié à l'horloge réelle, météo.
- Multijoueur, comptes, serveur, classement, monétisation, publicité, énergie.
- Doublage, cinématiques ; tout son, image ou réplique de l'œuvre.
- Langues autres que le français (textes centralisés quand même).
- Manette sur mobile, mode portrait mobile.

## 19. Plan de test de jeu (ce qu'on observe)

| Test | Joueur | Ce qu'on observe | Seuil de réussite |
|---|---|---|---|
| T1 Premier contact | Nouveau, sans consigne orale | Temps jusqu'au 1er combat ; le joueur comprend-il que l'attaque est automatique ? Lance-t-il Zoltraak sans aide ? | Combat < 3 min ; Zoltraak lancé dans les 15 s qui suivent la consigne |
| T2 Lisibilité des télégraphes | Après 10 min de jeu | Réagit-il au Fracas et à l'Embrasement ? Confond-il interruptible et non interruptible ? | ≥ 2 interruptions réussies sur 3 contre les lanternes au 2e essai |
| T3 Mana | 20 min | Se retrouve-t-il souvent sans mana ? Règle-t-il la réserve ? | Panne de mana < 20 % du temps de combat ; aucun « sort inutile » signalé |
| T4 Élite | Niveau 10 | Nombre d'essais ; comprend-il pourquoi il a perdu ? | Victoire en ≤ 3 essais ; il cite la bonne cause |
| T5 Boss | Niveau 11-12 | Durée, phases comprises, usage de la Barrière au Sceau | 2,5-3,5 min ; Sceau bouclié ≥ 50 % du temps au 2e essai |
| T6 Retour hors ligne | Après une nuit | Comprend-il le résumé ? Trouve-t-il le gain motivant et pas écrasant ? | Il peut dire d'où viennent les gains ; il veut dépenser |
| T7 Build | Niveau 8+ | Change-t-il de rune selon la zone ? | ≥ 1 changement de conversion en réponse aux affinités |
| T8 Tactile | Tablette ou téléphone | Erreurs d'appui, sorts accessibles au pouce | < 1 erreur d'appui par combat |

## 20. Questions ouvertes (à trancher par le propriétaire)

Les réponses mettront à jour les règles `[H]` concernées.

1. **Déplacement en combat** : Fern se place seule (proposition actuelle, comme AFK Journey), ou le joueur peut la repositionner d'un clic ? La seconde option ajoute de l'esquive, mais aussi de la complexité au tactile.
2. **Générosité du hors ligne** : `OFFLINE_EFFICIENCY = 0,4` (8 h valent 3,2 h de chasse, soit +2 à 3 niveaux par nuit vers le niveau 8). Faut-il garder cette valeur ou être plus sobre (0,25) ?
3. **Canon** : peut-on confirmer les graphies françaises « Fern » et « Zoltraak », la statue de Himmel en clin d'œil, et un boss démon original (Morvaine) plutôt qu'Aura dans la tranche ?
4. **Contrats du jour** : faut-il les garder (petite boucle quotidienne, sans série à entretenir) ou les couper, au nom du pilier « pas de culpabilisation » ?
5. **Durée de la tranche** : niveau max 20, boss vers le niveau 12 au jour 2 ou 3, plafond atteint en ~2 semaines de jeu léger. Est-ce la bonne ambition ?
