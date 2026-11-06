import { expect, test, type Page, type TestInfo } from '@playwright/test';
import { boot, clearStorage, click, probe, waitScreen, type Probe } from './helpers';

// Milestone 7 accessibility (ROADMAP 1.11, 7.3, 7.6, 7.7). Software WebGL is
// slow: generous timeouts.
test.setTimeout(240_000);

type Rect = { x: number; y: number; w: number; h: number; visible: boolean; text?: string };
type MotionFlags = {
  reduce_motion: boolean;
  camera_shake: boolean;
  screen_fades: boolean;
  hit_stop: boolean;
  particle_scale: number;
  shakes_applied: number;
  hit_stops_applied: number;
  fades_played: number;
};
type Full = Probe & {
  world: Record<string, unknown> & { motion_flags?: MotionFlags };
  settings: Probe['settings'] & { bindings?: Record<string, unknown> };
};
type Point = { x: number; y: number; dist?: number };

const full = async (page: Page) => (await probe(page)) as Full;
const control = async (page: Page, id: string) => (await full(page)).controls[id] as Rect | undefined;
const flags = async (page: Page) => (await full(page)).world.motion_flags!;

function testCommand(page: Page, name: string) {
  return page.evaluate((n) => (window as unknown as { __afterlightTest: (n: string) => void }).__afterlightTest(n), name);
}

async function canvasSize(page: Page) {
  return page.evaluate(() => {
    const c = document.querySelector('canvas')!;
    return { w: c.width, h: c.height };
  });
}

async function canvasPoint(page: Page, x: number, y: number) {
  const box = (await page.locator('canvas').boundingBox())!;
  const scale = await page.evaluate(() => {
    const c = document.querySelector('canvas')!;
    return c.width / c.clientWidth;
  });
  return { x: box.x + x / scale, y: box.y + y / scale };
}

/**
 * Every visible registered control lies inside the canvas. Controls whose id
 * starts with one of `scrolled` live in a scroll list: only their horizontal
 * extent is checked.
 */
async function expectNoOverflow(page: Page, label: string, scrolled: string[] = []) {
  const size = await canvasSize(page);
  const controls = (await full(page)).controls as Record<string, Rect>;
  const out: string[] = [];
  for (const [id, c] of Object.entries(controls)) {
    if (!c.visible || c.w <= 0 || c.h <= 0) continue;
    if (c.x < -1 || c.x + c.w > size.w + 1) out.push(`${id} sideways ${JSON.stringify(c)}`);
    if (!scrolled.some((p) => id.startsWith(p)) && (c.y < -1 || c.y + c.h > size.h + 1)) {
      out.push(`${id} vertically ${JSON.stringify(c)}`);
    }
  }
  expect(out, `${label}: controls outside the ${size.w}x${size.h} canvas`).toEqual([]);
}

async function capture(page: Page, info: TestInfo, name: string) {
  // Saved under test-results/<test>/ for the reference captures of 7.7.
  await page.screenshot({ path: info.outputPath(`${name}-${info.project.name}.png`) });
}

