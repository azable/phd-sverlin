/** Validate and package one authored HTML/JS artifact for sandbox playback. */

import { randomUUID } from 'node:crypto';

import type { BrowserBundlePresentation } from '$lib/shared/presentations';
import { recordText } from '$lib/server/projects/fingerprints';

import { stepSignature } from '../signature.server';
import { compileHtmlJs } from './compile.server';

export async function buildHtmlJsPresentation(
  source: string,
  seed: number,
  generationEventId?: number
): Promise<BrowserBundlePresentation> {
  const bundle = await compileHtmlJs(JSON.parse(source));
  return {
    presentationId: randomUUID(),
    format: 'browser-bundle-v1',
    mode: 'html-js',
    stepSignature: stepSignature(bundle.steps),
    labels: bundle.steps,
    seed,
    source: recordText(source, 'application/json'),
    html: recordText(bundle.html, 'text/html'),
    javascript: recordText(bundle.javascript, 'text/javascript'),
    ...(generationEventId ? { generationEventId } : {})
  };
}

export { buildHtmlJsPresentation as buildPresentation };
