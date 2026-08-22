/** Project-rename event contract. */

import * as v from 'valibot';

import { eventEnvelope } from './values';

/** Runtime schema for a project title change. */
export const projectRenamedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('project.renamed'),
  payload: v.object({ previousTitle: v.string(), title: v.string() })
});
