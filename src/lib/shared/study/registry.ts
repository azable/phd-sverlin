/** Versioned study-protocol registry used by enrollment, playback, and exports. */

import type { StudyDefinition } from './definition';
import { pilotStudyV1 } from './pilot-v1';

const definitions = [pilotStudyV1] as const;
const registry = new Map(
  definitions.map((definition) => [key(definition.id, definition.version), definition])
);

/** Protocol assigned to participants enrolled after this deployment. */
export const activeStudyDefinition = pilotStudyV1;

/** Resolve the exact immutable protocol recorded on an enrollment. */
export function studyDefinition(id: string, version: number): StudyDefinition {
  const definition = registry.get(key(id, version));
  if (!definition) throw new Error(`Unknown study protocol ${id} version ${version}.`);
  return definition;
}

/** Return registered protocols for lossless research exports. */
export function registeredStudyDefinitions(): StudyDefinition[] {
  return [...definitions];
}

function key(id: string, version: number): string {
  return `${id}:${version}`;
}
