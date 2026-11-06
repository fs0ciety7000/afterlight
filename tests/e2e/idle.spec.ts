import { expect, test, type Page } from '@playwright/test';
import { START_URL, boot, clearStorage, click, probe, waitSaved, waitScreen } from './helpers';

// Milestone 5 (ROADMAP 5.5, 5.7, 5.8): the offline hunt choice, the
// « Pendant votre absence » summary on a simulated clock, and « Chasser ici ».
// The test channel (`?test=1`) moves the game clock with `clock_offset_s`
// and offers `grant_level` (one level for the leader, see game/app/main.gd)
// so the won pack can be a hunt Fern survives offline.
test.setTimeout(420_000);

type Point = { x: number; y: number; dist?: number };
type Loot = { xp: number; gold: number; wallet: number };

const THREE_HOURS = 3 * 3600;
const world = async (page: Page) => (await probe(page))!.world as Record<string, unknown>;
const text = async (page: Page, id: string) => (await probe(page))!.controls[id]?.text ?? '';
const control = async (page: Page, id: string) => (await probe(page))!.controls[id];
const state = async (page: Page) => (await probe(page))!.state as Record<string, unknown>;
const testCommand = (page: Page, name: string) =>
  page.evaluate((n) => (window as unknown as { __afterlightTest: (n: string) => void }).__afterlightTest(n), name);

async function canvasPoint(page: Page, x: number, y: number) {
  const box = (await page.locator('canvas').boundingBox())!;
  const scale = await page.evaluate(() => {
    const c = document.querySelector('canvas')!;
    return c.width / c.clientWidth;
  });
  return { x: box.x + x / scale, y: box.y + y / scale };
}

/** New game, then travel to the wood (it reveals the ruins on the map). */
async function newGameInWood(page: Page): Promise<void> {
  await clearStorage(page);
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await click(page, 'hud.map');
  await waitScreen(page, 'world_map');
  await click(page, 'map.marker.whispering_wood');
  await click(page, 'map.travel');
  await expect.poll(async () => (await world(page)).location_id, { timeout: 30_000 }).toBe('location.whispering_wood');
}

