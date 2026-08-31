/**
 * Environment-neutral visualization wire contract generated from the Haskell IR.
 *
 * @packageDocumentation
 */

export type * from './generated/visualization-ir';

import * as v from 'valibot';

import type { Visualization } from './generated/visualization-ir';
import { validateVisualizationReferences, visualizationSchema } from './schema';

/** Raised when compiler output does not satisfy the current visualization contract. */
export class InvalidVisualizationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidVisualizationError';
  }
}

/** Decode and strictly validate either retained IR v1 or scenario-aware IR v2. */
export function decodeVisualization(json: string): Visualization {
  let input: unknown;
  try {
    input = JSON.parse(json);
  } catch (error) {
    throw new InvalidVisualizationError(
      `Invalid visualization JSON: ${error instanceof Error ? error.message : String(error)}`
    );
  }

  const parsed = v.safeParse(visualizationSchema, input);
  if (!parsed.success) {
    throw new InvalidVisualizationError(
      `Invalid visualization IR: ${v.summarize(parsed.issues)}`
    );
  }

  try {
    validateVisualizationReferences(parsed.output);
  } catch (error) {
    throw new InvalidVisualizationError(error instanceof Error ? error.message : String(error));
  }
  return parsed.output;
}

/** Decode a compiler batch without weakening validation of each member. */
export function decodeVisualizationBatch(json: string): Visualization[] {
  let input: unknown;
  try {
    input = JSON.parse(json);
  } catch (error) {
    throw new InvalidVisualizationError(
      `Invalid visualization JSON: ${error instanceof Error ? error.message : String(error)}`
    );
  }
  const values = Array.isArray(input) ? input : [input];
  return values.map((value) => decodeVisualization(JSON.stringify(value)));
}
