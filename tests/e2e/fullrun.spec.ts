import { expect, test, type Page } from '@playwright/test';
import { START_URL, boot, clearStorage, click, probe, readUserFile, waitSaved, waitScreen } from './helpers';

// Milestone 6 (ROADMAP 6.3): the whole vertical slice in one run.
// New game → quests main_01..main_03 → the cloister's 7 rooms → Morvaine
// defeated → the bell → Odile's hand-in and the epilogue → save → reload
// 3 h later → offline gains.
//
// Debug tools allowed by the criterion, all on the test channel (`?test=1`,
// game/app/main.gd and game/app/screens/explore_screen.gd):
// - accelerated XP: `grant_levels:<n>`; the gear a run would have by then:
//   `grant_gear:<rarity>/<enhance>`; gold for the potions: `grant_gold:<n>`;
// - Fern is put where a player would walk to: `go_to:<interactable>` (NPC,
//   postern, fountain, campfire, discovery), `go_to_pack:<encounter|"">`
//   (inside the pack's aggro radius), `go_to_room:<room>` (just past the
//   room's door), `go_to_exit:<exit>`;
// - ×4 speed outside the boss (the game caps the boss at ×2; it is played
//   at ×1 here, like a player reacting to the seal).
// Fights are really fought (the sim decides) and quests advance only through
// the game's own events: talks, wins, discoveries, rooms.
test.setTimeout(100 * 60_000);

test.afterEach(async ({ page }, info) => {
  if (info.status === info.expectedStatus) return;
  await page.screenshot({ path: info.outputPath('failure.png') }).catch(() => undefined);
  const p = await probe(page).catch(() => undefined);
  await info.attach('probe', { body: JSON.stringify(p, null, 1), contentType: 'application/json' }).catch(() => undefined);
  console.log(`[probe] screen=${p?.screen} world=${JSON.stringify(p?.world).slice(0, 3000)}`);
  console.log(`[probe] messages=${JSON.stringify(p?.messages)}`);
});

type Point = { x: number; y: number };
type Snapshot = {
  hero_hp: number;
  hero_max_hp: number;
  hero_mana: number;
  ult_charge: number;
  ult_charge_max: number;
  consumables: Record<string, number>;
  cooldowns: Record<string, number>;
  enemy_casts: { spell: string; remaining_s: number }[];
};

const world = async (page: Page) =>
  ((await probe(page)) as unknown as { world: Record<string, unknown> }).world;
const state = async (page: Page) => (await probe(page))!.state as Record<string, unknown>;
const text = async (page: Page, id: string) => (await probe(page))!.controls[id]?.text ?? '';
const quests = async (page: Page) => ((await world(page)).quests ?? {}) as Record<string, string>;
const cmd = async (page: Page, name: string) => {
  await page.evaluate((n) => (window as unknown as { __afterlightTest: (n: string) => void }).__afterlightTest(n), name);
  await page.waitForTimeout(400);
};
const log = (step: string) => console.log(`[fullrun ${new Date().toISOString().slice(11, 19)}] ${step}`);

/** Clicks a control at once (no settle wait), if it is visible and enabled. */
async function tap(page: Page, id: string): Promise<boolean> {
  const c = (await probe(page))?.controls[id];
  if (!c || !c.visible || c.disabled) return false;
  const box = (await page.locator('canvas').boundingBox())!;
  const scale = await page.evaluate(() => {
    const canvas = document.querySelector('canvas')!;
    return canvas.width / canvas.clientWidth;
  });
  await page.mouse.click(box.x + (c.x + c.w / 2) / scale, box.y + (c.y + c.h / 2) / scale);
  return true;
}

/**
 * Reads through every dialogue, card and story card on screen, like a player
 * pressing « Suivant » / « Accepter ». Returns what was seen.
 */
async function readThrough(page: Page, seen: string[] = []): Promise<string[]> {
  let quiet = 0;
  for (let i = 0; i < 200 && quiet < 4; i++) {
    const p = (await probe(page))!;
    const w = p.world as Record<string, unknown>;
    const c = p.controls;
    if (w.story_cards) {
      if (!seen.includes(`cards:${w.story_cards}`)) seen.push(`cards:${w.story_cards}`);
      if (await tap(page, 'story.next')) {
        quiet = 0;
        await page.waitForTimeout(500);
        continue;
      }
    } else if (c['dialogue.accept']?.visible) {
      seen.push(`card:${c['dialogue.card_title']?.text ?? ''}`);
      if (await tap(page, 'dialogue.accept')) {
        quiet = 0;
        await page.waitForTimeout(600);
        continue;
      }
    } else if (c['dialogue.next']?.visible) {
      if (w.dialogue && !seen.includes(`dialogue:${w.dialogue}`)) seen.push(`dialogue:${w.dialogue}`);
      if (await tap(page, 'dialogue.next')) {
        quiet = 0;
        await page.waitForTimeout(400);
        continue;
      }
    }
    if (!w.dialogue_open && !w.story_cards) quiet++;
    else quiet = 0;
    await page.waitForTimeout(500);
  }
  return seen;
}

