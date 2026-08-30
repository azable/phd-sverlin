import { expect, test, type APIRequestContext, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';
import path from 'node:path';

let projectId: string;
let createdProjectId: string;
const templateCount = (
  JSON.parse(readFileSync(path.resolve('examples/catalog.json'), 'utf8')) as {
    templates: unknown[];
  }
).templates.length;

test.beforeAll(async ({ request }) => {
  test.setTimeout(180_000);
  const startedAt = performance.now();
  console.info('[e2e setup] Creating and compiling the initial project fixture…');
  projectId = await createProject(request, 'blank');
  console.info(
    `[e2e setup] Initial project compilation completed in ${Math.round(performance.now() - startedAt)} ms.`
  );
});

test('new project combines template selection with the current Dev-detail preference', async ({
  page
}) => {
  const browserFailures = observeBrowserFailures(page);
  await page.goto(`/projects/${projectId}`);
  await expect(page.getByRole('button', { name: 'New project' })).toBeVisible();

  const devToggle = page.getByRole('switch', { name: 'Dev' });
  await devToggle.click();
  await expect(page).toHaveURL(new RegExp(`/projects/${projectId}\\?dev=1$`));
  await expect(page.getByText('Developer details', { exact: true })).toBeVisible();

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
  expect(created.status()).toBe(202);
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

  const devToggle = page.getByRole('switch', { name: 'Dev' });
  await expect(devToggle).not.toBeChecked();
  await expect(page.getByText('Developer details', { exact: true })).toHaveCount(0);

  await devToggle.click();
  await expect(devToggle).toBeChecked();
  await expect(page.getByText('Developer details', { exact: true })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Raw JSON' })).toBeVisible();

  await devToggle.click();
  await expect(page).toHaveURL(new RegExp(`/projects/${projectId}$`));
  await expect(page.getByText('Developer details', { exact: true })).toHaveCount(0);

  const projectResponse = await page.request.get(`/api/projects/${projectId}`);
  expect(projectResponse.ok()).toBe(true);
  const resource = (await projectResponse.json()) as ProjectResourceView;
  expect(resource.document.events[0].payload.creation).toEqual({ templateId: 'blank' });
  expect(browserFailures()).toEqual([]);
});

async function createProject(request: APIRequestContext, templateId: string): Promise<string> {
  const response = await request.post('/api/projects', { data: { templateId } });
  expect(response.status()).toBe(202);
  const created = (await response.json()) as { projectId: string; operationId: string };
  const observedMilestones = new Set<string>();
  console.info(
    `[e2e compile] Initial-render operation ${created.operationId} accepted for project ${created.projectId}; waiting for its real compile Timeline.`
  );
  await expect
    .poll(
      async () => {
        const project = await request.get(`/api/projects/${created.projectId}`);
        if (!project.ok()) return `http-${project.status()}: ${await project.text()}`;
        const resource = (await project.json()) as ProjectResourceView;
        for (const event of resource.document.events.filter(
          ({ operationId }) => operationId === created.operationId
        )) {
          if (observedMilestones.has(event.type)) continue;
          observedMilestones.add(event.type);
          console.info(`[e2e compile] ${created.operationId}: ${event.type}`);
        }
        return resource.document.events.findLast(
          (event) =>
            event.operationId === created.operationId &&
            (event.type === 'operation.completed' || event.type === 'operation.failed')
        )?.type;
      },
      { timeout: 150_000 }
    )
    .toBe('operation.completed');
  return created.projectId;
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
      request.failure()?.errorText === 'net::ERR_ABORTED' &&
      (request.url().includes('/events?after=') ||
        request.url().includes('/node_modules/.vite/deps/') ||
        request.url().includes('/__data.json'))
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
      type: string;
      operationId: string;
      payload: { creation?: { templateId: string }; [key: string]: unknown };
    }>;
  };
};
