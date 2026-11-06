import { expect, test, type Page, type TestInfo } from '@playwright/test';
import { START_URL, boot, clearStorage, click, probe, waitSaved, waitScreen } from './helpers';

// ROADMAP 7.7: reference captures of every GDD §17 screen reachable in the
// slice, at 100 % and 130 % text size, on each project (desktop, mobile,
// tablet). On each screen, every visible registered control must:
// - lie inside the canvas (sideways always; vertically unless it sits in a
//   scroll list, which may scroll it away);
// - not be clipped by a parent, unless that parent is a scroll list;
// - show its whole text (UiProbe `truncated`: a clipped or ellipsized line
//   shorter than its text, or wrapped lines that do not all fit).
// Problems are collected per screen and reported together at the end, so one
// run lists every screen to fix. Captures: test-results/<test>/<screen>-<size>-<project>.png.
//
// Test channel shortcuts (`?test=1`, game/app/main.gd and explore_screen.gd):
// `text_scale:<index>`, `grant_level`, `grant_levels:<n>`, `grant_forge_funds`,
// `go_to:<interactable>`, `go_to_pack:` (nearest pack), `reveal_watch_ruins`,
// `complete_quest:<quest>` (the cloister without playing quests 1-3).
//
// Software WebGL is slow: three groups per text size, each about 3 to 5
// minutes, with a generous timeout.
test.setTimeout(540_000);

type Control = {
  x: number;
  y: number;
  w: number;
  h: number;
  visible: boolean;
  clipped?: boolean;
  scrolled?: boolean;
  truncated?: boolean;
  disabled?: boolean;
  text?: string;
};
type Point = { x: number; y: number; dist?: number };

const SIZES = [
  { index: 1, name: '100', scale: 1.0 },
  { index: 3, name: '130', scale: 1.3 },
];
const THREE_HOURS = 3 * 3600;

const world = async (page: Page) => (await probe(page))!.world as Record<string, unknown>;
const state = async (page: Page) => (await probe(page))!.state as Record<string, unknown>;
const control = async (page: Page, id: string) => (await probe(page))?.controls[id] as Control | undefined;
const text = async (page: Page, id: string) => (await control(page, id))?.text ?? '';
const cmd = async (page: Page, name: string) => {
  await page.evaluate((n) => (window as unknown as { __afterlightTest: (n: string) => void }).__afterlightTest(n), name);
  await page.waitForTimeout(400);
};

test.afterEach(async ({ page }, info) => {
  if (info.status === info.expectedStatus) return;
  await page.screenshot({ path: info.outputPath('failure.png') }).catch(() => undefined);
  const p = await probe(page).catch(() => undefined);
  await info.attach('probe', { body: JSON.stringify(p, null, 1), contentType: 'application/json' }).catch(() => undefined);
});

/** Layout problems of the controls on screen now. `free`: id prefixes placed
 * by the 3D view or a panning map (bounds and clipping not checked). */
async function layoutProblems(page: Page, free: string[]): Promise<string[]> {
  const size = await page.evaluate(() => {
    const c = document.querySelector('canvas')!;
    return { w: c.width, h: c.height };
  });
  const controls = (await probe(page))!.controls as Record<string, Control>;
  const out: string[] = [];
  if (!Object.values(controls).some((c) => 'truncated' in c)) out.push('probe has no `truncated` flag (old build?)');
  for (const [id, c] of Object.entries(controls)) {
    if (!c.visible || c.w <= 0 || c.h <= 0) continue;
    const at = `(${Math.round(c.x)},${Math.round(c.y)} ${Math.round(c.w)}x${Math.round(c.h)})`;
    if (c.truncated) out.push(`${id} truncates « ${c.text ?? ''} » ${at}`);
    if (free.some((p) => id.startsWith(p))) continue;
    if (c.x < -1 || c.x + c.w > size.w + 1) out.push(`${id} leaves the ${size.w}x${size.h} canvas sideways ${at}`);
    if (c.scrolled) continue;
    if (c.y < -1 || c.y + c.h > size.h + 1) out.push(`${id} leaves the ${size.w}x${size.h} canvas vertically ${at}`);
    if (c.clipped) out.push(`${id} clipped by a parent that is not a scroll list ${at}`);
  }
  return out;
}

