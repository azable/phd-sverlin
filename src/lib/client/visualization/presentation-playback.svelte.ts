/** Reactive playback position shared by presentation controls and retained references. */

import { presentationStepLabels } from '$lib/shared/presentations';

import type { TimelinePresentation } from './presentation-history';

/** Renderer-aware boundary within which a numerical playback step may be retained. */
export type PresentationPlaybackContext = {
  key: string;
  stepCount: number;
};

/** Derive the playback identity and common safe step count for the visible presentations. */
export function presentationPlaybackContext(
  presentations: readonly TimelinePresentation[]
): PresentationPlaybackContext {
  if (presentations.length === 0) return { key: '', stepCount: 0 };
  const sourceHashes = presentations.flatMap(({ presentation }) =>
    presentation.format === 'sverlin-ir-v1' ? [presentation.source.sha256] : []
  );
  const sameSverlinSource =
    sourceHashes.length === presentations.length &&
    sourceHashes.every((sha256) => sha256 === sourceHashes[0]);
  const key = sameSverlinSource
    ? `sverlin:${sourceHashes[0]}`
    : `presentations:${presentations
        .map(({ presentation }) => presentation.presentationId)
        .join(':')}`;
  const stepCount = Math.min(
    ...presentations.map(({ presentation }) => presentationStepLabels(presentation).length)
  );
  return { key, stepCount };
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

function clampStep(step: number, stepCount: number): number {
  return Math.min(Math.max(0, step), Math.max(0, stepCount - 1));
}
