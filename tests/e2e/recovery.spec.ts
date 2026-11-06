import { readFileSync } from 'node:fs';
import { expect, test, type Page } from '@playwright/test';
import { boot, clearStorage, click, probe, waitSaved, waitScreen } from './helpers';

// ROADMAP 1.4 (E2E part): a damaged save in the browser storage. On the web,
// user:// lives in IndexedDB: Emscripten's IDBFS keeps one record per file in
// the `FILE_DATA` store of the `/userfs` database, keyed by the full path,
// `{ timestamp, mode, contents: Uint8Array }`, and copies the records into
// memory when the game starts. The test writes the damaged main file straight
// into that store, from a blank page of the same origin (the game is not
// running, so nothing overwrites it), keeps the valid backup, and reloads.
test.setTimeout(300_000);

const SAVES = '/userfs/godot/app_userdata/Afterlight/saves/';
const MAIN = `${SAVES}slot_0.json`;
const BACKUP = `${SAVES}slot_0.bak.json`;
const CORRUPT = `${SAVES}corrupt/`;
const BLANK = '/__recovery_blank';

type Kind = 'truncated' | 'future_version' | 'checksum';
const REASONS: Record<Kind, string> = {
  truncated: "le fichier n'est pas lisible (JSON invalide).",
  future_version: "elle vient d'une version plus récente du jeu.",
  checksum: 'son contenu a été modifié ou abîmé (somme de contrôle incorrecte).',
};

const testCommand = (page: Page, name: string) =>
  page.evaluate((n) => (window as unknown as { __afterlightTest: (n: string) => void }).__afterlightTest(n), name);
const text = async (page: Page, id: string) => (await probe(page))!.controls[id]?.text ?? '';

test.afterEach(async ({ page }, info) => {
  if (info.status === info.expectedStatus) return;
  await page.screenshot({ path: info.outputPath('failure.png') }).catch(() => undefined);
  const p = await probe(page).catch(() => undefined);
  await info.attach('probe', { body: JSON.stringify(p, null, 1), contentType: 'application/json' }).catch(() => undefined);
});

/** Every file stored under `prefix` in the IDBFS store, decoded as text. */
function readFiles(page: Page, prefix: string): Promise<Record<string, string>> {
  return page.evaluate(
    (pre) =>
      new Promise<Record<string, string>>((resolve) => {
        const out: Record<string, string> = {};
        const req = indexedDB.open('/userfs');
        req.onerror = () => resolve(out);
        req.onsuccess = () => {
          const db = req.result;
          if (!db.objectStoreNames.contains('FILE_DATA')) {
            db.close();
            resolve(out);
            return;
          }
          const cursor = db.transaction('FILE_DATA', 'readonly').objectStore('FILE_DATA').openCursor();
          cursor.onsuccess = () => {
            const c = cursor.result;
            if (!c) {
              db.close();
              resolve(out);
              return;
            }
            const v = c.value as { contents?: Uint8Array } | undefined;
            const key = String(c.key);
            if (key.startsWith(pre) && v?.contents) out[key] = new TextDecoder().decode(v.contents);
            c.continue();
          };
          cursor.onerror = () => {
            db.close();
            resolve(out);
          };
        };
      }),
    prefix,
  );
}

/** Replaces the contents of an existing IDBFS file record (same mode and time). */
function writeFile(page: Page, path: string, contents: string): Promise<boolean> {
  return page.evaluate(
    ([key, body]) =>
      new Promise<boolean>((resolve) => {
        const req = indexedDB.open('/userfs');
        req.onerror = () => resolve(false);
        req.onsuccess = () => {
          const db = req.result;
          const tx = db.transaction('FILE_DATA', 'readwrite');
          const store = tx.objectStore('FILE_DATA');
          const get = store.get(key);
          get.onsuccess = () => {
            const old = get.result as Record<string, unknown> | undefined;
            if (!old) {
              resolve(false);
              return;
            }
            store.put({ ...old, contents: new TextEncoder().encode(body) }, key);
          };
          tx.oncomplete = () => {
            db.close();
            resolve(true);
          };
          tx.onerror = tx.onabort = () => {
            db.close();
            resolve(false);
          };
        };
      }),
    [path, contents] as const,
  );
}

function damage(valid: string, kind: Kind): string {
  if (kind === 'truncated') return valid.slice(0, Math.floor(valid.length / 2));
  const save = JSON.parse(valid);
  if (kind === 'future_version') save.version = 99;
  else save.state.wallet.gold = Number(save.state.wallet.gold) + 1; // checksum no longer matches
  return JSON.stringify(save, null, '\t');
}

/**
 * New game, then a second save so the first one becomes the backup; then
 * the main file is damaged in IndexedDB while the game is not running.
 * Returns the damaged text and the backup kept intact.
 */
async function damagedSaveWithBackup(page: Page, kind: Kind): Promise<{ damaged: string; backup: string }> {
  await clearStorage(page);
  await boot(page);
  await click(page, 'title.new_game');
  await waitScreen(page, 'explore');
  await waitSaved(page, '"format": "afterlight-save"');
  await testCommand(page, 'grant_gold:123');
  await waitSaved(page, '"gold": 123');
  await expect
    .poll(async () => (await readFiles(page, BACKUP))[BACKUP] ?? '', { timeout: 45_000, message: 'backup written' })
    .toContain('"format": "afterlight-save"');

  // Leave the game for a blank page of the same origin, then edit the store.
  await page.route(`**${BLANK}`, (r) =>
    r.fulfill({ status: 200, contentType: 'text/html', body: '<!doctype html><title>blank</title>' }),
  );
  await page.goto(BLANK);
  const files = await readFiles(page, SAVES);
  const valid = files[MAIN];
  const backup = files[BACKUP];
  expect(valid).toContain('"gold": 123');
  expect(backup).toContain('"format": "afterlight-save"');
  const damaged = damage(valid, kind);
  expect(await writeFile(page, MAIN, damaged)).toBe(true);
  expect((await readFiles(page, MAIN))[MAIN]).toBe(damaged);
  return { damaged, backup };
}

