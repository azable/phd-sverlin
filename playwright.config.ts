import path from 'node:path';

import { defineConfig, devices } from '@playwright/test';

import { e2eAuthSecret, e2eSessionCookieValue, e2eSessionExpiresAt } from './scripts/e2e-auth';

const outputRoot = path.resolve('outputs/playwright');

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  workers: 1,
  // Compiler preparation and the initial compiled fixture have separate allowances below;
  // ordinary browser behavior should complete promptly once that fixture exists.
  timeout: 30_000,
  expect: { timeout: 20_000 },
  outputDir: path.join(outputRoot, 'test-results'),
  reporter: [['line'], ['html', { outputFolder: path.join(outputRoot, 'report'), open: 'never' }]],
  use: {
    ...devices['Desktop Chrome'],
    baseURL: 'http://127.0.0.1:4173',
    // Real compiler-backed flows may need the 180-second test budget, but a missing
    // control is a UI failure and should not consume that entire allowance.
    actionTimeout: 20_000,
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
    video: 'retain-on-failure',
    storageState: {
      cookies: [
        {
          name: 'sverlin.session_token',
          value: e2eSessionCookieValue(),
          domain: '127.0.0.1',
          path: '/',
          expires: Math.floor(e2eSessionExpiresAt().getTime() / 1_000),
          httpOnly: true,
          secure: false,
          sameSite: 'Lax'
        }
      ],
      origins: []
    }
  },
  webServer: {
    command: 'node scripts/run-with-test-database.mjs --seed-admin node scripts/start-e2e.mjs',
    url: 'http://127.0.0.1:4173/api/health/ready',
    gracefulShutdown: { signal: 'SIGTERM', timeout: 10_000 },
    reuseExistingServer: false,
    timeout: 180_000,
    env: {
      BETTER_AUTH_SECRET: e2eAuthSecret,
      BETTER_AUTH_URL: 'http://127.0.0.1:4173',
      SVERLIN_SCRATCH_DIR: path.join(outputRoot, 'compiler'),
      SVERLIN_STATE_DIR: path.join(outputRoot, 'state'),
      SVERLIN_E2E_AUTH_BYPASS: 'true'
    }
  }
});
