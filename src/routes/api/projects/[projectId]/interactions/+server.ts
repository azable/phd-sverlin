import { json } from '@sveltejs/kit';

import { requirePrincipal } from '$lib/server/authorization';
import {
  consumeStudyInteractionBatchAllowance,
  ingestStudyInteractions,
  StudyInteractionIngestionError
} from '$lib/server/study-interactions';
import { parseStudyInteractionBatch } from '$lib/shared/study/interactions';

import type { RequestHandler } from './$types';

// Twice the configured flush target permits JSON framing without accepting unbounded bodies.
const maximumBodyBytes = 64 * 1024;

/** Accept project observations independently from the project's durable Timeline. */
export const POST: RequestHandler = async ({ locals, params, request }) => {
  const principal = requirePrincipal(locals);
  if (principal.kind !== 'participant') {
    return json({ error: 'Participant interaction recording is required.' }, { status: 403 });
  }
  if (!consumeStudyInteractionBatchAllowance(principal.user.id)) {
    return json({ error: 'Interaction batches are arriving too quickly.' }, { status: 429 });
  }
  try {
    const text = await boundedRequestText(request);
    if (text === undefined) {
      return json({ error: 'The interaction batch is too large.' }, { status: 413 });
    }
    const batch = parseStudyInteractionBatch(JSON.parse(text));
    if (batch.session.projectId !== params.projectId) {
      return json(
        { error: 'The interaction project does not match the request.' },
        { status: 409 }
      );
    }
    return json(await ingestStudyInteractions(principal, batch, new Date()));
  } catch (cause) {
    if (cause instanceof StudyInteractionIngestionError) {
      return json({ error: cause.message }, { status: cause.status });
    }
    if (cause instanceof SyntaxError || (cause instanceof Error && cause.name === 'ValiError')) {
      return json({ error: 'The interaction batch is invalid.' }, { status: 400 });
    }
    console.error('Participant interaction ingestion failed.', cause);
    return json({ error: 'Interaction recording is temporarily unavailable.' }, { status: 503 });
  }
};

async function boundedRequestText(request: Request): Promise<string | undefined> {
  const declared = Number(request.headers.get('content-length'));
  if (Number.isFinite(declared) && declared > maximumBodyBytes) return undefined;
  if (!request.body) return '';
  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let received = 0;
  let text = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) return text + decoder.decode();
    received += value.byteLength;
    if (received > maximumBodyBytes) {
      await reader.cancel();
      return undefined;
    }
    text += decoder.decode(value, { stream: true });
  }
}
