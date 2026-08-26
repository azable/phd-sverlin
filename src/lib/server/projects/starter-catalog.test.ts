import { describe, expect, it } from 'vitest';

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

    expect(blank.source).toContain('program = return ()');
    expect(templates).toHaveLength(6);
    expect(templates.map(({ id }) => id)).toEqual([
      'blank',
      'lifecycle',
      'typed-addition',
      'continuity-and-fork',
      'linear-search',
      'csp-compositions'
    ]);
  });

  it('returns exact source only for a known server-owned ID', () => {
    const template = getProjectTemplate('linear-search');
    expect(template.file).toBe('LinearSearch.sverlin');
    expect(template.source).toContain('searchIteration ::');
    expect(() => getProjectTemplate('not-catalogued')).toThrow(UnknownProjectTemplateError);
  });
});