/** Back to the explore screen from a service panel opened after a talk. */
async function backToExplore(page: Page): Promise<void> {
  for (let i = 0; i < 10; i++) {
    const screen = (await probe(page))!.screen;
    if (screen === 'explore') return;
    for (const id of ['prog.close', 'journal.close', 'hunts.close', 'map.close']) {
      if (await tap(page, id)) break;
    }
    await page.waitForTimeout(1000);
  }
  await waitScreen(page, 'explore');
}

async function travel(page: Page, short: string): Promise<void> {
  await click(page, 'hud.map');
  await waitScreen(page, 'world_map');
  await click(page, `map.marker.${short}`);
  await click(page, 'map.travel');
  await expect.poll(async () => (await world(page)).location_id, { timeout: 60_000 }).toBe(`location.${short}`);
  await readThrough(page);
}

/** Walks up to an NPC (or thing) and uses it with the prompt button. */
async function use(page: Page, id: string): Promise<void> {
  await cmd(page, `go_to:${id}`);
  await expect.poll(async () => (await world(page)).interact_target, { timeout: 20_000, message: `prompt for ${id}` }).toBe(id);
  await click(page, 'hud.interact');
}

/** Talks to an NPC until nothing new is said; returns what was seen. */
async function talk(page: Page, npc: string): Promise<string[]> {
  await use(page, npc);
  await expect.poll(async () => (await world(page)).dialogue_open, { timeout: 15_000 }).toBe(true);
  const seen = await readThrough(page);
  await backToExplore(page);
  return seen;
}

async function levelTo(page: Page, level: number): Promise<void> {
  const now = (await state(page)).level as number;
  if (now >= level) return;
  await cmd(page, `grant_levels:${level - now}`);
  await expect.poll(async () => (await state(page)).level, { timeout: 15_000 }).toBe(level);
}

/** Cycles the speed button up to `speed` (the game caps it per encounter). */
async function setSpeed(page: Page, speed: number): Promise<void> {
  for (let i = 0; i < 4; i++) {
    if ((await world(page)).combat_speed === speed) return;
    await tap(page, 'combat.speed');
    await page.waitForTimeout(600);
  }
  expect((await world(page)).combat_speed).toBe(speed);
}

/**
 * Plays the fight on screen until it ends, like an attentive player: Barrier
 * when the ash seal is cast, a draught under 40 % HP, an elixir when out of
 * mana, the ultimate when charged. Returns "victory" or "defeat".
 */
async function fight(page: Page, speed: number): Promise<string> {
  await expect.poll(async () => (await world(page)).combat, { timeout: 30_000 }).toBeTruthy();
  await expect.poll(async () => (await probe(page))!.controls['combat.speed']?.visible ?? false, { timeout: 30_000 }).toBe(true);
  await setSpeed(page, speed);
  const deadline = Date.now() + 20 * 60_000;
  while (Date.now() < deadline) {
    const w = await world(page);
    if (w.combat_result) break;
    const s = w.combat_snapshot as Snapshot | undefined;
    if (s && s.hero_max_hp > 0) {
      const sealed = (s.enemy_casts ?? []).some((c) => c.spell.includes('ash_seal') && c.remaining_s < 2.8);
      if (sealed && (s.cooldowns['spell.defensive_barrier'] ?? 0) <= 0) {
        await tap(page, 'combat.spell.defensive_barrier');
      } else if (s.hero_hp / s.hero_max_hp < 0.4 && (s.consumables?.['consumable.healing_draught'] ?? 0) > 0) {
        await tap(page, 'combat.consumable.healing_draught');
      } else if (s.hero_mana < 20 && (s.consumables?.['consumable.mana_elixir'] ?? 0) > 0) {
        await tap(page, 'combat.consumable.mana_elixir');
      } else if (s.ult_charge_max > 0 && s.ult_charge >= s.ult_charge_max) {
        await tap(page, 'combat.spell.afterlight');
      }
    }
    await page.waitForTimeout(150);
  }
  await expect.poll(async () => (await world(page)).combat_result, { timeout: 60_000 }).not.toBe('');
  const result = (await world(page)).combat_result as string;
  await click(page, 'combat.continue');
  await expect.poll(async () => (await world(page)).combat, { timeout: 30_000 }).toBeFalsy();
  return result;
}

