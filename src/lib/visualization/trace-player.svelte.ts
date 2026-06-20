import { tick } from 'svelte';
import { SvelteMap } from 'svelte/reactivity';

import type { CompiledTrace, LiveElement, RenderElement, RenderId, RenderPatch } from './types';

type PatchAnimationOptions = {
  animateCreate: boolean;
  animateDestroy: boolean;
};

const transitionMs = 300;

export class TracePlayer {
  trace = $state<CompiledTrace | null>(null);
  elements = $state<LiveElement[]>([]);
  currentStep = $state(-1);

  #destroyTimers = new SvelteMap<RenderId, ReturnType<typeof setTimeout>>();
  #transitionVersion = 0;

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
    return this.hasTrace && this.currentStep > 0;
  }

  get canNext() {
    return this.hasTrace && this.currentStep < this.lastStep;
  }

  get canvasWidth() {
    return this.trace?.canvas.width ?? 0;
  }

  get canvasHeight() {
    return this.trace?.canvas.height ?? 0;
  }

  setTrace(trace: CompiledTrace) {
    this.trace = trace;
    this.currentStep = trace.frames.length > 0 ? 0 : -1;
    this.rebuildToStep(this.currentStep);
  }

  reset() {
    if (!this.trace) return;

    this.currentStep = this.trace.frames.length > 0 ? 0 : -1;
    this.rebuildToStep(this.currentStep);
  }

  next() {
    if (!this.trace || !this.canNext) return;

    const nextStep = this.currentStep + 1;

    this.applyFrame(this.trace.frames[nextStep], {
      animateCreate: true,
      animateDestroy: true
    });
    this.currentStep = nextStep;
  }

  previous() {
    if (!this.trace || !this.canPrevious) return;

    this.applyReverseFrame(this.trace.frames[this.currentStep], {
      animateCreate: true,
      animateDestroy: true
    });
    this.currentStep -= 1;
  }

  dispose() {
    this.clearDestroyTimers();
  }

  private rebuildToStep(step: number) {
    if (!this.trace) return;

    this.clearDestroyTimers();
    this.#transitionVersion += 1;

    const next = new SvelteMap<RenderId, LiveElement>();

    for (let i = 0; i <= step; i += 1) {
      this.applyPatchesToMap(next, this.trace.frames[i], {
        animateCreate: false,
        animateDestroy: false
      });
    }

    this.elements = Array.from(next.values());
  }

  private applyFrame(patches: RenderPatch[], options: PatchAnimationOptions) {
    this.#transitionVersion += 1;

    const next = this.liveElementMap();

    this.applyPatchesToMap(next, patches, options);

    this.elements = Array.from(next.values());
  }

  private applyReverseFrame(patches: RenderPatch[], options: PatchAnimationOptions) {
    this.#transitionVersion += 1;

    const next = this.liveElementMap();

    this.applyReversePatchesToMap(next, patches, options);

    this.elements = Array.from(next.values());
  }

  private liveElementMap() {
    const next = new SvelteMap<RenderId, LiveElement>();

    for (const element of this.elements) {
      next.set(element.id, element);
    }

    return next;
  }

  private applyPatchesToMap(
    next: Map<RenderId, LiveElement>,
    patches: RenderPatch[],
    options: PatchAnimationOptions
  ) {
    for (const patch of patches) {
      switch (patch.kind) {
        case 'create': {
          this.clearDestroyTimer(patch.id);
          const originStyle =
            options.animateCreate && patch.origin ? patch.origin.element.style : undefined;

          next.set(patch.id, {
            ...patch.element,
            style: originStyle ?? patch.element.style,
            id: patch.id,
            exiting: false
          });

          if (originStyle) {
            this.scheduleSettleElement(patch.id, patch.element);
          }

          break;
        }

        case 'update': {
          this.clearDestroyTimer(patch.id);

          next.set(patch.id, {
            ...patch.to,
            id: patch.id,
            exiting: false
          });

          break;
        }

        case 'destroy': {
          if (options.animateDestroy) {
            const current = next.get(patch.id);

            next.set(patch.id, {
              ...(current ?? patch.element),
              id: patch.id,
              exiting: true
            });

            this.scheduleDestroy(patch.id);
          } else {
            this.clearDestroyTimer(patch.id);
            next.delete(patch.id);
          }

          break;
        }
      }
    }
  }

  private applyReversePatchesToMap(
    next: Map<RenderId, LiveElement>,
    patches: RenderPatch[],
    options: PatchAnimationOptions
  ) {
    for (const patch of patches.slice().reverse()) {
      switch (patch.kind) {
        case 'create': {
          const current = next.get(patch.id);

          if (options.animateCreate) {
            next.set(patch.id, {
              ...(current ?? patch.element),
              style: patch.origin?.element.style ?? (current ?? patch.element).style,
              id: patch.id,
              exiting: true
            });

            this.scheduleDestroy(patch.id);
          } else {
            this.clearDestroyTimer(patch.id);
            next.delete(patch.id);
          }

          break;
        }

        case 'update': {
          this.clearDestroyTimer(patch.id);

          next.set(patch.id, {
            ...patch.from,
            id: patch.id,
            exiting: false
          });

          break;
        }

        case 'destroy': {
          this.clearDestroyTimer(patch.id);

          if (options.animateDestroy) {
            const current = next.get(patch.id);

            next.set(patch.id, {
              ...(current ?? patch.element),
              id: patch.id,
              exiting: true
            });

            this.scheduleSettleElement(patch.id, patch.element);
          } else {
            next.set(patch.id, {
              ...patch.element,
              id: patch.id,
              exiting: false
            });
          }

          break;
        }
      }
    }
  }

  private scheduleDestroy(id: RenderId) {
    this.clearDestroyTimer(id);

    const timer = setTimeout(() => {
      this.elements = this.elements.filter((element) => element.id !== id);
      this.#destroyTimers.delete(id);
    }, transitionMs);

    this.#destroyTimers.set(id, timer);
  }

  private scheduleSettleElement(id: RenderId, element: RenderElement) {
    const version = this.#transitionVersion;

    void tick().then(() => {
      if (version !== this.#transitionVersion) return;

      this.elements = this.elements.map((current) =>
        current.id === id
          ? {
              ...element,
              id,
              exiting: false
            }
          : current
      );
    });
  }

  private clearDestroyTimer(id: RenderId) {
    const timer = this.#destroyTimers.get(id);

    if (timer) {
      clearTimeout(timer);
      this.#destroyTimers.delete(id);
    }
  }

  private clearDestroyTimers() {
    for (const timer of this.#destroyTimers.values()) {
      clearTimeout(timer);
    }

    this.#destroyTimers.clear();
  }
}
