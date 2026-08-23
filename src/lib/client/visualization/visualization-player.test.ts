import { tick } from 'svelte';
import { describe, expect, it } from 'vitest';

import { decodeVisualization, type Visualization } from '$lib/shared/visualization';
import { VisualizationPlayer } from './visualization-player.svelte';

describe('VisualizationPlayer', () => {
  it('normalizes the former trace leaf tag in stored visualizations', () => {
    const stored = visualization(['one']);
    const json = JSON.stringify({
      seed: stored.seed,
      sourcePath: stored.sourcePath,
      canvas: stored.canvas,
      variables: stored.variables,
      elements: stored.elements.map((element) => ({
        id: element.id,
        role: element.role,
        style: element.style,
        styleVariables: element.styleVariables,
        content:
          element.content?.kind === 'legacyTextContent' ? element.content.textSource : undefined,
        kind: { kind: 'trace' }
      })),
      steps: stored.steps
    });

    expect(decodeVisualization(json).elements[0].kind).toEqual({ kind: 'leaf' });
  });

  it('clears a stale render when the project state has no active visualization', () => {
    const player = new VisualizationPlayer();
    player.setVisualization(visualization(['one']));

    player.clear();

    expect(player.hasVisualization).toBe(false);
    expect(player.currentStep).toBe(-1);
    expect(player.elements).toEqual([]);
  });

  it('joins the first checkpoint step to the element registry', () => {
    const player = new VisualizationPlayer();
    player.setVisualization(visualization(['one']));

    expect(player.currentStep).toBe(0);
    expect(player.stepCount).toBe(1);
    expect(player.currentStepLabel).toBe('Step 1');
    expect(player.elements).toHaveLength(1);
    expect(player.elements[0].content).toEqual({ kind: 'legacyTextContent', textSource: 'one' });
    expect(player.elements[0].instanceId).toBe(1);
  });

  it('seeks forward and backward with stable render lineage', () => {
    const player = new VisualizationPlayer();
    player.setVisualization(visualization(['one', 'two']));
    player.next();

    expect(player.currentStep).toBe(1);
    expect(player.currentStepLabel).toBe('Step 2');
    expect(player.elements[0].content).toEqual({ kind: 'legacyTextContent', textSource: 'two' });

    player.previous();
    expect(player.currentStep).toBe(0);
    expect(player.currentStepLabel).toBe('Step 1');
    expect(player.elements[0].content).toEqual({ kind: 'legacyTextContent', textSource: 'one' });
  });

  it('joins checkpoint-specific code emphasis onto a stable render instance', () => {
    const compiledVisualization = visualization(['one', 'two']);
    compiledVisualization.steps[0].instances[0].codeEmphasisRanges = [
      { sourceRangeStart: 0, sourceRangeEnd: 3 }
    ];
    compiledVisualization.steps[1].instances[0].codeEmphasisRanges = [
      { sourceRangeStart: 4, sourceRangeEnd: 7 }
    ];

    const player = new VisualizationPlayer();
    player.setVisualization(compiledVisualization);
    expect(player.elements[0].codeEmphasisRanges).toEqual([
      { sourceRangeStart: 0, sourceRangeEnd: 3 }
    ]);

    player.next();
    expect(player.elements[0].instanceId).toBe(1);
    expect(player.elements[0].codeEmphasisRanges).toEqual([
      { sourceRangeStart: 4, sourceRangeEnd: 7 }
    ]);
  });

  it('keeps the requested step when installing a replacement visualization', () => {
    const player = new VisualizationPlayer();
    player.setVisualization(visualization(['one', 'two']));
    player.next();
    player.setVisualization(visualization(['replacement-one', 'replacement-two']), {
      initialStep: player.currentStep
    });

    expect(player.currentStep).toBe(1);
    expect(player.elements[0].content).toEqual({
      kind: 'legacyTextContent',
      textSource: 'replacement-two'
    });
  });

  it('opens a different render at its first step by default', () => {
    const player = new VisualizationPlayer();
    player.setVisualization(visualization(['one', 'two']));
    player.next();

    player.setVisualization(visualization(['replacement-one', 'replacement-two']));

    expect(player.currentStep).toBe(0);
    expect(player.elements[0].content).toEqual({
      kind: 'legacyTextContent',
      textSource: 'replacement-one'
    });
  });

  it('clamps a requested replacement step to the available timeline', () => {
    const player = new VisualizationPlayer();
    player.setVisualization(visualization(['one']), { initialStep: 4 });

    expect(player.currentStep).toBe(0);
    expect(player.elements[0].content).toEqual({ kind: 'legacyTextContent', textSource: 'one' });
  });

  it('starts a fork at its origin and settles at its solved style', async () => {
    const compiledVisualization = visualization(['source', 'fork']);
    compiledVisualization.steps[1].instances = [
      { id: 1, elementId: 0 },
      { id: 2, elementId: 1, originElementId: 0 }
    ];
    compiledVisualization.elements[0].style.left = 10;
    compiledVisualization.elements[1].style.left = 80;

    const player = new VisualizationPlayer();
    player.setVisualization(compiledVisualization);
    player.next();

    expect(player.elements.find(({ instanceId }) => instanceId === 2)?.style.left).toBe(10);
    await tick();
    await new Promise((resolve) => setTimeout(resolve, 0));
    expect(player.elements.find(({ instanceId }) => instanceId === 2)?.style.left).toBe(80);
  });

  it('removes absent instances immediately so Svelte can own their outro', () => {
    const compiledVisualization = visualization(['one']);
    compiledVisualization.steps.push({ label: 'Empty', instances: [] });

    const player = new VisualizationPlayer();
    player.setVisualization(compiledVisualization);
    player.next();

    expect(player.elements).toEqual([]);
  });

  it('represents an empty step directly when seeking', () => {
    const player = new VisualizationPlayer();
    const compiledVisualization = visualization(['one']);
    compiledVisualization.steps.push({ label: 'Empty', instances: [] });
    player.setVisualization(compiledVisualization);
    player.seek(1);

    expect(player.elements).toEqual([]);
  });
});

function visualization(contents: string[]): Visualization {
  const elements = contents.map((content, id) => ({
    id,
    role: 'Value',
    kind: { kind: 'leaf' as const },
    content: { kind: 'legacyTextContent' as const, textSource: content },
    style: { top: 0, left: id * 10, width: 10, height: 10 },
    styleVariables: []
  }));

  return {
    irVersion: 2,
    seed: 1,
    sourcePath: 'Main.sverlin',
    sampling: { mode: 'legacyOptimizer', coverage: 'legacyCoverage' },
    coordinates: {
      systemName: 'sverlin-css96-y-down',
      systemUnitsPerInch: 96,
      systemOrigin: 'top-left',
      systemYAxis: 'down'
    },
    canvas: { width: 100, height: 80 },
    resources: [],
    findings: [],
    variables: [],
    elements,
    steps: elements.map((element, index) => ({
      label: `Step ${index + 1}`,
      instances: [{ id: 1, elementId: element.id }]
    }))
  };
}
