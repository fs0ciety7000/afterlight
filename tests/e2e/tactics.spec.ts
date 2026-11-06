import { expect, test, type Page } from '@playwright/test';
import { boot, clearStorage, click, probe, waitSaved, waitScreen } from './helpers';

// Milestone 6 (GDD decisions 23-27): panel.tactics from a real game.
// Test-only shortcut through the `?test=1` channel (game/app/main.gd):
// `grant_level` gives Fern one level (level 2 learns the Barrier).
test.setTimeout(240_000);

const world = async (page: Page) => (await probe(page))!.world as Record<string, unknown>;
const text = async (page: Page, id: string) => (await probe(page))!.controls[id]?.text ?? '';
const testCommand = (page: Page, name: string) =>
  page.evaluate((n) => (window as unknown as { __afterlightTest: (n: string) => void }).__afterlightTest(n), name);

/** Waits until a control is visible and entirely inside the canvas (phones: no scrolling needed). */
async function onScreen(page: Page, id: string): Promise<void> {
  await expect
    .poll(
      async () => {
        const c = (await probe(page))?.controls[id];
        if (!c || !c.visible) return false;
        const h = await page.evaluate(() => document.querySelector('canvas')!.height);
        return c.y >= 0 && c.y + c.h <= h;
      },
      { timeout: 15_000, message: `${id} on screen` },
    )
    .toBe(true);
}

/** New game, then Fern reaches level 2 (the Barrier). */
async function newGameLevel2(page: Page): Promise<void> {
  await clearStorage(page);
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await testCommand(page, 'grant_level');
  await expect.poll(async () => (await probe(page))!.state.level, { timeout: 15_000 }).toBe(2);
}

async function openFromGrimoire(page: Page, badge = ''): Promise<void> {
  await click(page, 'hud.grimoire');
  await waitScreen(page, 'grimoire');
  await click(page, badge !== '' ? `tactics.badge.${badge}` : 'tactics.open.grimoire');
  await expect.poll(async () => (await world(page)).tactics_open, { timeout: 15_000 }).toBe(true);
  // The actions sit at the top of the panel, on every screen size.
  for (const id of ['tactics.close', 'tactics.reset', 'tactics.apply_preset']) await onScreen(page, id);
}

test('tactics from the grimoire: the Barrier mode persists across a reload', async ({ page }) => {
  await newGameLevel2(page);
  await openFromGrimoire(page, 'defensive_barrier');
  expect(await text(page, 'tactics.say.defensive_barrier')).toBe(
    'Fern se protège juste avant un coup annoncé, ou si ses PV passent sous 30 %.',
  );
  await onScreen(page, 'tactics.opt.defensive_barrier.auto_before_telegraph');
  await click(page, 'tactics.opt.defensive_barrier.auto_before_telegraph');
  await expect
    .poll(async () => text(page, 'tactics.say.defensive_barrier'))
    .toBe('Fern se protège juste avant un coup annoncé au sol ou par une incantation.');
  expect(await text(page, 'tactics.status')).toBe('Réglage enregistré.');
  await click(page, 'tactics.close');
  await expect.poll(async () => (await world(page)).tactics_open).toBe(false);
  // The grimoire's badge shows the new mode.
  await expect
    .poll(async () => text(page, 'tactics.badge.defensive_barrier'))
    .toBe('Tactique : Avant un coup télégraphé');
  await waitSaved(page, 'auto_before_telegraph');

  await page.reload();
  await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
  await click(page, 'title.continue');
  await waitScreen(page, 'explore');
  await openFromGrimoire(page, 'defensive_barrier');
  expect(await text(page, 'tactics.say.defensive_barrier')).toBe(
    'Fern se protège juste avant un coup annoncé au sol ou par une incantation.',
  );
});

test('« Appliquer le conseil » shows the Morvaine diff before applying it', async ({ page }) => {
  await newGameLevel2(page);
  await openFromGrimoire(page);
  await click(page, 'tactics.apply_preset');
  await onScreen(page, 'tactics.diff_confirm');
  const diff = await text(page, 'tactics.diff');
  expect(diff).toContain("Ciblage : Le plus proche → Lanceurs d'abord");
  expect(diff).toContain('Barrière défensive : Avant un coup télégraphé, sinon sous X % → Avant un coup télégraphé');
  // Nothing changed yet.
  expect(await text(page, 'tactics.say.targeting')).toBe("Fern attaque l'ennemi le plus proche.");
  await click(page, 'tactics.diff_confirm');
  await expect.poll(async () => text(page, 'tactics.status')).toBe('Conseil appliqué.');
  expect(await text(page, 'tactics.say.targeting')).toBe('Fern abat d\'abord les lanternes et autres lanceurs.');
  // Applied: the button is disabled and says why.
  await expect.poll(async () => (await probe(page))!.controls['tactics.apply_preset']?.disabled).toBe(true);
  expect(await text(page, 'tactics.apply_preset_reason')).toBe('Vos réglages suivent déjà ce conseil.');
  await waitSaved(page, 'casters_first');
});

test('the Barrier tip appears at level 2 and opens the tactics', async ({ page }) => {
  await newGameLevel2(page);
  await expect.poll(async () => (await world(page)).tip, { timeout: 15_000 }).toBe('tip.barrier_unlocked');
  await onScreen(page, 'tip.card');
  expect(await text(page, 'tip.title')).toBe('Barrière débloquée');
  await click(page, 'tip.open');
  await expect.poll(async () => (await world(page)).tactics_open, { timeout: 15_000 }).toBe(true);
  await onScreen(page, 'tactics.close');
  expect((await probe(page))!.controls['tip.card']).toBeUndefined();
  await click(page, 'tactics.close');
  await expect.poll(async () => (await world(page)).tactics_open).toBe(false);
  // Seen once per save: it does not come back.
  await waitSaved(page, 'tip.barrier_unlocked');
  await testCommand(page, 'grant_level');
  await page.waitForTimeout(1500);
  expect((await world(page)).tip).toBe('');
});
