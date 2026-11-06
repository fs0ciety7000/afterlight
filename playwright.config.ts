import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: 'tests/e2e',
  timeout: 120_000,
  // Each browser renders WebGL in software here; more workers starve the CPU.
  workers: 2,
  use: { baseURL: 'http://localhost:8060', trace: 'off' },
  webServer: {
    command: 'pnpm build:web && pnpm serve',
    port: 8060,
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
  },
  projects: [
    { name: 'desktop', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['Pixel 7 landscape'] } },
    { name: 'tablet', use: { ...devices['iPad (gen 7) landscape'], browserName: 'chromium' } },
  ],
});
