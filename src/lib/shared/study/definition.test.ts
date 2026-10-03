import { describe, expect, it } from 'vitest';

import { mainStudy } from '$lib/studies/main';
import { registeredStudies, registerStudies, studyDefinition } from './registry';
import { resolveStudyArm } from './definition';

describe('study definition', () => {
  it('counterbalances the two renderer orders from one central protocol', () => {
    const sverlinFirst = resolveStudyArm(mainStudy, 'sverlin-first')
      .filter((phase) => phase.kind === 'task')
      .map((phase) => phase.condition.renderer);
    const htmlFirst = resolveStudyArm(mainStudy, 'html-first')
      .filter((phase) => phase.kind === 'task')
      .map((phase) => phase.condition.renderer);
    expect(sverlinFirst).toEqual(['sverlin', 'html']);
    expect(htmlFirst).toEqual(['html', 'sverlin']);
  });

  it('resolves the recorded protocol version and keeps renderer layouts explicit', () => {
    expect(studyDefinition('main-study', 1)).toBe(mainStudy);
    expect(registeredStudies()).toEqual([{ definition: mainStudy, enrollment: 'open' }]);
    expect(mainStudy.conditions.sverlin.workspace.layout).toBe('comparison');
    expect(mainStudy.conditions.sverlin.presentationBufferTarget).toBe(4);
    expect(mainStudy.conditions.html.workspace.layout).toBe('single');
    expect(mainStudy.conditions.sverlin.project.artifactFormat).toBe('svelte-component');
    expect(mainStudy.interactionCapture).toMatchObject({
      schemaVersion: 1,
      cursorSampleIntervalMs: 250,
      draftSnapshotIntervalMs: 1_000,
      outboxByteLimit: 5 * 1024 * 1024
    });
    expect(() => studyDefinition(mainStudy.id, 2)).toThrow('Unknown study protocol');
    expect(() => studyDefinition(mainStudy.id, 999)).toThrow('Unknown study protocol');
  });

  it('rejects duplicate configured protocol versions', () => {
    expect(() =>
      registerStudies([
        { definition: mainStudy, enrollment: 'open' },
        { definition: mainStudy, enrollment: 'closed' }
      ])
    ).toThrow('must be unique');
  });
});
