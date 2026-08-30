/** Versioned study-protocol registry used by enrollment, playback, and exports. */

import type { StudyDefinition } from './definition';
import { pilotStudyV1 } from './pilot-v1';

export type StudyRef = { id: string; version: number };
export type StudyRegistration = {
  definition: StudyDefinition;
  enrollment: 'open' | 'closed';
};

const registrations = registerStudies([{ definition: pilotStudyV1, enrollment: 'open' }]);
const registry = new Map(
  registrations.map((registration) => [
    key(registration.definition.id, registration.definition.version),
    registration
  ])
);

/** Resolve the exact immutable protocol recorded on an enrollment. */
export function studyDefinition(id: string, version: number): StudyDefinition {
  return studyRegistration({ id, version }).definition;
}

/** Return registered protocols for lossless research exports. */
export function registeredStudyDefinitions(): StudyDefinition[] {
  return registrations.map(({ definition }) => definition);
}

/** Resolve registration and deployment enrollment state for an exact protocol version. */
export function studyRegistration(ref: StudyRef): StudyRegistration {
  const registration = registry.get(key(ref.id, ref.version));
  if (!registration) throw new Error(`Unknown study protocol ${ref.id} version ${ref.version}.`);
  return registration;
}

/** Return every configured protocol version, including versions closed to new enrollment. */
export function registeredStudies(): StudyRegistration[] {
  return [...registrations];
}

/** Validate an immutable list of configured protocol versions before serving it. */
export function registerStudies(
  values: readonly StudyRegistration[]
): readonly StudyRegistration[] {
  const references = values.map(({ definition }) => key(definition.id, definition.version));
  if (new Set(references).size !== references.length) {
    throw new Error('Registered study protocol IDs and versions must be unique.');
  }
  return Object.freeze(values.map((registration) => Object.freeze(registration)));
}

function key(id: string, version: number): string {
  return `${id}:${version}`;
}
