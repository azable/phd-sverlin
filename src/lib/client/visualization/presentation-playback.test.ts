import { describe, expect, it } from 'vitest';

import type { TimelinePresentation } from './presentation-history';
import { presentationPlaybackContext, PresentationPlayback } from './presentation-playback.svelte';

const sourceA = 'a'.repeat(64);
const sourceB = 'b'.repeat(64);

describe('presentation playback', () => {
  it('retains the numerical step for the same Sverlin source despite presentation changes', () => {
    const playback = new PresentationPlayback();
    const first = presentationPlaybackContext([presentation(1, sourceA, 4, 'steps-a')]);
    const second = presentationPlaybackContext([presentation(2, sourceA, 4, 'steps-b')]);

    playback.activate(first);
    playback.seek(first, 2);
    playback.activate(second);

    expect(second.key).toBe(first.key);
    expect(playback.stepFor(second)).toBe(2);
  });

  it('commits a clamp when a same-source candidate has fewer steps', () => {
    const playback = new PresentationPlayback();
    const longer = presentationPlaybackContext([presentation(1, sourceA, 5, 'steps-a')]);
    const shorter = presentationPlaybackContext([presentation(2, sourceA, 2, 'steps-b')]);

    playback.activate(longer);
    playback.seek(longer, 4);
    playback.activate(shorter);
    expect(playback.stepFor(shorter)).toBe(1);

    playback.activate(longer);
    expect(playback.stepFor(longer)).toBe(1);
  });

  it('resets for a different source and bounds all seeks', () => {
    const playback = new PresentationPlayback();
    const first = presentationPlaybackContext([presentation(1, sourceA, 3, 'steps-a')]);
    const different = presentationPlaybackContext([presentation(2, sourceB, 2, 'steps-a')]);

    playback.activate(first);
    expect(playback.seek(first, 99)).toBe(2);
    playback.activate(different);
    expect(playback.stepFor(different)).toBe(0);
    expect(playback.seek(different, -3)).toBe(0);
  });

  it('uses presentation identity rather than source compatibility for HTML frames', () => {
    const playback = new PresentationPlayback();
    const first = presentationPlaybackContext([htmlPresentation(1, 3)]);
    const second = presentationPlaybackContext([htmlPresentation(2, 3)]);

    playback.activate(first);
    playback.seek(first, 2);
    playback.activate(second);

    expect(second.key).not.toBe(first.key);
    expect(playback.stepFor(second)).toBe(0);
  });
});

function presentation(
  id: number,
  sourceSha256: string,
  stepCount: number,
  stepSignature: string
): TimelinePresentation {
  return {
    eventId: id,
    eventType: 'visualization.presented',
    operationId: '12345678-1234-4123-8123-123456789abc',
    slot: 0,
    presentation: {
      presentationId: `12345678-1234-4123-8123-${String(id).padStart(12, '0')}`,
      format: 'sverlin-ir-v1',
      stepSignature,
      seed: id,
      source: { text: 'source', sha256: sourceSha256, mediaType: 'text/x-sverlin' },
      render: {
        text: JSON.stringify({
          steps: Array.from({ length: stepCount }, (_, index) => ({ label: `Step ${index + 1}` }))
        }),
        sha256: String(id).repeat(64).slice(0, 64),
        mediaType: 'application/json'
      }
    }
  };
}

function htmlPresentation(id: number, stepCount: number): TimelinePresentation {
  const content = JSON.stringify({
    format: 'sverlin-html-frames',
    version: 1,
    frames: Array.from({ length: stepCount }, (_, index) => ({
      label: `Step ${index + 1}`,
      html: `<p>${index + 1}</p>`
    }))
  });
  return {
    eventId: id,
    eventType: 'visualization.presented',
    operationId: '12345678-1234-4123-8123-123456789abc',
    slot: 0,
    presentation: {
      presentationId: `22345678-1234-4123-8123-${String(id).padStart(12, '0')}`,
      format: 'html-frames-v1',
      stepSignature: `steps-${id}`,
      authored: { text: content, sha256: 'c'.repeat(64), mediaType: 'application/json' },
      rendered: { text: content, sha256: 'd'.repeat(64), mediaType: 'application/json' }
    }
  };
}
