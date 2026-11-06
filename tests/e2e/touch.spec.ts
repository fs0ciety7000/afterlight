import { expect, test } from '@playwright/test';
import { boot, clearStorage, click, probe, waitScreen } from './helpers';

test.use({ hasTouch: true });

test('the touch joystick moves Fern', async ({ page }) => {
  await clearStorage(page);
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await expect.poll(async () => (await probe(page))!.controls['hud.joystick']?.visible).toBe(true);
  const stick = (await probe(page))!.controls['hud.joystick'];
  const box = (await page.locator('canvas').boundingBox())!;
  const scale = await page.evaluate(() => {
    const c = document.querySelector('canvas')!;
    return c.width / c.clientWidth;
  });
  const cx = box.x + (stick.x + stick.w / 2) / scale;
  const cy = box.y + (stick.y + stick.h / 2) / scale;
  const start = (await probe(page))!.world.player as { x: number; z: number };
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: cx, y: cy }] });
  for (let i = 1; i <= 5; i++) {
    await cdp.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: cx, y: cy + i * 12 }] });
  }
  await expect
    .poll(async () => {
      const p = (await probe(page))!.world.player as { x: number; z: number };
      return Math.hypot(p.x - start.x, p.z - start.z);
    }, { timeout: 20_000 })
    .toBeGreaterThanOrEqual(8);
  await cdp.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
});
