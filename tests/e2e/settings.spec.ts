import { expect, test } from '@playwright/test';
import { boot, clearStorage, click, probe, waitScreen } from './helpers';

test('reduced motion setting persists across reloads', async ({ page }) => {
  await clearStorage(page);
  await boot(page);
  await click(page, 'title.settings');
  await waitScreen(page, 'settings');
  const before = (await probe(page))!.settings.reduce_motion;
  await click(page, 'settings.reduce_motion');
  await expect.poll(async () => (await probe(page))!.settings.reduce_motion).toBe(!before);
  await page.waitForTimeout(1500);
  await page.reload();
  await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
  expect((await probe(page))!.settings.reduce_motion).toBe(!before);
  await click(page, 'title.settings');
  await click(page, 'settings.back');
  await waitScreen(page, 'title');
});
