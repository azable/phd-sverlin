/** Artifact-version event contract. */

import * as v from 'valibot';

import { artifactChangeSchema, artifactOriginSchema, eventEnvelope } from './values';

/** Runtime schema for one or more committed artifact changes. */
export const artifactVersionCreatedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('artifact.version-created'),
  payload: v.object({
    origin: artifactOriginSchema,
    changes: v.pipe(v.array(artifactChangeSchema), v.minLength(1))
  })
});
