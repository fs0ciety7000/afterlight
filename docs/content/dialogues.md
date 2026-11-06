# Contenu du jalon 6 : dialogues, introduction, épilogue

> Version 0.1 (2026-11-06). Spécification pour `game/data/original/dialogues.json`, `npcs.json` et `game/i18n/strings.csv`.
> **Toutes les lignes sont originales**, écrites pour AFTERLIGHT. Aucune n'est une citation de l'œuvre et aucune ne doit être marquée comme telle (critère 6.2). Fern parle avec une voix originale : calme, polie, brève. Elle ne cite personne et ne raconte rien de son passé : ses lignes ne s'appuient que sur ce que le GDD tient pour sûr (§6).

## 1. Règles

| Règle | Valeur testable |
|---|---|
| Longueur d'une ligne | ≤ 120 caractères (test sur `strings.csv` pour les clés `dialogue.*` et `story.*`) |
| Longueur d'un dialogue | ≤ 4 lignes ; Morvaine ≤ 3 lignes par prise de parole en combat |
| Clé de texte | `<dialogue_id>.<key_suffix>`, `key_suffix` = `line_01`, `line_02`… (CONTENT_PIPELINE §5.4) |
| Locuteur | `npc.*`, `character.fern` ou `enemy.morvaine` (**nouveau** : un ennemi peut parler, sous-titré, sans panneau de dialogue) |
| Vouvoiement | Partout. Fern vouvoie les villageois, les villageois la vouvoient |
| Avance | Clic, appui, E ou Espace ; « Passer » termine le dialogue (les effets de fin, comme l'activation d'une quête, s'appliquent quand même) |
| Choix | Aucun dans la tranche : l'offre d'une quête l'active à la fin du dialogue (`quests.md` §1.1) |
| Marquage | Aucun guillemet de citation, aucun champ `quote` ni `source` dans les données |

**Sélection du dialogue** : `npc.dialogues` devient une liste ordonnée de `{ "dialogue": ID, "condition": condition }` ; le premier dont la condition est vraie est joué. Nouvelle condition : `{"quest_state": {"id": ID, "state": "available" | "active" | "completed" | "turned_in" | "not_started"}}` (`not_started` = ni active ni plus loin, prérequis remplis ou non). Une ligne isolée peut aussi porter une `condition` (déjà dans le schéma).

Les PNJ de service (forge, graveuse, marchande, tableau) jouent leur dialogue d'accueil, puis ouvrent leur panneau. S'ils ont une quête à proposer ou à rendre, ce dialogue passe avant, et le panneau s'ouvre ensuite.

## 2. Introduction (cartes de récit)

Nouvelle préfixe de clé `story.` (à ajouter à CONTENT_PIPELINE §6). Trois cartes, une phrase chacune, « Passer » toujours visible (GDD §16.1).

| Clé | Texte |
|---|---|
| `story.intro.card_01` | Il y a quatre-vingts ans, la cloche du cloître d'Aubelin s'est tue au milieu d'un après-midi. |
| `story.intro.card_02` | Depuis, la brume descend plus tôt sur le val, et les loups descendent avec elle. |
| `story.intro.card_03` | Un matin d'automne, une jeune mage arrive au village par la route de l'ouest. |

Après la dernière carte : Fern apparaît dans Aubelin (`start.default`, point `default`), Odile est à 3 m (ancre `npc_well`) avec un losange d'offre ; consigne de déplacement selon le périphérique.

## 3. Odile (`npc.odile`)

Sonneuse du cloître « de mère en fille », qui n'a jamais sonné. Humour sec, tendresse retenue.

| Ordre | Dialogue | Condition |
|---|---|---|
| 1 | `dialogue.odile_epilogue` | `main_04` `completed` |
| 2 | `dialogue.odile_main04_offer` | `main_04` `available` |
| 3 | `dialogue.odile_main04_wait` | `main_04` `active` |
| 4 | `dialogue.odile_main01_done` | `main_01` `completed` |
| 5 | `dialogue.odile_intro` | `main_01` `active` et objectif `meet_odile` non rempli |
| 6 | `dialogue.odile_main01_wait` | `main_01` `active` |
| 7 | `dialogue.odile_after` | `main_04` `turned_in` |
| 8 | `dialogue.odile_idle` | toujours |

**`dialogue.odile_intro`** (fait avancer `meet_odile`)

| Suffixe | Locuteur | Texte |
|---|---|---|
| `line_01` | `npc.odile` | Une mage ? Vous tombez bien, ou très mal. Je n'ai pas encore décidé. |
| `line_02` | `npc.odile` | Je suis Odile, sonneuse du cloître, de mère en fille. Je n'ai jamais sonné une seule fois. |
| `line_03` | `character.fern` | La cloche est cassée ? |
| `line_04` | `npc.odile` | Muette. Ce n'est pas pareil. Les loups du Bois, eux, ne se taisent pas : commencez par là. |

**`dialogue.odile_main01_wait`**

| `line_01` | `npc.odile` | Le Bois est à l'ouest. Revenez quand les loups auront compris qui commande. |
|---|---|---|

**`dialogue.odile_main01_done`** (rendu de `main_01`)

| Suffixe | Locuteur | Texte |
|---|---|---|
| `line_01` | `npc.odile` | Les bûcherons sont rentrés sans une égratignure. Merci. |
| `line_02` | `npc.odile` | Maëlle, la graveuse, veut vous parler des lueurs de la tourbière. D'habitude, elle a peur pour rien. |
| `line_03` | `npc.odile` | Plus maintenant. |

**`dialogue.odile_idle`**

| `line_01` | `npc.odile` | Petite, je réglais le pain sur la cloche de midi. Maintenant, on le rate une fois sur deux. |
|---|---|---|

**`dialogue.odile_main04_offer`**

| Suffixe | Locuteur | Texte |
|---|---|---|
| `line_01` | `npc.odile` | Bastien dit que vous avez la clé. Je l'ai tenue une fois, à huit ans. Elle me semblait plus lourde. |
| `line_02` | `npc.odile` | Montez au cloître. Si quelque chose empêche la cloche de sonner, je veux savoir quoi. |
| `line_03` | `character.fern` | Je vous le dirai. |

**`dialogue.odile_main04_wait`**

| `line_01` | `npc.odile` | Prenez votre temps. J'ai attendu quatre-vingts ans, je peux attendre la fin de la semaine. |
|---|---|---|

**`dialogue.odile_epilogue`** (rendu de `main_04`, suivi des cartes du §9.3)

| Suffixe | Locuteur | Texte |
|---|---|---|
| `line_01` | `npc.odile` | Je l'ai entendue, depuis le puits. Elle sonne un peu plus bas que dans mon souvenir. |
| `line_02` | `character.fern` | Le bronze a vieilli. |
| `line_03` | `npc.odile` | Moi aussi. On s'est reconnues quand même. |
| `line_04` | `npc.odile` | Demain, je monterai la sonner. Ce sera la première fois. Venez écouter, si vous passez. |

**`dialogue.odile_after`**

| `line_01` | `npc.odile` | Midi sonne de nouveau. Le boulanger jure que son pain n'a jamais été aussi régulier. |
|---|---|---|

## 4. Maëlle, graveuse de runes (`npc.maelle`)

Précise, pédagogue, un peu ironique. Donne `quest.main_02`.

| Ordre | Dialogue | Condition |
|---|---|---|
| 1 | `dialogue.maelle_main02_done` | `main_02` `completed` |
| 2 | `dialogue.maelle_main02_offer` | `main_02` `available` |
| 3 | `dialogue.maelle_main02_wait` | `main_02` `active` |
| 4 | `dialogue.maelle_greet` | toujours (puis panneau Graveuse) |

**`dialogue.maelle_greet`**

| `line_01` | `npc.maelle` | Une rune ne rend pas un sort plus fort. Elle lui apprend autre chose. Que voulez-vous lui apprendre ? |
|---|---|---|

**`dialogue.maelle_main02_offer`**

| Suffixe | Locuteur | Texte |
|---|---|---|
| `line_01` | `npc.maelle` | Vous êtes la mage qui a calmé le Bois ? Bien. J'ai un problème qui flotte. |
| `line_02` | `npc.maelle` | Des lueurs se sont allumées sur la tourbière. Elles incantent avant de brûler. |
| `line_03` | `npc.maelle` | Une incantation, ça s'interrompt. Et le vieux passeur a laissé un journal là-bas : rapportez-le-moi. |

**`dialogue.maelle_main02_wait`**

| `line_01` | `npc.maelle` | Le feu ne leur fait rien. Le froid, si. Je dis ça, je ne dis rien. |
|---|---|---|

**`dialogue.maelle_main02_done`** (rendu : `rune.frost`)

| Suffixe | Locuteur | Texte |
|---|---|---|
| `line_01` | `npc.maelle` | D'après ce journal, les lueurs sont apparues l'année où la cloche s'est tue. Ce n'est pas un hasard. |
| `line_02` | `npc.maelle` | Prenez cette rune de givre. Sertissez-la sur un sort : les lueurs vous trouveront moins drôle. |
| `line_03` | `npc.maelle` | Et Bastien vous cherche. Il parle des Ruines du Guet, ce qui ne lui arrive jamais. |

## 5. Bastien, forgeron (`npc.bastien`)

Peu de mots, concret. Donne `quest.main_03`.

| Ordre | Dialogue | Condition |
|---|---|---|
| 1 | `dialogue.bastien_main03_done` | `main_03` `completed` |
| 2 | `dialogue.bastien_main03_offer` | `main_03` `available` |
| 3 | `dialogue.bastien_main03_wait` | `main_03` `active` |
| 4 | `dialogue.bastien_greet` | toujours (puis panneau Forge) |

**`dialogue.bastien_greet`**

| `line_01` | `npc.bastien` | Posez-le sur l'enclume. Je regarde. |
|---|---|---|

**`dialogue.bastien_main03_offer`**

| Suffixe | Locuteur | Texte |
|---|---|---|
| `line_01` | `npc.bastien` | Le guet, sur la colline. Mon grand-père y montait la garde. |
| `line_02` | `npc.bastien` | Les gardes avaient la clé du cloître. Maintenant, ce sont les sentinelles de pierre. Elles ne la rendent pas. |
| `line_03` | `npc.bastien` | Cassez-les. Rapportez la clé. Et méfiez-vous : la pierre, ça frappe tard mais fort. |

**`dialogue.bastien_main03_wait`**

| `line_01` | `npc.bastien` | Leur barrière tient contre tout, sauf la magie pure. Frappez juste. |
|---|---|---|

**`dialogue.bastien_main03_done`** (rendu : donjon débloqué)

| Suffixe | Locuteur | Texte |
|---|---|---|
| `line_01` | `npc.bastien` | C'est elle. Mon grand-père l'avait gravée sur la porte de la forge, de mémoire. |
| `line_02` | `npc.bastien` | Le cloître est derrière la tour, par la poterne. Dites-le à Odile avant d'y monter. |

## 6. Rosalie, marchande (`npc.aubelin_merchant`)

Bavarde, pratique. Donne `quest.side_statue`.

| Ordre | Dialogue | Condition |
|---|---|---|
| 1 | `dialogue.odette_statue_done` | `side_statue` `completed` |
| 2 | `dialogue.odette_statue_offer_found` | `side_statue` `available` et `discovery.moss_statue` trouvée |
| 3 | `dialogue.odette_statue_offer` | `side_statue` `available` |
| 4 | `dialogue.odette_statue_wait` | `side_statue` `active` |
| 5 | `dialogue.odette_greet` | toujours (puis panneau Marchande) |

| Dialogue | Suffixe | Locuteur | Texte |
|---|---|---|---|
| `dialogue.odette_greet` | `line_01` | `npc.aubelin_merchant` | Infusions fraîches, élixirs pas trop vieux. Et pas de crédit, même pour une mage polie. |
| `dialogue.odette_statue_offer` | `line_01` | `npc.aubelin_merchant` | À l'orée du Bois, il y a une statue. Un héros de passage, il y a longtemps. |
| | `line_02` | `npc.aubelin_merchant` | Ma grand-mère la brossait chaque printemps. Depuis, la mousse a gagné. Rendez-lui son visage, voulez-vous ? |
| `dialogue.odette_statue_offer_found` | `line_01` | `npc.aubelin_merchant` | On dit que la statue du Bois est propre. C'était vous ? Alors ma grand-mère vous remercie. Moi aussi. |
| `dialogue.odette_statue_wait` | `line_01` | `npc.aubelin_merchant` | Une brosse, de l'eau, un peu de patience. La mousse ne se défend pas. |
| `dialogue.odette_statue_done` | `line_01` | `npc.aubelin_merchant` | Himmel. Je n'arrivais plus à lire le nom depuis la route. |
| | `line_02` | `npc.aubelin_merchant` | Tenez, pour la peine. Et pour la grand-mère. |

`dialogue.odette_statue_offer_found` passe la quête à `active` puis, l'objectif étant déjà rempli, à `completed` : le joueur rend la quête en reparlant à Rosalie (`odette_statue_done`). `[H]` : si les tests montrent que ce double dialogue gêne, rendre directement.

## 7. Tobias, horloger (`npc.tobias`) et Ysaline, herboriste (`npc.ysaline`)

| PNJ | Ordre | Dialogue | Condition |
|---|---|---|---|
| Tobias | 1 | `dialogue.tobias_done` | `side_clockmaker` `completed` |
| | 2 | `dialogue.tobias_offer` | `side_clockmaker` `available` |
| | 3 | `dialogue.tobias_wait` | `side_clockmaker` `active` |
| | 4 | `dialogue.tobias_early` | `side_clockmaker` `not_started` (niveau < 6) |
| | 5 | `dialogue.tobias_idle` | toujours |
| Ysaline | 1 | `dialogue.ysaline_done` | `side_herbalist` `completed` |
| | 2 | `dialogue.ysaline_offer` | `side_herbalist` `available` |
| | 3 | `dialogue.ysaline_wait` | `side_herbalist` `active` |
| | 4 | `dialogue.ysaline_idle` | toujours |

| Dialogue | Suffixe | Locuteur | Texte |
|---|---|---|---|
| `dialogue.tobias_early` | `line_01` | `npc.tobias` | Revenez quand vous saurez porter deux choses à la fois. Niveau 6, disons. |
| `dialogue.tobias_offer` | `line_01` | `npc.tobias` | Ne bougez pas. Vous avez du mana sur vous… non, en vous. Parfait. |
| | `line_02` | `npc.tobias` | Je répare l'horloge du cloître, pièce par pièce, depuis trente ans. Il me manque des rouages qui tiennent la magie. |
| | `line_03` | `npc.tobias` | Dix éclats runiques. Je les taille, vous gagnez un sablier. Il est fêlé, mais il compte mieux que moi. |
| `dialogue.tobias_wait` | `line_01` | `npc.tobias` | Dix éclats. Pas neuf. Neuf, c'est une horloge qui retarde. |
| `dialogue.tobias_done` | `line_01` | `npc.tobias` | Voilà. Un sablier qui continue de couler quand vous ne regardez pas. |
| | `line_02` | `npc.tobias` | J'ai ajusté une attache à votre ceinture : il se porte comme un artefact. Ne me remerciez pas, ça me gêne. |
| `dialogue.tobias_idle` | `line_01` | `npc.tobias` | Tic, tac. Pardon, c'est une habitude. |
| `dialogue.ysaline_offer` | `line_01` | `npc.ysaline` | La brume dépose des herbes là où elle stagne. Bleues, un peu froides au toucher. |
| | `line_02` | `npc.ysaline` | Il m'en faut six : trois dans le Bois, trois sur la tourbière. Moi, les loups me voient venir. |
| `dialogue.ysaline_wait` | `line_01` | `npc.ysaline` | Cherchez près de l'eau et des racines. Elles luisent un peu quand on ne les regarde pas. |
| `dialogue.ysaline_done` | `line_01` | `npc.ysaline` | Six, et bien cueillies. Merci. |
| | `line_02` | `npc.ysaline` | Cette boussole était à mon père. Elle ne montre pas le nord : elle montre ce qu'on n'a pas encore vu. |
| `dialogue.ysaline_idle` | `line_01` | `npc.ysaline` | Les herbes de brume sèchent mal. Comme les souvenirs, disait ma mère. |

## 8. Tableau des contrats (`npc.notice_board`)

Le tableau joue une ligne d'ambiance puis ouvre le journal sur l'onglet Contrats. Textes d'interface du panneau : préfixe `ui.contracts.` (`contracts.md` §5).

| Dialogue | Suffixe | Locuteur | Texte |
|---|---|---|---|
| `dialogue.notice_board_read` | `line_01` | `npc.notice_board` | Des avis cloués les uns sur les autres. Ceux du jour sont en haut, l'encre encore fraîche. |

## 9. Fern, Morvaine, la cloche

### 9.1 Lignes de Fern (bulles courtes, sans panneau, 3 s ou jusqu'à l'appui)

| Dialogue | Déclencheur | Texte (`line_01`) |
|---|---|---|
| `dialogue.fern_enter_mire` | Première visite de `location.lantern_mire` | Ces lueurs incantent. Il faut les couper avant la fin. |
| `dialogue.fern_enter_ruins` | Première visite de `location.watch_ruins` | Des sentinelles. Leur barrière cède plus vite à la magie pure. |
| `dialogue.fern_afterlight_unlock` | Passage au niveau 5 (déblocage de `spell.afterlight`) | Je peux maintenant libérer toute ma réserve d'un coup. Il faudra choisir le moment. |
| `dialogue.fern_dungeon_enter` | Première entrée dans le donjon | Dehors, c'est l'après-midi. Ici, il fait nuit. Quelqu'un a arrêté plus que la cloche. |
| `dialogue.fern_fountain` | Salle 3, à l'approche de la fontaine | L'eau est restée claire. Une pause. |
| `dialogue.fern_campfire` | Salle 6, première arrivée | Quelqu'un a laissé du bois sec. On peut se préparer ici. |

`dialogue.fern_afterlight_unlock` est la « scène de l'ultime » du GDD §13 : elle suit le déblocage par le niveau 5 (données de `character.fern`), pas une quête. La consigne d'interface `tip.afterlight_unlocked` suit (« Lumière d'après débloquée : touche R »).

### 9.2 Morvaine (`enemy.morvaine`, sous-titres en combat)

Elle parle peu et ment avec douceur (GDD §9.3). Lignes originales.

| Dialogue | Déclencheur | Suffixe | Locuteur | Texte |
|---|---|---|---|---|
| `dialogue.morvaine_intro` | Entrée dans le cercle du cadran (salle 7), avant `encounter_started` ; seulement au premier essai, ensuite une seule ligne | `line_01` | `enemy.morvaine` | Entrez. Il n'y a rien à craindre ici. Rien ne bouge. |
| | | `line_02` | `character.fern` | C'est vous qui retenez la cloche. |
| | | `line_03` | `enemy.morvaine` | Je la protège. Le bruit use les choses, et vous vivez si peu de temps pour les entendre. |
| `dialogue.morvaine_retry` | Essais suivants | `line_01` | `enemy.morvaine` | Vous revoilà. Je savais que vous resteriez. |
| `dialogue.morvaine_phase_veil` | `boss_phase_changed` → `veil` | `line_01` | `enemy.morvaine` | Doucement. Je n'ai jamais fait de mal à personne ici. Personne n'est venu. |
| `dialogue.morvaine_phase_hollow` | `boss_phase_changed` → `hollow_hour` | `line_01` | `enemy.morvaine` | Restez. Une heure de plus, une heure de moins : qui compte, sous ce cadran ? |
| `dialogue.morvaine_defeat` | `enemy_defeated` de Morvaine | `line_01` | `enemy.morvaine` | Écoutez… Non. N'écoutez pas. |
| `dialogue.fern_after_boss` | Après `dialogue.morvaine_defeat` | `line_01` | `character.fern` | Elle a menti jusqu'au bout. |

Les sous-titres de combat ne mettent pas la simulation en pause et ne la ralentissent pas, en dehors du ralenti visuel de 400 ms déjà prévu au changement de phase.

### 9.3 La cloche et l'épilogue

| Clé | Moment | Texte |
|---|---|---|
| `story.bell.subtitle` | Premier coup de cloche, après la victoire (sous-titre du son porteur d'information) | La cloche du cloître sonne. |
| `story.epilogue.card_01` | Après `dialogue.odile_epilogue` | Ce jour-là, la cloche sonna midi avec quatre-vingts ans de retard. |
| `story.epilogue.card_02` | | Personne à Aubelin ne songea à la corriger. |
| `story.epilogue.card_03` | | Fern resta encore un peu. Il restait des loups dans le Bois, et des contrats sur le tableau. |

Après la dernière carte : retour au monde, dans Aubelin, en jour ; la partie continue. Si le joueur ne rend jamais la quête, la cloche a sonné quand même (séquence jouée à la victoire) : seul l'épilogue attend.

## 10. Relecture

- Critère 6.2 : un test vérifie que les clés `dialogue.*` et `story.*` existent dans `strings.csv`, qu'aucune entrée de dialogue n'a de champ `quote` ou `source`, et que chaque ligne fait ≤ 120 caractères.
- Le nom canon « Himmel » n'apparaît que dans `dialogue.odette_statue_done.line_01` et dans le texte de la plaque (`discovery.moss_statue.lore`). Relecture du propriétaire demandée.
