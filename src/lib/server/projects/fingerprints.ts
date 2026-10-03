/** Content-addressed source and presentation text retained directly in Timelines. */

import { createHash } from 'node:crypto';

import type { RecordedText } from '$lib/shared/projects/events/values';

export function sourceSha256(content: string): string {
  return createHash('sha256').update(content).digest('hex');
}

export function recordText(text: string, mediaType: string): RecordedText {
  return { text, sha256: sourceSha256(text), mediaType };
}