/** Collects every screen's problems; the test fails at the end with all of them. */
class Report {
  problems: string[] = [];
  screens: string[] = [];

  constructor(
    private page: Page,
    private info: TestInfo,
    private size: string,
  ) {}

  /** Lets the screen settle, saves the capture, then checks the layout
   * (polled a few seconds: wrapped labels take a frame or two to settle). */
  async check(name: string, free: string[] = []): Promise<void> {
    await this.page.waitForTimeout(800);
    await this.page.screenshot({ path: this.info.outputPath(`${name}-${this.size}-${this.info.project.name}.png`) });
    let found: string[] = [];
    for (let i = 0; i < 8; i++) {
      found = await layoutProblems(this.page, free);
      if (found.length === 0) break;
      await this.page.waitForTimeout(500);
    }
    this.screens.push(name);
    for (const p of found) this.problems.push(`${name} ${this.size} %: ${p}`);
  }

  async done(): Promise<void> {
    await this.info.attach('screens', {
      body: JSON.stringify({ screens: this.screens, problems: this.problems }, null, 1),
      contentType: 'application/json',
    });
    expect(this.problems, `layout problems on ${this.screens.length} screens`).toEqual([]);
  }
}

async function setTextSize(page: Page, index: number, scale: number): Promise<void> {
  await cmd(page, `text_scale:${index}`);
  await expect.poll(async () => (await probe(page))!.settings.text_scale).toBeCloseTo(scale);
  await page.waitForTimeout(500);
}

async function newGame(page: Page): Promise<void> {
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await page.waitForTimeout(1500);
}

async function travel(page: Page, short: string): Promise<void> {
  await click(page, 'hud.map');
  await waitScreen(page, 'world_map');
  await click(page, `map.marker.${short}`);
  await click(page, 'map.travel');
  await expect.poll(async () => (await world(page)).location_id, { timeout: 60_000 }).toBe(`location.${short}`);
  await page.waitForTimeout(1000);
}

/** Clicks a control at once (no settle wait), if it is visible and enabled. */
async function tap(page: Page, id: string): Promise<boolean> {
  const c = await control(page, id);
  if (!c || !c.visible || c.disabled) return false;
  const box = (await page.locator('canvas').boundingBox())!;
  const ratio = await page.evaluate(() => {
    const canvas = document.querySelector('canvas')!;
    return canvas.width / canvas.clientWidth;
  });
  await page.mouse.click(box.x + (c.x + c.w / 2) / ratio, box.y + (c.y + c.h / 2) / ratio);
  return true;
}

/** Skips whatever dialogue or story card is on screen until it stays quiet. */
async function dismissStory(page: Page): Promise<void> {
  let quiet = 0;
  for (let i = 0; i < 40 && quiet < 3; i++) {
    const w = await world(page);
    if (
      (await tap(page, 'story.skip')) ||
      (await tap(page, 'dialogue.accept')) ||
      (await tap(page, 'dialogue.skip')) ||
      (await tap(page, 'dialogue.next'))
    ) {
      quiet = 0;
    } else if (!w.dialogue_open && !w.story_cards) {
      quiet++;
    }
    await page.waitForTimeout(500);
  }
}

/** Ids (short) of the hunts whose « Choisir » button is enabled. */
async function enabledHunts(page: Page): Promise<string[]> {
  const controls = (await probe(page))!.controls as Record<string, Control>;
  return Object.keys(controls)
    .filter((id) => /^hunts\.choose\.[a-z0-9_]+$/.test(id) && !id.endsWith('_reason'))
    .filter((id) => controls[id].visible && controls[id].disabled === false)
    .map((id) => id.slice('hunts.choose.'.length));
}

