import { describe, expect, it } from 'vitest';

import { TracePlayer } from './trace-player.svelte';
import type { VisualizationPackage } from './types';

describe('TracePlayer', () => {
  it('joins the first scene snapshot to the element registry', () => {
    const player = new TracePlayer();
    player.setTrace(trace(['one']));

    expect(player.currentStep).toBe(0);
    expect(player.stepCount).toBe(1);
    expect(player.elements).toHaveLength(1);
    expect(player.elements[0].content).toBe('one');
    expect(player.elements[0].instanceId).toBe('instance.one');
  });

  it('seeks forward and backward without replaying prior frames', () => {
    const player = new TracePlayer();
    player.setTrace(trace(['one', 'two']));
    player.next();

    expect(player.currentStep).toBe(1);
    expect(player.elements[0].content).toBe('two');

    player.previous();
    expect(player.currentStep).toBe(0);
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

  it('clamps a requested replacement step to the available snapshots', () => {
    const player = new TracePlayer();
    player.setTrace(trace(['one']), { initialStep: 4 });

    expect(player.currentStep).toBe(0);
    expect(player.elements[0].content).toBe('one');
  });

  it('represents an empty snapshot directly', () => {
    const player = new TracePlayer();
    const visualization = trace(['one']);
    visualization.frames.push({ durationMs: 300, instances: [] });
    player.setTrace(visualization);
    player.next();

    expect(player.elements).toEqual([]);
  });
});

function trace(contents: string[]): VisualizationPackage {
  const elements = contents.map((content, index) => ({
    id: `element.${index}`,
    nodeId: index,
    nodeKey: 'node',
    role: 'Value',
    kind: { kind: 'trace' as const },
    content,
    style: { top: 0, left: 0, width: 10, height: 10 },
    variables: emptyVariableTrace()
  }));

  return {
    schemaVersion: 1,
    seed: 1,
    source: { path: 'compile/app/DSL/Main.hs', compilerVersion: 'test' },
    canvas: { width: 100, height: 80 },
    variables: [],
    elements,
    frames: elements.map((element, index) => ({
      durationMs: 300,
      instances: [{ id: `instance.${contents[index]}`, elementId: element.id }]
    }))
  };
}

function emptyVariableTrace() {
  return {
    top: [],
    left: [],
    width: [],
    height: [],
    opacity: [],
    zIndex: [],
    padding: [],
    fontSize: [],
    radius: [],
    strokeWidth: [],
    alpha: [],
    fill: [],
    stroke: [],
    fontFamily: [],
    fontWeight: [],
    fontStyle: [],
    textAlign: [],
    borderStyle: [],
    whiteSpace: []
  };
}
