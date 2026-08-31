import { json } from '@sveltejs/kit';
import * as v from 'valibot';

import { requirePrincipal } from '$lib/server/authorization';
import {
  consumeStudyInteractionBatchAllowance,
  ingestStudyInteractions,
  StudyInteractionIngestionError
} from '$lib/server/study-interactions';
import {
  parseStudyInteractionBatch,
  studyInteractionEventInputSchema,
  studyInteractionSessionInputSchema,
  studyInteractionTerminalSchema,
  type StudyInteractionBatchInput,
  type StudyInteractionErrorCode
} from '$lib/shared/study/interactions';

import type { RequestHandler } from './$types';

// Twice the configured flush target permits JSON framing without accepting unbounded bodies.
const maximumBodyBytes = 64 * 1024;

/** Accept project observations independently from the project's durable Timeline. */
export const POST: RequestHandler = async ({ locals, params, request }) => {
  const principal = requirePrincipal(locals);
  if (principal.kind !== 'participant') {
    return interactionError(
      'Participant interaction recording is required.',
      'capture-unavailable',
      403
    );
  }
  if (!consumeStudyInteractionBatchAllowance(principal.user.id)) {
    return interactionError('Interaction batches are arriving too quickly.', 'rate-limited', 429, {
      headers: { 'retry-after': '5' }
    });
  }
  try {
    const text = await boundedRequestText(request);
    if (text === undefined) {
      return interactionError('The interaction batch is too large.', 'body-too-large', 413);
    }
    const parsed = parseRequestBatch(JSON.parse(text));
    if ('response' in parsed) return parsed.response;
    const batch = parsed.batch;
    if (batch.session.projectId !== params.projectId) {
      return interactionError(
        'The interaction project does not match the request.',
        'project-mismatch',
        409
      );
    }
    return json(await ingestStudyInteractions(principal, batch, new Date()));
  } catch (cause) {
    if (cause instanceof StudyInteractionIngestionError) {
      return json(
        { error: cause.message, code: cause.code, ...cause.details },
        { status: cause.status }
      );
    }
    if (cause instanceof SyntaxError) {
      return interactionError('The interaction batch is not valid JSON.', 'invalid-json', 400);
    }
    console.error('Participant interaction ingestion failed.', cause);
    return interactionError(
      'Interaction recording is temporarily unavailable.',
      'temporarily-unavailable',
      503
    );
  }
};

function parseRequestBatch(
  value: unknown
): { batch: StudyInteractionBatchInput } | { response: Response } {
  if (!isRecord(value)) {
    return {
      response: interactionError('The interaction batch is invalid.', 'invalid-batch', 400)
    };
  }
  if (!v.safeParse(studyInteractionSessionInputSchema, value.session).success) {
    return {
      response: interactionError('The interaction session is invalid.', 'invalid-session', 400)
    };
  }
  if (
    value.terminal !== undefined &&
    !v.safeParse(studyInteractionTerminalSchema, value.terminal).success
  ) {
    return {
      response: interactionError(
        'The interaction terminal metadata is invalid.',
        'invalid-session',
        400
      )
    };
  }
  if (!Array.isArray(value.events)) {
    return {
      response: interactionError('The interaction batch is invalid.', 'invalid-batch', 400)
    };
  }
  for (const [invalidEventIndex, event] of value.events.entries()) {
    if (!v.safeParse(studyInteractionEventInputSchema, event).success) {
      return {
        response: json(
          {
            error: 'One interaction event is invalid.',
            code: 'invalid-event',
            invalidEventIndex
          },
          { status: 400 }
        )
      };
    }
  }
  try {
    return { batch: parseStudyInteractionBatch(value) };
  } catch {
    return {
      response: interactionError('The interaction batch is invalid.', 'invalid-batch', 400)
    };
  }
}

function interactionError(
  error: string,
  code: StudyInteractionErrorCode,
  status: number,
  init: Omit<ResponseInit, 'status'> = {}
): Response {
  return json({ error, code }, { ...init, status });
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

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
