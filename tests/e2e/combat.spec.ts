import { expect, test, type Page } from '@playwright/test';
import { boot, clearStorage, click, probe, waitScreen } from './helpers';

// Milestone 3 (ROADMAP 3.5-3.13). Combats start on the spot when Fern walks
// into a pack in the Whispering Wood. Software WebGL is slow: generous timeouts.
test.setTimeout(240_000);

async function canvasPoint(page: Page, x: number, y: number) {
  const box = (await page.locator('canvas').boundingBox())!;
  const scale = await page.evaluate(() => {
    const c = document.querySelector('canvas')!;
    return c.width / c.clientWidth;
  });
  return { x: box.x + x / scale, y: box.y + y / scale };
}

type Point = { x: number; y: number; dist?: number };

/** New game, travel to the wood, walk to the nearest pack until combat starts. */
async function enterCombat(page: Page): Promise<string> {
  await clearStorage(page);
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await click(page, 'hud.map');
  await waitScreen(page, 'world_map');
  await click(page, 'map.marker.whispering_wood');
  await click(page, 'map.travel');
  await expect.poll(async () => (await probe(page))!.world.location_id, { timeout: 30_000 }).toBe('location.whispering_wood');
  await page.waitForTimeout(1500);
  for (let i = 0; i < 40; i++) {
    const w = (await probe(page))!.world;
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
  await expect.poll(async () => (await probe(page))!.world.combat, { timeout: 30_000 }).toBeTruthy();
  return (await probe(page))!.world.combat as string;
}

const world = async (page: Page) => (await probe(page))!.world;

test('3.5 the first combat is won without any action and grants a level', async ({ page }) => {
  await enterCombat(page);
  await expect.poll(async () => (await world(page)).combat_result, { timeout: 120_000 }).toBe('victory');
  await expect.poll(async () => (await probe(page))!.controls['combat.result_title']?.text).toBe('Victoire');
  await click(page, 'combat.continue');
  await expect.poll(async () => (await world(page)).combat).toBeFalsy();
  await expect.poll(async () => (await probe(page))!.controls['hud.level'].text).toBe('Niv. 2');
});

test('3.6 key 1 casts Zoltraak, the cooldown shows and a refusal is explained', async ({ page }) => {
  await enterCombat(page);
  await page.locator('canvas').focus();
  // Wait until Zoltraak is ready, then press 1.
  await expect
    .poll(async () => Number((await world(page)).combat_snapshot?.cooldowns?.['spell.zoltraak'] ?? 0), { timeout: 30_000 })
    .toBe(0);
  await page.keyboard.press('Digit1');
  await expect
    .poll(async () => Number((await world(page)).combat_snapshot?.cooldowns?.['spell.zoltraak'] ?? 0), { timeout: 15_000 })
    .toBeGreaterThan(1);
  await expect.poll(async () => (await probe(page))!.controls['combat.log'].text).toContain('Fern lance Zoltraak');
  // Pressing again during the cooldown is refused with the reason on screen.
  await page.keyboard.press('Digit1');
  await expect.poll(async () => (await probe(page))!.messages.join('\n')).toContain('Sort en recharge');
});

test('3.7 pause freezes the simulation and 3.8 x2 speeds it up', async ({ page }) => {
  await enterCombat(page);
  await page.locator('canvas').focus();
  await page.keyboard.press('Space');
  await expect.poll(async () => (await world(page)).combat_paused).toBe(true);
  const frozen = (await world(page)).combat_ticks;
  await page.waitForTimeout(2000);
  expect((await world(page)).combat_ticks).toBe(frozen);
  await page.keyboard.press('Space');
  await expect.poll(async () => (await world(page)).combat_paused).toBe(false);

  const rate = async () => {
    const a = (await world(page)).combat_ticks as number;
    const t = Date.now();
    await page.waitForTimeout(2500);
    return (((await world(page)).combat_ticks as number) - a) / ((Date.now() - t) / 1000);
  };
  const x1 = await rate();
  await click(page, 'combat.speed');
  await expect.poll(async () => (await world(page)).combat_speed).toBe(2);
  const x2 = await rate();
  expect(x2 / x1).toBeGreaterThan(1.5);
});

test('3.11 a defeat sends Fern back to the entrance, nothing lost', async ({ page }) => {
  await enterCombat(page);
  const gold = (await probe(page))!.state.gold;
  await page.evaluate(() => (window as unknown as { __afterlightTest: (n: string) => void }).__afterlightTest('defeat_party'));
  await expect.poll(async () => (await world(page)).combat_result, { timeout: 60_000 }).toBe('defeat');
  await expect.poll(async () => (await probe(page))!.controls['combat.result_title']?.text).toBe('Défaite');
  await click(page, 'combat.continue');
  await expect.poll(async () => (await world(page)).combat).toBeFalsy();
  expect((await world(page)).location_id).toBe('location.whispering_wood');
  expect((await probe(page))!.state.gold).toBe(gold);
  expect((await probe(page))!.state.level).toBe(1);
});

test('3.12 the combat log lists damage and filters by source', async ({ page }) => {
  await enterCombat(page);
  await expect.poll(async () => (await probe(page))!.controls['combat.log']?.text ?? '', { timeout: 30_000 }).toMatch(/Loup des brumes inflige/);
  await expect.poll(async () => (await probe(page))!.controls['combat.log'].text).toMatch(/Fern (inflige|lance)/);
  await click(page, 'combat.log_filter.enemies');
  await expect.poll(async () => (await probe(page))!.controls['combat.log'].text).not.toMatch(/^Fern /m);
  await click(page, 'combat.log_filter.party');
  await expect.poll(async () => (await probe(page))!.controls['combat.log'].text).not.toMatch(/^Loup des brumes /m);
});
