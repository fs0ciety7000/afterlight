import { expect, test } from '@playwright/test';
import { boot, clearStorage, click, probe, waitScreen } from './helpers';

test.beforeEach(async ({ page }) => {
  await clearStorage(page);
});

test('first launch shows the title with New game and no Continue', async ({ page }) => {
  await boot(page);
  await waitScreen(page, 'title');
  const p = await probe(page);
  expect(p!.controls['title.new_game'].visible).toBe(true);
  expect(p!.controls['title.continue']?.visible ?? false).toBe(false);
});

test('new game, save, reload and continue restores the game', async ({ page }) => {
  await boot(page);
  await waitScreen(page, 'title');
  await click(page, 'title.new_game');
  await waitScreen(page, 'camp');
  let p = await probe(page);
  expect(p!.state.leader).toBe('character.fern');
  expect(p!.state.level).toBe(1);
  expect(p!.controls['camp.party.0.level'].text).toBe('Niveau 1');
  const createdAt = p!.state.created_at;

  await click(page, 'camp.save');
  await expect.poll(async () => (await probe(page))!.controls['camp.save_status'].text).toMatch(/^Sauvegardé à \d\d:\d\d$/);

  // Give IDBFS a moment to sync, then reload the page like a returning player.
  await page.waitForTimeout(1500);
  await page.reload();
  await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
  await waitScreen(page, 'title');
  await click(page, 'title.continue');
  await waitScreen(page, 'camp');
  p = await probe(page);
  expect(p!.state.created_at).toBe(createdAt);
  expect(p!.state.leader).toBe('character.fern');
});

test('starting over asks for confirmation and can be cancelled', async ({ page }) => {
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'camp');
  const createdAt = (await probe(page))!.state.created_at;
  await click(page, 'camp.main_menu');
  await waitScreen(page, 'title');
  await click(page, 'title.new_game');
  await click(page, 'new_game_confirm.cancel');
  await page.waitForTimeout(300);
  expect((await probe(page))!.screen).toBe('title');
  expect((await probe(page))!.state.created_at).toBe(createdAt);
});
