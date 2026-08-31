import { describe, expect, it } from 'vitest';

import { mainStudyV1 } from './main-v1';
import { registerStudies, studyDefinition } from './registry';
import { resolveStudyArm } from './definition';

describe('study definition', () => {
  it('counterbalances the two renderer orders from one central protocol', () => {
    const sverlinFirst = resolveStudyArm(mainStudyV1, 'sverlin-first')
      .filter((phase) => phase.kind === 'task')
      .map((phase) => phase.condition.renderer);
    const htmlFirst = resolveStudyArm(mainStudyV1, 'html-first')
      .filter((phase) => phase.kind === 'task')
      .map((phase) => phase.condition.renderer);
    expect(sverlinFirst).toEqual(['sverlin', 'html']);
    expect(htmlFirst).toEqual(['html', 'sverlin']);
  });

  it('resolves the recorded protocol version and keeps renderer layouts explicit', () => {
    expect(studyDefinition(mainStudyV1.id, mainStudyV1.version)).toBe(mainStudyV1);
    expect(mainStudyV1.conditions.sverlin.workspace.layout).toBe('comparison');
    expect(mainStudyV1.conditions.sverlin.presentationBufferTarget).toBe(4);
    expect(mainStudyV1.conditions.html.workspace.layout).toBe('single');
    expect(mainStudyV1.conditions.sverlin).not.toHaveProperty('candidatePool');
    expect(mainStudyV1.interactionCapture).toMatchObject({
      schemaVersion: 1,
      cursorSampleIntervalMs: 250,
      draftSnapshotIntervalMs: 1_000,
      outboxByteLimit: 5 * 1024 * 1024
    });
    expect(() => studyDefinition(mainStudyV1.id, 999)).toThrow('Unknown study protocol');
  });

  it('rejects duplicate configured protocol versions', () => {
    expect(() =>
      registerStudies([
        { definition: mainStudyV1, enrollment: 'open' },
        { definition: mainStudyV1, enrollment: 'closed' }
      ])
    ).toThrow('must be unique');
  });
});
