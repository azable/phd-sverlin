import { SvelteMap } from 'svelte/reactivity';

import type { CompiledVisualization, LiveElement, VisualElement } from './types';

type SetTraceOptions = { initialStep?: number };

/**
 * A seekable player over complete IR scene snapshots.
 *
 * Temporal reconstruction belongs to the compiler. The frontend only joins a
 * frame's lightweight instances to the package element registry.
 */
export class TracePlayer {
  trace = $state<CompiledVisualization | null>(null);
  elements = $state<LiveElement[]>([]);
  currentStep = $state(-1);

  get hasTrace() {
    return this.trace !== null;
  }

  get stepCount() {
    return this.trace?.frames.length ?? 0;
  }

  get lastStep() {
    return this.stepCount - 1;
  }

  get canPrevious() {
    return this.currentStep > 0;
  }

  get canNext() {
    return this.currentStep >= 0 && this.currentStep < this.lastStep;
  }

  get canvasWidth() {
    return this.trace?.canvas.width ?? 0;
  }

  get canvasHeight() {
    return this.trace?.canvas.height ?? 0;
  }

  setTrace(trace: CompiledVisualization, options: SetTraceOptions = {}) {
    this.trace = trace;
    this.seek(options.initialStep ?? 0);
  }

  reset() {
    this.seek(0);
  }

  next() {
    if (this.canNext) this.seek(this.currentStep + 1);
  }

  previous() {
    if (this.canPrevious) this.seek(this.currentStep - 1);
  }

  seek(requestedStep: number) {
    if (!this.trace || this.trace.frames.length === 0) {
      this.currentStep = -1;
      this.elements = [];
      return;
    }

    const step = Math.min(Math.max(0, requestedStep), this.lastStep);
    const elements = new SvelteMap<string, VisualElement>(
      this.trace.elements.map((element) => [element.id, element])
    );

    this.currentStep = step;
    this.elements = this.trace.frames[step].instances.flatMap((instance) => {
      const element = elements.get(instance.elementId);
      if (!element) return [];

      return [
        {
          ...element,
          instanceId: instance.id,
          ...(instance.origin ? { origin: instance.origin } : {})
        }
      ];
    });
  }

  dispose() {}
}
