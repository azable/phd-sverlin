/**
 * Elements participants select in visible presentations, to reference in feedback. A selection
 * belongs to one presentation at one playback step; stepping elsewhere drops it, and opening an
 * element reference restores it at its step.
 */

import type * as v from 'valibot';

import type { selectedElementSchema } from '$lib/shared/projects/events/message-content';

/** A selected element, with the constraint layouts around it (see selectedElementSchema). */
export type SelectedElement = v.InferOutput<typeof selectedElementSchema>;

export type VisualSelection = {
  presentationId: string;
  step: number;
  elements: SelectedElement[];
};

export class VisualSelections {
  current = $state.raw<VisualSelection[]>([]);

  /** The selection shown in one presentation at a step, if any. */
  for(presentationId: string, step: number): VisualSelection | undefined {
    return this.current.find(
      (selection) => selection.presentationId === presentationId && selection.step === step
    );
  }

  /** Replace one presentation's selection; an empty selection clears it. */
  set(presentationId: string, step: number, elements: readonly SelectedElement[]): void {
    const others = this.current.filter((selection) => selection.presentationId !== presentationId);
    this.current = elements.length
      ? [...others, { presentationId, step, elements: [...elements] }]
      : others;
  }

  /** Keep only selections of these presentations at this step. */
  retain(presentationIds: readonly string[], step: number): void {
    const kept = this.current.filter(
      (selection) => selection.step === step && presentationIds.includes(selection.presentationId)
    );
    if (kept.length !== this.current.length) this.current = kept;
  }
}
