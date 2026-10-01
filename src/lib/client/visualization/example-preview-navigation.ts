import { resolve } from '$app/paths';

/** Choose a positive view seed in the compiler's supported browser range. */
export function randomExampleSeed(): number {
  return 1 + Math.floor(Math.random() * 2147483646);
}

/** Keep the selected example and its seed together in one navigable URL. */
export function examplePreviewPath(exampleId: string, seed: number): string {
  return `${resolve('/examples')}?example=${encodeURIComponent(exampleId)}&seed=${seed}`;
}
