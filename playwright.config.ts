import path from 'node:path';

import { defineConfig, devices } from '@playwright/test';

const outputRoot = path.resolve('outputs/playwright');

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  workers: 1,
  timeout: 180_000,
  expect: { timeout: 20_000 },
  outputDir: path.join(outputRoot, 'test-results'),
  reporter: [['line'], ['html', { outputFolder: path.join(outputRoot, 'report'), open: 'never' }]],
  use: {
    ...devices['Desktop Chrome'],
    baseURL: 'http://127.0.0.1:4173',
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    video: 'retain-on-failure'
  },
  webServer: {
    command: 'node scripts/run-with-test-database.mjs --seed-admin node scripts/start-e2e.mjs',
    url: 'http://127.0.0.1:4173/api/health/ready',
    gracefulShutdown: { signal: 'SIGTERM', timeout: 10_000 },
    reuseExistingServer: false,
    timeout: 180_000,
    env: {
      SVERLIN_SCRATCH_DIR: path.join(outputRoot, 'compiler'),
      SVERLIN_E2E_AUTH_BYPASS: 'true'
    }
  }
});
