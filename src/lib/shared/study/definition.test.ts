import { describe, expect, it } from 'vitest';

import { pilotStudyV1 } from './pilot-v1';
import { registerStudies, studyDefinition } from './registry';
import { resolveStudyArm } from './definition';

describe('study definition', () => {
  it('counterbalances the two renderer orders from one central protocol', () => {
    const sverlinFirst = resolveStudyArm(pilotStudyV1, 'sverlin-first')
      .filter((phase) => phase.kind === 'task')
      .map((phase) => phase.condition.renderer);
    const htmlFirst = resolveStudyArm(pilotStudyV1, 'html-first')
      .filter((phase) => phase.kind === 'task')
      .map((phase) => phase.condition.renderer);
    expect(sverlinFirst).toEqual(['sverlin', 'html']);
    expect(htmlFirst).toEqual(['html', 'sverlin']);
  });

  it('resolves the recorded protocol version and keeps renderer layouts explicit', () => {
    expect(studyDefinition(pilotStudyV1.id, pilotStudyV1.version)).toBe(pilotStudyV1);
    expect(pilotStudyV1.conditions.sverlin.workspace.layout).toBe('comparison');
    expect(pilotStudyV1.conditions.sverlin.presentationBufferTarget).toBe(4);
    expect(pilotStudyV1.conditions.html.workspace.layout).toBe('single');
    expect(pilotStudyV1.conditions.sverlin).not.toHaveProperty('candidatePool');
    expect(() => studyDefinition(pilotStudyV1.id, 999)).toThrow('Unknown study protocol');
  });

  it('rejects duplicate configured protocol versions', () => {
    expect(() =>
      registerStudies([
        { definition: pilotStudyV1, enrollment: 'open' },
        { definition: pilotStudyV1, enrollment: 'closed' }
      ])
    ).toThrow('must be unique');
  });
});
