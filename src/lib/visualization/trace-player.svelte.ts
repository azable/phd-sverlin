import { tick } from 'svelte';
import { SvelteMap } from 'svelte/reactivity';

import type {
  CompiledVisualization,
  LiveElement,
  VisualElement,
  VisualId,
  VisualInstance
} from './types';

type SetTraceOptions = { initialStep?: number };

/**
 * A seekable player over compiler-produced checkpoint steps. Stable instance
 * identities animate updates; keyed Svelte transitions own entry and exit.
 */
export class TracePlayer {
  trace = $state<CompiledVisualization | null>(null);
  elements = $state<LiveElement[]>([]);
  currentStep = $state(-1);

  #transitionVersion = 0;

  get hasTrace() {
    return this.trace !== null;
  }

  get stepCount() {
    return this.trace?.steps.length ?? 0;
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

  get currentStepLabel() {
    return this.currentStep >= 0 ? (this.trace?.steps[this.currentStep]?.label ?? '') : '';
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
    if (this.canNext) this.transitionTo(this.currentStep + 1);
  }

  previous() {
    if (this.canPrevious) this.transitionTo(this.currentStep - 1);
  }

  seek(requestedStep: number) {
    this.#transitionVersion += 1;

    if (!this.trace || this.trace.steps.length === 0) {
      this.currentStep = -1;
      this.elements = [];
      return;
    }

    this.currentStep = this.clampStep(requestedStep);
    this.elements = this.elementsForStep(this.trace.steps[this.currentStep].instances);
  }

  dispose() {
    this.#transitionVersion += 1;
  }

  private transitionTo(step: number) {
    if (!this.trace) return;

    this.#transitionVersion += 1;

    const current = new SvelteMap(this.elements.map((element) => [element.instanceId, element]));
    const targetStep = this.trace.steps[step];
    const target = this.elementsForStep(targetStep.instances);
    const instances = new SvelteMap(
      targetStep.instances.map((instance) => [instance.id, instance])
    );
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
      return { ...element, style: origin.style };
    });

    this.currentStep = step;
    this.elements = next;
  }

  private elementsForStep(instances: VisualInstance[]) {
    const registry = this.elementRegistry();

    return instances.flatMap<LiveElement>((instance) => {
      const element = registry.get(instance.elementId);
      return element ? [{ ...element, instanceId: instance.id }] : [];
    });
  }

  private elementRegistry() {
    return new SvelteMap<VisualId, VisualElement>(
      this.trace?.elements.map((element) => [element.id, element]) ?? []
    );
  }

  private clampStep(step: number) {
    return Math.min(Math.max(0, step), this.lastStep);
  }

  private scheduleSettle(element: LiveElement) {
    const version = this.#transitionVersion;

    void tick().then(() => afterPaint(() => this.settleElement(version, element)));
  }

  private settleElement(version: number, element: LiveElement) {
    if (version !== this.#transitionVersion) return;
    this.elements = this.elements.map((current) =>
      current.instanceId === element.instanceId ? element : current
    );
  }
}

function afterPaint(callback: () => void) {
  if (typeof requestAnimationFrame === 'function') {
    requestAnimationFrame(() => requestAnimationFrame(callback));
  } else {
    setTimeout(callback, 0);
  }
}
