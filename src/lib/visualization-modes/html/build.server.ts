/** Validate and package one authored script-free HTML manifest. */

import { randomUUID } from 'node:crypto';

import type { HtmlFramesPresentation } from '$lib/shared/presentations';
import { recordText } from '$lib/server/projects/fingerprints';
import { stepSignature } from '../signature.server';

import { validateHtmlFramesManifest } from './html-safety.server';

export function buildHtmlPresentation(
  source: string,
  generationEventId?: number
): HtmlFramesPresentation {
  const { authored, rendered } = validateHtmlFramesManifest(JSON.parse(source));
  return {
    presentationId: randomUUID(),
    format: 'html-frames-v1',
    stepSignature: stepSignature(rendered.frames.map(({ label }) => label)),
    authored: recordText(JSON.stringify(authored), 'application/vnd.sverlin.html-frames+json'),
    rendered: recordText(JSON.stringify(rendered), 'application/vnd.sverlin.html-frames+json'),
    ...(generationEventId ? { generationEventId } : {})
  };
}

/** Uniform mode builder; the static format does not use the view seed. */
export async function buildPresentation(
  source: string,
  _seed: number,
  generationEventId?: number
): Promise<HtmlFramesPresentation> {
  return buildHtmlPresentation(source, generationEventId);
}
