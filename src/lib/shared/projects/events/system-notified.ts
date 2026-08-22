/** System-notification event contract. */

import * as v from 'valibot';

import { eventEnvelope } from './values';

/** Runtime schema for a user-facing system notice. */
export const systemNotifiedEventSchema = v.object({
  ...eventEnvelope,
  type: v.literal('system.notified'),
  payload: v.object({
    severity: v.picklist(['info', 'warning', 'error']),
    message: v.string()
  })
});
