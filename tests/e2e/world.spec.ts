import { expect, test, type Page } from '@playwright/test';
import { boot, clearStorage, click, probe, waitSaved, waitScreen } from './helpers';

// Note: the CI container renders WebGL in software (SwiftShader, ~5 fps), so
// physics runs slower than real time. Movement checks therefore wait for the
// distance with a generous timeout instead of a strict 2 s (ROADMAP 2.1).

async function newGame(page: Page): Promise<void> {
  await clearStorage(page);
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await expect.poll(async () => (await probe(page))!.world.location_id).toBe('location.aubelin');
}

type Vec = { x: number; z: number };
const player = async (page: Page): Promise<Vec> => (await probe(page))!.world.player as Vec;
const dist = (a: Vec, b: Vec) => Math.hypot(a.x - b.x, a.z - b.z);

async function canvasPoint(page: Page, x: number, y: number) {
  const box = (await page.locator('canvas').boundingBox())!;
  const scale = await page.evaluate(() => {
    const c = document.querySelector('canvas')!;
    return c.width / c.clientWidth;
  });
  return { x: box.x + x / scale, y: box.y + y / scale };
}

test('Fern walks with the keyboard (WASD / ZQSD positions)', async ({ page }) => {
  await newGame(page);
  const start = await player(page);
  await page.locator('canvas').focus();
  // South leads down the village road, away from the well.
  await page.keyboard.down('KeyS');
  await expect.poll(async () => dist(start, await player(page)), { timeout: 20_000 }).toBeGreaterThanOrEqual(8);
  await page.keyboard.up('KeyS');
});

test('Fern walks where the player clicks', async ({ page }) => {
  await newGame(page);
  const start = await player(page);
  const ps = (await probe(page))!.world.player_screen as { x: number; y: number };
  const h = await page.evaluate(() => document.querySelector('canvas')!.height);
  const target = await canvasPoint(page, ps.x, ps.y + h * 0.22);
  await page.mouse.click(target.x, target.y);
  await expect.poll(async () => dist(start, await player(page)), { timeout: 20_000 }).toBeGreaterThanOrEqual(2);
});

test('the world map opens, zooms, pans and explains locked places', async ({ page }) => {
  await newGame(page);
  await page.locator('canvas').focus();
  await page.keyboard.press('KeyM');
  await waitScreen(page, 'world_map');
  await click(page, 'map.zoom_in');
  await expect.poll(async () => (await probe(page))!.world.map.zoom).toBe(1.5);
  const before = (await probe(page))!.world.map;
  const frame = (await probe(page))!.controls['map.frame'];
  const from = await canvasPoint(page, frame.x + frame.w / 2, frame.y + frame.h / 2);
  await page.mouse.move(from.x, from.y);
  await page.mouse.down();
  await page.mouse.move(from.x - 120, from.y - 60, { steps: 6 });
  await page.mouse.up();
  await expect
    .poll(async () => {
      const m = (await probe(page))!.world.map;
      return Math.abs(m.pan_x - before.pan_x) + Math.abs(m.pan_y - before.pan_y);
    })
    .toBeGreaterThan(20);
  await click(page, 'map.zoom_in');
  await expect.poll(async () => (await probe(page))!.world.map.zoom).toBe(2.25);
  await click(page, 'map.zoom_out');
  await click(page, 'map.zoom_out');
  await click(page, 'map.marker.lantern_mire');
  await expect.poll(async () => (await probe(page))!.controls['map.detail_status'].text).toContain('Accessible au niveau 4');
  expect((await probe(page))!.controls['map.travel'].disabled).toBe(true);
});

test('travel from the map loads the place fast; fog stays lifted after a reload', async ({ page }) => {
  await newGame(page);
  expect((await probe(page))!.controls['map.marker.watch_ruins']).toBeUndefined();
  await click(page, 'hud.map');
  await waitScreen(page, 'world_map');
  expect((await probe(page))!.controls['map.marker.watch_ruins']).toBeUndefined();
  await click(page, 'map.marker.whispering_wood');
  await click(page, 'map.travel');
  await waitScreen(page, 'explore');
  await expect.poll(async () => (await probe(page))!.world.location_id).toBe('location.whispering_wood');
  const w = (await probe(page))!.world;
  expect(w.location_ready_at_ms - w.travel_clicked_ms).toBeLessThanOrEqual(1500);

  await waitSaved(page, '"location_id": "location.whispering_wood"');
  await page.reload();
  await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
  await click(page, 'title.continue');
  await waitScreen(page, 'explore');
  expect((await probe(page))!.state.location_id).toBe('location.whispering_wood');
  await click(page, 'hud.map');
  await waitScreen(page, 'world_map');
  await expect.poll(async () => (await probe(page))!.controls['map.marker.watch_ruins']?.visible).toBe(true);
});

test('walking into a zone exit leads to the neighbouring place', async ({ page }) => {
  test.setTimeout(240_000);
  await newGame(page);
  const size = await page.evaluate(() => {
    const c = document.querySelector('canvas')!;
    return { w: c.width, h: c.height };
  });
  const onHud = (x: number, y: number, controls: Record<string, { x: number; y: number; w: number; h: number; visible: boolean }>) =>
    Object.entries(controls).some(
      ([id, c]) => id.startsWith('hud.') && c.visible && x >= c.x - 20 && x <= c.x + c.w + 20 && y >= c.y - 20 && y <= c.y + c.h + 20,
    );
  let last = await player(page);
  let turn = 0;
  for (let i = 0; i < 60; i++) {
    const snap = (await probe(page))!;
    if (snap.world.location_id === 'location.whispering_wood') break;
    const exit = snap.world.exits?.['location.whispering_wood'] as { x: number; y: number } | undefined;
    const ps = snap.world.player_screen as { x: number; y: number };
    // Head for the exit (off-screen points are still projected), turning when stuck.
    let angle = Math.atan2((exit?.y ?? ps.y - 150) - ps.y, (exit?.x ?? ps.x - 300) - ps.x) + turn;
    const remaining = exit ? Math.hypot(exit.x - ps.x, exit.y - ps.y) : Infinity;
    let target = { x: ps.x, y: ps.y };
    for (const f of [0.4, 0.3, 0.2]) {
      const r = Math.min(remaining, Math.min(size.w, size.h) * f);
      const x = Math.min(Math.max(ps.x + Math.cos(angle) * r, 8), size.w - 8);
      const y = Math.min(Math.max(ps.y + Math.sin(angle) * r, 8), size.h - 8);
      if (!onHud(x, y, snap.controls)) {
        target = { x, y };
        break;
      }
    }
    const p = await canvasPoint(page, target.x, target.y);
    await page.mouse.click(p.x, p.y);
    await page.waitForTimeout(2000);
    const now = await player(page);
    turn = dist(now, last) < 0.5 ? (turn <= 0 ? -turn + Math.PI / 4 : -turn) : 0;
    last = now;
  }
  await expect.poll(async () => (await probe(page))!.world.location_id, { timeout: 20_000 }).toBe('location.whispering_wood');
  expect((await probe(page))!.state.location_id).toBe('location.whispering_wood');
});
