import { describe, expect, it, vi } from 'vitest';

import { TracePlayer } from './trace-player.svelte';
import type { RenderElement } from './types';

describe('TracePlayer', () => {
  it('rebuilds the first frame when a trace is installed', () => {
    const player = new TracePlayer();

    player.setTrace({
      canvas: { width: 100, height: 80 },
      frames: [[{ kind: 'create', id: 'a', element: element('one') }]]
    });

    expect(player.currentStep).toBe(0);
    expect(player.stepCount).toBe(1);
    expect(player.elements).toHaveLength(1);
    expect(player.elements[0].content).toBe('one');

    player.dispose();
  });

  it('moves forward and backward through update patches', () => {
    const player = new TracePlayer();

    player.setTrace({
      canvas: { width: 100, height: 80 },
      frames: [
        [{ kind: 'create', id: 'a', element: element('one') }],
        [
          {
            kind: 'update',
            id: 'a',
            from: element('one'),
            to: element('two')
          }
        ]
      ]
    });

    player.next();

    expect(player.currentStep).toBe(1);
    expect(player.elements[0].content).toBe('two');

    player.previous();

    expect(player.currentStep).toBe(0);
    expect(player.elements[0].content).toBe('one');

    player.dispose();
  });

  it('keeps destroyed elements during the transition and then removes them', () => {
    vi.useFakeTimers();

    const player = new TracePlayer();

    player.setTrace({
      canvas: { width: 100, height: 80 },
      frames: [
        [{ kind: 'create', id: 'a', element: element('one') }],
        [{ kind: 'destroy', id: 'a', element: element('one') }]
      ]
    });

    player.next();

    expect(player.elements).toHaveLength(1);
    expect(player.elements[0].exiting).toBe(true);

    vi.advanceTimersByTime(300);

    expect(player.elements).toHaveLength(0);

    player.dispose();
    vi.useRealTimers();
  });
});

function element(content: string): RenderElement {
  return {
    blockId: 1,
    kind: 'Value',
    content,
    style: {
      position: 'absolute',
      top: '0px',
      left: '0px',
      width: '10px',
      height: '10px'
    }
  };
}
