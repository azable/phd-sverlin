import { tick } from 'svelte';
import { describe, expect, it } from 'vitest';

import { TracePlayer } from './trace-player.svelte';
import type { VisualizationPackage } from './types';

describe('TracePlayer', () => {
  it('joins the first checkpoint step to the element registry', () => {
    const player = new TracePlayer();
    player.setTrace(trace(['one']));

    expect(player.currentStep).toBe(0);
    expect(player.stepCount).toBe(1);
    expect(player.currentStepLabel).toBe('Step 1');
    expect(player.elements).toHaveLength(1);
    expect(player.elements[0].content).toBe('one');
    expect(player.elements[0].instanceId).toBe(1);
  });

  it('seeks forward and backward with stable render lineage', () => {
    const player = new TracePlayer();
    player.setTrace(trace(['one', 'two']));
    player.next();

    expect(player.currentStep).toBe(1);
    expect(player.currentStepLabel).toBe('Step 2');
    expect(player.elements[0].content).toBe('two');

    player.previous();
    expect(player.currentStep).toBe(0);
    expect(player.currentStepLabel).toBe('Step 1');
    expect(player.elements[0].content).toBe('one');
  });

  it('keeps the requested step when installing a replacement trace', () => {
    const player = new TracePlayer();
    player.setTrace(trace(['one', 'two']));
    player.next();
    player.setTrace(trace(['replacement-one', 'replacement-two']), {
      initialStep: player.currentStep
    });

    expect(player.currentStep).toBe(1);
    expect(player.elements[0].content).toBe('replacement-two');
  });

  it('clamps a requested replacement step to the available timeline', () => {
    const player = new TracePlayer();
    player.setTrace(trace(['one']), { initialStep: 4 });

    expect(player.currentStep).toBe(0);
    expect(player.elements[0].content).toBe('one');
  });

  it('starts a fork at its origin and settles at its solved style', async () => {
    const visualization = trace(['source', 'fork']);
    visualization.steps[1].instances = [
      { id: 1, elementId: 0 },
      { id: 2, elementId: 1, originElementId: 0 }
    ];
    visualization.elements[0].style.left = 10;
    visualization.elements[1].style.left = 80;

    const player = new TracePlayer();
    player.setTrace(visualization);
    player.next();

    expect(player.elements.find(({ instanceId }) => instanceId === 2)?.style.left).toBe(10);
    await tick();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(player.elements.find(({ instanceId }) => instanceId === 2)?.style.left).toBe(80);
  });

  it('removes absent instances immediately so Svelte can own their outro', () => {
    const visualization = trace(['one']);
    visualization.steps.push({ label: 'Empty', instances: [] });

    const player = new TracePlayer();
    player.setTrace(visualization);
    player.next();

    expect(player.elements).toEqual([]);
  });

  it('represents an empty step directly when seeking', () => {
    const player = new TracePlayer();
    const visualization = trace(['one']);
    visualization.steps.push({ label: 'Empty', instances: [] });
    player.setTrace(visualization);
    player.seek(1);

    expect(player.elements).toEqual([]);
  });
});

function trace(contents: string[]): VisualizationPackage {
  const elements = contents.map((content, id) => ({
    id,
    role: 'Value',
    kind: { kind: 'trace' as const },
    content,
    style: { top: 0, left: id * 10, width: 10, height: 10 },
    styleVariables: []
  }));

  return {
    seed: 1,
    sourcePath: 'Main.sverlin',
    canvas: { width: 100, height: 80 },
    variables: [],
    elements,
    steps: elements.map((element, index) => ({
      label: `Step ${index + 1}`,
      instances: [{ id: 1, elementId: element.id }]
    }))
  };
}
