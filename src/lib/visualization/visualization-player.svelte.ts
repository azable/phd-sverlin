/* eslint-disable svelte/prefer-svelte-reactivity -- These Maps are ephemeral lookup tables, not reactive state. */
import { tick } from 'svelte';

import type { LiveElement, VisualElement, VisualId, VisualInstance, Visualization } from './types';

type SetVisualizationOptions = { initialStep?: number };

/**
 * A seekable player over compiler-produced checkpoint steps. Stable instance
 * identities animate updates; keyed Svelte transitions own entry and exit.
 */
export class VisualizationPlayer {
  visualization = $state<Visualization | null>(null);
  elements = $state<LiveElement[]>([]);
  currentStep = $state(-1);

  #transitionVersion = 0;

  get hasVisualization() {
    return this.visualization !== null;
  }

  get stepCount() {
    return this.visualization?.steps.length ?? 0;
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
    return this.currentStep >= 0 ? (this.visualization?.steps[this.currentStep]?.label ?? '') : '';
  }

  get canvasWidth() {
    return this.visualization?.canvas.width ?? 0;
  }

  get canvasHeight() {
    return this.visualization?.canvas.height ?? 0;
  }

  setVisualization(visualization: Visualization, options: SetVisualizationOptions = {}) {
    this.visualization = visualization;
    this.seek(options.initialStep ?? 0);
  }

  clear() {
    this.#transitionVersion += 1;
    this.visualization = null;
    this.elements = [];
    this.currentStep = -1;
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

    if (!this.visualization || this.visualization.steps.length === 0) {
      this.currentStep = -1;
      this.elements = [];
      return;
    }

    this.currentStep = this.clampStep(requestedStep);
    this.elements = this.elementsForStep(this.visualization.steps[this.currentStep].instances);
  }

  dispose() {
    this.clear();
  }

  private transitionTo(step: number) {
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
    return new Map<VisualId, VisualElement>(
      this.visualization?.elements.map((element) => [element.id, element]) ?? []
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
