import { expect, test, type Page } from '@playwright/test';
import { boot, clearStorage, click, probe, waitSaved, waitScreen } from './helpers';

// Milestone 4 (ROADMAP 4.8, 4.10): the progression screens from a real game.
// Test-only shortcuts go through the `?test=1` channel (see game/app/main.gd):
// `force_item_drop` makes the next victory drop an item (a field pack drops
// one only 25 % of the time) and `grant_forge_funds` pays for the forge.
test.setTimeout(300_000);

type Point = { x: number; y: number; dist?: number };

const world = async (page: Page) => (await probe(page))!.world;
const text = async (page: Page, id: string) => (await probe(page))!.controls[id]?.text ?? '';
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

/** New game, travel to the wood, walk into the nearest pack (as in combat.spec.ts). */
async function enterCombat(page: Page): Promise<void> {
  await clearStorage(page);
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await click(page, 'hud.map');
  await waitScreen(page, 'world_map');
  await click(page, 'map.marker.whispering_wood');
  await click(page, 'map.travel');
  await expect.poll(async () => (await world(page)).location_id, { timeout: 30_000 }).toBe('location.whispering_wood');
  await testCommand(page, 'force_item_drop');
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
}

/** Every value of the character sheet, by stat id. */
async function sheet(page: Page): Promise<Record<string, string>> {
  const controls = (await probe(page))!.controls;
  const out: Record<string, string> = {};
  for (const id of Object.keys(controls)) {
    if (id.startsWith('character.stat.')) out[id] = controls[id].text ?? '';
  }
  return out;
}

async function wornNames(page: Page): Promise<string[]> {
  const controls = (await probe(page))!.controls;
  return Object.keys(controls)
    .filter((id) => id.startsWith('character.slot.'))
    .map((id) => controls[id].text ?? '');
}

test('4.8 victory, loot, equip, the stat changes, forge, save, reload, same state', async ({ page }) => {
  await enterCombat(page);
  await expect.poll(async () => (await world(page)).combat_result, { timeout: 120_000 }).toBe('victory');

  // The dropped item is listed on the result panel.
  await expect.poll(() => text(page, 'combat.loot.item.0'), { timeout: 15_000 }).not.toBe('');
  const itemName = await text(page, 'combat.loot.item.0');
  await click(page, 'combat.continue');
  await expect.poll(async () => (await world(page)).combat).toBeFalsy();

  // Character sheet before equipping.
  await click(page, 'hud.character');
  await waitScreen(page, 'character');
  await expect.poll(async () => Object.keys(await sheet(page)).length).toBeGreaterThan(5);
  const before = await sheet(page);
  expect(await wornNames(page)).not.toContain(itemName);

  // Bag: the new item is selected, Équiper wears it.
  await click(page, 'prog.tab.bag');
  await waitScreen(page, 'bag');
  await expect.poll(() => text(page, 'bag.count')).toBe('Sac : 1 / 60');
  await click(page, 'bag.slot.0');
  await expect.poll(() => text(page, 'bag.detail_name')).toBe(itemName);
  await click(page, 'bag.equip');
  await expect.poll(() => text(page, 'bag.count')).toBe('Sac : 0 / 60');
  await expect.poll(() => text(page, 'bag.status')).toBe('Objet équipé');

  // The character sheet shows the item and at least one stat changed.
  await click(page, 'prog.tab.character');
  await waitScreen(page, 'character');
  await expect.poll(() => wornNames(page)).toContain(itemName);
  const worn = await sheet(page);
  expect(worn).not.toEqual(before);

  // Forge: +1 is guaranteed.
  await testCommand(page, 'grant_forge_funds');
  await click(page, 'prog.tab.forge');
  await waitScreen(page, 'forge');
  await expect.poll(() => text(page, 'forge.item_name')).toBe(itemName);
  await expect.poll(() => text(page, 'forge.chance')).toBe('100 %');
  await click(page, 'forge.enhance');
  await expect.poll(() => text(page, 'forge.result')).toBe("Réussite : l'objet passe à +1");
  await expect.poll(() => text(page, 'forge.level')).toMatch(/^\+1 \/ \+\d+$/);
  const enhancedName = `${itemName} +1`;
  await expect.poll(() => text(page, 'forge.item_name')).toBe(enhancedName);

  await click(page, 'prog.tab.character');
  await waitScreen(page, 'character');
  await expect.poll(() => wornNames(page)).toContain(enhancedName);
  const after = await sheet(page);
  const level = await text(page, 'character.level');
  const xp = await text(page, 'character.xp');
  const gold = (await probe(page))!.state.gold;

  // The action saved by itself: reload like a returning player.
  await waitSaved(page, '"enhance_attempts": 1');
  await page.reload();
  await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
  await waitScreen(page, 'title');
  await click(page, 'title.continue');
  await waitScreen(page, 'explore');
  expect((await probe(page))!.state.gold).toBe(gold);
  await click(page, 'hud.character');
  await waitScreen(page, 'character');
  await expect.poll(() => wornNames(page)).toContain(enhancedName);
  expect(await sheet(page)).toEqual(after);
  expect(await text(page, 'character.level')).toBe(level);
  expect(await text(page, 'character.xp')).toBe(xp);
});

