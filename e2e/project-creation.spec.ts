import { expect, test, type APIRequestContext, type Page } from '@playwright/test';
import { readFileSync } from 'node:fs';
import path from 'node:path';

let projectId: string;
let selectionProjectId: string;
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
  selectionProjectId = await createProject(request, 'typed-addition');
  await runProjectCommand(request, selectionProjectId, { type: 'render', seed: 2026 });
  console.info(
    `[e2e setup] Initial project compilation completed in ${Math.round(performance.now() - startedAt)} ms.`
  );
});

test('administrator root remains an explicit project landing page', async ({ page }) => {
  const browserFailures = observeBrowserFailures(page);
  await page.goto('/');

  await expect(page).toHaveURL('/');
  await expect(page.getByRole('heading', { name: 'Projects', exact: true })).toBeVisible();
  await expect(page.getByText('Your projects and previews', { exact: true })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Open' }).first()).toBeVisible();
  expect(browserFailures()).toEqual([]);
});

test('canvas element selection is included in submitted feedback', async ({ page }) => {
  const browserFailures = observeBrowserFailures(page);
  await page.goto(`/projects/${selectionProjectId}`);
  const viewport = page.getByRole('region', { name: 'Visualization 1' });
  const stepStatus = page.getByText(/^Step \d+ of \d+$/);
  await expect(stepStatus).toBeVisible();
  const initialStepText = await stepStatus.textContent();
  const stepCount = Number(initialStepText?.match(/of (\d+)$/)?.[1]);
  expect(stepCount).toBeGreaterThan(1);
  for (let step = 1; step < stepCount; step += 1) {
    await page.getByLabel('Next visualization step').click();
  }
  await expect(stepStatus).toHaveText(`Step ${stepCount} of ${stepCount}`);

  const elements = viewport.locator('[data-instance-id]');
  const firstElement = elements.nth(0);
  const secondElement = elements.nth(1);
  await expect(firstElement).toBeVisible();
  await expect(secondElement).toBeVisible();
  const firstInstance = Number(await firstElement.getAttribute('data-instance-id'));
  const secondInstance = Number(await secondElement.getAttribute('data-instance-id'));
  await firstElement.click();
  await secondElement.click({ modifiers: ['Shift'] });
  const referenceSelection = page.getByRole('button', { name: 'Reference selection' });
  await expect(referenceSelection).toBeVisible();
  const automaticContext = page.getByTestId('automatic-feedback-context');
  await expect(automaticContext.locator('[data-slot="badge"]')).toHaveCount(2);
  await expect(automaticContext).toContainText(`/ S${stepCount} / E${firstInstance}`);
  await expect(automaticContext).toContainText(`/ S${stepCount} / E${secondInstance}`);

  const feedbackResponse = page.waitForResponse(
    (response) =>
      response.url().endsWith(`/api/projects/${selectionProjectId}`) &&
      response.request().method() === 'POST'
  );
  await page.getByLabel('Project feedback').pressSequentially('Focus on this element');
  await page.getByLabel('Project feedback').press('Enter');
  const response = await feedbackResponse;
  expect(response.status()).toBe(202);
  const accepted = (await response.json()) as { operationId: string };
  const payload = response.request().postDataJSON() as {
    content: Array<{
      type: string;
      presentationEvent?: number;
      step?: number;
      instances?: number[];
    }>;
  };
  expect(payload.content[0]).toEqual({ type: 'markdown', text: 'Viewing ' });
  expect(payload.content[1]).toMatchObject({
    type: 'element-ref',
    presentationEvent: expect.any(Number),
    step: stepCount - 1,
    instances: [firstInstance]
  });
  expect(payload.content[2]).toMatchObject({
    type: 'element-ref',
    presentationEvent: expect.any(Number),
    step: stepCount - 1,
    instances: [secondInstance]
  });
  expect(payload.content.at(-1)).toMatchObject({
    type: 'markdown',
    text: '.\n\nFocus on this element'
  });
  await waitForOperation(page.request, selectionProjectId, accepted.operationId);
  await expect(page.getByText('Thanks, I have noted that feedback.')).toBeVisible();
  const submittedFeedback = page
    .locator('article')
    .filter({ hasText: 'Focus on this element' })
    .last();
  const submittedReferences = submittedFeedback.getByRole('button');
  await expect(submittedReferences).toHaveCount(2);
  await expect(submittedReferences.nth(0)).toContainText(`/ S${stepCount} / E${firstInstance}`);
  await expect(submittedReferences.nth(1)).toContainText(`/ S${stepCount} / E${secondInstance}`);
  expect(await submittedReferences.nth(0).evaluate(elementContrastRatio)).toBeGreaterThanOrEqual(
    4.5
  );

  await submittedReferences.nth(0).click();
  await expect(viewport.locator('.selection-outline')).toHaveCount(1);
  await submittedReferences.nth(1).click({ modifiers: ['Shift'] });
  await expect(viewport.locator('.selection-outline')).toHaveCount(2);
  expect(browserFailures()).toEqual([]);
});

test('same-source candidates retain the current visualization step', async ({ page }) => {
  const browserFailures = observeBrowserFailures(page);
  await page.goto(`/projects/${selectionProjectId}`);

  const nextStep = page.getByLabel('Next visualization step');
  await expect(nextStep).toBeEnabled();
  await nextStep.click();
  await expect(page.getByText(/^Step 2 of \d+$/)).toBeVisible();

  const candidates = page.getByRole('button', { name: /^Candidate/ });
  expect(await candidates.count()).toBeGreaterThan(1);
  const firstSelected = (await candidates.nth(0).getAttribute('aria-pressed')) === 'true';
  const targetCard = candidates.nth(firstSelected ? 1 : 0).locator('..');
  const cardBounds = await targetCard.boundingBox();
  expect(cardBounds).not.toBeNull();
  await targetCard.click({ position: { x: 12, y: cardBounds!.height - 8 } });

  await expect(page.getByText(/^Step 2 of \d+$/)).toBeVisible();
  expect(browserFailures()).toEqual([]);
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
  await page.goto(`/projects/${selectionProjectId}`);

  const visualization = page.getByRole('button', { name: /^Candidate/ }).last();
  await expect(visualization).toBeVisible();
  await expect(visualization).toHaveAttribute('aria-pressed', 'true');
  const friendlyReference = page.getByRole('button', { name: /^Add .+ to feedback$/ }).last();
  const friendlyName = (await friendlyReference.textContent())?.trim();
  expect(friendlyName).toBeTruthy();
  await friendlyReference.click();
  await expect(page.getByLabel('Project feedback')).toContainText(friendlyName!);
  await expect(visualization).toHaveAttribute('aria-pressed', 'true');
  await page.getByRole('button', { name: `Remove reference ${friendlyName}` }).click();
  await expect(page.getByLabel('Project feedback')).not.toContainText(friendlyName!);
  await expect(page.getByRole('button', { name: 'Reference', exact: true })).toHaveCount(0);
  const visualizationCard = visualization.locator('..');
  const cardBounds = await visualizationCard.boundingBox();
  expect(cardBounds).not.toBeNull();
  await visualizationCard.click({ position: { x: 12, y: cardBounds!.height - 8 } });
  await expect(visualization).toBeFocused();
  await visualizationCard.hover();
  await expect
    .poll(() => visualizationCard.evaluate((card) => getComputedStyle(card).translate))
    .not.toBe('none');
  await expect(page.getByText('Visualization updated', { exact: true })).toHaveCount(0);

  await page.getByLabel('Presentation layout').selectOption('comparison');
  const comparisonCards = page.getByRole('button', { name: /^Candidate/ });
  await expect(comparisonCards).toHaveCount(2);
  await comparisonCards.nth(0).click();
  await comparisonCards.nth(1).click({ modifiers: ['Shift'] });
  await expect(comparisonCards.nth(0)).toHaveAttribute('aria-pressed', 'true');
  await expect(comparisonCards.nth(1)).toHaveAttribute('aria-pressed', 'true');
  const comparisonContext = page.getByTestId('automatic-feedback-context');
  await expect(comparisonContext).toContainText('Comparing');
  await expect(comparisonContext.locator('[data-slot="badge"]').first()).toHaveCSS(
    'overflow',
    'visible'
  );

  const devToggle = page.getByRole('switch', { name: 'Dev' });
  await expect(devToggle).not.toBeChecked();
  await expect(page.getByText('Developer details', { exact: true })).toHaveCount(0);

  await devToggle.click();
  await expect(devToggle).toBeChecked();
  await expect(page.getByText('Developer details', { exact: true })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Raw JSON' })).toBeVisible();

  await devToggle.click();
  await expect(page).toHaveURL(new RegExp(`/projects/${selectionProjectId}$`));
  await expect(page.getByText('Developer details', { exact: true })).toHaveCount(0);

  const projectResponse = await page.request.get(`/api/projects/${selectionProjectId}`);
  expect(projectResponse.ok()).toBe(true);
  const resource = (await projectResponse.json()) as ProjectResourceView;
  expect(resource.document.events[0].payload.creation).toEqual({ templateId: 'typed-addition' });
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
  await delayNextAdminAction(page, 'createPreview');
  await previewDialog.getByRole('button', { name: 'Create preview' }).click({ noWaitAfter: true });
  await expect(previewDialog.getByRole('button', { name: 'Creating preview' })).toBeDisabled();
  await expect(page).toHaveURL(/\/admin\/previews\//);
  await expect(page.getByText('Welcome', { exact: true }).last()).toBeVisible();
  await page.getByRole('button', { name: 'Next phase' }).click({ noWaitAfter: true });
  await expect(page).toHaveURL(/\/projects\//, { timeout: 150_000 });

  await expect(page.getByText('Preview', { exact: true })).toBeVisible();
  await expect(page.getByRole('button', { name: 'Next phase' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Return to administration' })).toBeVisible();
  await expect(page.getByText('Presentation layout', { exact: true })).toHaveCount(0);
  await expect(page.getByRole('switch', { name: 'Dev' })).toHaveCount(0);
  await expect(page.getByText('Assistant', { exact: true })).toBeVisible();
  const candidates = page.getByRole('button', { name: /^Candidate/ });
  await expect(candidates).toHaveCount(0);
  await expect(
    page.getByText('Your visualization will appear here.', { exact: true })
  ).toBeVisible();
  await expect(page.getByText('Preparing a visualization…', { exact: true })).toHaveCount(0);
  await expect(page.getByText('Generating more visualizations…', { exact: true })).toHaveCount(0);

  await page.getByRole('button', { name: 'Next phase' }).click();
  await expect(page).toHaveURL(/\/admin\/previews\//);
  await expect(page.getByText('First task complete', { exact: true }).last()).toBeVisible();
  await page.getByRole('link', { name: 'Return to administration' }).click();
  await expect(page).toHaveURL('/admin');
  await expect(
    page.getByRole('heading', { name: 'Administrator projects and previews' })
  ).toBeVisible();
  await expect(page.getByText(/Preview · Pilot study/).first()).toBeVisible();

  const participant = page.locator('[data-slot="card"]').filter({ hasText: 'E2E-GIFT' });
  await expect(participant.locator('[data-slot="card-description"]')).toContainText(
    /^Pilot study v1 · .+$/
  );
  await expect(participant.getByText('Not started', { exact: true })).toHaveAttribute(
    'data-slot',
    'badge'
  );
  await participant.getByRole('button', { name: 'Add gift card' }).click();
  let giftCardDialog = page.getByRole('dialog', { name: 'Gift card for E2E-GIFT' });
  const giftCardInput = giftCardDialog.getByLabel('Gift-card URL');
  await giftCardInput.fill('http://gift.example/card/static');
  await delayNextAdminAction(page, 'giftCard');
  await giftCardDialog.getByRole('button', { name: 'Save gift card' }).click();
  await expect(giftCardDialog.getByRole('button', { name: 'Saving gift card' })).toBeDisabled();
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
  await giftCardDialog.getByRole('button', { name: 'Cancel' }).click();
  await expect(giftCardDialog).toHaveCount(0);
  await expect(participant.getByText('Gift card assigned', { exact: true })).toBeVisible();

  await page.getByRole('button', { name: 'Add participant' }).click();
  let participantDialog = page.getByRole('dialog', { name: 'Add participant' });
  await participantDialog.getByLabel('Participant ID').fill('discarded');
  await participantDialog.getByRole('button', { name: 'Cancel' }).click();
  await page.getByRole('button', { name: 'Add participant' }).click();
  participantDialog = page.getByRole('dialog', { name: 'Add participant' });
  await expect(participantDialog.getByLabel('Participant ID')).toHaveValue('');
  await participantDialog.getByLabel('Participant ID').fill('invalid participant ID');
  await delayNextAdminAction(page, 'create');
  await participantDialog.getByRole('button', { name: 'Create participant' }).click();
  await expect(
    participantDialog.getByRole('button', { name: 'Creating participant' })
  ).toBeDisabled();
  await expect(
    participantDialog.getByText(
      'Participant ID must use 1–128 letters, numbers, hyphens, or underscores.'
    )
  ).toBeVisible();
  await participantDialog.getByRole('button', { name: 'Cancel' }).click();
  await expect(participantDialog).toHaveCount(0);

  await page.getByRole('button', { name: 'Add participant' }).click();
  participantDialog = page.getByRole('dialog', { name: 'Add participant' });
  await participantDialog.getByLabel('Participant ID').fill('E2E-CREATED');
  await delayNextAdminAction(page, 'create');
  await participantDialog.getByRole('button', { name: 'Create participant' }).click();
  await expect(
    participantDialog.getByRole('button', { name: 'Creating participant' })
  ).toBeDisabled();
  const createdDialog = page.getByRole('dialog', { name: 'Participant created' });
  await expect(createdDialog.getByLabel('Participant ID')).toHaveValue('E2E-CREATED');
  await expect(createdDialog.getByLabel('One-time password')).not.toHaveValue('');
  await createdDialog.getByRole('button', { name: 'Done' }).click();
  await expect(page.locator('[data-slot="card"]').filter({ hasText: 'E2E-CREATED' })).toBeVisible();

  await participant.getByRole('button', { name: 'Generate new password' }).click();
  let passwordDialog = page.getByRole('alertdialog', {
    name: 'Generate a new password for E2E-GIFT?'
  });
  await passwordDialog.getByRole('button', { name: 'Cancel' }).click();
  await expect(passwordDialog).toHaveCount(0);
  await participant.getByRole('button', { name: 'Generate new password' }).click();
  passwordDialog = page.getByRole('alertdialog', {
    name: 'Generate a new password for E2E-GIFT?'
  });
  await delayNextAdminAction(page, 'password');
  await passwordDialog.getByRole('button', { name: 'Generate new password' }).click();
  await expect(
    passwordDialog.getByRole('button', { name: 'Generating new password' })
  ).toBeDisabled();
  const generatedPasswordDialog = page.getByRole('alertdialog', {
    name: 'New password for E2E-GIFT'
  });
  await expect(generatedPasswordDialog.getByLabel('One-time password')).not.toHaveValue('');
  await generatedPasswordDialog.getByRole('button', { name: 'Done' }).click();

  await participant.getByRole('button', { name: 'Delete participant' }).click();
  let deleteDialog = page.getByRole('alertdialog', {
    name: 'Delete participant E2E-GIFT?'
  });
  const confirmation = deleteDialog.getByLabel('Enter DELETE E2E-GIFT to confirm');
  await confirmation.fill('DELETE E2E-GIFT');
  await deleteDialog.getByRole('button', { name: 'Cancel' }).click();
  await participant.getByRole('button', { name: 'Delete participant' }).click();
  deleteDialog = page.getByRole('alertdialog', { name: 'Delete participant E2E-GIFT?' });
  await expect(deleteDialog.getByLabel('Enter DELETE E2E-GIFT to confirm')).toHaveValue('');
  await expect(deleteDialog.getByRole('button', { name: 'Delete participant' })).toBeDisabled();
  await deleteDialog.getByLabel('Enter DELETE E2E-GIFT to confirm').fill('DELETE E2E-GIFT');
  await expect(deleteDialog.getByRole('button', { name: 'Delete participant' })).toBeEnabled();
  await deleteDialog.getByRole('button', { name: 'Cancel' }).click();
  await expect(deleteDialog).toHaveCount(0);

  await participant.getByRole('button', { name: 'Delete participant' }).click();
  deleteDialog = page.getByRole('alertdialog', { name: 'Delete participant E2E-GIFT?' });
  await deleteDialog.getByLabel('Enter DELETE E2E-GIFT to confirm').fill('DELETE E2E-GIFT');
  await delayNextAdminAction(page, 'purgeParticipant');
  await deleteDialog.getByRole('button', { name: 'Delete participant' }).click();
  await expect(deleteDialog.getByRole('button', { name: 'Deleting participant' })).toBeDisabled();
  await expect(participant).toHaveCount(0);

  expect(browserFailures()).toEqual([]);
});

async function createProject(request: APIRequestContext, templateId: string): Promise<string> {
  const response = await request.post('/api/projects', { data: { templateId } });
  expect(response.status()).toBe(templateId === 'blank' ? 201 : 202);
  const created = (await response.json()) as { projectId: string; operationId?: string };
  if (templateId === 'blank') return created.projectId;
  expect(created.operationId).toBeTruthy();
  const operationId = created.operationId as string;
  const observedMilestones = new Set<string>();
  console.info(
    `[e2e compile] Initial-render operation ${operationId} accepted for project ${created.projectId}; waiting for its real compile Timeline.`
  );
  await expect
    .poll(
      async () => {
        const project = await request.get(`/api/projects/${created.projectId}`);
        if (!project.ok()) return `http-${project.status()}: ${await project.text()}`;
        const resource = (await project.json()) as ProjectResourceView;
        for (const event of resource.document.events.filter(
          (event) => event.operationId === operationId
        )) {
          if (observedMilestones.has(event.type)) continue;
          observedMilestones.add(event.type);
          console.info(`[e2e compile] ${operationId}: ${event.type}`);
        }
        return resource.document.events.findLast(
          (event) =>
            event.operationId === operationId &&
            (event.type === 'operation.completed' || event.type === 'operation.failed')
        )?.type;
      },
      { timeout: 150_000 }
    )
    .toBe('operation.completed');
  return created.projectId;
}

async function runProjectCommand(
  request: APIRequestContext,
  projectId: string,
  command: { type: 'render'; seed: number }
): Promise<void> {
  const project = await request.get(`/api/projects/${projectId}`);
  expect(project.ok()).toBe(true);
  const resource = (await project.json()) as ProjectResourceView;
  const operationId = crypto.randomUUID();
  const response = await request.post(`/api/projects/${projectId}`, {
    data: { ...command, operationId, expectedHead: resource.document.events.length }
  });
  expect(response.status()).toBe(202);
  await waitForOperation(request, projectId, operationId);
}

async function waitForOperation(
  request: APIRequestContext,
  projectId: string,
  operationId: string
): Promise<void> {
  await expect
    .poll(async () => {
      const project = await request.get(`/api/projects/${projectId}`);
      if (!project.ok()) return `http-${project.status()}`;
      const resource = (await project.json()) as ProjectResourceView;
      return resource.document.events.findLast(
        (event) =>
          event.operationId === operationId &&
          (event.type === 'operation.completed' || event.type === 'operation.failed')
      )?.type;
    })
    .toBe('operation.completed');
}

async function delayNextAdminAction(page: Page, action: string): Promise<void> {
  await page.route(
    (url) => url.pathname === '/admin' && url.search === `?/${action}`,
    async (route) => {
      await new Promise((resolve) => setTimeout(resolve, 250));
      await route.continue();
    },
    { times: 1 }
  );
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

function elementContrastRatio(element: HTMLElement): number {
  const canvas = document.createElement('canvas');
  const context = canvas.getContext('2d', { willReadFrequently: true });
  if (!context) return 0;
  const rgb = (color: string): [number, number, number] => {
    context.clearRect(0, 0, 1, 1);
    context.fillStyle = color;
    context.fillRect(0, 0, 1, 1);
    return [...context.getImageData(0, 0, 1, 1).data.slice(0, 3)] as [number, number, number];
  };
  const luminance = (color: string) =>
    rgb(color)
      .map((channel) => channel / 255)
      .map((channel) => (channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4))
      .reduce((total, channel, index) => total + channel * [0.2126, 0.7152, 0.0722][index], 0);
  const style = getComputedStyle(element);
  const foreground = luminance(style.color);
  const background = luminance(style.backgroundColor);
  return (Math.max(foreground, background) + 0.05) / (Math.min(foreground, background) + 0.05);
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
