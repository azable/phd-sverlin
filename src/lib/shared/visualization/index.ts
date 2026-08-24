/**
 * Environment-neutral visualization wire contract generated from the Haskell IR.
 *
 * @packageDocumentation
 */

export type * from './generated/visualization-ir';

import * as v from 'valibot';

import type { Visualization } from './generated/visualization-ir';
import { validateVisualizationReferences, visualizationV1Schema } from './schema';

/** Raised when compiler output does not satisfy the current visualization contract. */
export class InvalidVisualizationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'InvalidVisualizationError';
  }
}

/** Decode and strictly validate Haskell-generated root-based visualization IR v1. */
export function decodeVisualization(json: string): Visualization {
  let input: unknown;
  try {
    input = JSON.parse(json);
  } catch (error) {
    throw new InvalidVisualizationError(
      `Invalid visualization JSON: ${error instanceof Error ? error.message : String(error)}`
    );
  }

  const parsed = v.safeParse(visualizationV1Schema, input);
  if (!parsed.success) {
    throw new InvalidVisualizationError(
      `Invalid visualization IR v1: ${v.summarize(parsed.issues)}`
    );
  }

  try {
    validateVisualizationReferences(parsed.output);
  } catch (error) {
    throw new InvalidVisualizationError(error instanceof Error ? error.message : String(error));
  }
  return parsed.output;
}
