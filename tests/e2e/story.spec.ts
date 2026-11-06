import { expect, test, type Page } from '@playwright/test';
import { START_URL, boot, clearStorage, click, probe, waitSaved, waitScreen } from './helpers';

// Milestone 6 (ROADMAP 6.4, 6.5, 6.6): the intro cards and the first fight,
// the bestiary and the discoveries (fog, journal), quest objectives that
// advance on the right event and survive a reload.
// `intro=1` keeps the intro cards on the test channel (other specs skip
// them); `go_to_discovery` (test channel, game/app/screens/explore_screen.gd)
// puts Fern on the first discovery of the place not found yet.
test.setTimeout(300_000);

type Point = { x: number; y: number; dist?: number };

const INTRO_URL = `${START_URL}&intro=1`;
const world = async (page: Page) =>
  ((await probe(page)) as unknown as { world: Record<string, unknown> }).world;
const text = async (page: Page, id: string) => (await probe(page))!.controls[id]?.text ?? '';
const controls = async (page: Page) => (await probe(page))!.controls;
const testCommand = (page: Page, name: string) =>
  page.evaluate((n) => (window as unknown as { __afterlightTest: (n: string) => void }).__afterlightTest(n), name);

async function canvasPoint(page: Page, x: number, y: number) {
  const box = (await page.locator('canvas').boundingBox())!;
  const scale = await page.evaluate(() => {
    const c = document.querySelector('canvas')!;
    return c.width / c.clientWidth;
  });
  return { x: box.x + x / scale, y: box.y + y / scale };
}

/** New game with the intro cards; « Passer » skips them. Returns the click time. */
async function newGameSkippingIntro(page: Page): Promise<number> {
  await clearStorage(page);
  await page.goto(INTRO_URL);
  await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
  await waitScreen(page, 'title');
  const started = Date.now();
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await expect.poll(async () => (await world(page)).story_cards, { timeout: 15_000 }).toBe('intro');
  expect(await text(page, 'story.card')).toContain('cloche');
  await click(page, 'story.skip');
  await expect.poll(async () => (await world(page)).story_cards).toBe('');
  return started;
}

async function travel(page: Page, short: string): Promise<void> {
  await click(page, 'hud.map');
  await waitScreen(page, 'world_map');
  await click(page, `map.marker.${short}`);
  await click(page, 'map.travel');
  await expect.poll(async () => (await world(page)).location_id, { timeout: 30_000 }).toBe(`location.${short}`);
}

/** Walks into the nearest pack (as in combat.spec.ts) until the fight starts. */
async function engageNearest(page: Page): Promise<void> {
  await page.waitForTimeout(1000);
  for (let i = 0; i < 40; i++) {
    const w = await world(page);
    if (w.combat) break;
    const packs = (w.packs ?? {}) as Record<string, Point>;
    const ids = Object.keys(packs).sort((a, b) => (packs[a].dist ?? 0) - (packs[b].dist ?? 0));
    if (ids.length === 0) break;
    const ps = w.player_screen as Point;
    const t = packs[ids[0]];
    const k = Math.min(1, 250 / Math.max(1, Math.hypot(t.x - ps.x, t.y - ps.y)));
    const p = await canvasPoint(page, ps.x + (t.x - ps.x) * k, ps.y + (t.y - ps.y) * k);
    await page.mouse.click(p.x, p.y);
    await page.waitForTimeout(1500);
  }
  await expect.poll(async () => (await world(page)).combat, { timeout: 30_000 }).toBeTruthy();
}

async function winOnce(page: Page): Promise<void> {
  await engageNearest(page);
  await expect.poll(async () => (await world(page)).combat_result, { timeout: 120_000 }).toBe('victory');
  await click(page, 'combat.continue');
  await expect.poll(async () => (await world(page)).combat).toBeFalsy();
}

const banners = async (page: Page) => ((await world(page)).banners ?? []) as string[];

test('6.4 new game, intro skipped, the first fight starts within 60 s', async ({ page }) => {
  const started = await newGameSkippingIntro(page);
  // Odile waits by the well with her quest marker.
  await expect
    .poll(async () => ((await world(page)).interactables as Record<string, { kind: string }> | undefined)?.['npc.odile']?.kind)
    .toBe('npc');
  expect(await text(page, 'hud.quest')).toBe('Une cloche qui ne sonne plus');
  await travel(page, 'whispering_wood');
  await engageNearest(page);
  const elapsed = (Date.now() - started) / 1000;
  expect(elapsed).toBeLessThanOrEqual(60);
});

