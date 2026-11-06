import { expect, test, type Page } from '@playwright/test';
import { boot, clearStorage, click, probe, waitScreen } from './helpers';

// ROADMAP 3.13: on touch screens, spells sit in a thumb arc (targets >= 48 px)
// and tapping an enemy focuses it.
test.use({ hasTouch: true });
test.setTimeout(240_000);

async function canvasPoint(page: Page, x: number, y: number) {
  const box = (await page.locator('canvas').boundingBox())!;
  const scale = await page.evaluate(() => {
    const c = document.querySelector('canvas')!;
    return c.width / c.clientWidth;
  });
  return { x: box.x + x / scale, y: box.y + y / scale, scale };
}

test('3.13 touch: spell buttons are large enough and tapping an enemy focuses it', async ({ page }) => {
  await clearStorage(page);
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await click(page, 'hud.map');
  await click(page, 'map.marker.whispering_wood');
  await click(page, 'map.travel');
  await expect.poll(async () => (await probe(page))!.world.location_id, { timeout: 30_000 }).toBe('location.whispering_wood');
  await page.waitForTimeout(1500);
  for (let i = 0; i < 40; i++) {
    const w = (await probe(page))!.world;
    if (w.combat) break;
    const packs = w.packs as Record<string, { x: number; y: number; dist: number }>;
    const ids = Object.keys(packs ?? {}).sort((a, b) => packs[a].dist - packs[b].dist);
    if (!ids.length) break;
    const ps = w.player_screen as { x: number; y: number };
    const t = packs[ids[0]];
    const k = Math.min(1, 200 / Math.max(1, Math.hypot(t.x - ps.x, t.y - ps.y)));
    const p = await canvasPoint(page, ps.x + (t.x - ps.x) * k, ps.y + (t.y - ps.y) * k);
    await page.touchscreen.tap(p.x, p.y);
    await page.waitForTimeout(1500);
  }
  await expect.poll(async () => (await probe(page))!.world.combat, { timeout: 30_000 }).toBeTruthy();

  const button = (await probe(page))!.controls['combat.spell.zoltraak'];
  const { scale } = await canvasPoint(page, 0, 0);
  expect(button.w / scale).toBeGreaterThanOrEqual(48);
  expect(button.h / scale).toBeGreaterThanOrEqual(48);

  await expect
    .poll(async () => Object.keys((await probe(page))!.world.combat_snapshot?.targets ?? {}).length, { timeout: 20_000 })
    .toBeGreaterThan(0);
  const targets = (await probe(page))!.world.combat_snapshot.targets as Record<string, { x: number; y: number }>;
  const [uid, at] = Object.entries(targets)[0];
  const p = await canvasPoint(page, at.x, at.y);
  await page.touchscreen.tap(p.x, p.y);
  await expect.poll(async () => (await probe(page))!.world.combat_snapshot?.focus, { timeout: 10_000 }).toBe(uid);
});
