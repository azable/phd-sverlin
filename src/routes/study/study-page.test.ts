import { render } from 'svelte/server';
import { describe, expect, it } from 'vitest';

import StudyPage from './+page.svelte';

const completionState = {
  studyId: 'pilot-study',
  studyVersion: 1,
  armId: 'sverlin-first',
  phaseIndex: 4,
  phase: {
    id: 'complete',
    kind: 'completion' as const,
    title: 'Study complete',
    paragraphs: ['Thank you. Your responses have been recorded.']
  },
  expired: false
};

describe('completed study page', () => {
  it('shows the participant gift-card link and logout action', () => {
    const { body } = render(StudyPage, {
      props: {
        data: {
          state: completionState,
          giftCardUrl: 'https://gift.example/card/static'
        },
        form: null
      } as never
    });

    expect(body).toContain('Open your gift card');
    expect(body).toContain('https://gift.example/card/static');
    expect(body).toContain('referrerpolicy="no-referrer"');
    expect(body).toContain('action="/logout"');
    expect(body).toContain('Sign out');
  });

  it('shows contact guidance without hiding logout when no card is assigned', () => {
    const { body } = render(StudyPage, {
      props: { data: { state: completionState }, form: null } as never
    });

    expect(body).toContain('No gift card has been assigned. Please contact the researcher.');
    expect(body).toContain('action="/logout"');
  });
});
