import { describe, expect, it } from 'vitest';

import { activeStudyDefinition } from '$lib/shared/study/registry';

import {
  adminPreviewTask,
  studyPreviewOption,
  studyPreviewOptions,
  studyPreviewProjectUrl
} from './study-preview';

describe('admin study previews', () => {
  it('derives one choice per active condition from the central protocol', () => {
    const options = studyPreviewOptions();

    expect(options).toHaveLength(2);
    expect(options).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          conditionId: 'sverlin',
          renderer: 'sverlin',
          layout: 'comparison',
          presentationCount: 2,
          durationSeconds: 900
        }),
        expect.objectContaining({
          conditionId: 'html',
          renderer: 'html',
          layout: 'single',
          presentationCount: 1,
          durationSeconds: 900
        })
      ])
    );
    expect(options.every(({ studyId }) => studyId === activeStudyDefinition.id)).toBe(true);
  });

  it('derives expiry from the server-issued start time', () => {
    const option = studyPreviewOptions()[0];
    const startedAt = Date.UTC(2026, 7, 30, 12, 0, 0);

    expect(adminPreviewTask(option.key, String(startedAt), startedAt + 1_000)).toMatchObject({
      context: 'admin-preview',
      previewKey: option.key,
      expired: false,
      layout: option.layout
    });
    expect(
      adminPreviewTask(option.key, String(startedAt), startedAt + option.durationSeconds * 1_000)
        .expired
    ).toBe(true);
  });

  it('rejects invented choices and malformed start times', () => {
    expect(() => studyPreviewOption('invented')).toThrow('Unknown study preview option');
    const option = studyPreviewOptions()[0];
    expect(() => adminPreviewTask(option.key, 'not-a-time')).toThrow(
      'Invalid study preview start time'
    );
  });

  it('builds a canonical project URL', () => {
    const option = studyPreviewOptions()[0];
    const url = new URL(
      studyPreviewProjectUrl('preview-project', option.key, 1_000),
      'https://sverlin.invalid'
    );

    expect(url.pathname).toBe('/projects/preview-project');
    expect(url.searchParams.get('studyPreview')).toBe(option.key);
    expect(url.searchParams.get('previewStartedAt')).toBe('1000');
  });
});