test('4.10 progression buttons work and a disabled button shows its reason', async ({ page }) => {
  await clearStorage(page);
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');

  // Marchande from the game menu: a new game has no gold.
  await click(page, 'hud.menu');
  await click(page, 'menu.open.merchant');
  await waitScreen(page, 'merchant');
  const buy = (await probe(page))!.controls['shop.buy.healing_draught'];
  expect(buy.disabled).toBe(true);
  await expect.poll(() => text(page, 'shop.buy.healing_draught_reason')).toMatch(/^Or insuffisant : \d+ requis$/);
  expect((await probe(page))!.controls['shop.buy.healing_draught_reason'].visible).toBe(true);
  expect(await text(page, 'shop.carried.healing_draught')).toBe('Porté : 0 / 5');

  // Grimoire: ranking up needs a level, gold and grimoire pages.
  await click(page, 'prog.tab.grimoire');
  await waitScreen(page, 'grimoire');
  await click(page, 'grimoire.spell.zoltraak');
  await expect.poll(() => text(page, 'grimoire.spell_name')).toBe('Zoltraak');
  expect((await probe(page))!.controls['grimoire.rank_up'].disabled).toBe(true);
  await expect.poll(() => text(page, 'grimoire.rank_up_reason')).toMatch(/requis$/);

  // Graveuse: fusion needs three identical runes.
  await click(page, 'prog.tab.runecarver');
  await waitScreen(page, 'runecarver');
  expect((await probe(page))!.controls['runes.fuse'].disabled).toBe(true);
  await expect.poll(() => text(page, 'runes.fuse_reason')).toMatch(/^Il faut 3 runes identiques/);

  // Sac: nothing to salvage in an empty bag; the other views open.
  await click(page, 'prog.tab.bag');
  await waitScreen(page, 'bag');
  expect((await probe(page))!.controls['bag.bulk_salvage'].disabled).toBe(true);
  await expect.poll(() => text(page, 'bag.bulk_salvage_reason')).toBe('Rien à recycler');
  await click(page, 'bag.view.materials');
  await expect.poll(() => text(page, 'bag.material.gold')).toBe('0');
  await click(page, 'bag.view.consumables');
  await expect.poll(() => text(page, 'bag.consumable.healing_draught')).toBe('Porté : 0 / 5');

  // Personnage: artifact slots are locked with their level.
  await click(page, 'prog.tab.character');
  await waitScreen(page, 'character');
  await expect.poll(() => text(page, 'character.artifact_slot.0')).toBe('Emplacement disponible au niveau 6');

  // With gold, the purchase goes through and the carried count updates.
  await testCommand(page, 'grant_forge_funds');
  await click(page, 'prog.tab.merchant');
  await waitScreen(page, 'merchant');
  await click(page, 'shop.buy.healing_draught');
  await expect.poll(() => text(page, 'shop.carried.healing_draught')).toBe('Porté : 1 / 5');

  // Fermer returns to the world.
  await click(page, 'prog.close');
  await waitScreen(page, 'explore');
});
