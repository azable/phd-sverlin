import { describe, expect, it } from 'vitest';

import { activeStudyDefinition, studyDefinition } from './registry';
import { resolveStudyArm } from './definition';

describe('study definition', () => {
  it('counterbalances the two renderer orders from one central protocol', () => {
    const sverlinFirst = resolveStudyArm(activeStudyDefinition, 'sverlin-first')
      .filter((phase) => phase.kind === 'task')
      .map((phase) => phase.condition.renderer);
    const htmlFirst = resolveStudyArm(activeStudyDefinition, 'html-first')
      .filter((phase) => phase.kind === 'task')
      .map((phase) => phase.condition.renderer);
    expect(sverlinFirst).toEqual(['sverlin', 'html']);
    expect(htmlFirst).toEqual(['html', 'sverlin']);
  });

  it('resolves the recorded protocol version and keeps renderer layouts explicit', () => {
    expect(studyDefinition(activeStudyDefinition.id, activeStudyDefinition.version)).toBe(
      activeStudyDefinition
    );
    expect(activeStudyDefinition.conditions.sverlin.workspace.layout).toBe('comparison');
    expect(activeStudyDefinition.conditions.html.workspace.layout).toBe('single');
    expect(activeStudyDefinition.conditions.sverlin).not.toHaveProperty('candidatePool');
    expect(() => studyDefinition(activeStudyDefinition.id, 999)).toThrow('Unknown study protocol');
  });
});
