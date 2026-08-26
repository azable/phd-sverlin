import { expect, test, type APIRequestContext, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';
import path from 'node:path';

import { clearMaintenanceLock, writeMaintenanceLock } from '../src/lib/server/maintenance-lock.js';

let projectId: string;
let createdProjectId: string;
const maintenancePath = path.resolve('outputs/playwright/app-lock.json');
const templateCount = (
  JSON.parse(readFileSync(path.resolve('examples/catalog.json'), 'utf8')) as {
    templates: unknown[];
  }
).templates.length;

test.beforeAll(async ({ request }) => {
  projectId = await createProject(request, 'blank');
});

test.afterEach(async () => {
  await clearMaintenanceLock(maintenancePath);
});

test('new project combines template selection with the current Dev-detail preference', async ({
  page
}) => {
  const browserFailures = observeBrowserFailures(page);
  await page.goto(`/projects/${projectId}`);
  await expect(page.getByRole('button', { name: 'New project' })).toBeVisible();

  const devToggle = page.getByRole('switch', { name: 'Dev mode' });
  await devToggle.click();
  await expect(page).toHaveURL(new RegExp(`/projects/${projectId}\\?dev=1$`));
  await expect(page.getByText('Expanded diagnostics', { exact: true })).toBeVisible();

  await page.getByRole('button', { name: 'New project' }).click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Create a project' })).toBeVisible();
  await expect(page.getByRole('radio', { name: /^Use / })).toHaveCount(templateCount);
  const creationResponse = page.waitForResponse(
    (response) =>
      response.url().endsWith('/api/projects') && response.request().method() === 'POST',
    { timeout: 150_000 }
  );
  await page
    .getByRole('button', { name: 'Create from Blank project' })
    .click({ noWaitAfter: true });

  const created = await creationResponse;
  expect(created.status()).toBe(201);
  expect(created.request().postDataJSON()).toEqual({ templateId: 'blank' });
  createdProjectId = ((await created.json()) as { projectId: string }).projectId;
  expect(createdProjectId).not.toBe(projectId);
  await expect(page).toHaveURL(`/projects/${createdProjectId}?dev=1`);

  const projectResponse = await page.request.get(`/api/projects/${createdProjectId}`);
  expect(projectResponse.ok()).toBe(true);
  const resource = (await projectResponse.json()) as ProjectResourceView;
  expect(resource.document.projectId).toBe(createdProjectId);
  expect(resource.document.events[0].payload.creation).toEqual({ templateId: 'blank' });
  expect(JSON.stringify(resource.document.events)).toContain('program = return ()');
  expect(browserFailures()).toEqual([]);
});

test('Dev mode is reversible frontend state, not a project type', async ({ page }) => {
  const browserFailures = observeBrowserFailures(page);
  await page.goto(`/projects/${projectId}`);

  const devToggle = page.getByRole('switch', { name: 'Dev mode' });
  await expect(devToggle).not.toBeChecked();
  await expect(page.getByText('Expanded diagnostics', { exact: true })).toHaveCount(0);

  await devToggle.click();
  await expect(devToggle).toBeChecked();
  await expect(page.getByText('Expanded diagnostics', { exact: true })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Raw project JSON' })).toBeVisible();

  await devToggle.click();
  await expect(page).toHaveURL(new RegExp(`/projects/${projectId}$`));
  await expect(page.getByText('Expanded diagnostics', { exact: true })).toHaveCount(0);

  const projectResponse = await page.request.get(`/api/projects/${projectId}`);
  expect(projectResponse.ok()).toBe(true);
  const resource = (await projectResponse.json()) as ProjectResourceView;
  expect(resource.document.events[0].payload.creation).toEqual({ templateId: 'blank' });
  expect(browserFailures()).toEqual([]);
});

test('maintenance lock keeps reads and playback available while rejecting mutations', async ({
  page
}) => {
  const browserFailures = observeBrowserFailures(page);
  await page.goto(`/projects/${createdProjectId}`);
  await expect(page.getByRole('button', { name: 'Reset', exact: true })).toBeEnabled();

  await writeMaintenanceLock('Compiler boundary maintenance.', maintenancePath);
  await expect(page.getByText('Read-only maintenance mode', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'New project' })).toBeDisabled();
  await expect(page.getByRole('textbox', { name: 'Project feedback' })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Regenerate' })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Reset', exact: true })).toBeEnabled();

  const blocked = await page.request.post('/api/projects', {
    data: { templateId: 'blank' }
  });
  expect(blocked.status()).toBe(423);
  await expect(blocked.json()).resolves.toMatchObject({ code: 'app_locked' });

  await clearMaintenanceLock(maintenancePath);
  await expect(page.getByText('Read-only maintenance mode', { exact: true })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'New project' })).toBeEnabled();
  expect(browserFailures()).toEqual([]);
});

async function createProject(request: APIRequestContext, templateId: string): Promise<string> {
  const response = await request.post('/api/projects', { data: { templateId } });
  expect(response.status()).toBe(201);
  return ((await response.json()) as { projectId: string }).projectId;
}

function observeBrowserFailures(page: Page): () => string[] {
  const failures: string[] = [];
  page.on('pageerror', (error) => failures.push(`page: ${error.message}`));
  page.on('console', (message) => {
    if (message.type() === 'error') failures.push(`console: ${message.text()}`);
  });
  page.on('requestfailed', (request) => {
    if (
      request.method() === 'GET' &&
      request.url().includes('/events?after=') &&
      request.failure()?.errorText === 'net::ERR_ABORTED'
    ) {
      return;
    }
    failures.push(`request: ${request.method()} ${request.url()} ${request.failure()?.errorText}`);
  });
  return () => failures;
}

type ProjectResourceView = {
  document: {
    projectId: string;
    events: Array<{
      payload: { creation?: { templateId: string }; [key: string]: unknown };
    }>;
  };
};
