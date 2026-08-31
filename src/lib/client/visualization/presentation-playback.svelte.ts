/** Reactive playback position shared by presentation controls and retained references. */

import {
  isSverlinPresentation,
  presentationScenarioKey,
  presentationStepLabels,
  type CompilerPresentation
} from '$lib/shared/presentations';
import { decodeVisualization } from '$lib/shared/visualization';

import type { TimelinePresentation } from './presentation-history';

export type PresentationPlaybackFrame = {
  key: string;
  label: string;
  localSteps: Readonly<Record<string, number>>;
};

/** Renderer-aware boundary within which a numerical playback step may be retained. */
export type PresentationPlaybackContext = {
  key: string;
  stepCount: number;
  frames: readonly PresentationPlaybackFrame[];
};

/** Derive one ordered frame union and the held local frame for every visible view. */
export function presentationPlaybackContext(
  presentations: readonly TimelinePresentation[]
): PresentationPlaybackContext {
  if (presentations.length === 0) return { key: '', stepCount: 0, frames: [] };
  const compilerPresentations = presentations.filter(
    (entry): entry is TimelinePresentation & { presentation: CompilerPresentation } =>
      isSverlinPresentation(entry.presentation)
  );
  const scenarioKeys = compilerPresentations.map(({ presentation }) =>
    presentationScenarioKey(presentation)
  );
  const sameV2Scenario =
    compilerPresentations.length === presentations.length &&
    compilerPresentations.every(({ presentation }) => presentation.format === 'sverlin-ir-v2') &&
    scenarioKeys.every((key) => key === scenarioKeys[0]);
  if (sameV2Scenario) {
    const frames = hierarchicalFrames(compilerPresentations);
    return { key: `sverlin:${scenarioKeys[0]}`, stepCount: frames.length, frames };
  }

  const stepCount = Math.min(
    ...presentations.map(({ presentation }) => presentationStepLabels(presentation).length)
  );
  const frames = Array.from({ length: stepCount }, (_, step) => ({
    key: `legacy:${step}`,
    label: presentationStepLabels(presentations[0].presentation)[step] ?? `Step ${step + 1}`,
    localSteps: Object.fromEntries(
      presentations.map(({ presentation }) => [presentation.presentationId, step])
    )
  }));
  const legacySourceHashes = compilerPresentations.flatMap(({ presentation }) =>
    presentation.format === 'sverlin-ir-v1' ? [presentation.source.sha256] : []
  );
  const sameLegacySource =
    legacySourceHashes.length === presentations.length &&
    legacySourceHashes.every((hash) => hash === legacySourceHashes[0]);
  return {
    key: sameLegacySource
      ? `sverlin:${legacySourceHashes[0]}`
      : `presentations:${presentations
          .map(({ presentation }) => presentation.presentationId)
          .join(':')}`,
    stepCount,
    frames
  };
}

/** Resolve a union position to the frame actually displayed by one presentation. */
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

  /** Reconcile playback after the visible presentation context changes. */
  activate(context: PresentationPlaybackContext): void {
    if (this.#contextKey !== context.key) {
      this.#contextKey = context.key;
      this.#step = 0;
      return;
    }
    this.#step = clampStep(this.#step, context.stepCount);
  }

  /** Return the resolved step without exposing stale state from another context. */
  stepFor(context: PresentationPlaybackContext): number {
    return this.#contextKey === context.key ? clampStep(this.#step, context.stepCount) : 0;
  }

  /** Seek within a context and return the bounded step shared by every consumer. */
  seek(context: PresentationPlaybackContext, step: number): number {
    this.#contextKey = context.key;
    this.#step = clampStep(step, context.stepCount);
    return this.#step;
  }
}

function hierarchicalFrames(
  presentations: readonly TimelinePresentation[]
): PresentationPlaybackFrame[] {
  const decoded = presentations.map((entry) => {
    if (!isSverlinPresentation(entry.presentation)) {
      throw new Error('Hierarchical playback requires compiler presentations.');
    }
    return { entry, visualization: decodeVisualization(entry.presentation.render.text) };
  });
  // These lookup indexes are populated and consumed synchronously inside this pure projection.
  // eslint-disable-next-line svelte/prefer-svelte-reactivity
  const occurrences = new Map<string, { ordinal: number; label: string }>();
  // eslint-disable-next-line svelte/prefer-svelte-reactivity
  const occurrenceKeysByOrdinal = new Map<number, string>();
  for (const { visualization } of decoded) {
    for (const frame of visualization.steps) {
      if (frame.occurrenceKey === undefined || frame.ordinal === undefined) continue;
      const existing = occurrences.get(frame.occurrenceKey);
      if (existing && (existing.ordinal !== frame.ordinal || existing.label !== frame.label)) {
        throw new Error(`Views disagree about frame occurrence ${frame.occurrenceKey}.`);
      }
      const retainedKey = occurrenceKeysByOrdinal.get(frame.ordinal);
      if (retainedKey !== undefined && retainedKey !== frame.occurrenceKey) {
        throw new Error(`Views disagree about frame ordinal ${frame.ordinal}.`);
      }
      occurrences.set(frame.occurrenceKey, { ordinal: frame.ordinal, label: frame.label });
      occurrenceKeysByOrdinal.set(frame.ordinal, frame.occurrenceKey);
    }
  }
  return [...occurrences.entries()]
    .toSorted(
      (left, right) => left[1].ordinal - right[1].ordinal || left[0].localeCompare(right[0])
    )
    .map(([key, occurrence]) => ({
      key,
      label: occurrence.label,
      localSteps: Object.fromEntries(
        decoded.map(({ entry, visualization }) => {
          const localStep = visualization.steps.findLastIndex(
            ({ ordinal }) => ordinal !== undefined && ordinal <= occurrence.ordinal
          );
          return [entry.presentation.presentationId, localStep];
        })
      )
    }));
}

function clampStep(step: number, stepCount: number): number {
  return Math.min(Math.max(0, step), Math.max(0, stepCount - 1));
}
