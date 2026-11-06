import { expect, test } from '@playwright/test';
import { boot, clearStorage, probe, waitScreen } from './helpers';

test('title and settings work with the keyboard alone', async ({ page }) => {
  await clearStorage(page);
  await boot(page);
  await waitScreen(page, 'title');
  await page.locator('canvas').focus();
  // Focus starts on "Nouvelle partie"; move down to "Réglages" and open it.
  await page.waitForTimeout(500);
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('ArrowDown');
  await page.keyboard.press('Enter');
  await waitScreen(page, 'settings');
  await page.keyboard.press('Escape');
  await waitScreen(page, 'title');
  // Back on the title, Enter on the focused first button starts a game.
  await page.waitForTimeout(500);
  await page.keyboard.press('Enter');
  await waitScreen(page, 'explore');
  expect((await probe(page))!.state.leader).toBe('character.fern');
});
