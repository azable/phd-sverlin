import { render } from 'svelte/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import RootPage from './+page.svelte';

const mocks = vi.hoisted(() => ({
  list: vi.fn(),
  requirePrincipal: vi.fn(),
  templates: vi.fn(() => [{ id: 'blank' }])
}));

vi.mock('$lib/server/authorization', () => ({ requirePrincipal: mocks.requirePrincipal }));
vi.mock('$lib/server/projects/repository', () => ({
  projectRepository: { list: mocks.list }
}));
vi.mock('$lib/server/projects/starter-catalog', () => ({
  listProjectTemplates: mocks.templates
}));

beforeEach(() => {
  mocks.list.mockReset();
  mocks.requirePrincipal.mockReset();
});

describe('application root', () => {
  it('lists only projects owned by the signed-in administrator without redirecting', async () => {
    mocks.requirePrincipal.mockReturnValue(adminPrincipal());
    const projects = [
      {
        projectId: 'admin-project',
        title: 'Administrator project',
        updatedAt: '2026-08-30T00:00:00.000Z',
        eventCount: 1
      }
    ];
    mocks.list.mockResolvedValue(projects);
    const { load } = await import('./+page.server');

    await expect(load({ locals: {} } as never)).resolves.toEqual({
      isAdmin: true,
      projects,
      templates: [{ id: 'blank' }]
    });
    expect(mocks.list).toHaveBeenCalledWith('admin-one');
  });

  it('shows project creation when the administrator owns no projects', async () => {
    mocks.requirePrincipal.mockReturnValue(adminPrincipal());
    mocks.list.mockResolvedValue([]);
    const { load } = await import('./+page.server');

    await expect(load({ locals: {} } as never)).resolves.toEqual({
      isAdmin: true,
      projects: [],
      templates: [{ id: 'blank' }]
    });
  });

  it('sends participants through their assigned study flow without listing projects', async () => {
    mocks.requirePrincipal.mockReturnValue({ kind: 'participant' });
    const { load } = await import('./+page.server');

    await expect(load({ locals: {} } as never)).rejects.toMatchObject({
      status: 307,
      location: '/study'
    });
    expect(mocks.list).not.toHaveBeenCalled();
  });

  it('renders administrator projects as explicit links on the landing page', () => {
    const { body } = render(RootPage, {
      props: {
        data: {
          isAdmin: true,
          projects: [
            {
              projectId: 'admin-project',
              title: 'Administrator project',
              updatedAt: '2026-08-30T00:00:00.000Z',
              eventCount: 1,
              renderer: 'sverlin'
            }
          ],
          templates: [
            { id: 'blank', title: 'Blank project', summary: 'Start with a blank project.' }
          ]
        }
      } as never
    });

    expect(body).toContain('Your projects and previews');
    expect(body).toContain('Administrator project');
    expect(body).toContain('href="/projects/admin-project"');
  });
});

function adminPrincipal() {
  return { kind: 'admin', user: { id: 'admin-one' } };
}
