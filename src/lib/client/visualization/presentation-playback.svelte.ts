/** Reactive, mode-neutral playback position for one or two retained presentations. */

import { presentationScenarioKey, presentationStepLabels } from '$lib/shared/presentations';
import type { TimelinePresentation } from './presentation-history';

export type PresentationPlaybackFrame = {
  key: string;
  label: string;
  localSteps: Readonly<Record<string, number>>;
};

export type PresentationPlaybackContext = {
  key: string;
  stepCount: number;
  frames: readonly PresentationPlaybackFrame[];
};

export function presentationPlaybackContext(
  presentations: readonly TimelinePresentation[]
): PresentationPlaybackContext {
  if (presentations.length === 0) return { key: '', stepCount: 0, frames: [] };
  const labels = presentations.map(({ presentation }) => presentationStepLabels(presentation));
  const stepCount = Math.min(...labels.map((steps) => steps.length));
  const frames = Array.from({ length: stepCount }, (_, step) => ({
    key: `step:${step}`,
    label: labels[0][step] ?? `Step ${step + 1}`,
    localSteps: Object.fromEntries(
      presentations.map(({ presentation }) => [presentation.presentationId, step])
    )
  }));
  const scenarios = presentations.map(({ presentation }) =>
    presentation.format === 'browser-bundle-v1' ? presentationScenarioKey(presentation) : undefined
  );
  const sameSource = scenarios.every((key) => key !== undefined && key === scenarios[0]);
  return {
    key: sameSource
      ? `source:${scenarios[0]}`
      : `presentations:${presentations.map(({ presentation }) => presentation.presentationId).join(':')}`,
    stepCount,
    frames
  };
}

export function localPresentationStep(
  context: PresentationPlaybackContext,
  presentationId: string,
  step: number
): number {
  return context.frames[clampStep(step, context.stepCount)]?.localSteps[presentationId] ?? -1;
}

export class PresentationPlayback {
  #contextKey = $state('');
  #step = $state(0);

  activate(context: PresentationPlaybackContext): void {
    if (this.#contextKey !== context.key) {
      this.#contextKey = context.key;
      this.#step = 0;
      return;
    }
    this.#step = clampStep(this.#step, context.stepCount);
  }

  stepFor(context: PresentationPlaybackContext): number {
    return this.#contextKey === context.key ? clampStep(this.#step, context.stepCount) : 0;
  }

  seek(context: PresentationPlaybackContext, step: number): number {
    this.#contextKey = context.key;
    this.#step = clampStep(step, context.stepCount);
    return this.#step;
  }
}

function clampStep(step: number, stepCount: number): number {
  return Math.min(Math.max(0, step), Math.max(0, stepCount - 1));
}