/** Goes into the nearest pack (or `encounter`) and wins the fight at ×4. */
/** A defeat is played like a player would: back at the entrance, try again. */
async function winPack(page: Page, encounter = ''): Promise<string> {
  for (let attempt = 1; ; attempt++) {
    await cmd(page, `go_to_pack:${encounter}`);
    await expect.poll(async () => (await world(page)).combat, { timeout: 30_000, message: `engage ${encounter || 'nearest pack'}` }).toBeTruthy();
    const id = (await world(page)).combat as string;
    const result = await fight(page, 4);
    log(`${result} ${id} (level ${(await state(page)).level})`);
    if (result === 'victory') return id;
    expect(attempt, `fight ${id}`).toBeLessThan(2);
    encounter = id;
    await page.waitForTimeout(1500);
  }
}

async function questIs(page: Page, quest: string, wanted: string): Promise<void> {
  await expect.poll(async () => (await quests(page))[quest], { timeout: 30_000, message: `${quest} ${wanted}` }).toBe(wanted);
}

/** Talks to the giver until the quest is handed in (and the next offered). */
async function handIn(page: Page, npc: string, quest: string): Promise<string[]> {
  const seen: string[] = [];
  for (let i = 0; i < 3 && (await quests(page))[quest] !== 'turned_in'; i++) {
    seen.push(...(await talk(page, npc)));
  }
  await questIs(page, quest, 'turned_in');
  return seen;
}

const dungeon = async (page: Page) => ((await world(page)).dungeon ?? {}) as Record<string, unknown>;

/** Past the door of `room`; the run follows Fern there. */
async function enterRoom(page: Page, room: string): Promise<void> {
  await cmd(page, `go_to_room:${room}`);
  await expect.poll(async () => (await dungeon(page)).room, { timeout: 20_000, message: `in room ${room}` }).toBe(room);
  log(`room ${room}`);
}

async function winRoom(page: Page, room: string, speed = 4): Promise<void> {
  await enterRoom(page, room);
  await cmd(page, 'go_to_pack:');
  await readThrough(page);
  const result = await fight(page, speed);
  expect(result, `room ${room}`).toBe('victory');
  await expect.poll(async () => (await dungeon(page)).cleared as string[]).toContain(room);
  // The room's grille opens.
  await expect.poll(async () => ((await world(page)).dungeon_gates as Record<string, boolean>)?.[room]).toBe(true);
}

