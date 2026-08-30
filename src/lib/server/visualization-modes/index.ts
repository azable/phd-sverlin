/** Renderer-neutral construction helpers at the visualization-mode boundary. */

import { createHash, randomUUID } from 'node:crypto';

import type { HtmlFramesManifest, HtmlFramesPresentation } from '$lib/shared/presentations';
import { recordText } from '$lib/server/projects/fingerprints';

import { validateHtmlFramesManifest } from './html-safety';

/** Validate, sanitize, and package one conversational HTML result for presentation. */
export function createHtmlPresentation(
  manifest: HtmlFramesManifest,
  generationEventId?: number
): HtmlFramesPresentation {
  const { authored, rendered } = validateHtmlFramesManifest(manifest);
  return {
    presentationId: randomUUID(),
    format: 'html-frames-v1',
    stepSignature: stepSignature(rendered.frames.map(({ label }) => label)),
    authored: recordText(JSON.stringify(authored), 'application/vnd.sverlin.html-frames+json'),
    rendered: recordText(JSON.stringify(rendered), 'application/vnd.sverlin.html-frames+json'),
    ...(generationEventId ? { generationEventId } : {})
  };
}

/** Stable signature used to synchronize one or two presentations. */
export function stepSignature(labels: readonly string[]): string {
  return createHash('sha256').update(JSON.stringify(labels)).digest('hex');
}
