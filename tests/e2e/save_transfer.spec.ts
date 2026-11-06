import { readFileSync, writeFileSync } from 'node:fs';
import { expect, test } from '@playwright/test';
import { boot, clearStorage, click, probe, waitScreen } from './helpers';

test.beforeEach(async ({ page }) => {
  await clearStorage(page);
});

test('export downloads a valid save that imports back after confirmation', async ({ page }, info) => {
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  const createdAt = (await probe(page))!.state.created_at;

  const downloadPromise = page.waitForEvent('download');
  await click(page, 'hud.menu');
  await click(page, 'menu.export');
  const download = await downloadPromise;
  const file = info.outputPath('save.json');
  await download.saveAs(file);
  const save = JSON.parse(readFileSync(file, 'utf8'));
  expect(save.format).toBe('afterlight-save');
  expect(save.version).toBe(6);
  expect(save.state.party[0]).toBe('character.fern');

  // Fresh browser storage, then import the file from the title screen.
  await clearStorage(page);
  await boot(page);
  await waitScreen(page, 'title');
  const chooser = page.waitForEvent('filechooser');
  await click(page, 'title.import');
  await (await chooser).setFiles(file);
  await click(page, 'import_confirm.ok');
  await waitScreen(page, 'explore');
  expect((await probe(page))!.state.created_at).toBe(createdAt);
});

test('a tampered file is refused with a clear message and changes nothing', async ({ page }, info) => {
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  const downloadPromise = page.waitForEvent('download');
  await click(page, 'hud.menu');
  await click(page, 'menu.export');
  const file = info.outputPath('save.json');
  await (await downloadPromise).saveAs(file);
  const tampered = info.outputPath('tampered.json');
  writeFileSync(tampered, readFileSync(file, 'utf8').replace('"gold": 0', '"gold": 99999'));

  const chooser = page.waitForEvent('filechooser');
  await click(page, 'menu.import');
  await (await chooser).setFiles(tampered);
  await expect
    .poll(async () => (await probe(page))!.messages.join('\n'))
    .toContain('somme de contrôle incorrecte');
  expect((await probe(page))!.state.gold).toBe(0);
});
