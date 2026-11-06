import { expect, type Page } from '@playwright/test';

export type Probe = {
  ready: boolean;
  screen: string;
  controls: Record<string, { x: number; y: number; w: number; h: number; visible: boolean; clipped?: boolean; disabled?: boolean; text?: string }>;
  state: Record<string, unknown>;
  save: { last_saved_at: number; error: string };
  messages: string[];
  settings: { text_scale: number; reduce_motion: boolean };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  world: Record<string, any>;
};

export async function probe(page: Page): Promise<Probe | undefined> {
  return page.evaluate(() => (window as unknown as { __afterlight?: Probe }).__afterlight);
}

/** Tests run on software WebGL (no GPU): use the low graphics quality. */
export const START_URL = '/?quality=low&test=1';

export async function boot(page: Page): Promise<void> {
  await page.goto(START_URL);
  await expect.poll(async () => (await probe(page))?.ready ?? false, { timeout: 60_000 }).toBe(true);
  await waitContent(page);
}

/** The world pack (content.pck) downloads while the title shows; « Continuer »
 * and « Nouvelle partie » wait for it. Builds in one pack report no state. */
export async function waitContent(page: Page): Promise<void> {
  await expect
    .poll(
      async () => {
        const w = (await probe(page))?.world as { content?: { state?: string } } | undefined;
        return w?.content?.state ?? 'ready';
      },
      { timeout: 120_000, message: 'content pack ready' },
    )
    .toBe('ready');
}

export async function waitScreen(page: Page, screen: string): Promise<void> {
  await expect.poll(async () => (await probe(page))?.screen, { timeout: 15_000 }).toBe(screen);
}

/** Clicks a registered control at its real on-screen position, like a player. */
export async function click(page: Page, id: string): Promise<void> {
  await expect
    .poll(async () => {
      const c = (await probe(page))?.controls[id];
      return Boolean(c && c.visible && !c.disabled);
    }, { timeout: 15_000, message: `control ${id} visible and enabled` })
    .toBe(true);
  // A control scrolled out of its list is drawn but not where it says: scroll
  // it into view first, as a player would.
  if ((await probe(page))!.controls[id].clipped) {
    await page.evaluate(
      (n) => (window as unknown as { __afterlightTest?: (n: string) => void }).__afterlightTest?.(n),
      `reveal:${id}`,
    );
    await expect
      .poll(async () => (await probe(page))!.controls[id]?.clipped, { timeout: 5_000, message: `control ${id} scrolled into view` })
      .toBe(false);
  }
  // Let the fade finish so the control has settled.
  await page.waitForTimeout(350);
  const c = (await probe(page))!.controls[id];
  const box = (await page.locator('canvas').boundingBox())!;
  const scale = await page.evaluate(() => {
    const canvas = document.querySelector('canvas')!;
    return canvas.width / canvas.clientWidth;
  });
  await page.mouse.click(box.x + (c.x + c.w / 2) / scale, box.y + (c.y + c.h / 2) / scale);
}

export async function clearStorage(page: Page): Promise<void> {
  await page.goto(START_URL);
  await page.evaluate(async () => {
    const dbs = await indexedDB.databases();
    await Promise.all(dbs.map((d) => new Promise((r) => { const q = indexedDB.deleteDatabase(d.name!); q.onsuccess = q.onerror = q.onblocked = () => r(null); })));
    localStorage.clear();
  });
}

/** Waits until the save file stored in IndexedDB contains `text`. */
export async function waitSaved(page: Page, text: string): Promise<void> {
  await expect
    .poll(
      () =>
        page.evaluate(
          () =>
            new Promise<string>((resolve) => {
              const req = indexedDB.open('/userfs');
              req.onerror = () => resolve('');
              req.onsuccess = () => {
                const db = req.result;
                if (!db.objectStoreNames.contains('FILE_DATA')) return resolve('');
                const get = db
                  .transaction('FILE_DATA', 'readonly')
                  .objectStore('FILE_DATA')
                  .get('/userfs/godot/app_userdata/Afterlight/saves/slot_0.json');
                get.onsuccess = () => {
                  const v = get.result as { contents?: Uint8Array } | undefined;
                  resolve(v?.contents ? new TextDecoder().decode(v.contents) : '');
                };
                get.onerror = () => resolve('');
              };
            }),
        ),
      { timeout: 45_000, message: `save contains ${text}` },
    )
    .toContain(text);
}
