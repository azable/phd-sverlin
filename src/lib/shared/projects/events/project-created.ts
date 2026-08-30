/** Project-creation event contract. */

import * as v from 'valibot';

import { assistantIdSchema } from '$lib/shared/assistants';

import { projectCreationSchema } from '../creation';
import { eventEnvelope, textSchema } from './values';

/** Runtime schema for the root event of a project. */
export const projectCreatedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('project.created'),
  payload: v.object({
    title: v.string(),
    entryArtifactId: textSchema,
    assistantId: assistantIdSchema,
    creation: projectCreationSchema
  })
});