/** Walks into the nearest pack (as in combat.spec.ts) and waits for the victory. */
async function winOnce(page: Page): Promise<void> {
  await page.waitForTimeout(1500);
  for (let i = 0; i < 40; i++) {
    const w = await world(page);
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
  await expect.poll(async () => (await world(page)).combat, { timeout: 30_000 }).toBeTruthy();
  await expect.poll(async () => (await world(page)).combat_result, { timeout: 120_000 }).toBe('victory');
}

/** Ids (short) of the hunts whose « Choisir » button is enabled. */
async function enabledHunts(page: Page): Promise<string[]> {
  const controls = (await probe(page))!.controls;
  return Object.keys(controls)
    .filter((id) => /^hunts\.choose\.[a-z0-9_]+$/.test(id) && controls[id].visible && !controls[id].disabled)
    .map((id) => id.slice('hunts.choose.'.length));
}

async function reloadAt(page: Page, offsetS: number): Promise<void> {
  await page.goto(`${START_URL}&clock_offset_s=${offsetS}`);
  await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
  await waitScreen(page, 'title');
}

test('5.5 elites, bosses and never-won encounters cannot be the offline hunt; the button says why', async ({ page }) => {
  await newGameInWood(page);

  // From the explore HUD: the current place comes first.
  expect(await text(page, 'hud.hunt')).toBe('Choisir une chasse');
  await click(page, 'hud.hunt');
  await waitScreen(page, 'hunts');
  await expect.poll(() => text(page, 'hunts.current')).toBe('Aucune chasse hors ligne choisie');
  for (const short of ['cloister_alpha', 'cloister_boss']) {
    await expect.poll(async () => (await control(page, `hunts.choose.${short}`))?.disabled).toBe(true);
    expect(await text(page, `hunts.choose.${short}_reason`)).toBe(
      'Les élites et les boss ne peuvent pas être chassés hors ligne',
    );
    expect((await control(page, `hunts.choose.${short}_reason`)).visible).toBe(true);
  }
  // Nothing won yet: every normal encounter of the wood explains it too.
  expect((await control(page, 'hunts.choose.whispering_wood_01')).disabled).toBe(true);
  expect(await text(page, 'hunts.choose.whispering_wood_01_reason')).toBe('Battez d\'abord cette rencontre une fois');
  expect(await enabledHunts(page)).toEqual([]);
  await click(page, 'hunts.close');
  await waitScreen(page, 'explore');

  // The same choice from the world map.
  await click(page, 'hud.map');
  await waitScreen(page, 'world_map');
  await click(page, 'map.hunts');
  await waitScreen(page, 'hunts');
  await expect.poll(async () => (await control(page, 'hunts.choose.cloister_boss'))?.disabled).toBe(true);
  await click(page, 'hunts.close');
  await waitScreen(page, 'world_map');
});

test('5.7 save, come back 3 h later, the summary shows the gains, Récupérer credits them once', async ({ page }) => {
  await newGameInWood(page);
  await winOnce(page);
  await click(page, 'combat.continue');
  await expect.poll(async () => (await world(page)).combat).toBeFalsy();

  // The won pack is now a valid offline hunt; level up until Fern survives it.
  await click(page, 'hud.hunt');
  await waitScreen(page, 'hunts');
  await expect.poll(async () => (await enabledHunts(page)).length).toBe(1);
  const short = (await enabledHunts(page))[0];
  for (let i = 0; i < 4 && (await text(page, `hunts.warning.${short}`)) !== ''; i++) {
    const level = (await state(page)).level as number;
    await testCommand(page, 'grant_level');
    await expect.poll(async () => (await state(page)).level).toBe(level + 1);
    await page.waitForTimeout(300);
  }
  expect(await text(page, `hunts.warning.${short}`)).toBe('');
  expect(await text(page, `hunts.stats.${short}`)).toMatch(/^Victoire en ~\d+ s · \d+ XP\/h · \d+ or\/h$/);
  const huntName = await text(page, `hunts.name.${short}`);
  await click(page, `hunts.choose.${short}`);
  await expect.poll(() => text(page, 'hunts.current')).toBe(`Chasse actuelle : ${huntName}`);
  expect((await state(page)).farming).toBe(`encounter.${short}`);
  expect((await control(page, `hunts.choose.${short}`)).disabled).toBe(true);
  await waitSaved(page, `"farming": "encounter.${short}"`);
  await click(page, 'hunts.close');
  await waitScreen(page, 'explore');
  expect(await text(page, 'hud.hunt')).toBe(`Chasse : ${huntName}`);
  const gold0 = (await state(page)).gold as number;
  const level0 = (await state(page)).level as number;
  const xp0 = (await state(page)).xp as number;

  // Come back 3 h later: title → Continuer → « Pendant votre absence ».
  await reloadAt(page, THREE_HOURS);
  expect((await state(page)).offline_pending).toBe(true);
  await click(page, 'title.continue');
  await waitScreen(page, 'offline_summary');
  expect(await text(page, 'offline.title')).toBe('Pendant votre absence');
  expect(await text(page, 'offline.hunt')).toBe(`Chasse : ${huntName}`);
  expect(await text(page, 'offline.duration')).toMatch(/^Temps pris en compte : 3 h 0\d$/);
  expect((await control(page, 'offline.capped')).visible).toBe(false);
  expect(Number(await text(page, 'offline.clears'))).toBeGreaterThan(0);
  const gold = Number((await text(page, 'offline.gold')).replace('+', ''));
  const xp = Number((await text(page, 'offline.xp')).replace('+', ''));
  expect(gold).toBeGreaterThan(0);
  expect(xp).toBeGreaterThan(0);
  // Nothing is credited before the claim.
  expect((await state(page)).gold).toBe(gold0);

  await click(page, 'offline.claim');
  await waitScreen(page, 'explore');
  const after = await state(page);
  expect(after.gold).toBe(gold0 + gold);
  expect(after.offline_pending).toBe(false);
  expect((after.level as number) > level0 || (after.xp as number) > xp0).toBe(true);
  await waitSaved(page, '"pending": []');
  await waitSaved(page, `"gold": ${gold0 + gold}`);

  // A second reload at the same clock credits nothing again.
  await reloadAt(page, THREE_HOURS);
  expect((await state(page)).offline_pending).toBe(false);
  await click(page, 'title.continue');
  await waitScreen(page, 'explore');
  expect((await state(page)).gold).toBe(gold0 + gold);
  expect((await state(page)).level).toBe(after.level);
  expect((await state(page)).xp).toBe(after.xp);
});

test('5.8 « Chasser ici » replays the encounter, each victory gives its loot, Arrêter stops it', async ({ page }) => {
  await newGameInWood(page);
  await winOnce(page);
  expect((await control(page, 'combat.hunt_here')).disabled).toBe(false);
  await click(page, 'combat.hunt_here');
  await expect.poll(async () => (await world(page)).hunt_active).toBe(true);
  const encounter = (await world(page)).hunt_encounter as string;
  expect((await world(page)).combat).toBe(encounter);
  await expect.poll(() => text(page, 'combat.hunt_counter')).toBe('Victoires : 0');

  // At least two victories in a row, each with its XP, and the counter follows.
  await expect.poll(async () => (await world(page)).hunt_wins, { timeout: 300_000 }).toBeGreaterThanOrEqual(2);
  const loot = (await world(page)).hunt_loot as Loot[];
  expect(loot.length).toBeGreaterThanOrEqual(2);
  for (const l of loot) expect(l.xp).toBeGreaterThan(0);
  for (let i = 1; i < loot.length; i++) expect(loot[i].wallet).toBeGreaterThanOrEqual(loot[i - 1].wallet);
  expect(await text(page, 'combat.hunt_counter')).toMatch(/^Victoires : \d+$/);

  // Arrêter la chasse: at once between two fights, else once the fight is over.
  await click(page, 'combat.hunt_stop');
  await expect
    .poll(
      async () => {
        if (!(await world(page)).combat) return 'out';
        return (await control(page, 'combat.continue'))?.visible ? 'panel' : 'fight';
      },
      { timeout: 180_000 },
    )
    .not.toBe('fight');
  if ((await world(page)).combat) await click(page, 'combat.continue');
  await expect.poll(async () => (await world(page)).combat).toBeFalsy();
  expect((await world(page)).hunt_active).toBe(false);
  const wins = (await world(page)).hunt_wins as number;
  await page.waitForTimeout(3000);
  expect((await world(page)).hunt_wins).toBe(wins);
  expect((await world(page)).combat).toBeFalsy();
  // The hunted pack became the offline hunt (a normal encounter of the wood).
  expect((await state(page)).farming).toBe(encounter);
  expect(await text(page, 'hud.hunt')).toMatch(/^Chasse : /);
});

test('5.8 a defeat stops « Chasser ici »', async ({ page }) => {
  await newGameInWood(page);
  await winOnce(page);
  await click(page, 'combat.hunt_here');
  await expect.poll(async () => (await world(page)).hunt_active).toBe(true);
  await expect.poll(async () => (await world(page)).combat_result, { timeout: 15_000 }).toBe('');
  await testCommand(page, 'defeat_party');
  await expect.poll(async () => (await world(page)).combat_result, { timeout: 30_000 }).toBe('defeat');
  expect(await control(page, 'combat.hunt_next')).toBeUndefined();
  await click(page, 'combat.continue');
  await expect.poll(async () => (await world(page)).combat).toBeFalsy();
  expect((await world(page)).hunt_active).toBe(false);
});