/** From the current game: travel to the wood and walk into the nearest pack. */
async function walkIntoCombat(page: Page): Promise<void> {
  await click(page, 'hud.map');
  await waitScreen(page, 'world_map');
  await click(page, 'map.marker.whispering_wood');
  await click(page, 'map.travel');
  await expect.poll(async () => (await full(page)).world.location_id, { timeout: 30_000 }).toBe('location.whispering_wood');
  await page.waitForTimeout(1500);
  for (let i = 0; i < 40; i++) {
    const w = (await full(page)).world;
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
  await expect.poll(async () => (await full(page)).world.combat, { timeout: 30_000 }).toBeTruthy();
}

const zoltraakCooldown = async (page: Page) =>
  Number(((await full(page)).world.combat_snapshot as { cooldowns?: Record<string, number> } | undefined)?.cooldowns?.['spell.zoltraak'] ?? 0);

async function openControls(page: Page) {
  await click(page, 'title.settings');
  await waitScreen(page, 'settings');
  await click(page, 'settings.tab.controls');
  await expect.poll(async () => (await control(page, 'controls.key.combat_spell_1'))?.visible).toBe(true);
}

test('7.6 spell 1 rebound to G survives a reload and casts', async ({ page }) => {
  await clearStorage(page);
  await boot(page);
  await openControls(page);
  expect((await control(page, 'controls.key.combat_spell_1'))!.text).toContain('1');

  // Rebind: the button waits for a key, then shows it.
  await click(page, 'controls.key.combat_spell_1');
  await expect.poll(async () => (await control(page, 'controls.key.combat_spell_1'))?.text).toBe('Appuyez sur une touche…');
  await page.keyboard.press('KeyG');
  await expect.poll(async () => (await control(page, 'controls.key.combat_spell_1'))?.text).toBe('G');
  await expect.poll(async () => (await full(page)).messages.join('\n')).toContain('« Sort 1 » : G.');

  // A conflict swaps the two commands, with a message saying so; swap back.
  await click(page, 'controls.key.combat_spell_2');
  await page.keyboard.press('KeyG');
  await expect.poll(async () => (await control(page, 'controls.key.combat_spell_2'))?.text).toBe('G');
  expect((await control(page, 'controls.key.combat_spell_1'))!.text).toContain('2');
  await expect.poll(async () => (await full(page)).messages.join('\n')).toContain('ont échangé leurs commandes');
  await click(page, 'controls.key.combat_spell_1');
  await page.keyboard.press('KeyG');
  await expect.poll(async () => (await control(page, 'controls.key.combat_spell_1'))?.text).toBe('G');
  expect((await control(page, 'controls.key.combat_spell_2'))!.text).toContain('2');

  // Escape is reserved: it cancels the capture and keeps the binding.
  await click(page, 'controls.key.interact');
  await page.keyboard.press('Escape');
  await expect.poll(async () => (await full(page)).messages.join('\n')).toContain('Changement annulé.');
  expect((await control(page, 'controls.key.interact'))!.text).toBe('E');
  await expect.poll(async () => (await full(page)).settings.bindings?.combat_spell_1).toBeTruthy();

  // Persisted (user:// is IndexedDB on the web): the reload keeps it.
  await page.waitForTimeout(1500);
  await page.reload();
  await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
  expect((await full(page)).settings.bindings?.combat_spell_1).toBeTruthy();
  await openControls(page);
  expect((await control(page, 'controls.key.combat_spell_1'))!.text).toBe('G');
  await click(page, 'settings.back');
  await waitScreen(page, 'title');

  // In combat, G casts Zoltraak; 1 no longer does.
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await walkIntoCombat(page);
  await page.locator('canvas').focus();
  await expect.poll(() => zoltraakCooldown(page), { timeout: 30_000 }).toBe(0);
  await page.keyboard.press('Digit1');
  await page.waitForTimeout(800);
  expect(await zoltraakCooldown(page)).toBe(0);
  await page.keyboard.press('KeyG');
  await expect.poll(() => zoltraakCooldown(page), { timeout: 15_000 }).toBeGreaterThan(1);
});

test('7.3 reduce motion: cuts, no shake, no hit-stop, half the particles', async ({ page }) => {
  await clearStorage(page);
  await boot(page);
  await testCommand(page, 'reduce_motion:0');
  await expect.poll(async () => (await flags(page))?.screen_fades).toBe(true);
  const f0 = await flags(page);
  expect(f0).toMatchObject({ camera_shake: true, hit_stop: true, particle_scale: 1 });
  // A screen change fades.
  await click(page, 'title.settings');
  await waitScreen(page, 'settings');
  await expect.poll(async () => (await flags(page)).fades_played).toBeGreaterThan(f0.fades_played);

  await testCommand(page, 'reduce_motion:1');
  await expect.poll(async () => (await flags(page)).reduce_motion).toBe(true);
  expect(await flags(page)).toMatchObject({ camera_shake: false, screen_fades: false, hit_stop: false, particle_scale: 0.5 });
  // Screen changes now cut.
  const fades = (await flags(page)).fades_played;
  await click(page, 'settings.back');
  await waitScreen(page, 'title');
  expect((await flags(page)).fades_played).toBe(fades);

  // A whole first combat (crits included) plays without shake or hit-stop.
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await walkIntoCombat(page);
  await expect.poll(async () => (await full(page)).world.combat_result, { timeout: 120_000 }).toBe('victory');
  const after = await flags(page);
  expect(after.shakes_applied).toBe(0);
  expect(after.hit_stops_applied).toBe(0);
  expect(after.fades_played).toBe(fades);
});

test('1.11 and 7.7 text at 130 %: title, settings and HUD without overflow', async ({ page }, info) => {
  await clearStorage(page);
  await boot(page);
  await testCommand(page, 'text_scale:1');
  await expect.poll(async () => (await full(page)).settings.text_scale).toBe(1);
  await page.waitForTimeout(500);
  const normal = (await control(page, 'title.new_game'))!;
  await capture(page, info, 'title-100');

  await testCommand(page, 'text_scale:3');
  await expect.poll(async () => (await full(page)).settings.text_scale).toBeCloseTo(1.3);
  await page.waitForTimeout(500);
  const big = (await control(page, 'title.new_game'))!;
  await capture(page, info, 'title-130');
  // The text grew and the button grew with it: nothing is cut.
  expect(big.h).toBeGreaterThanOrEqual(normal.h);
  expect(big.text).toBe(normal.text);
  await expectNoOverflow(page, 'title 130 %');

  await click(page, 'title.settings');
  await waitScreen(page, 'settings');
  await page.waitForTimeout(400);
  await capture(page, info, 'settings-130');
  await expectNoOverflow(page, 'settings 130 %');
  await click(page, 'settings.tab.controls');
  await expect.poll(async () => (await control(page, 'controls.key.interact'))?.visible).toBe(true);
  await page.waitForTimeout(400);
  await capture(page, info, 'settings-controls-130');
  await expectNoOverflow(page, 'settings controls 130 %', ['controls.']);
  await click(page, 'settings.back');
  await waitScreen(page, 'title');

  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await page.waitForTimeout(1500);
  await capture(page, info, 'explore-130');
  await expectNoOverflow(page, 'explore HUD 130 %');
});
