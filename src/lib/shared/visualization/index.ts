/**
 * Environment-neutral visualization wire contract generated from the Haskell IR.
 *
 * @packageDocumentation
 */

export type * from './generated/visualization-ir';

import type { Visualization } from './generated/visualization-ir';

/** Decode the trusted, Haskell-generated visualization wire format at its boundary. */
export function decodeVisualization(json: string): Visualization {
  const visualization = JSON.parse(json) as Visualization;

  for (const element of visualization.elements) {
    if ((element.kind as { kind: string }).kind === 'trace') {
      element.kind = { kind: 'leaf' };
    }
  }

  return visualization;
}
