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

  await expect(page.getByText('Sverlin Assistant', { exact: true })).toBeVisible();
  await expect(
    page.getByText('Tell me what algorithm or program you would like to visualize', {
      exact: false
    })
  ).toBeVisible();
  const visualization = page.getByRole('button', { name: /^Visualization/ }).first();
  await expect(visualization).toBeVisible();
  await expect(visualization).toHaveAttribute('aria-pressed', 'true');
  await expect(page.getByText('Visualization updated', { exact: true })).toHaveCount(0);

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

test('administrator can run a timed study preview and configure a participant gift card', async ({
  page
}) => {
  test.setTimeout(180_000);
  const browserFailures = observeBrowserFailures(page);
  await page.goto('/admin');

  await expect(page.getByRole('heading', { name: 'Configured studies' })).toBeVisible();
  await page.getByRole('button', { name: 'Create preview' }).first().click();
  const previewDialog = page.getByRole('dialog', { name: /Preview Pilot study/ });
  await expect(previewDialog.getByText('Full flow', { exact: true })).toBeVisible();
  await previewDialog.getByRole('button', { name: 'Create preview' }).click({ noWaitAfter: true });
  await expect(page).toHaveURL(/\/admin\/previews\//);
  await expect(page.getByText('Welcome', { exact: true }).last()).toBeVisible();
  await page.getByRole('button', { name: 'Force next phase' }).click({ noWaitAfter: true });
  await expect(page).toHaveURL(/\/projects\//, { timeout: 150_000 });

  await expect(page.getByText('Preview', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Force next phase' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Return to administration' })).toBeVisible();
  await expect(page.getByText('Presentation layout', { exact: true })).toHaveCount(0);
  await expect(page.getByRole('switch', { name: 'Dev' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: /^Visualization/ })).toHaveCount(2);

  await page.getByRole('button', { name: 'Force next phase' }).click();
  await expect(page).toHaveURL(/\/admin\/previews\//);
  await expect(page.getByText('First task complete', { exact: true }).last()).toBeVisible();
  await page.getByRole('link', { name: 'Return to administration' }).click();
  await expect(page).toHaveURL('/admin');
  await expect(
    page.getByRole('heading', { name: 'Administrator projects and previews' })
  ).toBeVisible();
  await expect(page.getByText(/Preview · Pilot study/).first()).toBeVisible();

  const participant = page.locator('[data-slot="card"]').filter({ hasText: 'E2E-GIFT' });
  await expect(participant.getByText('Not started', { exact: true })).toBeVisible();
  await participant.getByRole('button', { name: 'Add gift card' }).click();
  let giftCardDialog = page.getByRole('dialog', { name: 'Gift card for E2E-GIFT' });
  const giftCardInput = giftCardDialog.getByLabel('Gift-card URL');
  await giftCardInput.fill('http://gift.example/card/static');
  await giftCardDialog.getByRole('button', { name: 'Save gift card' }).click();
  await expect(giftCardDialog.getByText('Gift-card URLs must use HTTPS.')).toBeVisible();
  await giftCardInput.fill('https://gift.example/card/static');
  await giftCardInput.press('Enter');
  await expect(giftCardDialog).toHaveCount(0);
  await expect(participant.getByText('Gift card assigned', { exact: true })).toBeVisible();

  await participant.getByRole('button', { name: 'Edit gift card' }).click();
  giftCardDialog = page.getByRole('dialog', { name: 'Gift card for E2E-GIFT' });
  await giftCardDialog.getByLabel('Gift-card URL').fill('https://gift.example/card/updated');
  await giftCardDialog.getByLabel('Gift-card URL').press('Enter');
  await expect(giftCardDialog).toHaveCount(0);
  await participant.getByRole('button', { name: 'Edit gift card' }).click();
  giftCardDialog = page.getByRole('dialog', { name: 'Gift card for E2E-GIFT' });
  await expect(giftCardDialog.getByLabel('Gift-card URL')).toHaveValue(
    'https://gift.example/card/updated'
  );
  await giftCardDialog.getByRole('button', { name: 'Clear' }).click();
  await expect(giftCardDialog).toHaveCount(0);
  await expect(participant.getByText('No gift card', { exact: true })).toBeVisible();

  await page.getByRole('button', { name: 'Add participant' }).click();
  let participantDialog = page.getByRole('dialog', { name: 'Add participant' });
  await participantDialog.getByLabel('Participant ID').fill('discarded');
  await participantDialog.getByRole('button', { name: 'Cancel' }).click();
  await page.getByRole('button', { name: 'Add participant' }).click();
  participantDialog = page.getByRole('dialog', { name: 'Add participant' });
  await expect(participantDialog.getByLabel('Participant ID')).toHaveValue('');
  await participantDialog.getByLabel('Participant ID').fill('invalid participant ID');
  await participantDialog.getByRole('button', { name: 'Create participant' }).click();
  await expect(
    participantDialog.getByText(
      'Participant ID must use 1–128 letters, numbers, hyphens, or underscores.'
    )
  ).toBeVisible();
  await participantDialog.getByRole('button', { name: 'Cancel' }).click();
  await expect(participantDialog).toHaveCount(0);

  await participant.getByRole('button', { name: 'Generate new password' }).click();
  const passwordDialog = page.getByRole('alertdialog', {
    name: 'Generate a new password for E2E-GIFT?'
  });
  await passwordDialog.getByRole('button', { name: 'Cancel' }).click();
  await expect(passwordDialog).toHaveCount(0);

  await participant.getByRole('button', { name: 'Delete participant data' }).click();
  let deleteDialog = page.getByRole('alertdialog', {
    name: 'Delete data for E2E-GIFT?'
  });
  const confirmation = deleteDialog.getByLabel('Enter DELETE E2E-GIFT to confirm');
  await confirmation.fill('DELETE E2E-GIFT');
  await deleteDialog.getByRole('button', { name: 'Cancel' }).click();
  await participant.getByRole('button', { name: 'Delete participant data' }).click();
  deleteDialog = page.getByRole('alertdialog', { name: 'Delete data for E2E-GIFT?' });
  await expect(deleteDialog.getByLabel('Enter DELETE E2E-GIFT to confirm')).toHaveValue('');
  await expect(
    deleteDialog.getByRole('button', { name: 'Delete participant data' })
  ).toBeDisabled();
  await deleteDialog.getByLabel('Enter DELETE E2E-GIFT to confirm').fill('DELETE E2E-GIFT');
  await expect(deleteDialog.getByRole('button', { name: 'Delete participant data' })).toBeEnabled();
  await deleteDialog.getByRole('button', { name: 'Cancel' }).click();
  await expect(deleteDialog).toHaveCount(0);

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