test('6.3 full run: quests 1-3, the cloister, Morvaine, the bell, the epilogue, save, reload, offline gains', async ({ page }) => {
  const t0 = Date.now();
  page.on('console', (m) => {
    if (m.type() === 'error') console.log(`[browser error] ${m.text()}`);
  });

  // --- New game: main_01 is active. -----------------------------------------------
  await clearStorage(page);
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await questIs(page, 'quest.main_01', 'active');
  log('new game');

  // --- main_01: three packs of the wood, then Odile. -------------------------------
  await travel(page, 'whispering_wood');
  // The first fight at level 1, as a new player; then a little accelerated XP.
  await winPack(page);
  await levelTo(page, 3);
  // Starter gear only loses wood_04 at level 3 (bench: 60 %); a few common
  // drops (the "unlucky" profile of the bench) win it.
  await cmd(page, 'grant_gear:common/0');
  for (let i = 0; i < 2; i++) await winPack(page);
  await expect.poll(() => text(page, 'hud.quest.objective.clear_wood')).toContain('3/3');
  await travel(page, 'aubelin');
  await handIn(page, 'npc.odile', 'quest.main_01');
  log('main_01 turned in');

  // --- main_02: Maëlle; the mire (4 wins, the ferryman's journal). -----------------
  await talk(page, 'npc.maelle');
  await questIs(page, 'quest.main_02', 'active');
  await levelTo(page, 5);
  await cmd(page, 'grant_gear:uncommon/2');
  await travel(page, 'lantern_mire');
  for (let i = 0; i < 4; i++) await winPack(page);
  await cmd(page, 'go_to:discovery.ferryman_journal');
  await page.waitForTimeout(1500);
  if ((await world(page)).interact_target === 'discovery.ferryman_journal') await click(page, 'hud.interact');
  await expect
    .poll(async () => ((await world(page)).discoveries_found ?? []) as string[], { timeout: 30_000 })
    .toContain('discovery.ferryman_journal');
  await readThrough(page);
  await questIs(page, 'quest.main_02', 'completed');
  await travel(page, 'aubelin');
  await handIn(page, 'npc.maelle', 'quest.main_02');
  log('main_02 turned in');

  // --- main_03: Bastien; the watch ruins (4 sentinels, the cloister key). ----------
  await talk(page, 'npc.bastien');
  await questIs(page, 'quest.main_03', 'active');
  await levelTo(page, 9);
  await cmd(page, 'grant_gear:uncommon/3');
  await travel(page, 'watch_ruins');
  await winPack(page, 'encounter.watch_ruins_05');
  for (let i = 0; i < 6 && (await quests(page))['quest.main_03'] !== 'completed'; i++) await winPack(page);
  await questIs(page, 'quest.main_03', 'completed');
  await travel(page, 'aubelin');
  await handIn(page, 'npc.bastien', 'quest.main_03');
  log('main_03 turned in');

  // --- main_04: Odile; potions from Rosalie; level and gear for the cloister. ------
  const offer = await talk(page, 'npc.odile');
  await questIs(page, 'quest.main_04', 'active');
  log(`main_04 offered (${offer.join(', ')})`);
  await levelTo(page, 14);
  await cmd(page, 'grant_gear:rare/3');
  await cmd(page, 'grant_gold:3000');
  await use(page, 'npc.aubelin_merchant');
  await readThrough(page);
  await waitScreen(page, 'merchant');
  for (const potion of ['healing_draught', 'mana_elixir']) {
    for (let i = 0; i < 5; i++) {
      if (!(await tap(page, `shop.buy.${potion}`))) break;
      await page.waitForTimeout(700);
    }
  }
  await expect.poll(() => text(page, 'shop.carried.healing_draught')).toBe('Porté : 5 / 5');
  await backToExplore(page);

  // --- The cloister. ------------------------------------------------------------------
  await travel(page, 'watch_ruins');
  await use(page, 'gate:dungeon.silent_dial_cloister');
  await expect.poll(async () => (await state(page)).dungeon, { timeout: 30_000 }).toBe('dungeon.silent_dial_cloister');
  await expect.poll(async () => (await world(page)).location_id, { timeout: 60_000 }).toBe('dungeon.silent_dial_cloister');
  await readThrough(page);
  await expect.poll(async () => (await dungeon(page)).room).toBe('vestibule');
  log('in the cloister');

  // 1 Vestibule, 2 Gallery.
  await cmd(page, 'go_to_pack:');
  expect(await fight(page, 4), 'vestibule').toBe('victory');
  await expect.poll(async () => (await dungeon(page)).cleared as string[]).toContain('vestibule');
  await winRoom(page, 'gallery');
  // 3 Fountain: +30 % HP, once.
  await enterRoom(page, 'fountain');
  await readThrough(page);
  await use(page, 'fountain');
  await expect.poll(async () => (await dungeon(page)).fountain_used, { timeout: 15_000 }).toBe(true);
  // 4 Courtyard, its chest; 5 Kennel (the alpha).
  await winRoom(page, 'courtyard');
  await use(page, 'discovery.cloister_chest');
  await expect
    .poll(async () => ((await world(page)).discoveries_found ?? []) as string[], { timeout: 30_000 })
    .toContain('discovery.cloister_chest');
  await readThrough(page);
  await winRoom(page, 'kennel');
  // 6 Campfire: the checkpoint, rest.
  await enterRoom(page, 'campfire');
  await expect.poll(async () => (await dungeon(page)).checkpoint).toBe('campfire');
  await use(page, 'campfire');
  await expect.poll(async () => (await dungeon(page)).hp_pct, { timeout: 15_000 }).toBe(1);
  await readThrough(page);

  // 7 The dial: Morvaine (×1, played), at most three tries from the campfire.
  let won = false;
  for (let attempt = 1; attempt <= 3 && !won; attempt++) {
    await enterRoom(page, 'dial');
    await cmd(page, 'go_to_pack:encounter.cloister_boss');
    // Her intro lines come first; the fight starts after them.
    await expect.poll(async () => (await world(page)).dialogue_open || Boolean((await world(page)).combat), { timeout: 30_000 }).toBe(true);
    await readThrough(page);
    const result = await fight(page, 1);
    log(`Morvaine, try ${attempt}: ${result}`);
    won = result === 'victory';
    if (!won) {
      await expect.poll(async () => (await dungeon(page)).room, { timeout: 30_000 }).toBe('campfire');
      await use(page, 'campfire');
    }
  }
  expect(won, 'Morvaine defeated').toBe(true);
  await questIs(page, 'quest.main_04', 'active');

  // The bell: her last words, Fern's, the bell (subtitles, no input).
  await expect.poll(async () => (await world(page)).bell_rung, { timeout: 15_000 }).toBe(true);
  await expect
    .poll(async () => (await world(page)).dialogue_line, { timeout: 60_000, message: 'the bell subtitle' })
    .toBe('story.bell.subtitle');
  await expect.poll(async () => (await dungeon(page)).shortcut_open).toBe(true);
  await readThrough(page);
  log('the bell rang');

  // Out by the stair after the boss, no confirmation.
  await cmd(page, 'go_to_exit:to_watch_ruins_back');
  await expect.poll(async () => (await world(page)).location_id, { timeout: 60_000 }).toBe('location.watch_ruins');
  expect((await state(page)).dungeon).toBe('');
  await readThrough(page);

  // --- Odile: hand-in, then the epilogue cards. ------------------------------------
  await travel(page, 'aubelin');
  const end = await handIn(page, 'npc.odile', 'quest.main_04');
  log(`main_04 turned in (${end.join(', ')})`);
  expect(end).toContain('cards:epilogue');
  await expect.poll(async () => (await world(page)).story_cards).toBe('');

  // --- An offline hunt, saved. --------------------------------------------------------
  await click(page, 'hud.hunt');
  await waitScreen(page, 'hunts');
  await page.waitForTimeout(1000);
  const controls = (await probe(page))!.controls;
  const frame = controls['hunts.close'];
  const canvasH = await page.evaluate(() => document.querySelector('canvas')!.height);
  // An enabled « Choisir » shown in the list's visible part (the list scrolls).
  const hunt = Object.keys(controls).find(
    (id) =>
      /^hunts\.choose\.[a-z0-9_]+$/.test(id) &&
      !id.endsWith('_reason') &&
      controls[id].visible &&
      controls[id].disabled === false &&
      controls[id].y > frame.y + frame.h &&
      controls[id].y + controls[id].h < canvasH * 0.9,
  );
  expect(hunt, 'an offline hunt to choose').toBeTruthy();
  await click(page, hunt!);
  await expect.poll(async () => (await state(page)).farming).toBe(`encounter.${hunt!.slice('hunts.choose.'.length)}`);
  await click(page, 'hunts.close');
  await waitScreen(page, 'explore');
  await waitSaved(page, `"farming": "encounter.${hunt!.slice('hunts.choose.'.length)}"`);
  const before = await state(page);
  // Loading on a later local day also claims yesterday's completed contracts
  // (docs/content/contracts.md): whether 3 h later is another day depends on
  // when the run starts, so work out that gold from the save and the clock.
  type Book = { day_index: number; offers: { state: string; reward: { gold: number } }[] };
  const book = (JSON.parse(await readUserFile(page, 'saves/slot_0.json')).state.progress.contracts) as Book;
  const contractGold = await page.evaluate(
    ({ offset, b }) => {
      const day = Math.floor((Date.now() / 1000 + offset - new Date().getTimezoneOffset() * 60) / 86400);
      if (day <= b.day_index) return 0;
      return b.offers.filter((o) => o.state === 'completed').reduce((sum, o) => sum + o.reward.gold, 0);
    },
    { offset: 3 * 3600, b: book },
  );

  // --- Reload 3 h later: the save holds, the absence pays. -----------------------------
  await page.goto(`${START_URL}&clock_offset_s=${3 * 3600}`);
  await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
  await waitScreen(page, 'title');
  expect((await state(page)).offline_pending).toBe(true);
  expect((await state(page)).level).toBe(before.level);
  await click(page, 'title.continue');
  await waitScreen(page, 'offline_summary');
  expect((await state(page)).gold, 'the saved gold, plus any contracts of yesterday').toBe(
    (before.gold as number) + contractGold,
  );
  const gold = Number((await text(page, 'offline.gold')).replace('+', ''));
  expect(gold).toBeGreaterThan(0);
  await click(page, 'offline.claim');
  await waitScreen(page, 'explore');
  expect((await state(page)).gold).toBe((before.gold as number) + contractGold + gold);
  await expect.poll(async () => (await quests(page))['quest.main_04']).toBe('turned_in');
  for (const q of ['quest.main_01', 'quest.main_02', 'quest.main_03']) expect((await quests(page))[q]).toBe('turned_in');
  log(`done in ${Math.round((Date.now() - t0) / 1000)} s`);
});