for (const size of SIZES) {
  test.describe(`text ${size.name} %`, () => {
    test(`title, settings, world HUD, map, hunts, journal, panels, tactics, menu at ${size.name} %`, async ({ page }, info) => {
      const r = new Report(page, info, size.name);
      await clearStorage(page);
      await boot(page);
      await setTextSize(page, size.index, size.scale);
      await waitScreen(page, 'title');
      await r.check('title');

      // Réglages: Affichage, Son, Commandes.
      await click(page, 'title.settings');
      await waitScreen(page, 'settings');
      for (const tab of ['general', 'sound', 'controls']) {
        await click(page, `settings.tab.${tab}`);
        await r.check(`settings-${tab}`);
      }
      await click(page, 'settings.back');
      await waitScreen(page, 'title');

      // World (explore HUD).
      await newGame(page);
      await r.check('explore');

      // World map, then the offline hunts from it (nothing won yet).
      await click(page, 'hud.map');
      await waitScreen(page, 'world_map');
      await r.check('world-map', ['map.marker.']);
      await click(page, 'map.hunts');
      await waitScreen(page, 'hunts');
      await r.check('hunts');
      await click(page, 'hunts.close');
      await waitScreen(page, 'world_map');
      await click(page, 'map.close');
      await waitScreen(page, 'explore');

      // Journal and its four tabs.
      await click(page, 'hud.journal');
      await waitScreen(page, 'journal');
      for (const tab of ['quests', 'contracts', 'bestiary', 'discoveries']) {
        await click(page, `journal.tab.${tab}`);
        await r.check(`journal-${tab}`);
      }
      await click(page, 'journal.close');
      await waitScreen(page, 'explore');

      // Progression panels; level 2 opens the tactics, gold fills the shops.
      await click(page, 'hud.character');
      await waitScreen(page, 'character');
      await cmd(page, 'grant_level');
      await expect.poll(async () => (await state(page)).level, { timeout: 15_000 }).toBe(2);
      await cmd(page, 'grant_forge_funds');
      await r.check('character');
      for (const panel of ['bag', 'grimoire']) {
        await click(page, `prog.tab.${panel}`);
        await waitScreen(page, panel);
        await r.check(panel);
      }
      await click(page, 'tactics.open.grimoire');
      await expect.poll(async () => (await world(page)).tactics_open, { timeout: 15_000 }).toBe(true);
      await r.check('tactics');
      await click(page, 'tactics.close');
      await expect.poll(async () => (await world(page)).tactics_open).toBe(false);
      for (const panel of ['forge', 'runecarver', 'merchant']) {
        await click(page, `prog.tab.${panel}`);
        await waitScreen(page, panel);
        await r.check(panel);
      }
      await click(page, 'prog.close');
      await waitScreen(page, 'explore');

      // Back in the world: the Barrier tip (level 2), then the game menu.
      await page.waitForTimeout(1500);
      if ((await control(page, 'tip.card'))?.visible) await r.check('explore-tip');
      await click(page, 'hud.menu');
      await expect.poll(async () => (await control(page, 'menu.resume'))?.visible).toBe(true);
      await r.check('game-menu');
      await click(page, 'menu.resume');
      await r.done();
    });

    test(`combat HUD, result panel, hunts, offline summary at ${size.name} %`, async ({ page }, info) => {
      const r = new Report(page, info, size.name);
      await clearStorage(page);
      await boot(page);
      await setTextSize(page, size.index, size.scale);
      await newGame(page);
      await travel(page, 'whispering_wood');

      // Combat HUD: Fern is put inside the nearest pack's aggro radius.
      await cmd(page, 'go_to_pack:');
      await expect.poll(async () => (await world(page)).combat, { timeout: 30_000 }).toBeTruthy();
      await expect.poll(async () => (await control(page, 'combat.speed'))?.visible ?? false, { timeout: 30_000 }).toBe(true);
      await page.waitForTimeout(1500);
      // Enemy plates follow the 3D models.
      await r.check('combat-hud', ['combat.enemy.']);
      // Faster to the end (the game caps the speed per encounter).
      for (let i = 0; i < 4 && (await world(page)).combat_speed !== 4; i++) {
        await tap(page, 'combat.speed');
        await page.waitForTimeout(600);
      }

      // Result panel.
      await expect.poll(async () => (await world(page)).combat_result, { timeout: 180_000 }).toBe('victory');
      await expect.poll(async () => (await control(page, 'combat.continue'))?.visible, { timeout: 15_000 }).toBe(true);
      await r.check('combat-result', ['combat.enemy.']);
      await click(page, 'combat.continue');
      await expect.poll(async () => (await world(page)).combat, { timeout: 30_000 }).toBeFalsy();

      // Hunts with a won encounter; it becomes the offline hunt once Fern survives it.
      await click(page, 'hud.hunt');
      await waitScreen(page, 'hunts');
      await expect.poll(async () => (await enabledHunts(page)).length, { timeout: 15_000 }).toBe(1);
      const short = (await enabledHunts(page))[0];
      for (let i = 0; i < 4 && (await text(page, `hunts.warning.${short}`)) !== ''; i++) {
        const level = (await state(page)).level as number;
        await cmd(page, 'grant_level');
        await expect.poll(async () => (await state(page)).level).toBe(level + 1);
      }
      await r.check('hunts-won');
      await click(page, `hunts.choose.${short}`);
      expect((await state(page)).farming).toBe(`encounter.${short}`);
      await waitSaved(page, `"farming": "encounter.${short}"`);

      // Three hours later: « Pendant votre absence ».
      await page.goto(`${START_URL}&clock_offset_s=${THREE_HOURS}`);
      await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
      await waitScreen(page, 'title');
      expect((await probe(page))!.settings.text_scale).toBeCloseTo(size.scale);
      await click(page, 'title.continue');
      await waitScreen(page, 'offline_summary');
      await r.check('offline-summary');
      await click(page, 'offline.claim');
      await waitScreen(page, 'explore');
      await r.done();
    });

    test(`dialogue overlay and dungeon HUD at ${size.name} %`, async ({ page }, info) => {
      const r = new Report(page, info, size.name);
      await clearStorage(page);
      await boot(page);
      await setTextSize(page, size.index, size.scale);
      await newGame(page);

      // Dialogue: Odile by the well, then her quest card.
      await cmd(page, 'go_to:npc.odile');
      await expect.poll(async () => (await world(page)).interact_target, { timeout: 20_000 }).toBe('npc.odile');
      await click(page, 'hud.interact');
      await expect.poll(async () => (await world(page)).dialogue_open, { timeout: 15_000 }).toBe(true);
      await page.waitForTimeout(1500);
      await r.check('dialogue');
      await click(page, 'dialogue.skip');
      await page.waitForTimeout(1000);
      if ((await control(page, 'dialogue.accept'))?.visible) await r.check('dialogue-quest-card');
      await dismissStory(page);
      await waitScreen(page, 'explore');

      // The cloister: its quests count as done, the Watch Ruins show on the map.
      for (const q of ['quest.main_01', 'quest.main_02', 'quest.main_03']) await cmd(page, `complete_quest:${q}`);
      await cmd(page, 'reveal_watch_ruins');
      await travel(page, 'watch_ruins');
      await dismissStory(page);
      await cmd(page, 'go_to:gate:dungeon.silent_dial_cloister');
      await expect
        .poll(async () => (await world(page)).interact_target, { timeout: 20_000 })
        .toBe('gate:dungeon.silent_dial_cloister');
      await click(page, 'hud.interact');
      await expect.poll(async () => (await state(page)).dungeon, { timeout: 30_000 }).toBe('dungeon.silent_dial_cloister');

      // Fern's line on the first entry, when it plays.
      const spoke = await expect
        .poll(async () => (await world(page)).dialogue_open, { timeout: 20_000 })
        .toBe(true)
        .then(() => true, () => false);
      if (spoke) {
        await page.waitForTimeout(1200);
        await r.check('dialogue-dungeon');
      }
      await dismissStory(page);

      // Dungeon HUD: the expedition vitals.
      await expect.poll(async () => (await control(page, 'hud.dungeon_vitals'))?.visible, { timeout: 30_000 }).toBe(true);
      await page.waitForTimeout(1000);
      await r.check('dungeon-hud');
      await r.done();
    });
  });
}
