import { describe, expect, it } from 'vitest';

import type { TimelinePresentation } from './presentation-history';
import {
  localPresentationStep,
  presentationPlaybackContext,
  PresentationPlayback
} from './presentation-playback.svelte';

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

  it('aligns hierarchical v2 frames and holds an omitted inner frame', () => {
    const left = v2Presentation(1, [0, 1, 3]);
    const right = v2Presentation(2, [0, 2, 3]);
    const context = presentationPlaybackContext([left, right]);

    expect(context.frames.map(({ key }) => key)).toEqual([
      'frame-0',
      'frame-1',
      'frame-2',
      'frame-3'
    ]);
    expect(localPresentationStep(context, left.presentation.presentationId, 2)).toBe(1);
    expect(localPresentationStep(context, right.presentation.presentationId, 1)).toBe(0);
    expect(localPresentationStep(context, right.presentation.presentationId, 2)).toBe(1);
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

function v2Presentation(id: number, ordinals: number[]): TimelinePresentation {
  const scenarioKey = 'e'.repeat(64);
  const render = JSON.stringify({
    irVersion: 2,
    seed: id,
    scenarioKey,
    scenarioSeed: 1,
    viewSeed: id,
    sourcePath: 'Main.sverlin',
    sampling: { mode: 'balancedChoices', coverage: 'exactEnumeration' },
    coordinates: {
      systemName: 'sverlin-logical-y-down',
      systemOrigin: 'top-left',
      systemYAxis: 'down'
    },
    root: -1,
    resources: [],
    findings: [],
    variables: [],
    elements: [
      {
        id: -1,
        role: 'Canvas',
        box: {
          bounds: { rectX: 0, rectY: 0, rectWidth: 100, rectHeight: 80 },
          padding: { top: 0, right: 0, bottom: 0, left: 0 },
          margin: { top: 0, right: 0, bottom: 0, left: 0 }
        },
        children: [],
        style: {},
        styleVariables: []
      }
    ],
    connectors: [],
    steps: ordinals.map((ordinal) => ({
      label: `Frame ${ordinal}`,
      instances: [],
      occurrenceKey: `frame-${ordinal}`,
      ordinal,
      connectorInstances: []
    }))
  });
  return {
    eventId: id,
    eventType: 'visualization.presented',
    operationId: '12345678-1234-4123-8123-123456789abc',
    slot: (id - 1) as 0 | 1,
    presentation: {
      presentationId: `32345678-1234-4123-8123-${String(id).padStart(12, '0')}`,
      format: 'sverlin-ir-v2',
      scenarioKey,
      scenarioSeed: 1,
      viewSeed: id,
      source: { text: 'source', sha256: sourceA, mediaType: 'text/x-sverlin' },
      render: {
        text: render,
        sha256: String(id).repeat(64).slice(0, 64),
        mediaType: 'application/json'
      }
    }
  };
}
