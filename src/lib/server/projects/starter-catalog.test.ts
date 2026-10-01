import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';

import { describe, expect, it, vi } from 'vitest';

import catalog from '../../../../examples/catalog.json';

import {
  getProjectTemplate,
  listProjectTemplates,
  resolveProjectTemplate,
  UnknownProjectTemplateError
} from './starter-catalog';

describe('starter catalog', () => {
  it('offers the blank source and executable examples through one template catalog', () => {
    const blank = resolveProjectTemplate({ templateId: 'blank' });
    const templates = listProjectTemplates();

    expect(blank.source).toContain('domain :: Domain ()');
    expect(blank.source).toContain('render :: Render ()');
    expect(templates).toHaveLength(15);
    expect(templates.map(({ id }) => id)).toEqual([
      'blank',
      'lifecycle',
      'typed-addition',
      'continuity-and-fork',
      'linear-search',
      'binary-search',
      'bubble-sort',
      'merge-sort',
      'heap-sort',
      'breadth-first-search',
      'dijkstra-shortest-path',
      'topological-sort',
      'linked-list-reversal',
      'longest-common-subsequence',
      'csp-compositions'
    ]);
  });

  it('returns exact source only for a known server-owned ID', () => {
    const template = getProjectTemplate('linear-search');
    expect(template.file).toBe('LinearSearch.sverlin');
    expect(template.source).toContain('searchIteration ::');
    expect(() => getProjectTemplate('not-catalogued')).toThrow(UnknownProjectTemplateError);
  });

  it('reads an edited example from disk without restarting the catalog module', async () => {
    const root = await mkdtemp(path.join(tmpdir(), 'sverlin-example-catalog-'));
    const directory = path.join(root, 'examples');
    const previousRoot = process.env.SVERLIN_REPOSITORY_ROOT;
    try {
      await mkdir(directory);
      await Promise.all(
        catalog.templates.map(({ file }) =>
          writeFile(path.join(directory, file), 'original source')
        )
      );
      process.env.SVERLIN_REPOSITORY_ROOT = root;
      vi.resetModules();
      const current = await import('./starter-catalog');
      expect(current.getProjectTemplate('linear-search').source).toBe('original source');

      await writeFile(path.join(directory, 'LinearSearch.sverlin'), 'revised source');
      expect(current.getProjectTemplate('linear-search').source).toBe('revised source');
    } finally {
      if (previousRoot === undefined) delete process.env.SVERLIN_REPOSITORY_ROOT;
      else process.env.SVERLIN_REPOSITORY_ROOT = previousRoot;
      vi.resetModules();
      await rm(root, { recursive: true, force: true });
    }
  });
});
