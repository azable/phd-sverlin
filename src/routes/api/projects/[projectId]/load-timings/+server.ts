import { isHttpError, json } from '@sveltejs/kit';
import * as v from 'valibot';

import { requireProjectAccess } from '$lib/server/authorization';
import { presentationLoadTimingSchema } from '$lib/shared/presentation-load-timing';

import type { RequestHandler } from './$types';

// One timing is a few hundred bytes; this bounds the body well above that.
const maximumBodyBytes = 4 * 1024;

/**
 * Write how long a presentation took to appear to the server log, one JSON line per load, so load
 * times can be audited. Outside the project Timeline, it never conflicts with project commands.
 */
export const POST: RequestHandler = async ({ params, request, locals }) => {
  try {
    const principal = await requireProjectAccess(locals, params.projectId);
    const text = await request.text();
    if (text.length > maximumBodyBytes)
      return json({ error: 'The timing report is too large.' }, { status: 413 });
    const parsed = v.safeParse(presentationLoadTimingSchema, JSON.parse(text));
    if (!parsed.success) return json({ error: v.summarize(parsed.issues) }, { status: 400 });
    console.info(
      JSON.stringify({
        type: 'sverlin.presentation-load',
        at: new Date().toISOString(),
        projectId: params.projectId,
        viewer: principal.kind,
        ...parsed.output
      })
    );
    return new Response(null, { status: 204 });
  } catch (cause) {
    if (isHttpError(cause)) return json({ error: cause.body.message }, { status: cause.status });
    if (cause instanceof SyntaxError)
      return json({ error: 'The timing report is not JSON.' }, { status: 400 });
    throw cause;
  }
};
