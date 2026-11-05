import { expect, test } from '@playwright/test';

test('web export boots and reaches the main scene', async ({ page }) => {
  const logs: string[] = [];
  page.on('console', (msg) => logs.push(msg.text()));
  await page.goto('/');
  await expect(page.locator('canvas')).toBeVisible();
  await expect.poll(() => logs.some((l) => l.includes('Afterlight booted')), { timeout: 45_000 }).toBe(true);
});
