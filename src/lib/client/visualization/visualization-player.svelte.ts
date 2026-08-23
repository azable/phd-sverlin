/**
 * Reactive playback state for compiler-produced visualizations.
 *
 * @packageDocumentation
 */

/* eslint-disable svelte/prefer-svelte-reactivity -- These Maps are ephemeral lookup tables, not reactive state. */
import { tick } from 'svelte';

import type { LiveElement, VisualElement, VisualId, VisualInstance, Visualization } from './types';

/** Options controlling the initial checkpoint when loading a visualization. */
export type SetVisualizationOptions = { initialStep?: number };

/**
 * A seekable player over compiler-produced checkpoint steps. Stable instance
 * identities animate updates; keyed Svelte transitions own entry and exit.
 */
export class VisualizationPlayer {
  /** The visualization currently loaded for playback. */
  visualization = $state.raw<Visualization | null>(null);
  /** Elements visible at the current checkpoint. */
  elements = $state.raw<LiveElement[]>([]);
  /** Zero-based checkpoint index, or `-1` when no step is active. */
  currentStep = $state(-1);

  #transitionVersion = 0;

  /** Whether a visualization is currently loaded. */
  get hasVisualization(): boolean {
    return this.visualization !== null;
  }

  /** Number of checkpoint steps in the loaded visualization. */
  get stepCount(): number {
    return this.visualization?.steps.length ?? 0;
  }

  /** Zero-based index of the final checkpoint. */
  get lastStep(): number {
    return this.stepCount - 1;
  }

  /** Whether playback can move to an earlier checkpoint. */
  get canPrevious(): boolean {
    return this.currentStep > 0;
  }

  /** Whether playback can move to a later checkpoint. */
  get canNext(): boolean {
    return this.currentStep >= 0 && this.currentStep < this.lastStep;
  }

  /** Label of the active checkpoint, or an empty string when none is active. */
  get currentStepLabel(): string {
    return this.currentStep >= 0 ? (this.visualization?.steps[this.currentStep]?.label ?? '') : '';
  }

  /** Solved canvas width for the loaded visualization. */
  get canvasWidth(): number {
    return this.visualization?.canvas.width ?? 0;
  }

  /** Solved canvas height for the loaded visualization. */
  get canvasHeight(): number {
    return this.visualization?.canvas.height ?? 0;
  }

  /** Load a visualization and seek to its requested initial checkpoint. */
  setVisualization(visualization: Visualization, options: SetVisualizationOptions = {}): void {
    this.visualization = visualization;
    this.seek(options.initialStep ?? 0);
  }

  /** Remove the loaded visualization and reset playback state. */
  clear(): void {
    this.#transitionVersion += 1;
    this.visualization = null;
    this.elements = [];
    this.currentStep = -1;
  }

  /** Return playback to the first checkpoint. */
  reset(): void {
    this.seek(0);
  }

  /** Advance one checkpoint when possible. */
  next(): void {
    if (this.canNext) this.transitionTo(this.currentStep + 1);
  }

  /** Move back one checkpoint when possible. */
  previous(): void {
    if (this.canPrevious) this.transitionTo(this.currentStep - 1);
  }

  /** Seek to a checkpoint, clamping the requested index to the available range. */
  seek(requestedStep: number): void {
    this.#transitionVersion += 1;

    if (!this.visualization || this.visualization.steps.length === 0) {
      this.currentStep = -1;
      this.elements = [];
      return;
    }

    this.currentStep = this.clampStep(requestedStep);
    this.elements = this.elementsForStep(this.visualization.steps[this.currentStep].instances);
  }

  /** Release pending playback work and clear state. */
  dispose(): void {
    this.clear();
  }

  private transitionTo(step: number): void {
    if (!this.visualization) return;

    this.#transitionVersion += 1;

    const current = new Map(this.elements.map((element) => [element.instanceId, element]));
    const targetStep = this.visualization.steps[step];
    const target = this.elementsForStep(targetStep.instances);
    const instances = new Map(targetStep.instances.map((instance) => [instance.id, instance]));
    const registry = this.elementRegistry();

    const next = target.map((element) => {
      const existing = current.get(element.instanceId);
      if (existing) return element;

      const instance = instances.get(element.instanceId);
      const origin =
        instance?.originElementId !== undefined
          ? registry.get(instance.originElementId)
          : undefined;

      if (!origin) return element;

      this.scheduleSettle(element);
      return { ...element, box: origin.box, style: origin.style };
    });

    this.currentStep = step;
    this.elements = next;
  }

  private elementsForStep(instances: VisualInstance[]): LiveElement[] {
    const registry = this.elementRegistry();

    return instances.flatMap<LiveElement>((instance) => {
      const element = registry.get(instance.elementId);
      return element
        ? [
            {
              ...element,
              instanceId: instance.id,
              codeEmphasisRanges: instance.codeEmphasisRanges ?? []
            }
          ]
        : [];
    });
  }

  private elementRegistry(): Map<VisualId, VisualElement> {
    return new Map<VisualId, VisualElement>(
      this.visualization?.elements.map((element) => [element.id, element]) ?? []
    );
  }

  private clampStep(step: number): number {
    return Math.min(Math.max(0, step), this.lastStep);
  }

  private scheduleSettle(element: LiveElement): void {
    const version = this.#transitionVersion;

    void tick().then(() => afterPaint(() => this.settleElement(version, element)));
  }

  private settleElement(version: number, element: LiveElement): void {
    if (version !== this.#transitionVersion) return;
    this.elements = this.elements.map((current) =>
      current.instanceId === element.instanceId ? element : current
    );
  }
}

function afterPaint(callback: () => void): void {
  if (typeof requestAnimationFrame === 'function') {
    requestAnimationFrame(() => requestAnimationFrame(callback));
  } else {
    setTimeout(callback, 0);
  }
}
