import { render } from 'svelte/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import ExamplesPage from './+page.svelte';

const mocks = vi.hoisted(() => ({
  page: { url: new URL('http://localhost/examples') },
  requireAdmin: vi.fn(),
  templates: vi.fn(() => [
    { id: 'blank', title: 'Blank project', summary: 'Blank' },
    { id: 'linear-search', title: 'Linear search', summary: 'Search an array' }
  ])
}));

vi.mock('$lib/server/authorization', () => ({
  requireAdmin: mocks.requireAdmin
}));
vi.mock('$app/state', () => ({ page: mocks.page }));
vi.mock('$lib/server/projects/starter-catalog', () => ({ listProjectTemplates: mocks.templates }));

beforeEach(() => {
  mocks.page.url = new URL('http://localhost/examples');
  mocks.requireAdmin.mockReset();
});

describe('examples page', () => {
  it('shows a project-free dropdown for catalogued examples without a chat interface', async () => {
    const { load } = await import('./+page.server');
    const data = await load({ locals: {} } as never);
    const { body } = render(ExamplesPage, { props: { data } as never });

    expect(mocks.requireAdmin).toHaveBeenCalledOnce();
    expect(body).toContain('id="example-source"');
    expect(body).toContain('value="linear-search"');
    expect(body).not.toContain('value="blank"');
    expect(body).toContain('Load example');
    expect(body).toContain('without creating a project');
    expect(body).not.toContain('data-replay-region="feedback-composer"');
  });

  it('opens a seeded preview without project or Timeline controls', async () => {
    mocks.page.url = new URL('http://localhost/examples?example=linear-search&seed=7');
    const { load } = await import('./+page.server');
    const data = await load({ locals: {} } as never);
    const { body } = render(ExamplesPage, { props: { data } as never });

    expect(body).toContain('Seed 7');
    expect(body).toContain('Retry');
    expect(body).not.toContain('Open project workspace');
    expect(body).not.toContain('feedback-composer');
  });
});
