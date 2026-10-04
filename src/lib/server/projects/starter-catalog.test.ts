import { describe, expect, it } from 'vitest';

import { compileSvelteComponent } from '$lib/modes/sverlin/compile.server';

import {
  getProjectTemplate,
  listProjectTemplates,
  resolveProjectTemplate,
  UnknownProjectTemplateError
} from './starter-catalog';

describe('starter catalog', () => {
  it('offers only developer-owned, buildable components', async () => {
    expect(listProjectTemplates().map(({ id }) => id)).toEqual(['blank', 'linear-search']);
    const blank = resolveProjectTemplate({ templateId: 'blank' });
    expect((await compileSvelteComponent(blank.source)).labels).toEqual(['Start']);
    expect(
      (await compileSvelteComponent(getProjectTemplate('linear-search').source)).masterLabels
    ).toEqual([
      'Start',
      'Compare index 0',
      'Compare index 1',
      'Compare index 2',
      'Found 2 at index 3'
    ]);
  });

  it('rejects unknown templates and mode-incompatible examples', () => {
    expect(() => getProjectTemplate('not-catalogued')).toThrow(UnknownProjectTemplateError);
    expect(() => resolveProjectTemplate({ templateId: 'linear-search', mode: 'html' })).toThrow(
      'only for the Svelte-backed mode'
    );
  });
});