/** Reload: the recovery screen, its reason, the copy in quarantine, the backup untouched. */
async function expectRecovery(page: Page, kind: Kind, damaged: string, backup: string): Promise<void> {
  await boot(page);
  await waitScreen(page, 'save_recovery');
  expect(await text(page, 'recovery.title')).toBe('Sauvegarde endommagée');
  await expect.poll(() => text(page, 'recovery.body')).toContain(REASONS[kind]);
  for (const id of ['recovery.restore', 'recovery.export', 'recovery.new_game']) {
    await expect
      .poll(async () => {
        const c = (await probe(page))!.controls[id];
        return Boolean(c?.visible && !c.disabled);
      }, { timeout: 30_000, message: `${id} offered` })
      .toBe(true);
  }
  // The damaged file was copied to user://saves/corrupt/ before anything else.
  await expect
    .poll(async () => Object.values(await readFiles(page, CORRUPT)), { timeout: 30_000, message: 'quarantined copy' })
    .toContain(damaged);
  expect((await readFiles(page, BACKUP))[BACKUP]).toBe(backup);
}

test('truncated JSON: export downloads the damaged file, restore brings the backup back', async ({ page }, info) => {
  const { damaged, backup } = await damagedSaveWithBackup(page, 'truncated');
  await expectRecovery(page, 'truncated', damaged, backup);

  const download = page.waitForEvent('download');
  await click(page, 'recovery.export');
  const file = info.outputPath('damaged.json');
  await (await download).saveAs(file);
  expect(readFileSync(file, 'utf8')).toBe(damaged);
  // Exporting changes nothing: still on the recovery screen.
  expect((await probe(page))!.screen).toBe('save_recovery');

  const gold = JSON.parse(backup).state.wallet.gold;
  await click(page, 'recovery.restore');
  await expect
    .poll(async () => (await probe(page))!.screen, { timeout: 60_000 })
    .toMatch(/^(explore|offline_summary)$/);
  expect((await probe(page))!.state.gold).toBe(gold);
  // The backup is the main save again; the damaged copy stays in quarantine.
  await expect.poll(async () => (await readFiles(page, MAIN))[MAIN], { timeout: 30_000 }).toBe(backup);
  expect(Object.values(await readFiles(page, CORRUPT))).toContain(damaged);

  // A returning player continues from the restored save.
  await boot(page);
  await waitScreen(page, 'title');
  await click(page, 'title.continue');
  await expect
    .poll(async () => (await probe(page))!.screen, { timeout: 60_000 })
    .toMatch(/^(explore|offline_summary)$/);
  expect((await probe(page))!.state.gold).toBe(gold);
});

test('unknown version: a new game asks for confirmation and keeps the backup and the damaged copy', async ({ page }) => {
  const { damaged, backup } = await damagedSaveWithBackup(page, 'future_version');
  await expectRecovery(page, 'future_version', damaged, backup);

  // Cancel: nothing happens.
  await click(page, 'recovery.new_game');
  await expect.poll(async () => (await probe(page))!.controls['new_game_confirm.ok']?.visible).toBe(true);
  await click(page, 'new_game_confirm.cancel');
  await expect.poll(async () => (await probe(page))!.controls['new_game_confirm.ok']).toBeUndefined();
  expect((await probe(page))!.screen).toBe('save_recovery');
  expect((await readFiles(page, MAIN))[MAIN]).toBe(damaged);

  // Confirm: a fresh game, saved over the damaged main only.
  await click(page, 'recovery.new_game');
  await click(page, 'new_game_confirm.ok');
  await waitScreen(page, 'explore');
  const state = (await probe(page))!.state;
  expect(state.gold).toBe(0);
  expect(state.created_at).not.toBe(JSON.parse(backup).state.meta.created_at);
  await expect
    .poll(
      async () => {
        try {
          return JSON.parse((await readFiles(page, MAIN))[MAIN] ?? '').state.meta.created_at;
        } catch {
          return null;
        }
      },
      { timeout: 30_000, message: 'the new game is the main save' },
    )
    .toBe(state.created_at);
  expect((await readFiles(page, BACKUP))[BACKUP]).toBe(backup);
  expect(Object.values(await readFiles(page, CORRUPT))).toContain(damaged);
});

test('bad checksum: restore, then the game loads normally', async ({ page }) => {
  const { damaged, backup } = await damagedSaveWithBackup(page, 'checksum');
  await expectRecovery(page, 'checksum', damaged, backup);
  const gold = JSON.parse(backup).state.wallet.gold;
  await click(page, 'recovery.restore');
  await expect
    .poll(async () => (await probe(page))!.screen, { timeout: 60_000 })
    .toMatch(/^(explore|offline_summary)$/);
  expect((await probe(page))!.state.gold).toBe(gold);
  await expect.poll(async () => (await readFiles(page, MAIN))[MAIN], { timeout: 30_000 }).toBe(backup);
  expect(Object.values(await readFiles(page, CORRUPT))).toContain(damaged);
  await boot(page);
  await waitScreen(page, 'title');
});
