import { describe, expect, it } from 'vitest';

import type { TimelinePresentation } from './presentation-history';
import {
  localPresentationStep,
  presentationPlaybackContext,
  PresentationPlayback
} from './presentation-playback.svelte';

describe('presentation playback', () => {
  it('retains the selected step across seeded views of the same component', () => {
    const playback = new PresentationPlayback();
    const first = presentationPlaybackContext([presentation(1, 'a'.repeat(64), 4)]);
    const second = presentationPlaybackContext([presentation(2, 'a'.repeat(64), 4)]);
    playback.activate(first);
    playback.seek(first, 2);
    playback.activate(second);
    expect(second.key).toBe(first.key);
    expect(playback.stepFor(second)).toBe(2);
  });

  it('clamps on fewer steps and resets for a different source', () => {
    const playback = new PresentationPlayback();
    const first = presentationPlaybackContext([presentation(1, 'a'.repeat(64), 4)]);
    const shorter = presentationPlaybackContext([presentation(2, 'a'.repeat(64), 2)]);
    playback.activate(first);
    playback.seek(first, 3);
    playback.activate(shorter);
    expect(playback.stepFor(shorter)).toBe(1);
    const other = presentationPlaybackContext([presentation(3, 'b'.repeat(64), 3)]);
    playback.activate(other);
    expect(playback.stepFor(other)).toBe(0);
  });

  it('maps one shared position to each visible presentation', () => {
    const left = presentation(1, 'a'.repeat(64), 3);
    const right = presentation(2, 'a'.repeat(64), 3);
    const context = presentationPlaybackContext([left, right]);
    expect(context.frames.map(({ label }) => label)).toEqual(['Step 1', 'Step 2', 'Step 3']);
    expect(localPresentationStep(context, left.presentation.presentationId, 2)).toBe(2);
    expect(localPresentationStep(context, right.presentation.presentationId, 2)).toBe(2);
  });
});

function presentation(id: number, sourceSha256: string, stepCount: number): TimelinePresentation {
  return {
    eventId: id,
    eventType: 'visualization.presented',
    operationId: '12345678-1234-4123-8123-123456789abc',
    slot: 0,
    presentation: {
      presentationId: `12345678-1234-4123-8123-${String(id).padStart(12, '0')}`,
      format: 'browser-bundle-v1',
      mode: 'sverlin',
      stepSignature: 'same-source',
      labels: Array.from({ length: stepCount }, (_, step) => `Step ${step + 1}`),
      seed: id,
      source: { text: 'component', sha256: sourceSha256, mediaType: 'text/x-svelte' },
      html: { text: '', sha256: '0'.repeat(64), mediaType: 'text/html' },
      javascript: {
        text: 'void 0;',
        sha256: String(id).repeat(64).slice(0, 64),
        mediaType: 'text/javascript'
      }
    }
  };
}
