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
    command:
      'pnpm run prepare:compiler && node scripts/run-with-state-lock.mjs node node_modules/vite/bin/vite.js dev --host 127.0.0.1 --port 4173 --strictPort',
    url: 'http://127.0.0.1:4173/projects/__ready__',
    gracefulShutdown: { signal: 'SIGTERM', timeout: 10_000 },
    reuseExistingServer: false,
    timeout: 180_000,
    env: {
      SVERLIN_STATE_DIR: path.join(outputRoot, 'state'),
      SVERLIN_SCRATCH_DIR: path.join(outputRoot, 'compiler'),
      SVERLIN_APP_LOCK_PATH: path.join(outputRoot, 'app-lock.json'),
      SVERLIN_E2E_AUTH_BYPASS: 'true',
      SVERLIN_PROJECT_STORE: 'file'
    }
  }
});
