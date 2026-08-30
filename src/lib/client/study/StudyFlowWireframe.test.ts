import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';

import type { StudyFlow } from '$lib/shared/study/projection';

import StudyFlowWireframe from './StudyFlowWireframe.svelte';

const flow: StudyFlow = {
  runId: 'preview-one',
  mode: 'preview',
  studyId: 'pilot-study',
  studyVersion: 1,
  studyName: 'Pilot study',
  armId: 'html-first',
  status: 'not-started',
  currentPhaseIndex: 0,
  phases: [
    {
      sequenceIndex: 0,
      status: 'pending',
      phase: {
        id: 'welcome',
        kind: 'instruction',
        title: 'Welcome',
        paragraphs: ['Welcome to the study.'],
        continueLabel: 'Start'
      }
    }
  ]
};

describe('StudyFlowWireframe', () => {
  it('can omit repeated study metadata when embedded in a labelled card', () => {
    const { body } = render(StudyFlowWireframe, { props: { flow, showHeader: false } });

    expect(body).not.toContain('<p class="font-medium">Pilot study');
    expect(body).not.toContain('Arm: html-first');
    expect(body).toContain('Welcome');
  });
});