test('6.5 one win opens a bestiary entry; a discovery lifts the fog and is listed', async ({ page }) => {
  await newGameSkippingIntro(page);
  await travel(page, 'whispering_wood');
  await winOnce(page);
  await expect.poll(async () => (await banners(page)).some((b) => /^Bestiaire : .+, nouvelle fiche$/.test(b))).toBe(true);

  // The journal's bestiary shows the tier 1 entry, and what unlocks tier 2.
  await click(page, 'hud.journal');
  await waitScreen(page, 'journal');
  await click(page, 'journal.tab.bestiary');
  await expect
    .poll(async () => Object.keys(await controls(page)).filter((id) => /^journal\.bestiary\.[a-z_]+\.tier$/.test(id)).length)
    .toBeGreaterThan(0);
  const tiers = Object.entries(await controls(page)).filter(([id]) => /^journal\.bestiary\.[a-z_]+\.tier$/.test(id));
  expect(tiers.some(([, c]) => (c.text ?? '').startsWith('Palier 1 : nouvelle fiche'))).toBe(true);
  const nexts = Object.entries(await controls(page)).filter(([id]) => /^journal\.bestiary\.[a-z_]+\.next$/.test(id));
  expect(nexts.some(([, c]) => c.text === 'Prochain palier : 5 victoires')).toBe(true);
  await click(page, 'journal.close');
  await waitScreen(page, 'explore');

  // A discovery of the wood: found on arrival (zone), banner, journal, fog.
  await page.waitForTimeout(500);
  await testCommand(page, 'go_to_discovery');
  await expect.poll(async () => ((await world(page)).discoveries_found ?? []) as string[], { timeout: 15_000 }).not.toEqual([]);
  const found = (((await world(page)).discoveries_found ?? []) as string[])[0];
  await expect.poll(async () => (await banners(page)).some((b) => b.startsWith('Découverte : '))).toBe(true);
  await click(page, 'hud.journal');
  await waitScreen(page, 'journal');
  await click(page, 'journal.tab.discoveries');
  await expect.poll(() => text(page, 'journal.discoveries.whispering_wood.count')).toBe('Découvertes 1/2');
  const short = found.split('.')[1];
  expect(await text(page, `journal.discovery.${short}`)).not.toBe('???');
  await click(page, 'journal.close');
  await waitScreen(page, 'explore');
  await click(page, 'hud.map');
  await waitScreen(page, 'world_map');
  await expect.poll(async () => ((await world(page)).fog_discs ?? []) as string[]).toContain(found);
});

test('6.6 a quest objective advances on the right event and survives a reload', async ({ page }) => {
  await newGameSkippingIntro(page);
  await expect.poll(() => text(page, 'hud.quest.objective.clear_wood')).toContain('(0/3)');

  // Entering the wood is not a fight: the count does not move.
  await travel(page, 'whispering_wood');
  await page.waitForTimeout(500);
  expect(await text(page, 'hud.quest.objective.clear_wood')).toContain('(0/3)');

  // A won fight there is: 1/3, with its banner, then saved.
  await winOnce(page);
  await expect.poll(() => text(page, 'hud.quest.objective.clear_wood')).toContain('(1/3)');
  expect((await banners(page)).some((b) => b.includes('(1/3)'))).toBe(true);
  await waitSaved(page, 'clear_wood');

  // Reload mid-quest: the state is the same.
  await page.goto(START_URL);
  await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
  await waitScreen(page, 'title');
  await click(page, 'title.continue');
  await waitScreen(page, 'explore');
  await expect.poll(() => text(page, 'hud.quest.objective.clear_wood')).toContain('(1/3)');

  // Talking to Odile is the other objective (TalkedTo).
  await travel(page, 'aubelin');
  await expect.poll(async () => (await world(page)).interact_target, { timeout: 15_000 }).toBe('npc.odile');
  await click(page, 'hud.interact');
  await expect.poll(() => text(page, 'dialogue.speaker')).toBe('Odile');
  await click(page, 'dialogue.skip');
  await expect.poll(() => text(page, 'hud.quest.objective.meet_odile')).toContain(': fait');
  expect(await text(page, 'hud.quest.objective.clear_wood')).toContain('(1/3)');
});
